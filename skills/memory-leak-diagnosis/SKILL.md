---
name: memory-leak-diagnosis
description: >
  用户态/内核态内存泄漏检测与诊断技能。用户态覆盖 RSS 持续增长趋势分析、
  /proc/[pid]/smaps 匿名页增长、valgrind/AddressSanitizer 报告解析；
  内核态覆盖 slab 增长（slabinfo/slabtop 趋势）、vmalloc 泄漏、
  kmalloc 未释放追踪、memcg 内存泄漏等场景。当用户提到
  内存泄漏、OOM、RSS 持续增长、内存占用不断上升、valgrind 报告泄露、
  slab 增长、kmemleak、vmalloc 泄漏、memcg 内存泄漏、
  memory.usage_in_bytes 持续增长、匿名页增长、进程内存越用越多、
  容器内存泄漏、内核内存泄漏、SUnreclaim 增长等问题时，必须使用此 skill。
---

# 用户态/内核态内存泄漏检测与诊断 Skill

## 第一节：概述

本 skill 提供系统化的内存泄漏故障分析方法论，覆盖以下核心场景：

- **用户态 RSS 持续增长**：进程 Resident Set Size 随时间递增不回落，最终触发 OOM
- **匿名页（Anon Pages）泄漏**：`/proc/[pid]/smaps` 中匿名页持续增长，heap 段异常
- **堆内存泄漏（Valgrind/ASan）**：通过 valgrind/AddressSanitizer 定位未释放的堆内存
- **Slab 内存泄漏**：内核 slab 缓存（`dentry`、`inode_cache`、`kmalloc-*`）持续增长
- **vmalloc 泄漏**：`/proc/vmallocinfo` 显示大量未释放的 vmalloc 区域
- **kmalloc 未释放**：`/proc/slabinfo` 中 kmalloc 缓存 active 对象持续增长
- **Memcg 泄漏**：cgroup 内存计数器持续增长但进程 RSS 未同步增长

> **重要原则**：本 skill 仅进行信息收集和分析诊断，**不执行任何修复命令**，只给出修复建议。所有修复操作需由用户确认后手动执行。

---

## 第二节：文件结构

```text
memory-leak-diagnosis/
├── SKILL.md                                # 诊断流程文档
├── references/
│   ├── memory_leak_scenarios.md           # 内存泄漏场景分类与特征表
│   ├── memory_leak_diagnosis_commands.md  # 内存泄漏诊断命令与工具参考
│   └── proc_mem_reference.md             # /proc 内存诊断参考
├── scripts/
│   ├── collect_mem_info.sh               # 内存综合信息收集脚本（基线）
│   ├── diagnose_rss_growth.sh            # RSS 持续增长诊断（分支 A）
│   ├── diagnose_anon_page.sh             # 匿名页泄漏诊断（分支 B）
│   ├── diagnose_heap_profiler.sh         # Valgrind/ASan 堆泄漏诊断（分支 C）
│   ├── diagnose_slab_leak.sh             # Slab 泄漏诊断（分支 D）
│   ├── diagnose_vmalloc_leak.sh          # vmalloc 泄漏诊断（分支 E）
│   ├── diagnose_kmalloc_leak.sh          # kmalloc 未释放诊断（分支 F）
│   ├── diagnose_memcg_leak.sh            # Memcg 泄漏诊断（分支 G）
│   ├── Dockerfile.test                   # Docker 测试环境
│   └── entrypoint.sh                     # 容器测试入口
├── docs/                                   # 测试报告
│   └── ...
└── references/
    ├── memory_leak_scenarios.md           # 内存泄漏场景分类与特征表
    ├── memory_leak_diagnosis_commands.md  # 内存泄漏诊断命令与工具参考
    └── proc_mem_reference.md             # /proc 内存诊断参考
```

---

## 第三节：分析策略（假设驱动 + 分支验证）

**本 skill 采用假设驱动（Hypothetico-Deductive）的分析模型**：

```
┌──────────────────────────────────────────────────────────────────┐
│             用户态/内核态内存泄漏分析模型                          │
│                                                                  │
│  第一层：症状识别（内存指标匹配）    第二层：假设驱动排查           │
│  ──────────────────────────────    ───────────────────────       │
│  从用户描述和系统指标中自动识别       对每个症状构建多假设树        │
│  故障场景                               │
│                                                                  │
│  回答：什么指标异常？走哪条诊断        回答：为什么泄漏？如何验证  │
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
| **时间锚定** | 所有分析以故障时间 T0 为锚点，内存趋势分析需至少采集 2 个时间点的数据 |
| **证据驱动** | 每个结论必须有 `/proc` 指标输出、进程状态或日志作为支撑（至少 2 个独立来源） |
| **区分现象与根因** | RSS 增长是现象，具体是 anonymous page / heap / slab / vmalloc 泄漏才是根因 |
| **只读原则** | 诊断阶段严格只读，不执行任何内存释放或进程重启命令 |
| **量化表达** | 报告中泄漏量尽量给出具体值（MB/h 增长速率、泄漏对象数、分配栈）|

---

## 第四节：统一分析流程（症状识别 → 基线收集 → 分支定界 → 假设验证 → 排除确认 → 输出报告）

> 执行约束：所有分析脚本的默认超时时间为 **3 分钟（180s）**。

### Step 1：症状自动识别（关键词匹配）

直接从用户的故障描述和系统指标中提取关键信息，**不询问用户**，自主判断后立即进入分析流程。

| 用户描述关键词 / 系统指标 | 判断症状 | 推荐分支 |
|--------------------------|----------|----------|
| RSS 持续增长 / 进程内存越用越多 / VmRSS 不断上升 | 用户态 RSS 增长 | → 分支 A |
| 匿名页增长 / AnonPages 上升 / /proc/pid/smaps Anonymous | 匿名页泄漏 | → 分支 B |
| valgrind 报告 leak / definitely lost / AddressSanitizer / ASan 报告泄漏 | 堆泄漏 | → 分支 C |
| slab 增长 / slabtop 活跃对象上涨 / SUnreclaim 上升 / dentry/inode_cache 增长 | Slab 泄漏 | → 分支 D |
| vmalloc 泄漏 / VmallocUsed 增长 / /proc/vmallocinfo 大量未释放 | vmalloc 泄漏 | → 分支 E |
| kmalloc 未释放 / kmemleak 报告 / kmalloc-* active 对象增长 | kmalloc 未释放 | → 分支 F |
| memcg 泄漏 / memory.usage_in_bytes 增长 / 容器内存泄漏 | Memcg 泄漏 | → 分支 G |

> 如果描述同时命中多个症状（如"RSS 增长且 slab 也在涨"），优先排查用户态（A/B/C），再排查内核态（D/E/F/G）。

从用户输入中自动提取以下信息，**已有则直接使用，缺失才补充询问**：

- **目标进程 PID 或进程名**：用户已提供时直接使用；**未提供时才询问**
- **故障时间窗口**：用户已提供时作为锚点 T0；**未提供时以当前时间为准**
- **系统环境**：是否容器环境、内核版本信息

---

### Step 2：基线信息收集（系统内存综合信息采集）

📄 **脚本**：`scripts/collect_mem_info.sh`

**参数说明**：

| 参数 | 含义 | 是否必填 |
|------|------|---------|
| `-p <pid>` | 目标进程 PID | 强烈建议（用户态场景） |
| `-n <name>` | 目标进程名（与 -p 二选一） | 可选 |
| `-i <interval>` | 采集间隔（秒），默认 10 | 可选 |
| `-c <count>` | 采集次数，默认 2 | 可选 |

**调用示例**：

```bash
# 对指定 PID 进行 3 次采集，间隔 5 秒
bash collect_mem_info.sh -p 12345 -i 5 -c 3

# 按进程名采集
bash collect_mem_info.sh -n nginx
```

该脚本**一次性完成**以下所有收集：

| 输出类型 | 内容 | 说明 |
|---------|------|------|
| 终端直接输出 | 系统内存概览、进程内存详情、TOP 内存消费者 | 附带诊断说明 |
| 文件输出 | 完整 meminfo、smaps、slabinfo、vmallocinfo | 保存到 `/tmp/mem_diag_*/` |

**收集范围**：

1. **系统内存概览**：`free -h`、`/proc/meminfo` 关键字段
2. **进程内存详情**：`/proc/[pid]/status`（VmRSS/VmPeak/VmData/VmStk）、`pmap -x [pid]`
3. **匿名页统计**：`/proc/[pid]/smaps` 中 Anonymous 汇总
4. **Slab 分配器**：`cat /proc/slabinfo`、`slabtop -o`
5. **vmalloc 状态**：`cat /proc/vmallocinfo`、`grep Vmalloc /proc/meminfo`
6. **Memcg 信息**：`memory.usage_in_bytes`、`memory.stat`（如存在）
7. **TOP 内存消费者**：`ps aux --sort=-%mem` 前 10
8. **内核内存**：`/proc/meminfo` 中 Slab/SUnreclaim/VmallocUsed/PageTables

**基线输出**（供后续分支判断使用）：

```
系统时间：<timestamp>
系统总内存：<total> MB
系统可用内存：<available> MB
Slab 总量：<slab> MB（不可回收：<sunreclaim> MB）
Vmalloc 使用：<vmalloc_used> MB
进程 <PID> VmRSS：<rss> MB
进程 <PID> 匿名页：<anon> MB
进程 <PID> VmData：<vmdata> MB
Top 内存进程：<top_process_list>
```

---

### Step 3：故障分支定界

按 Step 1 识别结果 + Step 2 基线输出，执行对应分支脚本：

```bash
# 分支 A：用户态 RSS 持续增长
bash scripts/diagnose_rss_growth.sh -p <pid> [-i <interval>] [-c <count>]

# 分支 B：匿名页泄漏
bash scripts/diagnose_anon_page.sh -p <pid>

# 分支 C：Valgrind/ASan 堆泄漏
bash scripts/diagnose_heap_profiler.sh -p <pid> [-b <binary_path>]

# 分支 D：Slab 泄漏
bash scripts/diagnose_slab_leak.sh [-i <interval>] [-c <count>]

# 分支 E：vmalloc 泄漏
bash scripts/diagnose_vmalloc_leak.sh

# 分支 F：kmalloc 未释放
bash scripts/diagnose_kmalloc_leak.sh [-i <interval>] [-c <count>]

# 分支 G：Memcg 泄漏
bash scripts/diagnose_memcg_leak.sh [-g <cgroup_path>]
```

脚本对应参考：

```
内存泄漏症状
  ├─ 进程 RSS 持续增长 / 内存越用越多              → 分支 A: RSS 增长
  ├─ 匿名页不断增长 / smaps Anonymous 上升          → 分支 B: 匿名页泄漏
  ├─ valgrind/ASan 报告泄漏                         → 分支 C: 堆泄漏
  ├─ slab 缓存活跃对象增长 / SUnreclaim 上升         → 分支 D: Slab 泄漏
  ├─ VmallocUsed 持续增长 / /proc/vmallocinfo 大量   → 分支 E: vmalloc 泄漏
  ├─ kmalloc 对象持续增长 / kmemleak 报告             → 分支 F: kmalloc 未释放
  └─ cgroup memory.usage_in_bytes 持续增长           → 分支 G: Memcg 泄漏
```

---

### Step 4：假设驱动排查（逐假设验证）

基于 Step 2 基线数据 + Step 3 分支输出，对当前症状构建**多假设树**。

#### 分支 A 示例：用户态 RSS 持续增长

```text
进程 RSS 持续增长
├─► 假设 A1: Heap 段内存泄漏 → VmData / heap 段持续增长
├─► 假设 A2: 匿名映射泄漏 → Anonymous 页持续增长
├─► 假设 A3: 线程栈泄漏 → 线程 VmStk 总和持续增长（线程泄漏）
├─► 假设 A4: 文件描述符泄漏 → lsof -p 显示 fd 数持续增长（关联内存）
├─► 假设 A5: 共享内存泄漏 → /dev/shm 或 tmpfs 占用增长
```

#### 分支 B 示例：匿名页泄漏

```text
匿名页泄漏
├─► 假设 B1: 堆内存未释放 → pmap -x 中 heap 段 [heap] 持续增长
├─► 假设 B2: mmap 匿名映射未释放 → smaps 中匿名 mmap 区域增长
├─► 假设 B3: malloc arena 膨胀 → glibc malloc arena 过多导致内存膨胀
├─► 假设 B4: 递归增长缓存 → 应用层缓存/连接池/对象池无上限
├─► 假设 B5: 内存池碎片化 → 应用内存池反复申请释放导致碎片
```

#### 分支 C 示例：Valgrind/ASan 堆泄漏

```text
Valgrind/ASan 报告堆泄漏
├─► 假设 C1: 常规堆泄漏 → malloc 后未 free，valgrind 报 definitely lost
├─► 假设 C2: 间接泄漏 → 指针覆盖导致原指针丢失，相关联对象均泄漏
├─► 假设 C3: 循环引用泄漏 → C++ shared_ptr 循环引用导致智能指针未释放
├─► 假设 C4: RAII 异常路径泄漏 → 异常发生时析构函数未调用
├─► 假设 C5: 第三方库泄漏 → 调用的共享库内部存在泄漏
```

#### 分支 D 示例：Slab 缓存泄漏

```text
Slab 缓存泄漏
├─► 假设 D1: dentry 缓存泄漏 → 文件系统元数据操作后 dentry 未回收
├─► 假设 D2: inode_cache 泄漏 → inode 在 umount 或删除文件后未释放
├─► 假设 D3: kmalloc-* 通用缓存泄漏 → 驱动或内核模块反复分配未释放
├─► 假设 D4: radix_tree_node 泄漏 → 页缓存索引节点泄漏
├─► 假设 D5: 密钥/安全结构泄漏 → 内核安全模块的结构体未释放
```

#### 分支 E 示例：vmalloc 泄漏

```text
vmalloc 泄漏
├─► 假设 E1: 内核模块 vmalloc 未释放 → 模块分配内存未在卸载时释放
├─► 假设 E2: 驱动连续 vmalloc 分配 → 设备驱动反复 vmalloc 不 free
├─► 假设 E3: 网络缓存 vmalloc 泄漏 → 网络协议栈分配的内存未回收
├─► 假设 E4: 帧缓冲/图形 vmalloc 泄漏 → DRM/GPU 驱动 vmalloc 未释放
├─► 假设 E5: vmalloc 碎片化 → 反复分配释放导致碎片无法满足大块分配
```

#### 分支 F 示例：kmalloc 未释放

```text
kmalloc 未释放
├─► 假设 F1: 特定尺寸 kmalloc 持续增长 → 驱动使用固定尺寸分配未释放
├─► 假设 F2: 引用计数泄漏 → 对象引用计数未归零导致无法释放
├─► 假设 F3: 内核事件/通知链泄漏 → 注册的回调未注销导致结构体滞留
├─► 假设 F4: 网络 socket 缓冲泄漏 → TCP/UDP 缓冲区未正确释放
├─► 假设 F5: 文件系统缓存泄漏 → 文件系统元数据缓存泄漏
```

#### 分支 G 示例：Memcg 泄漏

```text
Memcg 泄漏
├─► 假设 G1: 内核内存泄漏 → memory.kmem.usage_in_bytes 持续增长
├─► 假设 G2: Slab 不可回收内存泄漏 → SUnreclaim 在 cgroup 内增长
├─► 假设 G3: 页面缓存不回收 → memory.stat 中 cache 持续增长
├─► 假设 G4: 内存 cgroup 僵尸页 → 已释放进程仍占用 cgroup 内存计数
├─► 假设 G5: 容器内匿名页泄漏 → 容器内进程 RSS 配合 memcg 同步增长
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
✓ 推演的内存增长模式 == 实际的 /proc/meminfo 趋势？
✓ 推演的泄漏对象 == slabtop/pmap 中的增长项？
✓ 推演的故障场景与实际观察到的行为一致？
```

**三条全 ✓ 才能判定"根因确认"**。若不通过，回到 Step 4 补充证据或构建新假设。

---

### Step 6：排除的替代假设

明确记录排除了哪些假设及其排除依据：

```
- 假设A3（线程栈泄漏）：排除原因 进程线程数稳定，VmStk 未增长
- 假设D1（dentry 泄漏）：排除原因 slabtop 中 dentry 稳定，未异常增长
- 假设G4（僵尸页）：排除原因 进程退出后 memcg 计数正常回落
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

### 分支 A：用户态 RSS 持续增长

#### 触发条件

> **先执行专项采集脚本**。

```bash
bash diagnose_rss_growth.sh -p <pid> -i 5 -c 5
```

#### 诊断依据

RSS（Resident Set Size）是进程驻留物理内存大小。RSS 持续增长表明进程在持续分配内存但未释放。需区分是 heap 增长、匿名映射增长还是线程栈增长。

**关键诊断命令**：

```bash
# 查看进程内存概览
grep -E "VmRSS|VmPeak|VmData|VmStk|VmPTE" /proc/<pid>/status

# 查看内存映射详情
pmap -x <pid> | sort -k3 -rn | head -20

# 匿名页统计
grep Anonymous /proc/<pid>/smaps | awk '{sum+=$2} END{print sum " kB"}'

# 持续监控
watch -n 2 'grep VmRSS /proc/<pid>/status'
```

#### 假设驱动排查

```
假设 A1: Heap 段内存泄漏
  → 检查方法: pmap -x <pid> 中 [heap] 段 RSS 是否增长
  → 判定条件: [heap] RSS 随时间持续上升

假设 A2: 匿名映射泄漏
  → 检查方法: 统计 smaps 中 Anonymous 总量，对比两次采集差值
  → 判定条件: Anonymous 总量持续上升

假设 A3: 线程栈泄漏
  → 检查方法: ls /proc/<pid>/task/ | wc -l 线程数及 VmStk 总和
  → 判定条件: 线程数或 VmStk 持续增长

假设 A4: 文件描述符泄漏
  → 检查方法: lsof -p <pid> | wc -l
  → 排除条件: fd 数稳定

假设 A5: 共享内存泄漏
  → 检查方法: ipcs -m 或 df /dev/shm
  → 判定条件: 共享内存段持续增加
```

---

### 分支 B：匿名页泄漏

#### 触发条件

```bash
bash diagnose_anon_page.sh -p <pid>
```

#### 诊断依据

匿名页（Anonymous pages）是没有文件背景的内存页，主要包括 heap、mmap 匿名映射、栈等。匿名页持续增长是内存泄漏的直接证据。

**关键诊断命令**：

```bash
# 汇总匿名页使用
grep Anonymous /proc/<pid>/smaps | awk '{sum+=$2} END{print sum " kB"}'

# 按区域查看匿名页分布
grep -A5 "Anonymous:" /proc/<pid>/smaps | grep -B5 "Anonymous:.*[1-9]"

# 查看 heap 段详情
grep -A10 "\[heap\]" /proc/<pid>/smaps

# 查看匿名 mmap 区域
cat /proc/<pid>/smaps | grep -B5 "Anonymous:" | grep -v "\[heap\]" | grep -v "\[stack\]"
```

---

### 分支 C：Valgrind/ASan 堆泄漏

#### 触发条件

```bash
bash diagnose_heap_profiler.sh -p <pid> [-b /path/to/binary]
```

#### 诊断依据

Valgrind memcheck 和 AddressSanitizer 是最常用的用户态堆泄漏检测工具。Valgrind 通过拦截 malloc/free 跟踪所有堆分配；ASan 通过编译时插桩检测泄漏。

**关键诊断命令**：

```bash
# Valgrind memcheck 完整检测
valgrind --tool=memcheck --leak-check=full --show-leak-kinds=all ./program

# Valgrind massif 堆分析
valgrind --tool=massif --massif-out-file=massif.out ./program
ms_print massif.out

# ASan 编译运行
gcc -fsanitize=address -g -o program program.c
./program

# 实时追踪分配（strace）
strace -p <pid> -e trace=brk,mmap -o /tmp/alloc.log
```

---

### 分支 D：Slab 缓存泄漏

#### 触发条件

```bash
bash diagnose_slab_leak.sh -i 10 -c 6
```

#### 诊断依据

Slab 分配器用于管理内核中频繁分配/释放的小对象。如果特定 slab 缓存的活跃对象数持续增长，表明内核某子系统存在内存泄漏。

**关键诊断命令**：

```bash
# 查看 slab 使用 TOP
slabtop -o | head -20

# 查看不可回收 slab
grep SUnreclaim /proc/meminfo

# 对比两次 slabinfo
cat /proc/slabinfo | awk '{print $1, $2, $3}' | head -30

# 查看特定缓存
cat /proc/slabinfo | grep -E "^dentry|^inode_cache|^kmalloc-"
```

---

### 分支 E：vmalloc 泄漏

#### 触发条件

```bash
bash diagnose_vmalloc_leak.sh
```

#### 诊断依据

vmalloc 用于分配虚拟地址连续但物理地址不一定连续的内存。vmalloc 泄漏常见于内核模块和驱动程序反复分配大块内存未释放。

**关键诊断命令**：

```bash
# 查看 vmalloc 概览
grep Vmalloc /proc/meminfo

# 查看 vmalloc 分配详情
cat /proc/vmallocinfo | head -30
cat /proc/vmallocinfo | awk '{sum+=$2} END{print sum/1024 " MB"}'

# 按调用者排序
cat /proc/vmallocinfo | awk '{print $4}' | sort | uniq -c | sort -rn | head -10

# 使用 kmemleak 检测
echo scan > /sys/kernel/debug/kmemleak
cat /sys/kernel/debug/kmemleak
```

---

### 分支 F：kmalloc 未释放

#### 触发条件

```bash
bash diagnose_kmalloc_leak.sh -i 10 -c 6
```

#### 诊断依据

kmalloc 是内核中最常用的内存分配函数。未释放的 kmalloc 会表现为 `kmalloc-*` 缓存在 `/proc/slabinfo` 中 active 对象持续增长。

**关键诊断命令**：

```bash
# 查看 kmalloc 缓存趋势
cat /proc/slabinfo | grep "^kmalloc-" | awk '{print $1, $2}'

# 按尺寸排序
cat /proc/slabinfo | grep "^kmalloc-" | sort -t- -k2 -n

# 使用 kmemleak 扫描
echo scan > /sys/kernel/debug/kmemleak
cat /sys/kernel/debug/kmemleak

# 查看特定尺寸的活跃对象
cat /proc/slabinfo | grep "kmalloc-128"
```

---

### 分支 G：Memcg 内存泄漏

#### 触发条件

```bash
bash diagnose_memcg_leak.sh [-g /sys/fs/cgroup/memory/<group>]
```

#### 诊断依据

Memory cgroup 用于限制和统计一组进程的内存使用。当 `memory.usage_in_bytes` 持续增长但进程 RSS 不增长时，可能存在内核内存泄漏或 slab 不可回收内存泄漏。

**关键诊断命令**：

```bash
# 查看 memcg 内存使用
cat /sys/fs/cgroup/memory/<group>/memory.usage_in_bytes
cat /sys/fs/cgroup/memory/<group>/memory.stat | head -20

# 查看内核内存使用
cat /sys/fs/cgroup/memory/<group>/memory.kmem.usage_in_bytes

# 对比进程总 RSS 与 memcg usage
cat /sys/fs/cgroup/memory/<group>/memory.usage_in_bytes
grep VmRSS /proc/<pid>/status

# 查看 memcg slab
cat /sys/fs/cgroup/memory/<group>/memory.stat | grep slab
```

---

## 第六节：注意事项与常见误判陷阱

### 常见误判陷阱

| 陷阱 | 说明 | 应对方式 |
|------|------|---------|
| **Page Cache 增长误判为泄漏** | 文件密集读操作导致 page cache 上升，但这是正常行为 | 用 `Cached` 与 `AnonPages` 区分，关注匿名页而非缓存页 |
| **一次性采样误判趋势** | 单次高内存不代表泄漏，可能是瞬态峰值 | 至少采集 2-3 次间隔数据确认增长趋势 |
| **Slab 增长 ≠ Slab 泄漏** | Slab 增长可能是正常业务负载增加 | 对比负载变化前后 slab 是否回落，确认不可回收部分趋势 |
| **Memcg usage ≠ 进程 RSS** | memcg usage 包含内核内存和 slab，可能远大于进程 RSS | 同时检查 `memory.stat` 中的 cache、slab、kernel_stack |
| **OOM killer ≠ 内存泄漏** | 内存不足可能只是过度承诺而非泄漏 | 检查 `Committed_AS` 是否超 MemTotal，overcommit 场景需区分 |
| **valgrind 误报** | valgrind 可能因优化级别或库初始化报泄漏 | 用 `--show-leak-kinds=definite` 排除 "possibly lost" |

### 内核版本注意事项

| 特性 | 最小内核版本 | 说明 |
|------|------------|------|
| smaps_rollup | 4.14 | smaps 汇总读取，减少性能开销 |
| kmemleak | 2.6.31 | 内核内存泄漏检测，需配置 `CONFIG_DEBUG_KMEMLEAK` |
| memcg kmem | 3.8 | cgroup 内核内存统计 |
| slabinfo | 2.6 | PROCFS slab 信息 |

---

## 第七节：最终报告结构

```markdown
# 🔴 内存泄漏诊断报告

## 一、故障概览
- 故障标题：<泄漏类型>
- 故障级别：[P0(严重) | P1(高) | P2(中) | P3(低)]
- 影响范围：<受影响的进程/服务/容器>
- 故障时段：<T0 ~ T1>
- 当前状态：[🔴 处理中 | 🟢 已恢复 | 🟡 待确认]
- 根因置信度：[🟢 高置信 | 🟡 中置信 | 🟠 低置信 | 🔴 未知]

## 二、根因速览
**根本原因**：<一句话描述>

### 故障因果链
```
[触发条件] → [内存分配路径] → [未释放/泄漏] → [OOM/服务不可用]
```

### 事故时间线
| 时间点 | 事件 | 证据来源 |
|--------|------|---------|
| T0 | <故障触发> | <meminfo/slabtop/进程状态> |

## 三、假设驱动排查
| 假设 | 验证操作 | 结果 | 排除依据 |
|------|---------|------|---------|
| <假设> | <方法> | 🎯 确认/❌ 排除 | <依据> |

## 四、关键证据
1. **证据1**：<描述> — 文件：<path> — 关键内容：<数据>

## 五、反事实验证
| 维度 | 推演结果 | 实际现象 | 是否吻合 |
|------|---------|---------|---------|
| 内存增长模式 | <推演> | <实际> | □ 是 □ 否 |

## 六、排除的替代假设
- **假设X**：排除原因 <具体数据>

## 七、修复建议
### 应急处置
1. <操作：重启进程/清空缓存/调整 limit>
### 永久修复
1. <措施：修复代码泄漏/更新驱动/配置限额>
### 预防措施
1. <措施：添加监控告警/定期 valgrind/配置内存上限>

## 八、附件
- 系统内存快照：<路径>
- 进程内存映射：<路径>
- Slab 分配器状态：<路径>
- vmalloc 详情：<路径>
```

---

## 第八节：故障模式速查表

| 故障模式 | 关键指标 | 一键诊断 | 诊断工具 |
|---------|---------|---------|---------|
| 用户态 RSS 增长 | VmRSS 持续上升 | `diagnose_rss_growth.sh` | `pmap -x` / `/proc/pid/status` |
| 匿名页泄漏 | Anonymous 增长 | `diagnose_anon_page.sh` | `/proc/pid/smaps` |
| 堆泄漏 | valgrind definitely lost | `diagnose_heap_profiler.sh` | `valgrind` / `ASan` |
| Slab 泄漏 | SUnreclaim 增长 | `diagnose_slab_leak.sh` | `slabtop` / `/proc/slabinfo` |
| vmalloc 泄漏 | VmallocUsed 增长 | `diagnose_vmalloc_leak.sh` | `/proc/vmallocinfo` |
| kmalloc 未释放 | kmalloc-* active 增长 | `diagnose_kmalloc_leak.sh` | `kmemleak` / slabinfo |
| Memcg 泄漏 | memory.usage_in_bytes 增长 | `diagnose_memcg_leak.sh` | cgroup memory.stat |

---

## 第九节：参考文件

- `references/memory_leak_scenarios.md`：内存泄漏故障场景分类与特征表
- `references/memory_leak_diagnosis_commands.md`：内存泄漏诊断命令与工具参考
- `references/proc_mem_reference.md`：/proc 内存诊断参考
- 外部工具：`valgrind`（堆泄漏检测）、`slabtop`（Slab 监控）、`kmemleak`（内核泄漏检测）、`pmap`（进程内存映射）
