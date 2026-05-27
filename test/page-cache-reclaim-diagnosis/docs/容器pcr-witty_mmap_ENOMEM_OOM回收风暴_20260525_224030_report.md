# 🔴 故障诊断报告

> **报告编号**: RCA-20260525-224030-001
> **故障级别**: P1 / Critical
> **报告时间**: 2026-05-25 22:40:00 UTC
> **当前状态**: 🟡 观察中（容器已重启，进程已终止）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | 容器 pcr-witty 因 `vm.max_map_count=5000` 极低限制触发 mmap ENOMEM，进而引发全局 OOM 回收风暴与进程被 kill |
| 影响范围 | 容器 `pcr-witty` 内运行的内存压力测试（Python PID 33 + `fault_reclaim_s` 高地址空间进程）；容器 Host 节点全局内存子系统 |
| 故障时段 | 2026-05-25 ~14:34:44 UTC ～ 2026-05-25 ~14:39:51 UTC（两次 OOM kill 时间点） |
| 根本原因 | 双重触发：(1) 容器 cgroup 覆写 `vm.max_map_count=5000` 仅为内核默认值 65530 的 7.6%，导致 Python 进程 mmap 4.95GB 时提前触达 VMA 上限返回 ENOMEM；(2) `fault_reclaim_s` 压力测试工具异常分配 6.5TB 虚拟地址空间（正常应为百 GB 级）→ page tables 膨胀至 6.4GB（占用 40% 物理内存）→ 触发极端 direct reclaim + 全局 OOM killer |
| 是否恢复 | ❌ 未恢复（容器已重启，进程已终止。底层 `vm.max_map_count=5000` 配置仍为低风险状态，但故障期间的压力已消退。） |
| 根因置信度 | 🟡 中置信（故障期间进程已销毁，VMA 实时数据无法获取；mmap ENOMEM 的直接触发条件是 VMA 上限 vs 地址空间碎片化无法 100% 定论） |

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
时间                          事件                                                         性质          溯源路径
──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-05-25 ~14:20:00?         Python PID 33 启动 mmap 压力分配（目标 4.95GB）                   📈 外部触发    [/proc/vmstat, T2 分析]
  │
  ▼
2026-05-25 ~14:20-14:30?      max_map_count=5000 → mmap 已达 VMA 上限 → ENOMEM                 ⚠️ 隐患激活    [kuafu_T2_20260525_224030_mmap_enomem.md:13]
  │                            overcommit_memory=1 (Always) 下仍失败 → 非 overcommit 问题
  │                            最可能原因：容器 cgroup 命名空间覆写 max_map_count=5000
  ▼
2026-05-25 ~14:30-14:34?      fault_reclaim_s 进程启动，持续 mmap 分配直至 6.5TB 虚拟地址空间     🟡 异常积累    [kuafu_T1_20260525_224030_oom_reclaim.md:78-94]
  │                            page tables 随之膨胀至 6.4GB（8 字节/PTE → ~860M 个 PTE）
  │                            物理内存 16GB，page tables 已吞噬约 40%
  ▼
2026-05-25 14:34:44 UTC       第一次 OOM killer 触发：fault_reclaim_s (PID 20893) 被 kill       🔴 故障爆发    [kuafu_T1_20260525_224030_oom_reclaim.md:76-84]
  │                            total-vm=6.5TB, anon-rss=8.4GB, pgtables=6.1GB
  │
  ▼
2026-05-25 14:34-14:39        系统内存压力 persist：新 fault_reclaim_s 进程 (PID 21383) 继续运行   🟡 二次积累    [kuafu_T1_20260525_224030_oom_reclaim.md:86-94]
  │                            allocstall_normal=2400, allocstall_movable=4666
  │                            pgscan_direct=2,445,150, pgscan_kswapd=7,891,748
  │                            共扫描 10.3M 页（~40GB），仅回收 2.4M 页（回收率 23%）
  ▼
2026-05-25 14:39:51 UTC       第二次 OOM killer 触发：fault_reclaim_s (PID 21383) 被 kill       🔴 故障复发    [kuafu_T1_20260525_224030_oom_reclaim.md:86-94]
  │                            total-vm=6.5TB, pgtables=6.1GB
  ▼
2026-05-25 ~14:40+            容器重启，仅剩 PID 1: sleep 3600                                  🟢 故障停歇    [kuafu_T2_20260525_224030_mmap_enomem.md:33-38]
                              系统当前空闲 ~14.4GB，page cache ~226MB，水流恢复正常
```

### 故障因果链

```text
容器 pcr-witty cgroup 覆写 vm.max_map_count=5000（极低）
    │
    ├─► Python PID 33 mmap 4.95GB → VMA 上限耗尽 → 返回 ENOMEM
    │       └─► 内存压力测试进入异常分支
    │
    └─► fault_reclaim_s 进程启动（LTP 风格压力测试）
            │   mmap 分配策略异常 → 分配至 6.5TB 虚拟地址空间
            │   （预期行为：应在数 GB 范围内停止）
            └─► page tables 膨胀至 6.4GB（PTE × ~860M 条目）
                    └─► 物理内存 16GB - 6.4GB page tables = 仅剩 ~9.6GB 可供匿名页/文件页
                            └─► allocstall 爆发：7,066 次直接分配 stall
                                    └─► pgscan 爆发：10.3M 页扫描（~40GB 虚拟地址遍历）
                                            └─► 直接回收效率 23%（pgsteal/pgscan = 2.4M/10.3M）
                                                    └─► kswapd 高水位快速命中 22 次（水位频繁震荡）
                                                            └─► 第一次 OOM killer (PID 20893)
                                                                    └─► 故障未彻底消除 → 新进程续跑 → 第二次 OOM (PID 21383)
                                                                            └─► 🔴 容器被迫重启
```

---

## 三、排查过程

### 3.1 初始现象

- **容器环境**: `pcr-witty`，运行 LTP/kernel selftests 风格内存压力测试
- **直接表象 1（用户感知）**: Python 进程 mmap 分配 4951MB 返回 ENOMEM
- **直接表象 2（系统告警）**: 两次 OOM killer 事件触发，进程被杀死
- **系统级告警信号**:
  - `allocstall_normal=2400`, `allocstall_movable=4666`（合计 7,066 次 direct reclaim stall）
  - `pgscan_direct=2,445,150`, `pgscan_kswapd=7,891,748`（合计 10.3M 页扫描）
  - `pgmajfault=40,198`（严重缺页中断异常）
  - `pgpgout=31,531,452`（约 126GB 换出 — 极大量）
  - PSI 累计: `some total=3,690,070`, `full total=3,656,733`

---

### 3.2 假设驱动排查（Hypotheses-Driven Analysis）

> 以下基于 `fault-rca-report-generation` 方法论，采用 **5 个独立假设** 对 page cache / reclaim 风暴进行系统性排查。

---

#### 假设 A：kswapd CPU 过载 / 水位震荡（kswapd High CPU / Watermark Thrashing）

> 🧪 **假设**: kswapd 内核线程因持续扫描大量页面而耗尽 CPU，导致无法及时补充 watermarks → 进程陷入 direct reclaim

**证据收集与验证：**

| 检查项 | 操作（基于诊断数据） | 结论 |
|--------|------|------|
| pgscan_kswapd | 7,891,748 页（约 30GB 虚拟地址扫描） | ✅ 极高 |
| kswapd_low_wmark_hit_quickly | 4 次 | ✅ kswapd 低水位被快速命中 |
| kswapd_high_wmark_hit_quickly | 22 次 | ✅ kswapd 高水位被快速命中 — 水位频繁震荡 |
| pageoutrun | 29 次 | ✅ kswapd 实际运行 |
| pgsteal_kswapd vs pgscan_kswapd | 回收 2,007,684 / 扫描 7,891,748 = 回收率 25% | ⚠️ 回收效率低 |
| 当前空闲内存 | 14.4GB（故障已消退，无法捕获实时 CPU） | ⏭ 仅能推断 |

**推理链路**:
- kswapd 在故障期间运行了 29 次，扫描 7.9M 页，但仅回收 2.0M 页（25% 效率）。
- 高水位命中 22 次说明：kswapd 刚把水位推高，又被快速消耗回落 → 典型 **thrashing 模式**。
- 直接原因：page tables 占用了 6.4GB 物理内存，导致可用页面池大幅缩小 → 水位易跌穿。

**✅ 确认子因子：kswapd 水位震荡属于回收效率低下的表现，是故障链中的中间态，非根因。**

---

#### 假设 B：Direct Reclaim 延迟与分配卡顿（Direct Reclaim Latency）

> 🧪 **假设**: 大量进程因 direct reclaim 而 stall，导致分配超时、内存分配全面堵塞

**证据收集与验证：**

| 检查项 | 操作（基于诊断数据） | 结论 |
|--------|------|------|
| allocstall_normal | 2,400 次 | ✅ 严重 |
| allocstall_movable | 4,666 次 | ✅ 非常严重 |
| pgscan_direct | 2,445,150 页 | ✅ 直接回收海量扫描 |
| pgsteal_direct | 仅 349,083 页 | ⚠️ 回收率仅 14% |
| PSI some total | 3,690,070 | ✅ 累计压力极大 |
| PSI full total | 3,656,733 | ✅ 进程长时间 stall |

**推理链路**:
- 7,066 次 direct reclaim stall 表明大量内存分配请求无法直接从 buddy 系统获取页面。
- 直接扫描 2.4M 页却只回收 349K 页（回收率 14%）→ 大量扫描未产生有效回收。
- 原因：被扫描的绝大多数页面是 `fault_reclaim_s` 的匿名页（pgscan_anon=9,804,683），但这些页面在 OOM kill 之前并未大量释放（被 active 引用）。

**✅ 确认子因子：direct reclaim 广泛发生、效率极低，是故障的症状而非根因。当回收率不足 15% 时，OOM killer 几乎是必然结局。**

---

#### 假设 C：脏页回写风暴（Dirty Writeback Storm）

> 🧪 **假设**: 大量脏页积压 → writeback 占满 IO → 页面回收卡在等待回写完成

**证据收集与验证：**

| 检查项 | 操作（基于诊断数据） | 结论 |
|--------|------|------|
| Dirty (当前) | 192 kB | ❌ 极少量 |
| Writeback (当前) | 0 | ❌ 无回写 |
| pgscan_file | 532,215 页 | ❌ 文件页扫描仅占 5% 总量 |
| pgsteal_file | 310,295 页 | ❌ 文件页回收很少 |
| 页类型占比 | anon:98% vs file:2% | ❌ 压力集中在匿名页，非文件页 |

**推理链路**:
- 回收压力集中在匿名页（pgscan_anon=9.8M vs pgscan_file=0.53M），文件页回写不是瓶颈。
- 当前 Dirty 极低（192KB），Writeback=0，故障期间也未见脏页爆发迹象（文件页扫描才 0.5M 页）。
- 压力测试工具 `fault_reclaim_s` 主要分配匿名映射（mmap MAP_ANONYMOUS），不涉及文件脏页。

**❌ 排除**：脏页回写风暴不是本次故障的贡献因素。回收风暴是匿名页驱动，与文件页回写无关。

---

#### 假设 D：Page Cache 过度使用 / 缓存膨胀（Page Cache Overuse）

> 🧪 **假设**: page cache 占用过多内存 → 压缩了可用匿名页空间 → 加剧回收压力

**证据收集与验证：**

| 检查项 | 操作（基于诊断数据） | 结论 |
|--------|------|------|
| Cached (当前) | 231,624 kB (~226MB) | ❌ 正常水平 |
| Active(file) | 56,396 kB (~55MB) | ❌ 正常 |
| Inactive(file) | 178,940 kB (~175MB) | ❌ 正常 |
| unevictable | 0 | ❌ 无不回收页 |
| cgroup inactive_file | 8,351,744 字节 (~8MB) | ❌ 正常 |
| cgroup active_file | 5,816,320 字节 (~5.5MB) | ❌ 正常 |

**推理链路**:
- 无论当前（226MB cache）还是故障时（cgroup 统计仅 ~13.5MB 文件页），page cache 占比均微不足道。
- 16GB 系统内存被 page tables 占据 6.4GB（40%），而非 page cache。
- 主力压力来源于 `fault_reclaim_s` 匿名页分配，不是 page cache 膨胀导致。

**❌ 排除**：Page cache 占用正常，不是回收压力的来源。真正的物理内存吞噬者是 **page tables**，而非 page cache。

---

#### 假设 E：drop_caches 人为触发 / 误操作（drop_caches Misuse）

> 🧪 **假设**: 有人工执行 `echo 3 > /proc/sys/vm/drop_caches` 或类似操作，强制清空 page cache → 触发大量 refault 和回收

**证据收集与验证：**

| 检查项 | 操作（基于诊断数据） | 结论 |
|--------|------|------|
| workingset_refault_file | 444 次 | ❌ 极低 refault |
| workingset_refault_anon | 154 次 | ❌ 极低 refault |
| kswapd_high_wmark_hit_quickly | 22 次 — 但非典型 drop_caches 后模式 | ❌ 不匹配 |
| Cached 仅 226MB | 已无 cache 可 drop | ❌ 当前无证据 |
| NR 压力集中于匿名页 | drop_caches 主要影响文件页 | ❌ 不匹配 |

**推理链路**:
- drop_caches 触发后，典型现象是：page cache 瞬间暴跌 → 后续访问大量 refault（refault 计数器显著升高）。但这里 refault 值极低（444 file + 154 anon）。
- 回收压力 98% 集中在匿名页，这与 drop_caches（作用于文件页）的行为不符。
- 压力测试为明显预期行为（LTP/kernel selftests 风格），无人工误操作线索。

**❌ 排除**：drop_caches 误操作未在本故障中发生。

---

### 3.3 排查结论与逻辑树

```text
mmap ENOMEM → 容器 OOM 系统回收风暴
│
├─► HYPOTHESIS C: 脏页回写风暴            → ❌ 排除（匿名页占 98%，无脏页/回写）
├─► HYPOTHESIS D: Page Cache 过度使用     → ❌ 排除（cache 仅 226MB，非根因）
├─► HYPOTHESIS E: drop_caches 误操作      → ❌ 排除（refault 极低，压力在匿名页）
│
├─► HYPOTHESIS A: kswapd 水位震荡          → ✅ 确认（高水位命中 22 次，thrashing 模式）
│       └─► 但此为中间传导，非根因
│
├─► HYPOTHESIS B: Direct Reclaim 低效      → ✅ 确认（7K+ stall，回收率 <15%）
│       └─► 此为故障症状，非根因
│
└─► 🎯 根因确认（双重触发）
        │
        ├─► 【触因 1】容器 vm.max_map_count=5000
        │       └─► Python PID 33 mmap 4.95GB 提前触达 VMA 上限 → ENOMEM
        │       └─► 证据：当前值 5000（仅为默认 65530 的 7.6%）
        │       └─► 证据：overcommit_memory=1（非 overcommit 导致）
        │       └─► 置信度：🟡 中（故障进程已销毁，VMA 实时数据不可得）
        │
        └─► 【触因 2】fault_reclaim_s 异常分配 6.5TB 虚拟地址空间
                └─► page tables 膨胀至 6.4GB（PTE × 860M 条目）
                └─► 物理内存 40% 被页表吞噬
                └─► allocstall 7,066 次 + pgscan 10.3M 页 → 回收率 23%
                └─► 2 次 OOM killer 触发
                └─► 置信度：🟢 高（dmesg OOM 日志、vmstat 数据明确）
```

---

## 四、关键数据交叉验证

### mmap ENOMEM 层（T2 证据）

| 参数 | 当前值 | 内核默认值 | 降幅 | 风险 |
|------|--------|-----------|------|------|
| `vm.max_map_count` | 5,000 | 65,530 | 92.4% 缩减 | 🔴 临界 — Java/Python 大量 mmap 极易触顶 |
| `overcommit_memory` | 1 (Always) | 0 (Heuristic) | — | 🟢 非限制因素 |
| `Committed_AS` | ~2.2GB | — | — | 🟢 当前正常 |

### 内存回收层（T1 证据）

| 计数器 | 值 | 物理含义 |
|--------|----|---------|
| `allocstall_normal + allocstall_movable` | 7,066 次 | 每次代表一次分配 stall，严重程度极高 |
| `pgscan_direct` | 2,445,150 页 | 直接回收扫描 ~9.3GB，占整体扫描 24% |
| `pgscan_kswapd` | 7,891,748 页 | kswapd 扫描 ~30GB |
| `pgsteal_total` | 2,356,767 页 | 回收 ~9GB，整体回收率 23% |
| `pgsteal_direct` | 349,083 页 | 直接回收仅 ~1.3GB，回收率 14% |
| `pgpgin / pgpgout` | 4.9M / 31.5M 页 | 大量换入换出（swap thrashing） |
| `pgmajfault` | 40,198 次 | 严重缺页中断激增 |

### OOM Killer 层（T1 证据）

| 事件 | 时间 (UTC) | PID | total-vm | pgtables |
|------|-----------|-----|----------|----------|
| 1st OOM | 2026-05-25 14:34:44 | 20893 | 6,556,265,176 kB (~6.5TB) | 6,427,712 kB (~6.1GB) |
| 2nd OOM | 2026-05-25 14:39:51 | 21383 | 6,538,320,600 kB (~6.5TB) | 6,410,112 kB (~6.1GB) |

---

## 五、修复方案

### 5.1 应急处置

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | OOM killer 自动触发，已杀死异常进程 | 内核 | 14:34 / 14:39 UTC | 短期恢复 |
| 2 | 容器自动/手动重启（当前仅剩 PID 1: sleep） | 编排系统/人工 | 14:40+ UTC | 故障已消退 |
| 3 | 当前状态确认：MemFree=14.4GB, Cached=226MB, PageTables=6.5MB | 人工 | 22:40 UTC | ✅ 系统正常 |

### 5.2 永久修复计划

| 修复措施 | 具体操作 | 负责人 | 优先级 | 完成时间 |
|---------|---------|--------|--------|---------|
| **提高 `vm.max_map_count`** | 在容器 Dockerfile 或启动参数中设置 `--sysctl vm.max_map_count=262144`（或显式调至 65530+） | 容器平台团队 | P0 | 尽快 |
| **约束容器内存上限** | 设置 `memory.max` 为合理值（如 8GB～12GB），避免单容器耗尽全局 Buddy 内存池 | 容器平台团队 | P1 | 尽快 |
| **修复压力测试工具** | `fault_reclaim_s` 分配 6.5TB 虚拟地址空间属异常行为，应修复为合理范围分配（如 <64GB 虚拟地址） | 测试开发团队 | P1 | 下个迭代 |
| **内核参数持久化** | `/etc/sysctl.d/99-override.conf` 中添加 `vm.max_map_count=262144`，cgroup namespace 不覆写此值 | 基础架构团队 | P1 | 下个迭代 |
| **监控告警增强** | 增加 page tables 使用率监控（>1GB 告警）、allocstall 计数监控（>100/min 告警） | 监控团队 | P2 | 下个迭代 |

### 5.3 恢复脚本参考

如需在运行中修改容器 sysctl 参数（以 Docker 为例）：

```bash
# 方式一：容器启动时设置
docker run --sysctl vm.max_map_count=262144 ...

# 方式二：已有容器（需重启）
docker update --sysctl vm.max_map_count=262144 pcr-witty
docker restart pcr-witty
```

---

**报告生成于**: 2026-05-25 22:40:00 UTC
**数据来源**:
- [`G:\witty-diagnosis-agent\dayu\report\kuafu_T1_20260525_224030_oom_reclaim.md`]
- [`G:\witty-diagnosis-agent\dayu\report\kuafu_T2_20260525_224030_mmap_enomem.md`]
