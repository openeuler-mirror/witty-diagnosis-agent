---
name: page-cache-reclaim-diagnosis
description: >
  页缓存与内存回收异常诊断技能。覆盖 kswapd 高 CPU（频繁回收）、direct reclaim 导致进程
  延迟抖动（allocstall 计数飙升）、dirty page writeback 风暴（dirty_ratio/dirty_background_ratio
  配置不当）、page cache 过度占用导致可用内存假告警、drop_caches 误用引发 I/O 风暴等场景。
  当用户提到 kswapd CPU 高、内存回收、direct reclaim、allocstall、dirty page writeback、
  page cache 过高、可用内存不足、drop_caches、I/O 风暴、内存压力、zone reclaim、
  kswapd0 CPU 100%、内存抖动等问题时，必须使用此 skill。
---

# 页缓存与内存回收异常诊断 Skill

## 第一节：概述

本 skill 提供系统化的页缓存（Page Cache）与内存回收（Reclaim）故障分析方法论，覆盖以下核心场景：

- **kswapd 高 CPU**：内核线程 kswapd0 持续占用高 CPU，频繁扫描 LRU 链表回收页面
- **direct reclaim 延迟抖动**：进程在内存分配路径上直接参与回收（direct reclaim），导致 allocstall 计数飙升和业务延迟抖动
- **dirty page writeback 风暴**：脏页回写配置不当（dirty_ratio / dirty_background_ratio）导致突发的密集 I/O 写入
- **page cache 过度占用**：文件缓存过度消耗内存，导致可用内存持续偏低，触发误告警
- **drop_caches 误用引发 I/O 风暴**：手动清理 page cache 后大量文件访问触发缺页，引发磁盘 I/O 风暴

> **重要原则**：本 skill 仅进行信息收集和分析诊断，**不执行任何修复命令**，只给出修复建议。所有修复操作需由用户确认后手动执行。

---

## 第二节：文件结构

```text
page-cache-reclaim-diagnosis/
├── SKILL.md                                # 诊断流程文档
├── references/
│   ├── page_cache_reclaim_scenarios.md     # 故障场景分类与特征表
│   ├── kernel_page_cache_reclaim.md        # 内核页缓存与回收子系统参考
│   └── sysctl_vm_tuning.md                # sysctl vm 参数调优指南
├── scripts/
│   ├── collect_page_cache_info.sh          # 页缓存综合信息收集脚本（基线）
│   ├── diagnose_kswapd.sh                  # kswapd 高 CPU 诊断（分支 A）
│   ├── diagnose_direct_reclaim.sh          # direct reclaim 延迟诊断（分支 B）
│   ├── diagnose_dirty_writeback.sh         # 脏页回写风暴诊断（分支 C）
│   ├── diagnose_page_cache_overuse.sh      # page cache 过度占用诊断（分支 D）
│   └── diagnose_drop_caches.sh             # drop_caches 误用诊断（分支 E）
├── docs/                                   # 测试报告
│   └── ...
└── Dockerfile.test                         # Docker 测试环境
```

---

## 第三节：分析策略（假设驱动 + 分支验证）

**本 skill 采用假设驱动（Hypothetico-Deductive）的分析模型**：

```
┌──────────────────────────────────────────────────────────────────┐
│              页缓存/内存回收故障分析模型                           │
│                                                                  │
│  第一层：症状识别（关键词匹配）    第二层：假设驱动排查             │
│  ────────────────────────────    ────────────────────────        │
│  从用户描述中自动识别故障症状      对每个症状构建多假设树           │
│                                                                  │
│  回答：什么症状？走哪条诊断        回答：为什么发生？如何验证       │
│        路径？                          哪个假设被证实？            │
│                                                                  │
│            ↓                              ↓                      │
│    ┌──────────────┐              ┌──────────────────┐            │
│    │  Step 1-2    │              │   Step 3-7       │            │
│    └──────────────┘              └──────────────────┘            │
│                                                                  │
│  见：第四节（统一分析流程）                                        │
└──────────────────────────────────────────────────────────────────┘
```

### 分析原则

| 原则 | 说明 |
|------|------|
| **时间锚定** | 所有分析以故障时间 T0 为锚点，时间窗口默认 T0±30min |
| **证据驱动** | 每个结论必须有 `/proc` 指标、内核事件或系统日志作为支撑（至少 2 个独立来源） |
| **区分现象与根因** | kswapd CPU 高是现象，LRU 不平衡或内存压力过大才是根因 |
| **只读原则** | 诊断阶段严格只读，不执行任何修复命令 |
| **量化表达** | 报告中的内存/时间/计数数据尽量给出具体数值 |
| **内核版本感知** | 不同内核版本（5.x vs 6.x）的回收行为有差异，需标注版本 |

---

## 第四节：统一分析流程（症状识别 → 基线收集 → 分支定界 → 假设验证 → 排除确认 → 输出报告）

> 执行约束：所有分析脚本的默认超时时间为 **3 分钟（180s）**。

### Step 1：症状自动识别（关键词匹配）

直接从用户的故障描述中提取关键信息，**不询问用户**，自主判断后立即进入分析流程。

| 用户描述关键词 | 判断症状 | 推荐分支 |
|--------------|----------|----------|
| kswapd / kswapd0 / 内存回收线程 / CPU 100% / 内核线程高 / reclaim 线程忙 | kswapd 高 CPU | → 分支 A |
| direct reclaim / allocstall / 分配延迟 / 分配阻塞 / 进程 stall / 内存分配慢 / 调度延迟 | direct reclaim 延迟抖动 | → 分支 B |
| dirty page / 脏页 / writeback / 回写 / dirty_ratio / 写延迟 / IO 风暴 / 磁盘写满 | dirty page writeback 风暴 | → 分支 C |
| page cache / 文件缓存 / 缓存占用过高 / 可用内存低 / 内存告警 / Cached 高 | page cache 过度占用 | → 分支 D |
| drop_caches / 清理缓存 / 缓存释放 / 清空 page cache / 释放内存后 / 磁盘 IO 暴增 | drop_caches 误用 | → 分支 E |

> 如果描述同时命中多个症状（如"direct reclaim 导致 kswapd 也升高"），优先以用户最关注的现象为主，同时关联分析其他路径。

从用户输入中自动提取以下信息，**已有则直接使用，缺失才补充询问**：

- **故障时间**：用户已提供时直接作为锚点 T0；**未提供时才询问**
- **目标进程**：用户已提到进程名/PID 时直接使用；系统级故障（如 kswapd）无需询问

---

### Step 2：基线信息收集（页缓存与回收综合信息收集）

📄 **脚本**：`scripts/collect_page_cache_info.sh`

**参数说明**：

| 参数 | 含义 | 是否必填 |
|------|------|---------|
| `-S <时间>` | 故障时间段开始时间，格式 `YYYY-MM-DD HH:MM:SS` | 强烈建议 |
| `-E <时间>` | 故障时间段结束时间，未填则默认 +1 小时 | 可选 |
| `-p <PID>` | 精确进程 ID，定位单个进程 | 可选 |
| `-n <名称>` | 模糊进程名 | 可选 |

**调用示例**：

```bash
# 系统级全量分析
bash collect_page_cache_info.sh -S "2024-01-15 14:00:00"

# 特定 PID
bash collect_page_cache_info.sh -S "2024-01-15 14:00:00" -p 12345
```

该脚本**一次性完成**以下所有收集：

| 输出类型 | 内容 | 说明 |
|---------|------|------|
| 终端直接输出 | 内存压力指标、回收活动、脏页状态、异常标记 | 附带诊断说明 |
| 文件输出 | 完整 `/proc/vmstat`、`/proc/meminfo`、`/proc/zoneinfo` 等 | 保存到 `/tmp/page_cache_diag_*/` |

**收集范围**：

1. **内存压力概览**：`/proc/meminfo`（MemFree, MemAvailable, Cached, Dirty, Writeback, Mlocked, Unevictable）
2. **回收活动统计**：`/proc/vmstat`（pgscan_kswapd, pgscan_direct, allocstall, kswapd_steal, kswapd_inodesteal）
3. **内存分配延迟**：`/proc/vmstat`（allocstall_dma, allocstall_normal, allocstall_movable）
4. **脏页状态**：`/proc/vmstat`（nr_dirty, nr_writeback, nr_dirty_threshold, nr_dirty_background_threshold）
5. **kswapd 状态**：`/proc/[pid]/status`（kswapd0 PID）、`ps aux` 确认 kswapd CPU 使用率
6. **LRU 链表大小**：`/proc/zoneinfo`（nr_active_anon, nr_inactive_anon, nr_active_file, nr_inactive_file）
7. **NUMA 节点状态**：`/sys/devices/system/node/node*/vmstat`
8. **drop_caches 计数器**：`/proc/sys/vm/drop_caches` 当前值
9. **内核日志**：`dmesg` + `journalctl`（搜索 reclaim/allocstall/OOM 关键词）
10. **内核配置**：`sysctl vm.dirty_ratio`, `vm.dirty_background_ratio`, `vm.vfs_cache_pressure`, `vm.swappiness`, `vm.min_free_kbytes`

**基线输出**（供后续分支判断使用）：

```
MemFree：<value>  MemAvailable：<value>  Cached：<value>
Dirty：<value>  Writeback：<value>
pgscan_kswapd：<value>  pgscan_direct：<value>  allocstall：<value>
kswapd CPU：<value>%
nr_dirty_threshold：<value>  dirty_ratio：<value>  dirty_background_ratio：<value>
内核日志异常关键词：[kswapd/reclaim/OOM/allocstall/无]
```

---

### Step 3：故障分支定界

按 Step 1 识别结果 + Step 2 基线输出，执行对应分支脚本：

```bash
# 分支 A：kswapd 高 CPU
bash scripts/diagnose_kswapd.sh -S "<time>" [-p PID]

# 分支 B：direct reclaim 延迟
bash scripts/diagnose_direct_reclaim.sh -S "<time>" [-p PID]

# 分支 C：脏页回写风暴
bash scripts/diagnose_dirty_writeback.sh -S "<time>"

# 分支 D：page cache 过度占用
bash scripts/diagnose_page_cache_overuse.sh -S "<time>"

# 分支 E：drop_caches 误用
bash scripts/diagnose_drop_caches.sh -S "<time>"
```

脚本对应参考：

```
页缓存/回收异常
  ├─ 关键词含 "kswapd" / "reclaim 线程" / "CPU 100%"        → 分支 A: kswapd 高 CPU
  ├─ 关键词含 "allocstall" / "direct reclaim" / "分配延迟"     → 分支 B: direct reclaim 延迟
  ├─ 关键词含 "dirty" / "writeback" / "dirty_ratio"           → 分支 C: 脏页回写风暴
  ├─ 关键词含 "Cached 高" / "可用内存低" / "page cache 告警"  → 分支 D: page cache 过度占用
  └─ 关键词含 "drop_caches" / "清理缓存" / "IO 暴增"          → 分支 E: drop_caches 误用
```

---

### Step 4：假设驱动排查（逐假设验证）

基于 Step 2 基线数据 + Step 3 分支输出，对当前症状构建**多假设树**。

#### 分支 A 示例：kswapd 高 CPU

```text
kswapd0 CPU 高
├─► 假设 A1: 内存严重不足 → pgscan_kswapd 高 + 频繁扫描 LRU
├─► 假设 A2: LRU 链表不平衡 → 大量 unevictable 页面阻塞回收
├─► 假设 A3: NUMA 节点内存不均衡 → 跨节点回收代价高
├─► 假设 A4: 内存碎片化 → 高阶页面分配频繁触发 compaction
├─► 假设 A5: 内核内存泄漏（slab/vmalloc）→ 不可回收内存持续增长
└─► 假设 A6: swap 颠簸 → 大量匿名页换入换出
```

#### 分支 B 示例：direct reclaim 延迟抖动

```text
allocstall 飙升 + 进程延迟抖动
├─► 假设 B1: 内存分配速度超过kswapd回收 → 进程被迫直接回收
├─► 假设 B2: min_free_kbytes 过小 → 内存水位线过低，kswapd 启动过晚
├─► 假设 B3: 大量 THP 大页分配 → 需要连续内存触发 compaction
├─► 假设 B4: cgroup memory 限制 → 容器/cgroup 内内存不足触发直接回收
├─► 假设 B5: 不可中断 D 进程堆积 → IO 等待导致回收路径阻塞
```

#### 分支 C 示例：脏页回写风暴

```text
dirty page writeback 风暴
├─► 假设 C1: dirty_ratio 过大 → 脏页积累过多后一次性回写
├─► 假设 C2: dirty_background_ratio 过小 → kswapd 过早开始刷脏页
├─► 假设 C3: 磁盘带宽不足 → 回写速度跟不上脏页生成速度
├─► 假设 C4: 特定文件系统瓶颈 → ext4/xfs journal 提交延迟
├─► 假设 C5: 存储设备队列深度过小 → 回写 IO 被限流
```

#### 分支 D 示例：page cache 过度占用

```text
Cached 持续高位 + MemAvailable 告警
├─► 假设 D1: 大量文件读操作 → page cache 自然增长
├─► 假设 D2: vfs_cache_pressure 过小 → 缓存回收优先级低
├─► 假设 D3: 应用层的 mmap 文件映射未释放 → 映射文件占用 page cache
├─► 假设 D4: tmpfs/shmem 占用过多 → 匿名页计入 Cached
├─► 假设 D5: 内核回收行为异常 → 可回收页面未被正常回收
```

#### 分支 E 示例：drop_caches 误用

```text
echo 3 > /proc/sys/vm/drop_caches 后 I/O 风暴
├─► 假设 E1: 大量文件访问触发缺页 → 清理后所有文件需要重新读盘
├─► 假设 E2: 数据库/WAL 文件 mmap 映射 → 清理后触发大量磁盘读
├─► 假设 E3: 容器共用宿主 page cache → 清理影响所有容器
├─► 假设 E4: HDD 而非 SSD → 随机读性能差放大了 I/O 影响
└─► 假设 E5: 频繁执行 drop_caches → page cache 反复重建
```

**每验证一个假设，填写验证记录**：

```
假设：<假设名>
验证操作：<具体命令或检查方法>
验证结果：[✅ 确认根因 | ❌ 已排除 | ⚠️ 待进一步验证]
排除依据（如适用）：<具体数据>
```

---

### Step 5：反事实验证（强制；不能止步于"找到原因"）

用根因假设正向推演，与观测现象逐条对齐：

```
✓ 推演的回收原因 == 实际的 `/proc/vmstat` 计数增长？
✓ 推演的触发条件 == 系统的 sysctl 参数配置？
✓ 推演的故障链路 == 实际的 kswapd/direct reclaim/dirty 回写时间序列？
```

**三条全 ✓ 才能判定"根因确认"**。若不通过，回到 Step 4 补充证据或构建新假设。

---

### Step 6：排除的替代假设

明确记录排除了哪些假设及其排除依据：

```
- 假设A3（NUMA 不均衡）：排除原因 单 NUMA 节点，无跨节点访问
- 假设B2（min_free_kbytes 过小）：排除原因 当前值 67584，符合 4% 规则
- 假设C3（磁盘带宽不足）：排除原因 磁盘 iostat 显示 avgqu-sz < 1
```

---

### Step 7：置信度评级

| 等级 | 标识 | 含义 |
|------|------|------|
| 高置信 | 🟢 | 根因已明确，反事实验证全通过，排除所有替代假设 |
| 中置信 | 🟡 | 根因基本确认，但有 1-2 个维度依赖推断 |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 |

---

### Step 8：最终输出（按第七节报告模板落盘）

将 Step 4/5/6/7 的输出填入第七节报告结构。

---

## 第五节：分场景深度分析

### 分支 A：kswapd 高 CPU

#### 触发条件

> **先执行专项采集脚本**。

```bash
bash diagnose_kswapd.sh -S "2024-01-15 14:00:00" [-p PID]
```

#### 诊断依据

kswapd 是 Linux 内核的内存回收守护进程。当系统内存低于水位线（watermark）时，kswapd 被唤醒扫描 LRU 链表并回收页面。持续高 CPU 表示 kswapd 无法满足内存需求。

**关键诊断命令**：

```bash
# 确认 kswapd CPU
ps -eo pid,comm,%cpu,%mem --sort=-%cpu | grep kswapd
top -b -n1 | grep kswapd

# 查看回收统计
grep -E "pgscan_kswapd|pgsteal_kswapd|kswapd_steal|kswapd_inodesteal" /proc/vmstat

# 查看内存水位线
cat /proc/zoneinfo | grep -A3 "min\|low\|high"

# 查看 LRU 链表大小
cat /proc/zoneinfo | grep -E "nr_active|nr_inactive|nr_unevictable"

# 查看内存压力
grep -E "nr_free_pages|nr_inactive_file|nr_active_file|nr_dirty|nr_writeback" /proc/vmstat

# 查看内存碎片
cat /proc/buddyinfo

# 查看 slab 内存
grep -E "SUnreclaim|Slab" /proc/meminfo
```

**内核源码路径**：`mm/vmscan.c → balance_pgdat() → shrink_node()`（kswapd 主循环）

#### 假设驱动排查

```
假设 A1: 内存严重不足
  → 检查方法: 对比 MemFree + Cached 与 MemTotal
  → 判定条件: MemAvailable < 10% MemTotal 且 pgscan_kswapd 持续增长

假设 A2: LRU 链表不平衡
  → 检查方法: 查看 zoneinfo 中 active/inactive 页面比例
  → 排除条件: nr_active / nr_inactive > 5 或 < 0.2

假设 A3: NUMA 内存不均衡
  → 检查方法: numactl --hardware 查看节点内存分布
  → 排除条件: 单 NUMA 节点

假设 A4: 内存碎片化
  → 检查方法: cat /proc/buddyinfo
  → 判定条件: 所有 order > 3 均不可用

假设 A5: 内核 slab 泄漏
  → 检查方法: cat /proc/meminfo | grep SUnreclaim
  → 判定条件: SUnreclaim 持续增长且无下降趋势
```

---

### 分支 B：direct reclaim 延迟抖动

#### 触发条件

```bash
bash diagnose_direct_reclaim.sh -S "2024-01-15 14:00:00" [-p PID]
```

#### 诊断依据

Direct reclaim 发生在进程的内存分配路径上 — 当 kswapd 无法及时补充空闲页面时，分配线程直接参与页面回收。这会导致进程被阻塞在内存分配上，产生明显的延迟抖动。

**关键诊断命令**：

```bash
# 查看 direct reclaim 计数
grep -E "pgscan_direct|allocstall|pgsteal_direct|compact_stall" /proc/vmstat

# 查看内存分配延迟分布
cat /proc/zoneinfo | grep -A5 "protection"

# 查看 min_free_kbytes
sysctl vm.min_free_kbytes

# 查看 watermark_scale_factor
sysctl vm.watermark_scale_factor

# 查看各 zone 的 watermark
cat /proc/zoneinfo | grep -E "pages free|min|low|high"

# 查看 THP 分配统计
grep -E "thp_fault_alloc|thp_collapse_alloc" /proc/vmstat

# 查看是否大量 D 进程
ps -eo pid,stat,wchan,comm | grep "^.* D"
```

**内核源码路径**：`mm/vmscan.c → try_to_free_pages()`（direct reclaim 入口）

#### 假设驱动排查

```
假设 B1: kswapd 回收不足
  → 检查方法: 对比 pgscan_direct / pgscan_kswapd 比例
  → 判定条件: pgscan_direct > 20% * pgscan_kswapd

假设 B2: min_free_kbytes 过小
  → 检查方法: sysctl vm.min_free_kbytes
  → 判定条件: 小于 MemTotal * 0.4% 时风险高

假设 B3: THP/大页分配触发 compaction
  → 检查方法: compact_stall 计数
  → 判定条件: compact_stall > 0 且有 THP 分配

假设 B4: cgroup memory 限制
  → 检查方法: cat /proc/self/cgroup
  → 判定条件: 容器内有 memory.max 限制

假设 B5: IO 等待阻塞回收路径
  → 检查方法: 检查 D 进程 + iostat 高 await
  → 判定条件: 大量 D 进程 + 磁盘 await > 100ms
```

---

### 分支 C：dirty page writeback 风暴

#### 触发条件

```bash
bash diagnose_dirty_writeback.sh -S "2024-01-15 14:00:00"
```

#### 诊断依据

Linux 使用两套阈值控制脏页回写：`dirty_background_ratio`（后台回写阈值）和 `dirty_ratio`（同步回写阈值）。配置不当可能导致脏页大量积累后一次性刷出，形成 I/O 风暴。

**关键诊断命令**：

```bash
# 查看脏页配置
sysctl vm.dirty_ratio
sysctl vm.dirty_background_ratio
sysctl vm.dirty_writeback_centisecs
sysctl vm.dirty_expire_centisecs

# 查看当前脏页状态
grep -E "Dirty|Writeback|WritebackTmp" /proc/meminfo

# 查看脏页阈值
cat /proc/sys/vm/dirty_background_bytes
cat /proc/sys/vm/dirty_bytes

# 查看磁盘写 IO
iostat -x 1 5 | grep -E "Device|sda|vda|nvme"

# 查看回写统计
grep -E "nr_dirty|nr_writeback|nr_dirty_threshold|nr_dirty_background_threshold" /proc/vmstat

# 查看哪个进程在写大量数据
iotop -oP -n1 2>/dev/null || echo "iotop not available"
```

**内核源码路径**：`mm/page-writeback.c → balance_dirty_pages()`（脏页平衡），`fs/fs-writeback.c`（回写线程）

#### 假设驱动排查

```
假设 C1: dirty_ratio 过大
  → 检查方法: sysctl vm.dirty_ratio
  → 判定条件: > 30% 时脏页积累风险高

假设 C2: dirty_background_ratio 过小
  → 检查方法: sysctl vm.dirty_background_ratio
  → 判定条件: < 5% 时 kswapd 过早回写

假设 C3: 磁盘带宽不足
  → 检查方法: iostat -x 1
  → 判定条件: avgqu-sz > 10 或 await > 50ms

假设 C4: 文件系统 journal 延迟
  → 检查方法: 查看文件系统类型和挂载参数
  → 判定条件: ext4 且 data=journal 模式

假设 C5: IO 队列深度过小
  → 检查方法: block device queue depth
  → 排除条件: SSD 通常 NR_REQUESTS=128 足够
```

---

### 分支 D：page cache 过度占用

#### 触发条件

```bash
bash diagnose_page_cache_overuse.sh -S "2024-01-15 14:00:00"
```

#### 诊断依据

Page cache 是 Linux 的文件缓存。正常情况下系统会根据内存压力自动回收，但在某些配置下 page cache 可能过度占用导致 MemAvailable 告警。

**关键诊断命令**：

```bash
# 查看缓存占用
grep -E "Cached|MemTotal|MemFree|MemAvailable|Buffers" /proc/meminfo

# 计算 page cache 占比
echo "scale=2; $(grep ^Cached /proc/meminfo | awk '{print $2}') / $(grep ^MemTotal /proc/meminfo | awk '{print $2}') * 100" | bc

# 查看缓存回收倾向
sysctl vm.vfs_cache_pressure
sysctl vm.swappiness

# 查看活跃/非活跃文件页面
grep -E "nr_active_file|nr_inactive_file" /proc/vmstat

# 查看哪些文件占用了大量 page cache
finfo(){ find /proc/*/fd -lname "$1*" 2>/dev/null | cut -d/ -f3 | xargs -I '{}' ps -o comm= -p '{}' | sort | uniq -c; }
# 查看大文件缓存占用（需要 linux-page-cache 工具或 fincore）

# 查看 tmpfs 使用
df -h /dev/shm
grep -E "Shmem|ShmemHugePages" /proc/meminfo
```

#### 假设驱动排查

```
假设 D1: 大量文件读操作
  → 检查方法: 对比 Cached 与 MemTotal 占比
  → 判定条件: Cached > 70% MemTotal 且有大量文件读取

假设 D2: vfs_cache_pressure 过小
  → 检查方法: sysctl vm.vfs_cache_pressure
  → 判定条件: < 50 时缓存回收不积极

假设 D3: tmpfs/shmem 占用
  → 检查方法: grep Shmem /proc/meminfo
  → 排除条件: Shmem < 10% Cached

假设 D4: 应用 mmap 文件映射
  → 检查方法: lsof 或 pmap 查看进程
  → 判定条件: 大量数据库/ES 类进程有文件 mmap

假设 D5: 内核回收行为异常
  → 检查方法: pgscan 计数变化
  → 排除条件: pgscan 正常增长说明回收在正常进行
```

---

### 分支 E：drop_caches 误用引发 I/O 风暴

#### 触发条件

```bash
bash diagnose_drop_caches.sh -S "2024-01-15 14:00:00"
```

#### 诊断依据

`/proc/sys/vm/drop_caches` 用于手动清理 page cache、dentries 和 inode 缓存。清理后所有文件访问都会触发磁盘 I/O，若清理了大量热数据 cache，将导致严重的 I/O 风暴。

**关键诊断命令**：

```bash
# 查看 drop_caches 当前值
cat /proc/sys/vm/drop_caches

# 查看清理前后的 Cached 变化
grep Cached /proc/meminfo

# 查看清理后磁盘 IO
iostat -x 1 5 | grep -E "Device|r/s|w/s|await"

# 查看清理后的缺页异常
grep -E "pgfault|pgmajfault" /proc/vmstat

# 查看系统日志是否有 drop_caches 记录
journalctl -k --since="<time>" | grep -i "drop_caches"

# 查看 audit 日志
ausearch -m SYSCALL -k drop_caches 2>/dev/null | head -10
```

#### 假设驱动排查

```
假设 E1: 大量缺页触发 IO
  → 检查方法: 对比清理前后的 pgmajfault
  → 判定条件: pgmajfault 增长 > 10x

假设 E2: 数据库/文件密集型应用受影响
  → 检查方法: 检查主要进程是否使用 mmap 文件
  → 判定条件: mysqld/postgres/es 等进程有大量 mmap 文件

假设 E3: 机械硬盘（非 SSD）
  → 检查方法: cat /sys/block/vda/queue/rotational
  → 判定条件: 返回 1（HDD）时 IO 影响更大

假设 E4: 频繁执行 drop_caches
  → 检查方法: journalctl 或 history 检查执行记录
  → 判定条件: 1 小时内执行多次

假设 E5: 容器共用宿主 page cache
  → 检查方法: 检查容器数量和共享缓存情况
  → 判定条件: 多容器场景下影响面更广
```

---

## 第六节：注意事项与常见误判陷阱

### 常见误判陷阱

| 陷阱 | 说明 | 应对方式 |
|------|------|---------|
| **MemAvailable ≠ MemFree** | MemAvailable 包括可回收的 page cache，误认为可用内存低 | 计算 MemAvailable 而非 MemFree |
| **kswapd CPU 高 ≠ 内存不足** | 也可能是内存碎片化导致 compaction 频繁 | 区分 pgscan（回收）和 compact（碎片整理） |
| **Cached 高 ≠ 异常** | Linux 会尽量利用空闲内存做 cache，Cached 高通常是正常行为 | 关注 MemAvailable 而非 Cached 绝对值 |
| **drop_caches 不承诺"不卡顿"** | 清理热 cache 后会导致 I/O 风暴，但不是所有场景都有问题 | 在低峰期执行，且确认应用热数据大小 |
| **allocstall = 0 ≠ 无回收** | kswapd 的后台回收不计数到 allocstall | 同时检查 pgscan_kswapd |
| **dirty_ratio 仅对写入进程生效** | 非写入进程不受 dirty_ratio 限制 | 区分前台写入进程和后台回写进程 |
| **page cache = Cached + tmpfs** | Shmem（tmpfs）也计入 Cached | 查看 Cached - Shmem 才是纯文件缓存 |

### 内核版本注意事项

| 内核版本 | 相关变化 | 影响 |
|---------|----------|------|
| 5.4+ | 新增 PSI（Pressure Stall Information） | 提供更精准的内存压力衡量 |
| 5.10+ | LRU 锁优化（folio 替代 page） | 高并发回收场景性能提升 |
| 5.15+ | MGLRU（多代 LRU）可选 | 回收效率大幅提升，需显式启用 |
| 6.1+ | MGLRU 默认启用 | kswapd 行为显著变化 |
| 6.4+ | page cache batch 回写 | 脏页回写吞吐提升 |

---

## 第七节：最终报告结构

```markdown
# 🔴 页缓存/内存回收故障诊断报告

## 一、故障概览
- 故障标题：<根因类型>
- 故障级别：[P0(严重) | P1(高) | P2(中) | P3(低)]
- 影响范围：<受影响的进程/服务>
- 故障时段：<T0 ~ T1>
- 当前状态：[🔴 处理中 | 🟢 已恢复 | 🟡 待确认]
- 根因置信度：[🟢 高置信 | 🟡 中置信 | 🟠 低置信 | 🔴 未知]

## 二、根因速览
**根本原因**：<一句话描述>

### 故障因果链
```
[触发条件] → [中间环节] → [最终故障]
```

### 事故时间线
| 时间点 | 事件 | 证据来源 |
|--------|------|---------|
| T0 | <故障触发> | <dmesg/vmstat/日志> |

## 三、假设驱动排查
| 假设 | 验证操作 | 结果 | 排除依据 |
|------|---------|------|---------|
| <假设> | <方法> | 🎯 确认/❌ 排除 | <依据> |

## 四、关键证据
1. **证据1**：<描述> — 文件：<path> — 关键内容：<数据>

## 五、反事实验证
| 维度 | 推演结果 | 实际现象 | 是否吻合 |
|------|---------|---------|---------|
| 回收原因 | <推演> | <实际> | □ 是 □ 否 |

## 六、排除的替代假设
- **假设X**：排除原因 <具体数据>

## 七、修复建议
### 应急处置
1. <操作>
### 永久修复
1. <措施>
### 预防措施
1. <措施>

## 八、附件
- 诊断脚本输出：<路径>
- sysctl 配置快照：<路径>
```

---

## 第八节：故障模式速查表

| 故障模式 | 关键指标 | 一键诊断 | 内核源码路径 |
|---------|---------|---------|------------|
| kswapd 高 CPU | kswapd CPU > 20%, pgscan_kswapd 持续增长 | `diagnose_kswapd.sh` | `mm/vmscan.c → balance_pgdat()` |
| direct reclaim 延迟 | allocstall > 0, pgscan_direct 上升 | `diagnose_direct_reclaim.sh` | `mm/vmscan.c → try_to_free_pages()` |
| dirty writeback 风暴 | nr_dirty > dirty_background_threshold, IO await 高 | `diagnose_dirty_writeback.sh` | `mm/page-writeback.c → balance_dirty_pages()` |
| page cache 过度占用 | Cached > 70% MemTotal, MemAvailable < 20% | `diagnose_page_cache_overuse.sh` | `mm/filemap.c → __add_to_page_cache_locked()` |
| drop_caches 误用 | Cached 骤降 + pgmajfault 飙升 + IO 升高 | `diagnose_drop_caches.sh` | `fs/drop_caches.c → drop_pagecache_sb()` |

---

## 第九节：参考文件

- `references/page_cache_reclaim_scenarios.md`：故障场景分类与特征表
- `references/kernel_page_cache_reclaim.md`：内核页缓存与回收子系统参考资料
- `references/sysctl_vm_tuning.md`：sysctl vm 参数调优指南
- 内核源码：`mm/vmscan.c`（页面回收）、`mm/page-writeback.c`（脏页回写）、`mm/filemap.c`（page cache）、`fs/drop_caches.c`（缓存清理）
