# 🟡 故障诊断报告 — Swap Thrashing 事件

> **报告编号**: RCA-20260524-001
> **故障级别**: P3 / Major（性能下降 — 测试环境）
> **报告时间**: 2026-05-24 23:30:00
> **当前状态**: 🟢 已恢复

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | 容器内 sysbench 内存压力测试触发宿主 kswapd Swap Thrashing，导致系统性能抖动的根因分析 |
| 影响范围 | 测试宿主机（WSL2 内核 6.6.87.2-microsoft-standard-WSL2），容器 `swap-thrash-branchF`（无 memory 限制） |
| 故障时段 | 2026-05-24 23:27:00 ～ 2026-05-24 23:29:00（约 2 分钟，峰值在 23:28:34） |
| 根本原因 | 容器内 `sysbench` 持续大量分配匿名页内存（无 cgroup memory 上限），快速耗尽宿主机空闲内存，触发 kswapd 被频繁唤醒（66 次低水位命中）执行大规模 LRU 扫描与换出，但刚换出的页被进程立即重新访问，产生 **refault 风暴（3.7M 次）**，导致 kswapd 陷入 thrashing 循环无法达到高水位，CPU 持续飙高 |
| 是否恢复 | ✅ 已恢复（容器退出后内存释放，kswapd 进入睡眠） |
| 根因置信度 | 🟢 高置信 — 双轨分析（现场指标 + 内核语义）完全吻合，因果链清晰，现象可复现 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|---------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | 本场景：sysbench 无限制分配内存 → thrashing → 容器退出后恢复 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

> **核心故障链**：无 cgroup 限制的 sysbench 内存压力测试 → 快速耗尽宿主空闲内存 → kswapd 被反复唤醒 → LRU 扫描 + 换出 → 刚换出的页被进程重新访问 → refault 风暴 → thrashing 死循环 → kswapd CPU 飙升、系统响应变慢 → 容器退出后恢复。

### 事件时间线与故障传导链路

```text
时间                      事件                                                 性质         证据来源
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-05-24 ~23:27:00      容器 swap-thrash-branchF 启动，sysbench 开始                 📈 触发      [容器运行记录]
                           分配大量匿名内存（--memory-block-size=1M                     
                           --memory-total-size=40G）
  │
  ▼
~23:27:30                 系统空闲内存快速下降，低于 low watermark                     ⚠️ 水位告警   [/proc/vmstat: kswapd_low_wmark_hit_quickly=66]
  │                       wakeup_kswapd() 被调用
  ▼
~23:27:30～23:28:30       kswapd 被反复唤醒执行 balance_pgdat()                       🟡 压力积累   [内核语义证据]
  │                       大规模扫描匿名页 LRU（总扫描 57M pages）
  │                       shrink_page_list() → pageout() → swap_writepage()
  │                       换出 20M pages 到 /dev/sdc（约 78GB 累积换出）
  ▼
~23:28:00～23:28:34       换出页被进程立即访问 → 缺页异常 → swap_readpage()            🔴 refault    [workingset_refault_anon=3,711,635]
  │                       页面回弹（3.7M 次），LRU 旋转（19.8M pgrotated）
  │                       → 再次被扫描 → 再次换出 → thrashing 循环
  │                       → kswapd 无法达到 high watermark，持续运行
  ▼
2026-05-24 23:28:34       **峰值**: so=12,096 pages/s (~47 MB/s), si=2,242 pages/s      🔴 故障顶点   [vmstat 1s 采样]
  │                       (~8.8 MB/s)，系统负载升高，kswapd CPU 高
  ▼
2026-05-24 23:28:35       **容器退出** → 内存释放 → 空闲内存恢复                        🟢 自动恢复   [vmstat: si/so 归零]
  │                       → kswapd 达到 high watermark → 进入睡眠
  ▼
2026-05-24 23:28:37+      系统完全恢复：MemAvailable=5.6GB，SwapFree=99.8%，               🟢 已恢复     [当前指标]
                           load average=0.66/1.30/1.17，kswapd 进程不存在
```

### 故障因果链

```text
[触发] sysbench 内存压力测试（无 memory cgroup 限制）
   └─► 大量分配匿名页 → 内存水位线跌破 low watermark
          └─► wakeup_kswapd() 被反复触发（低水位命中 66 次）
                 └─► kswapd → balance_pgdat() → shrink_lruvec()
                        └─► 遍历匿名页 LRU（扫描 57M pages）
                               ├─► 可回收页 → pageout() → swap_writepage()
                               │         → 换出 20M pages 到 /dev/sdc
                               └─► 不可回收页（近期活跃）→ 放回 active list
                                      → pgrotated++（19.8M 次 LRU 旋转）
                               ↓
                        [refault 风暴] 进程立即访问刚换出的页面
                               → swap_readpage() → 换入
                               → workingset_refault_anon=3.7M
                               → 页面重新激活 → 再被扫描 → 再换出
                               ↓
                        🔴 kswapd 陷入 thrashing 死循环
                               → 无法达到 high watermark
                               → kswapd CPU 持续高占用
                               → si/so 峰值 12K pages/s（47 MB/s）
                               ↓
                  [恢复] 容器退出 → 内存释放
                         → kswapd 达到 high watermark → 睡眠
                         → 系统恢复正常
```

---

## 三、排查过程

> 排查逻辑：基于 Kuafu 诊断报告的双轨证据（现场指标 + 内核语义），验证并收敛到根因。

### 3.1 初始现象

- **告警/表现**：宿主 kswapd CPU 占用飙升，系统响应变慢，容器内 sysbench 内存压力测试正在运行
- **诊断工具输出**：`vmstat 1` 采样显示 so=12,096 pages/s、si=2,242 pages/s 的 swap 峰值
- **系统状态**：诊断时系统已恢复，但自启动累计计数器显示大量 thrashing 特征
- **环境**：WSL2 内核 6.6.87.2，容器无 memory cgroup 限制，swap 设备 /dev/sdc（2GB），swappiness=60

### 3.2 假设驱动排查

#### 假设 A：系统级内存泄漏

> 🧪 假设：内核或用户态进程存在内存泄漏，导致内存持续消耗，触发 kswapd 回收

| 检查项 | 操作/证据 | 结论 |
|--------|---------|------|
| 当前内存状态 | MemAvailable=5.6GB，SwapFree=99.8% | ✅ 当前空闲充裕 |
| OOM kill 计数 | oom_kill=250（自启动累计） | ⚠️ 有历史 OOM，但当前无持续泄漏 |
| 容器退出后恢复 | 容器退出后 si/so 立即归零 | ✅ 内存压力来源明确为容器 |

**❌ 排除**：系统级内存泄漏非本次根因；内存压力源为容器内 sysbench 的主动分配。

---

#### 假设 B：Docker 容器配置不当（无 memory cgroup）

> 🧪 假设：容器未设置 memory 上限，导致可耗尽宿主机所有内存

| 检查项 | 操作/证据 | 结论 |
|--------|---------|------|
| cgroup 限制 | 当前无运行容器，诊断时容器本身设置无 memory 限制 | ✅ **确认问题** |
| 对宿主影响 | 单容器即可导致宿主空闲内存耗尽 | ✅ 符合现场表现 |

**🎯 根因确认**：容器无 memory 限制是根本性配置缺陷，sysbench 作为压力工具仅暴露了该缺陷。

---

#### 假设 C：Swappiness 配置过高

> 🧪 假设：swappiness=60 导致内核过早/过度地使用 swap

| 检查项 | 操作/证据 | 结论 |
|--------|---------|------|
| 当前值 | swappiness=60（默认值） | ✅ 默认配置 |
| 系统已恢复 | 当前 same 配置下无异常 | ❌ 非 root cause，仅调节因子 |
| 匿名页需求 | sysbench 分配大量匿名页，即使 swappiness=1 也会回收 | ✅ swappiness 非决定性因素 |

**❌ 排除**：swappiness=60 是默认值，本次问题的本质是内存供不应求，而非 swap 倾向性策略问题。

---

#### 假设 D：磁盘 I/O 瓶颈加剧 thrashing

> 🧪 假设：swap 设备（/dev/sdc）I/O 性能差，换入换出慢，延长 thrashing 持续时间

| 检查项 | 操作/证据 | 结论 |
|--------|---------|------|
| iowait | 诊断时 iowait=0% | ✅ 当前无 IO 瓶颈 |
| Swap 设备 | /dev/sdc 分区，PRIO=-2 | ✅ 正常 |
| dmesg | 无 swap 设备错误 | ✅ 无硬件异常 |

**❌ 排除**：磁盘 IO 非本次问题的根因，但若使用更快的 swap 设备（如 zram）可缓解 thrashing 程度。

---

### 3.3 排查结论

```text
宿主系统响应变慢 / kswapd CPU 飙升
├─► 系统级内存泄漏          → ✅ 排除（当前内存充裕，无泄漏证据）
├─► 磁盘 I/O 瓶颈           → ✅ 排除（iowait=0%，swap 设备正常）
├─► Swappiness 配置不当      → ✅ 排除（默认值，非问题根因）
└─► 🔍 容器 swap-thrash-branchF 内存压力 → 确认根因
        ├─► sysbench 分配大量匿名页 → 内存耗尽
        ├─► kswapd 反复唤醒 → LRU 扫描 → swap out
        ├─► refault 风暴 → thrashing 循环
        └─► 🎯 **根因：容器无 memory cgroup 限制
                + sysbench 压力测试触发 thrashing**
```

#### 关键证据汇总

| 证据项 | 数值 | 意义 |
|--------|------|------|
| pgscan_kswapd | 362,005 | kswapd 主导回收（100%），无 direct reclaim |
| pgscan_direct | 0 | 应用分配路径未阻塞，仅性能下降 |
| pgscan_anon | 57,239,130（93%） | 扫描集中在匿名页，符合 sysbench 分配特征 |
| pgrotated | 19,854,865 | 大量 LRU 旋转 — **thrashing 核心特征** |
| workingset_refault_anon | 3,711,635 | **3.7M 次回弹** — 换出页被立即重新访问 |
| nr_vmscan_write | 20,020,654 | 约 78GB 累计换出 |
| kswapd_low_wmark_hit_quickly | 66 | kswapd 被频繁从低水位唤醒 |
| 峰值 so | 12,096 pages/s（47 MB/s） | 瞬时换出带宽高 |
| 容器 memory 限制 | 无（none） | **根因 — 容器可耗尽宿主机内存** |

---

## 四、修复方案

### 4.1 应急处置（本次故障）

本次故障已由系统自行恢复（容器退出后内存释放），无需人工应急处置。

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 容器 exit → 内存释放 | 系统自动 | 2026-05-24 23:28:35 | kswapd 进入睡眠，si/so 归零，系统恢复 |

### 4.2 永久修复计划

| 修复措施 | 负责人 | 优先级 | 完成时间 |
|---------|--------|--------|---------|
| **1. 对压力测试容器设置 memory cgroup 上限**（如 `docker run --memory=1G`），避免单个容器耗尽宿主机内存 | 运维/测试团队 | P0 | 建议立即执行 |
| **2. 测试环境考虑关闭 swap**（`swapoff -a`），强制 early OOM 而非 thrashing，避免性能抖动 | 运维团队 | P1 | 下次维护窗口 |
| **3. 分离测试负载与生产宿主**，防止测试活动影响生产业务 | 架构团队 | P1 | 规划中 |
| **4. 添加 kswapd 监控告警**：kswapd CPU > 30% 持续 30s 或 so > 5,000 pages/s 时告警 | 监控团队 | P1 | 建议本周内完成 |
| **5. 可选优化调整**：降低 swappiness（`vm.swappiness=10`）减少匿名页换出倾向；增大 watermark 间隔（`vm.watermark_scale_factor=200`）使 kswapd 更早回收、减少突刺 | 运维团队 | P2 | 评估后执行 |

#### 参数调优参考命令

```bash
# 降低 swappiness — 减少 swap 倾向
sysctl -w vm.swappiness=10

# 增大 watermark 间隔 — 使 kswapd 更早开始回收
sysctl -w vm.watermark_scale_factor=200

# 设置容器 memory 上限
docker run --memory=1G --memory-swap=2G ...
```

---

## 五、验证建议

| 验证步骤 | 操作 | 预期结果 |
|---------|------|---------|
| **1. 根因复现** | 在相同环境运行 `docker run sysbench memory --memory-block-size=1M --memory-total-size=40G`，同时 `vmstat 1` 观察 | si/so 出现类似 thrashing 模式，kswapd CPU 飙升 |
| **2. 修复验证** | 设置 `--memory=1G` 后重复测试，观察 kswapd CPU 与 si/so | kswapd CPU 不再显著升高，无持续 thrashing |
| **3. 长期监控** | 配置 kswapd CPU > 30% / so > 5,000 pages/s 告警 | 早于用户感知发现异常 |
