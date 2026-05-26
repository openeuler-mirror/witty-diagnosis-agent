# 🔴 故障诊断报告

> **报告编号**：RCA-20260524-001
> **故障级别**：P2（容器级性能劣化，业务未中断）
> **报告时间**：2026-05-24 23:55:00
> **当前状态**：🟢 已恢复（容器已正常退出）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | 容器 swap-thrash-branchC 因 swappiness=100 与 cgroup 内存限制过小导致严重 swap thrashing |
| 影响范围 | 单容器 `swap-thrash-branchC`（宿主机无影响，其他容器无影响） |
| 故障时段 | 2026-05-24 23:19:55 ～ 2026-05-24 23:22:56（UTC+8，持续 181 秒） |
| 根本原因 | 宿主机 `vm.swappiness=100` 导致内核在文件缓存充足时仍优先换出匿名页，叠加容器 `memory.max=256MB` 远低于工作负载需求（约 410MB），引发严重 swap thrashing |
| 是否恢复 | ✅ 已恢复（stress-ng 运行 180s 后正常退出，ExitCode=0） |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|---------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | SQL 无索引 → 复现后加索引立即恢复 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | 定位到慢查询，但流量突增原因待查 |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | 多个组件同时异常，无法判断触发顺序 |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | 服务偶发崩溃，日志无异常，无法复现 |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                         事件                                                   性质         溯源路径
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-05-24 23:19:55         容器 swap-thrash-branchC 启动                             🚀 容器启动   [kuafu_T3: 容器启动命令]
  │                          Cmd: dd 180MB 文件 + stress-ng --vm-bytes 200M
  ▼
2026-05-24 23:19:56         内存分配开始：200MB VM 锁定 + 180MB 文件缓存                📈 资源需求   [kuafu_T1: 容器资源限制]
  │                          总需求 ≈ 410MB > cgroup memory.max=256MB
  ▼
2026-05-24 ~23:20:00        cgroup 内存控制器触发 memory reclaim                        ⚠️ 内核介入   [kuafu_T2: cgroup 触发]
  │                          kswapd + direct reclaim 被唤醒
  ▼
2026-05-24 ~23:20:05        swappiness=100 → 内核优先回收匿名页而非文件缓存              🔴 配置异常   [kuafu_T1: swappiness 分析]
  │                          即使 Cached=2.1GB 充足，仍大量 swap out 匿名页
  ▼
2026-05-24 ~23:20:10~23:22  严重 swap thrashing                                      🔴 故障爆发   [kuafu_T1: vmstat 采样]
  │                          si ≈ 49000 pages/s, so ≈ 48800 pages/s
  │                          swap used ≈ 140MB / 256MB (54.7%)
  ▼
2026-05-24 23:22:56         stress-ng 运行完成，容器正常退出 (ExitCode=0)              🟢 自动恢复   [kuafu_T2: 容器状态]
                             容器未触发 OOM，swap 充当了弹性缓冲区
```

### 故障因果链

```text
容器启动：swap-thrash-branchC
    │
    ├─► 工作负载：stress-ng --vm-bytes 200M（常驻匿名页 200MB）
    │       + dd/cat 循环（文件页缓存 180MB）
    │       = 总内存需求 ≈ 410MB
    │
    ├─► 容器 cgroup memory.max = 256MB（人为设低）
    │       └─► 总需求 > 限制 → 内核触发内存回收（kswapd + direct reclaim）
    │
    ├─► 宿主机 vm.swappiness = 100（正常默认值为 60）
    │       └─► 内核回收时同等对待匿名页和文件页缓存
    │           （正常行为应优先回收文件页缓存以保护匿名页）
    │
    ├─► kswapd 大量扫描 LRU 链表
    │       └─► 匿名页被换出 (so ≈ 48800 pages/s)
    │
    ├─► stress-ng 仍在活跃访问已换出的匿名页
    │       └─► 被换出的页被立即读回 (si ≈ 49000 pages/s)
    │
    ├─► 形成严重 swap thrashing（换入≈换出速率，无净收益）
    │       └─► swap used ≈ 140MB / 256MB
    │
    └─► 180s 后 stress-ng 完成，容器正常退出 (ExitCode=0)
            └─► 🟢 业务未中断，swap 充当了弹性缓冲区
```

---

## 三、排查过程

### 3.1 初始现象

- **容器** `swap-thrash-branchC` 运行后产生大规模非预期 swap 换入换出
- **监控指标**：vmstat 采样显示 si=49020 pages/s, so=48668 pages/s（峰值）
- **容器日志**：stress-ng: successful run completed in 180.18s
- **用户直观感受**：容器内 swap I/O 异常活跃，系统负载偏高

### 3.2 假设驱动排查

#### 假设 A：宿主机物理内存不足

> 🧪 假设：宿主机整体内存紧张，迫使内核使用 swap

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 总内存 | `cat /proc/meminfo` → MemTotal=7.4GiB | ✅ 内存总量正常 |
| 可用内存 | MemAvailable=5.4GiB (73% 空闲) | ✅ 充裕 |
| 直接内存回收 | pgscan_direct=0（T3 采样时）/ 61,320,360（T2 全系统累计） | ✅ 当前无 direct reclaim |
| 内存压力信号 | `/proc/pressure/memory` → some avg10=0.12 | ✅ 极低压力 |
| allocstall | allocstall=0 | ✅ 无内存分配阻塞 |

**❌ 排除**：宿主机内存极其充裕，不存在全系统内存压力。

---

#### 假设 B：Swap 空间耗尽

> 🧪 假设：Swap 设备空间不足导致异常

| 检查项 | 操作 | 结论 |
|--------|------|------|
| Swap 总量 | SwapTotal=2.0GiB | ✅ 正常 |
| Swap 空闲 | SwapFree=2.0GiB（仅使用 4.1MiB） | ✅ 几乎未用 |
| Swap I/O 错误 | dmesg 中无 swap I/O 错误 | ✅ 无异常 |
| Swap 设备 | `/dev/sdc` 正常 | ✅ 正常 |

**❌ 排除**：Swap 空间充裕，设备无故障。

---

#### 假设 C：容器 OOM Kill

> 🧪 假设：容器因超出内存限制被 OOM Killer 终止

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 容器退出码 | `docker inspect` → ExitCode=0 | ✅ 正常退出 |
| OOMKilled 标志 | OOMKilled=false | ✅ 未被 OOM Kill |
| 容器日志 | "successful run completed in 180.18s" | ✅ 完整运行 |
| 历史 OOM 记录 | OOM kill 计数 250（历史累计） | ✅ 本次无新增 |

**❌ 排除**：容器正常完成，未触发 OOM。

---

#### 假设 D：Swap 设备或文件系统故障

> 🧪 假设：底层 swap 设备损坏导致异常

| 检查项 | 操作 | 结论 |
|--------|------|------|
| dmesg swap 错误 | 无相关错误日志 | ✅ 正常 |
| 容器行为 | 正常完成，无 I/O 超时 | ✅ 正常 |
| CPU iowait | iowait=0% | ✅ 无磁盘 I/O 拥塞 |

**❌ 排除**：Swap 设备工作正常。

---

#### 假设 E：swappiness 配置不当 + cgroup 内存限制过小 ✅ 确认根因

> 🧪 假设：宿主机 `vm.swappiness=100` + 容器 `memory.max=256MB` 共同导致异常 swap thrashing

**Step 1 — 确认 swappiness 配置异常**

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 宿主机 swappiness | `sysctl vm.swappiness` → **100** | 🔴 远超默认值 60 |
| 容器 MemorySwappiness | 未设置，继承宿主机 | 🔴 继承 100 的行为 |
| 内核行为 | 在 Cached=2.1GB 充足时仍优先 swap 匿名页 | 🔴 非预期 |

**Step 2 — 确认 cgroup 内存限制**

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 容器 memory.max | 268,435,456 bytes (256 MB) | 🔴 远低于工作负载需求 |
| 容器 memory.swap.max | 268,435,456 bytes (256 MB) | 允许使用 swap 缓冲 |
| 工作负载总需求 | 200MB VM + 180MB 文件缓存 ≈ 410MB | 🔴 超限 60% |

**Step 3 — 核实 swap thrashing 程度**

| 指标 | 数值 | 评判 |
|------|------|------|
| si (swap in) 峰值 | ~49,020 pages/s ≈ 196 MB/s | 🔴 极高 |
| so (swap out) 峰值 | ~48,868 pages/s ≈ 195 MB/s | 🔴 极高 |
| 总 swap 使用 | ~140MB / 256MB (54.7%) | 🟡 高占用 |
| 宿主机累计 pswpin | 3,711,635 | 大量历史 swap in |
| 宿主机累计 pswpout | 20,018,675 | 大量历史 swap out |

**✅ 结论：swappiness=100 + memory.max=256MB 共同导致严重 swap thrashing。** 两个因素缺一不可：
- 若 `swappiness=60`（默认值），内核会优先回收文件缓存，匿名页换出将大幅减少
- 若 `memory.max=512MB`（匹配工作负载），不会触发内存回收，完全避免 swap

---

### 3.3 排查结论

```text
容器 swap-thrash-branchC 大量 swap 换入换出
│
├─► 宿主机物理内存不足       → ✅ MemAvailable=5.4GiB，排除
├─► Swap 空间耗尽           → ✅ SwapFree=2.0GiB，排除
├─► 容器 OOM Kill           → ✅ ExitCode=0，排除
├─► Swap 设备故障           → ✅ dmesg 无错误，排除
│
└─► cgroup 内存限制触发 + swappiness 配置不当 → 🔴 确认
        │
        ├─► 直接原因：容器的 cgroup memory.max=256MB 远低于实际需求（≈410MB）
        │       └─► 内核必须执行内存回收
        │
        ├─► 条件原因：memory.swap.max=256MB 允许 swap 作为溢出缓冲区
        │       └─► 使容器得以存活而非被 OOM Kill
        │
        └─► 促进因素：vm.swappiness=100
                └─► 内核优先回收匿名页而非文件缓存
                    └─► 导致严重 thrashing（si≈so≈49000 pages/s）
```

---

## 四、修复方案

### 4.1 应急处置（容器运行期间）

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 降低宿主机 swappiness 至 10 或 0 | `sysctl -w vm.swappiness=10` | 即时 | 减少匿名页被换出的倾向 |
| 2 | 调整容器 memory limit（需重建容器） | `docker run --memory=512m` | 需重建 | 匹配工作负载需求，避免内存回收触发 |

> 注：由于容器运行仅 180s，应急处置窗口有限。上述操作更适用于预防。

### 4.2 永久修复计划

| 修复措施 | 负责人 | 优先级 | 完成时间 |
|---------|--------|--------|---------|
| **1. 降低宿主机 swappiness 至合理值**（建议 10 或 60） | 系统管理员 | P0 | 立即 |
| ```bash
sudo sysctl -w vm.swappiness=10
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf
``` | | | |
| **2. 为容器设置独立的 MemorySwappiness** | 应用运维 | P0 | 下次部署 |
| ```bash
docker run --memory-swappiness=0 ... swap-thrash-branchC
``` | | | |
| **3. 评估容器实际内存需求，调整 memory limit** | 应用团队 | P1 | 下次迭代 |
| - 当前工作负载需求 ≈ 410MB（200MB VM + 180MB 文件 + 开销） | | | |
| - 建议设置 `--memory=512m --memory-swap=768m` 或更高 | | | |
| **4. 建立 cgroup swap 使用监控告警** | 监控团队 | P1 | 本周 |
| - 监控 `memory.swap.current`，当使用率 > 50% 时告警 | | | |
| **5. 优化容器内工作负载** | 应用团队 | P2 | 下个版本 |
| - 避免在内存严格受限的容器内同时运行大文件 I/O 和大内存分配 | | | |
| - 考虑将文件缓存操作和 VM 压测串行化 | | | |

### 4.3 验证方法

```bash
# 1. 验证 swappiness 修复
sysctl vm.swappiness
# 期望输出：vm.swappiness = 10（或 60）

# 2. 验证容器无 swap 活动
docker run --memory=512m --memory-swap=768m --memory-swappiness=0 swap-thrasher
vmstat 1 3
# 期望：si=0, so=0，无 swap 活动

# 3. 验证容器正常运行
docker logs <container-id>
# 期望："successful run completed"
```

---

## 五、证据索引

| 来源 | 文件路径 | 关键发现 |
|------|---------|---------|
| T1 - Swap Thrashing 分析 | `/home/win11/.witty-diagnosis-agent/dayu/report/kuafu_T1_20260524_232315.md` | swappiness=100 导致内核在文件缓存充足时仍换出匿名页；si/so 峰值 ≈ 49000 pages/s |
| T2 - Cgroup 内存限制验证 | `/home/win11/.witty-diagnosis-agent/dayu/report/kuafu_T2_20260524_232400.md` | cgroup memory.max=256MB 触发内存回收；pgscan_direct=61M；容器 ExitCode=0 正常退出 |
| T3 - 宿主机内存压力验证 | `/home/win11/.witty-diagnosis-agent/dayu/report/kuafu_T3_20260524_134848.md` | 宿主机 MemAvailable=5.4GiB，无内存压力；swappiness=100 确认；工作负载 200MB+180MB 超限 |
