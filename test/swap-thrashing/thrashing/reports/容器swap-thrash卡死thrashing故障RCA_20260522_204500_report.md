# 🔴 故障诊断报告

> **报告编号**：RCA-20260522-001
> **故障级别**：P1 / Critical
> **报告时间**：2026-05-22 20:45:00 CST
> **当前状态**：🟡 观察中（容器已退出但根因未修复，复现条件依旧存在）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | 容器 swap-thrash-test 因 cgroup 内存限制过小引发 Swap Thrashing，导致容器卡死、宿主机响应极慢 |
| 影响范围 | 容器 `swap-thrash-test`（stress-ng 压测进程）→ 宿主机 localhost（WSL2），系统级响应变慢，IO wait 高达 14% |
| 故障时段 | 2026-05-22 20:15:00 CST ～ 持续至诊断时刻（容器仍在运行或刚退出） |
| 根本原因 | 容器 cgroup memory.max = 256MB 远小于 stress-ng 工作集需求（4 × 384MB = 1.5GB），内核被迫持续在容器 cgroup 层面执行匿名页换入换出（thrashing），swap 设备 IO 饱和导致系统卡死 |
| 是否恢复 | ❌ 未恢复（根因未修复，若重新运行相同配置的容器会再次触发） |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|--------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | 本场景：cgroup 限制(256MB) << workload(1.5GB)，三份独立报告交叉印证，指标完全吻合 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                         事件                                                    性质          溯源路径
───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-05-22 20:15:00 CST      容器 swap-thrash-test 启动，执行 stress-ng --vm 4           📈 触发      [T2 : 时间线T1]
                                --vm-bytes 384M --page-in --vm-keep
                              ↓ 4 个 VM worker 各分配 384MB，总需求 1.5GB
                              ↓
2026-05-22 20:15:00+ CST     cgroup memory.max=256MB 被瞬间占满                          ⚠️ 限流激活    [T1 : 容器配置]
                              ↓ 内核进入 direct reclaim 路径
                              ↓
2026-05-22 20:15:01+ CST     匿名页被换出至 swap 设备 (/dev/sdc)                          🟡 压力积累    [T1 : 传播路径]
                              ↓ stress-ng --page-in 立即触发 do_swap_page() 重新换入
                              ↓
2026-05-22 20:15:01+ CST     Swap Thrashing 循环形成                                      🔴 故障爆发    [T1 : 异常指标]
                              ↓ si/so ≈ 50K~87K pages/s（阈值 60~80 倍）
                              ↓ pgmajfault 265 万次，workingset refault 640 万次
                              ↓
2026-05-22 20:15:02+ CST     swap 设备 /dev/sdc IO 饱和（占总 IO 95%+）                    🔴 瓶颈形成    [T3 : 磁盘I/O]
                              ↓ CPU iowait 飙升至 12~14%
                              ↓ Load average 高达 5.70~6.00
                              ↓
2026-05-22 20:15:03+ CST     3/4 的 stress-ng VM worker 陷入 D 状态（不可中断睡眠）          🔴 系统瘫痪    [T1 : 系统表现]
                              ↓ 容器卡死无响应，宿主机操作明显卡顿
                              ↓
2026-05-22 ~20:41 CST       诊断开始，三份 Kuafu 报告确认同一根因                         🔍 证据固定    [T1/T2/T3]
```

### 故障因果链

```text
[触发条件] 容器 swap-thrash-test 运行 stress-ng --vm 4 --vm-bytes 384M --page-in --vm-keep
    └─► 4 × 384MB = 1.5GB 工作集 >> 容器 cgroup memory.max = 256MB
        └─► 内核内存分配器进入 direct reclaim 路径
            └─► kswapd/direct reclaim 大量扫描匿名页 LRU 链表（pgscan_anon 1903 万页）
                └─► swap_writepage() 将匿名页换出至 /dev/sdc
                    └─► stress-ng --page-in 立即触发 do_swap_page() → swap_readpage() 重新换入
                        ↻ 换出→立即换入→再换出→再换入（Thrashing 锁定循环）
                        └─► si/so 速率 50K~87K pages/s（超过 thrashing 阈值 1000 pages/s 的 60~80 倍）
                            └─► pgmajfault 265 万次，workingset refault 640 万次
                                └─► swap 设备 /dev/sdc IO 饱和，占系统总 IO 的 95%+
                                    └─► CPU iowait 14%，Load 6.0，3/4 worker 进程 D 状态
                                        └─► 🔴 容器卡死，宿主机系统响应极慢
```

---

## 三、排查过程

### 3.1 初始现象

- **用户报告**：容器 `swap-thrash-test` 卡死无响应，宿主机系统响应极慢
- **容器状态**：处于 `Up` 状态约 3 分钟，但进程处于活跃争抢状态
- **Docker stats**：容器 CPU 占用 **165%**，内存占用 **99.85%（255.6MiB/256MiB）**
- **宿主机 vmstat**：可运行进程 **r=4~10**，阻塞进程 **b=1~3**，CPU iowait **13~14%**
- **关键日志/指标**：
  - swap 设备 `/dev/sdc` 承担系统 **95%+** 的 IO 流量
  - 容器 Block I/O 在 4 分钟内达到 **24.7GB 读入 / 24GB 写出**

---

### 3.2 假设驱动排查

#### 假设 A：宿主机全局内存不足

> 🧪 假设：宿主机物理内存耗尽，系统被迫大量使用 swap

| 检查项 | 操作 | 结论 |
|--------|------|------|
| MemAvailable | `cat /proc/meminfo` → MemAvailable=5.4GB/7.4GB | ✅ 充足 |
| SwapFree | `free -h` → SwapFree=1.8GB/2GB | ✅ 充裕 |
| OOM Killer | `dmesg` 无 oom-kill 记录 | ✅ 无 OOM |

**❌ 排除**：宿主机内存充裕，排除全局内存不足。

---

#### 假设 B：swap 空间耗尽

> 🧪 假设：swap 分区用尽，内存回收失败

| 检查项 | 操作 | 结论 |
|--------|------|------|
| swap.current | 容器 swap 使用约 170~180MB | 🟡 未耗尽 |
| SwapFree | 宿主机 SwapFree=1.8GB/2GB = 使用率仅 8.5% | ✅ 充裕 |
| memory.swap.events.fail | 仅 31 次（偶发触及 swap 上限） | ✅ 非空间耗尽 |

**❌ 排除**：swap 空间充裕，排除空间耗尽。

---

#### 假设 C：OOM Killer 触发进程被杀

> 🧪 假设：系统 OOM Killer 杀死了容器中的进程

| 检查项 | 操作 | 结论 |
|--------|------|------|
| memory.events.oom | cgroup v2 → oom=0 | ✅ 无 OOM 事件 |
| memory.events.oom_kill | 0 | ✅ 无进程被杀 |
| 容器 ExitCode | =0（clean exit） | ✅ 正常退出，非 SIGKILL |

**❌ 排除**：无 OOM Killer 触发。

---

#### 假设 D：磁盘/swap 设备硬件故障

> 🧪 假设：swap 设备发生硬件故障，IO 异常

| 检查项 | 操作 | 结论 |
|--------|------|------|
| dmesg I/O error | 无 I/O 超时或磁盘硬件错误日志 | ✅ 正常 |
| swapon | `/dev/sdc` 正常初始化，Priority=-2 | ✅ 正常 |
| 设备类型 | rotational=1（机械盘后端），非 SSD | 🟡 性能有限但无故障 |

**❌ 排除**：swap 设备无硬件故障。

---

#### 假设 E：容器 cgroup 内存限制过小导致 Swap Thrashing ✅ 确认根因

> 🧪 假设：容器 cgroup memory.max = 256MB 远小于 stress-ng workload 1.5GB 需求，触发剧烈 thrashing

**Step 1 — 确认 cgroup 内存限制与使用量**

| 检查项 | 值 | 状态 |
|--------|-----|------|
| 容器 memory.max | 256 MB（268,435,456 bytes） | 🔴 严重过低 |
| 容器 memory.current | ~256 MB（占用率 99.99%） | 🔴 触顶 |
| memory.events.max | **125,554 次**（持续约 5 分钟，即 ~382次/秒） | 🔴 极高 |
| 容器 swap.max | 256 MB | 🟡 适中 |
| 容器 swap.current | ~170~180 MB | 🟡 持续增长 |

**Step 2 — 确认 Thrashing 内核指标**

从三份诊断报告交叉印证：

| 指标 | T1 报告 | T2 报告 | T3 报告 | 含义 |
|------|--------|--------|--------|------|
| si（换入速率） | ~78,972 pages/s | ~60,000 pages/s（~240MB/s） | ~56,412 pages/s | 大量页面从 swap 读回 |
| so（换出速率） | ~73,968 pages/s | ~57,000 pages/s（~228MB/s） | ~52,556 pages/s | 大量页面写入 swap |
| pgmajfault | 2,651,409 次 | 2,430,252 次 | — | 主缺页中断（每次需磁盘 IO） |
| workingset_refault_anon | 5,854,905 次 | 5,621,766 次 | — | 匿名页 refault（thrashing 核心特征） |
| pgscan_anon | 19,722,068 页 | — | 19,033,294 页 | 匿名页扫描量极大 |
| iowait | 13~14% | 13~14% | 12~14% | CPU 大量等待 swap IO |
| swap 设备 IO 占比 | — | — | 95%+ | 系统 IO 几乎被 swap 占满 |

**Step 3 — 确认进程状态恶化**

- 3/4 的 stress-ng VM worker 进程处于 **D 状态**（不可中断睡眠，卡在 page fault → swap 读取路径）
- 1/4 处于 R 状态但 CPU 占用达 102%（页表操作开销）
- 容器 RSS ≈ 252MB，已占满 256MB cgroup 限制

**✅ 结论：容器 cgroup memory.max（256MB）远小于 stress-ng 工作集需求（1.5GB），触发内核在 cgroup 层面进行极度频繁的匿名页换入换出（thrashing），si/so 速率超过正常阈值 60~80 倍，swap 设备 IO 饱和，系统响应瘫痪。**

---

### 3.3 排查结论

```text
容器 swap-thrash-test 卡死 + 宿主机响应极慢
│
├─► 假设 A：宿主机全局内存不足          → ✅ 排除（MemAvailable 5.4GB/7.4GB）
│
├─► 假设 B：swap 空间耗尽               → ✅ 排除（SwapFree 1.8GB/2GB，仅用 8.5%）
│
├─► 假设 C：OOM Killer 进程被杀          → ✅ 排除（oom=0, oom_kill=0, ExitCode=0）
│
├─► 假设 D：磁盘/swap 设备硬件故障       → ✅ 排除（dmesg 无 I/O error）
│
└─► 假设 E：容器 cgroup 内存限制过小     → ❌ 确认根因 🎯
        └─► memory.max = 256MB << workload = 1.5GB
            └─► 持续 direct reclaim → 匿名页换出 → --page-in 立即换入
                └─► Thrashing 锁定循环（si+so > 108K pages/s）
                    └─► swap 设备 IO 饱和（占总 IO 95%+）
                        └─► 3/4 worker D 状态，容器卡死
```

---

## 四、修复方案

### 4.1 应急处置（已执行）

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | `docker stop swap-thrash-test` | 系统/运维 | 立即 | 停止容器后 thrashing 立即消除，si/so 应降至接近 0，iowait 回落至 < 2% |

容器已正常退出（ExitCode=0），当前无需进一步紧急操作。但如果重新以相同配置启动，故障将立即复现。

### 4.2 永久修复计划

| 修复措施 | 负责人 | 完成时间 |
|--------|------|--------|
| **增大容器内存限制**：将 `--memory` 从 256MB 提升至应用实际需求（建议 ≥2GB），如 `docker run --memory="2048m" --memory-swap="2560m"` | 容器配置负责人 | 待定 |
| **移除 `--vm-keep` 和 `--page-in` 参数**：这两个参数人为制造 thrashing，生产环境不应使用 | 应用开发团队 | 待定 |
| **调整宿主机 swappiness**：WSL2/容器场景建议调低至 10~20，减少匿名页换出倾向：`sysctl -w vm.swappiness=10`，并写入 `/etc/sysctl.conf` 持久化 | 系统管理员 | 待定 |
| **建立容器资源配置规范**：容器 Memory 限制应基于业务负载实际峰值安全余量（推荐 +30% buffer），避免硬限制过小 | 基础设施团队 | 待定 |
| **配置 thrashing 监控告警**：监控 `memory.events.max` 增长率（>100次/分钟告警），以及 si/so 速率（>1000 pages/s 告警），使用巡检脚本定期检测 | 监控团队 | 待定 |
| **评估 WSL2 swap 配置**：在 `.wslconfig` 中考虑增大内存分配或调整 swap 大小，避免机械盘后端导致的 IO 性能瓶颈 | 平台团队 | 待定 |

### 4.3 验证建议

1. **调整后验证**：运行 `vmstat 1 5` 观察 si/so 应降至 < 100 pages/s，CPU iowait 回落到 < 5%
2. **长期监控**：使用 `check_thrashing.sh` 脚本定期巡检，监控 `/proc/vmstat` 中的 `pgmajfault` 和 `workingset_refault_anon` 增长率
3. **复现验证**：以调整后的 memory 限制（≥2GB）重新启动容器，确认 stress-ng 正常运行而不触发 thrashing

---

## 附录：诊断证据汇总

### 关键证据交叉引用

| 证据项 | T1 报告 | T2 报告 | T3 报告 |
|--------|---------|---------|---------|
| 容器 memory.max = 256MB | 第 42 行 | 第 62 行 | 第 88 行 |
| si/so 速率超阈值 | 第 109~110 行（50K~87K pages/s） | 第 50~52 行（~240MB/s） | 第 77 行（峰值 425MB/s） |
| pgmajfault | 第 71 行（2,651,409） | 第 45 行（2,430,252） | — |
| workingset_refault_anon | 第 53 行（5,854,905） | 第 46 行（5,621,766） | — |
| iowait | 第 21 行（13~14%） | 第 52 行（13~14%） | 第 14 行（12~14%） |
| swap 设备 IO 占比 | — | — | 第 63 行（95%+） |
| 3/4 worker D 状态 | 第 20 行 | 第 53 行 | — |
| 排除 OOM | 第 160 行 | 第 30 行 | — |
| 宿主机内存充裕 | 第 156 行 | 第 31 行 | 第 109 行 |

### 诊断报告路径

- T1: `/home/win11/.witty-diagnosis-agent/kuafu/kuafu_T1_20260522_122039.md`
- T2: `/home/win11/.witty-diagnosis-agent/kuafu/kuafu_T2_20260522_121539.md`
- T3: `/home/win11/.witty-diagnosis-agent/kuafu/kuafu_T3_20260522_204155.md`
- **本 RCA 报告**: `/home/win11/.witty-diagnosis-agent/baize/reports/容器swap-thrash卡死thrashing故障RCA_20260522_204500_report.md`
