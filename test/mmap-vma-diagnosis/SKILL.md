---
name: mmap-vma-diagnosis
description: >
  内存映射与虚拟地址空间故障诊断技能。覆盖 mmap 返回 ENOMEM（vm.max_map_count 耗尽，
  常见于 Elasticsearch）、SIGBUS on truncated file（文件映射后文件被截断）、mlock 超限
  （RLIMIT_MEMLOCK）、共享内存映射 permission denied、进程地址空间碎片化等场景。
  当用户提到 mmap 失败、ENOMEM、SIGBUS、mlock 失败、共享内存映射失败、地址空间耗尽、
  vm.max_map_count、Cannot allocate memory for shared memory、Bus error (core dumped)、
  mmap: Operation not permitted 等问题时，必须使用此 skill。
---

# 内存映射与虚拟地址空间故障诊断 Skill

## 第一节：概述

本 skill 提供系统化的 mmap/VMA 故障分析方法论，覆盖用户态和内核态所有常见的 mmap 失败及地址空间异常场景，支持：

- **vm.max_map_count 耗尽**：进程 VMA 数量超过系统上限，mmap 返回 ENOMEM（Elasticsearch / Java 应用高频场景）
- **SIGBUS on truncated file**：文件映射后底层文件被截断，访问已截断区域触发 SIGBUS
- **mlock 超限**：mlock/mlockall 尝试锁定超过 RLIMIT_MEMLOCK 限制，返回 ENOMEM
- **共享内存映射 Permission denied**：shmget/shmat 或 mmap MAP_SHARED 权限校验失败
- **地址空间碎片化**：虚拟地址空间不足以容纳大块连续映射，mmap 返回 ENOMEM
- **MAP_FAILED 通用诊断**：其他 mmap 常见失败原因（EACCES/EINVAL/ENFILE/EOVERFLOW）

> **重要原则**：本 skill 仅进行信息收集和分析诊断，**不执行任何修复命令**，只给出修复建议。所有修复操作需由用户确认后手动执行。

---

## 第二节：文件结构

```text
mmap-vma-diagnosis/
├── SKILL.md                            # 诊断流程文档
├── references/
│   ├── mmap_fault_scenarios.md         # 故障场景分类与特征表
│   ├── mmap_scenario_analysis.md       # 分场景深度分析指南
│   ├── kernel_vma_reference.md         # 内核 VMA 子系统参考资料
│   └── elasticsearch_mmap_guide.md     # Elasticsearch mmap 专项指南
└── scripts/
    ├── collect_vma_info.sh             # VMA 综合信息收集脚本（基线）
    ├── diagnose_mapcount.sh            # vm.max_map_count 耗尽诊断（分支 A）
    ├── diagnose_sigbus.sh              # SIGBUS 文件截断诊断（分支 B）
    ├── diagnose_mlock.sh               # mlock 超限诊断（分支 C）
    ├── diagnose_shm.sh                 # 共享内存映射诊断（分支 D）
    └── diagnose_fragmentation.sh       # 地址空间碎片化诊断（分支 E）
```

---

## 第三节：分析策略（假设驱动 + 分支验证）

**本 skill 采用假设驱动（Hypothetico-Deductive）的双层分析模型**：

```
┌──────────────────────────────────────────────────────────────────┐
│                    mmap/VMA 故障分析模型                           │
│                                                                  │
│  第一层：场景识别（关键词匹配）        第二层：假设驱动排查          │
│  ──────────────────────────          ─────────────────────      │
│  从用户描述中自动识别故障场景          对每个场景构建多假设树         │
│                                                                  │
│  回答：什么场景？走哪条诊断            回答：为什么失败？如何验证     │
│        路径？                             哪个假设被证实？        │
│                                                                  │
│            ↓                                   ↓                 │
│   ┌────────────────┐                ┌──────────────────────┐     │
│   │ 阶段二 Step 1   │                │ 阶段三 Step 3-4       │     │
│   └────────────────┘                └──────────────────────┘     │
│                                                                  │
│  见：第四节（统一分析流程：基线→分支→假设→验证→输出）              │
└──────────────────────────────────────────────────────────────────┘
```

### 分析原则

| 原则 | 说明 |
|------|------|
| **时间锚定** | 所有分析以故障时间 T0 为锚点，时间窗口默认 T0±30min |
| **证据驱动** | 每个结论必须有日志/指标/系统状态作为支撑（至少 2 个独立来源） |
| **区分现象与根因** | mmap 返回 ENOMEM 是现象，max_map_count 耗尽才是根因 |
| **只读原则** | 诊断阶段严格只读，不执行任何修复命令 |
| **容器感知** | 注意 cgroup 第二层限制（`/sys/fs/cgroup/memory/`） |
| **量化表达** | 报告中的内存/限制数据尽量给出具体数值 |

---

## 第四节：统一分析流程（场景识别 → 基线收集 → 分支定界 → 假设验证 → 排除确认 → 输出报告）

> 执行约束：所有分析脚本的默认超时时间为 **3 分钟（180s）**。

### Step 1：场景自动识别（关键词匹配）

直接从用户的故障描述中提取关键信息，**不询问用户**，自主判断后立即进入分析流程。

| 用户描述关键词 | 判断场景 | 推荐分支 |
|--------------|----------|----------|
| mmap 返回 ENOMEM / Cannot allocate memory / max_map_count / Elasticsearch mmap / 映射数量超限 | vm.max_map_count 耗尽 | → 分支 A |
| Bus error / SIGBUS / 文件截断 / truncated file / 访问已删除文件 / core dumped (signal 7) | SIGBUS 文件截断 | → 分支 B |
| mlock 失败 / mlockall 失败 / RLIMIT_MEMLOCK / 内存锁定超限 / Could not lock memory | mlock 超限 | → 分支 C |
| shmget 失败 / shmat 失败 / 共享内存权限 / Permission denied for shared memory / shmid | 共享内存映射 Permission denied | → 分支 D |
| 地址空间不足 / 大块映射失败 / 连续内存不足 / address space fragmentation | 地址空间碎片化 | → 分支 E |
| mmap 失败 / MAP_FAILED / mmap: 其他错误 | 通用 mmap 失败诊断 | → 分支 F |

> 如果描述同时命中多个场景（如"容器内 ES mmap 失败"），优先以更具体的场景为主（vm.max_map_count 耗尽），同时参考 cgroup 相关限制。

从用户输入中自动提取以下信息，**已有则直接使用，缺失才补充询问**：

- **故障时间**：用户已提供时直接作为锚点 T0；**未提供时才询问**
- **目标进程**：用户已提到进程名/PID 时直接使用；**未提供时才询问**；系统级故障无需询问

---

### Step 2：基线信息收集（VMA 综合信息收集）

📄 **脚本**：`scripts/collect_vma_info.sh`

**参数说明**：

| 参数 | 含义 | 是否必填 |
|------|------|---------|
| `-S <时间>` | 故障时间段开始时间，格式 `YYYY-MM-DD HH:MM:SS` | 强烈建议 |
| `-E <时间>` | 故障时间段结束时间，未填则默认 +1 小时 | 可选 |
| `-p <PID>` | 精确进程 ID，直接定位单个进程 | 可选 |
| `-n <名称>` | 模糊进程名，匹配命令行中包含该字符串的所有进程 | 可选 |

**调用示例**：

```bash
# 系统级全量分析
bash collect_vma_info.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00"

# 精确 PID（用户已提供 PID）
bash collect_vma_info.sh -S "2024-01-15 14:00:00" -p 12345

# 进程名（如 elasticsearch）
bash collect_vma_info.sh -S "2024-01-15 14:00:00" -n elasticsearch
```

该脚本**一次性完成**以下所有收集：

| 输出类型 | 内容 | 说明 |
|---------|------|------|
| 终端直接输出 | 系统 VMA 参数、进程 VMA 统计、内核日志关键错误、异常标记 | 附带诊断说明 |
| 文件输出 | 完整 /proc/[pid]/maps、smaps、内核日志、进程 maps 历史 | 保存到 `/tmp/vma_diag_*/` |

**收集范围**：

1. **系统 VMA 参数**：`vm.max_map_count`、`vm.overcommit_memory`、`vm.overcommit_ratio`、`vm.mmap_min_addr`
2. **系统资源限制**：`ulimit -l`（memlock）、`ulimit -a` 全部限制
3. **目标进程 VMA 统计**：`/proc/[pid]/maps` 行数（当前 VMA 数量）、`/proc/[pid]/status`（VmPeak/VmSize/VmRSS/VmData/VmStk）
4. **目标进程详细 VMA 分布**：`/proc/[pid]/smaps` 或 `smaps_rollup`
5. **共享内存状态**：`ipcs -m -a`（共享内存段）、`ipcs -u`（共享内存资源限制）
6. **系统内存碎片**：`/proc/buddyinfo`、`/proc/pagetypeinfo`
7. **cgroup 相关限制**（容器场景）：`/proc/[pid]/cgroup`、memory.limit_in_bytes、memory.memsw.limit_in_bytes
8. **内核日志**：`dmesg` + `journalctl`（搜索 mmap/mlock/sigbus 关键词）
9. **ES 特定收集**（如进程名为 elasticsearch）：`/etc/elasticsearch/elasticsearch.yml` 中的 `bootstrap.memory_lock`

**基线输出**（供后续分支判断使用）：

```
系统 max_map_count：<value>
进程 PID：<PID>  进程名：<name>
进程 VMA 数量：<count>  使用率：<count/max_map_count*100%>
VmPeak：<value>  VmRSS：<value>  VmLck：<value>
内核日志异常关键词：[mmap_failed/SIGBUS/mlock/shm/无]
```

---

### Step 3：故障分支定界

按 Step 1 识别结果 + Step 2 基线输出，执行对应分支脚本：

```bash
# 分支 A：vm.max_map_count 耗尽
bash scripts/diagnose_mapcount.sh -S "<time>" -E "<time>" [-p PID | -n 进程名]

# 分支 B：SIGBUS 文件截断
bash scripts/diagnose_sigbus.sh -S "<time>" -E "<time>" [-p PID | -n 进程名]

# 分支 C：mlock 超限
bash scripts/diagnose_mlock.sh -S "<time>" -E "<time>" [-p PID | -n 进程名]

# 分支 D：共享内存映射 Permission denied
bash scripts/diagnose_shm.sh -S "<time>" -E "<time>" [-p PID | -n 进程名]

# 分支 E：地址空间碎片化
bash scripts/diagnose_fragmentation.sh -S "<time>" -E "<time>" [-p PID | -n 进程名]
```

脚本对应参考：

```
mmap 失败 / VMA 异常
  ├─ 关键词含 "max_map_count" / "ENOMEM" + maps 行数接近上限  → 分支 A: vm.max_map_count 耗尽
  ├─ 关键词含 "SIGBUS" / "signal 7" / "Bus error"              → 分支 B: SIGBUS 文件截断
  ├─ 关键词含 "mlock" / "Could not lock memory"                 → 分支 C: mlock 超限
  ├─ 关键词含 "shmget" / "shmat" / "Permission denied"         → 分支 D: 共享内存权限拒绝
  ├─ 关键词含 "地址空间不足" / "大块映射失败"                    → 分支 E: 地址空间碎片化
  └─ 关键词不匹配以上任何场景                                     → 分支 F: 通用 mmap 失败
```

---

### Step 4：假设驱动排查（逐假设验证）

基于 Step 2 基线数据 + Step 3 分支输出，对当前场景构建**多假设树**，按假设优先级逐条验证。

#### 分支 A 示例：vm.max_map_count 耗尽

```text
mmap 返回 ENOMEM (Cannot allocate memory)
├─► 假设 A1: vm.max_map_count 耗尽         → 检查 max_map_count 与 maps 行数
├─► 假设 A2: 系统物理内存不足               → 检查 VmRSS / MemFree / overcommit
├─► 假设 A3: 文件描述符耗尽                 → 检查 Max open files / FDSize
├─► 假设 A4: mlock 内存锁定超限            → 检查 VmLck / RLIMIT_MEMLOCK
└─► 假设 A5: overcommit 限制拒绝           → 检查 vm.overcommit_memory / CommitLimit
```

#### 分支 B 示例：SIGBUS 文件截断

```text
进程收到 SIGBUS 崩溃
├─► 假设 B1: mmap 映射后文件被 ftruncate    → strace 检查 ftruncate 调用
├─► 假设 B2: 文件描述符关闭后映射失效        → 检查 mmap 引用计数机制
├─► 假设 B3: 文件被删除/重命名（logrotate） → 检查 logrotate 配置
├─► 假设 B4: 硬件 I/O 错误导致 bus error    → 检查 dmesg 硬件错误
└─► 假设 B5: 映射参数错误                   → 检查 mmap flags / prot 有效性
```

#### 分支 C 示例：mlock 超限

```text
mlock 返回 ENOMEM
├─► 假设 C1: RLIMIT_MEMLOCK 默认值过小      → 检查 ulimit -l / limits.conf
├─► 假设 C2: systemd LimitMEMLOCK 未配置    → 检查 systemctl show
├─► 假设 C3: 容器内 memlock 继承限制        → 检查容器 cgroup / docker sysctls
├─► 假设 C4: root 绕过（CAP_SYS_RESOURCE）  → 检查 CapEff 权限
└─► 假设 C5: 实际内存不足（非限制问题）      → 检查 MemAvailable / VmLck
```

#### 分支 D 示例：共享内存权限拒绝

```text
shmget/shmat 失败 (EACCES)
├─► 假设 D1: 共享内存段权限不匹配           → 检查 ipcs -m perm.mode
├─► 假设 D2: 容器 /dev/shm 大小不足         → 检查 df -h /dev/shm
├─► 假设 D3: 进程缺少 CAP_IPC_OWNER         → 检查 getpcaps / CapEff
├─► 假设 D4: 内核 shm 参数限制              → 检查 shmall / shmmax / shmmni
└─► 假设 D5: SELinux / seccomp 拦截         → 检查 SELinux / seccomp 状态
```

#### 分支 E 示例：地址空间碎片化

```text
大块 mmap 失败 (ENOMEM) 但总地址空间充足
├─► 假设 E1: 进程地址空间被小 VMA 分割      → 分析 maps 计算最大空洞
├─► 假设 E2: 大量线程栈交错分布             → 统计 [stack:<tid>] VMA 数量
├─► 假设 E3: 频繁 dlopen/dlclose 导致       → 检查进程操作历史
├─► 假设 E4: 物理内存碎片影响 hugepage      → 检查 buddyinfo
└─► 假设 E5: ASLR 加剧碎片化                → 检查 randomize_va_space
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
✓ 推演的失败原因 == 实际的错误码（ENOMEM / EACCES / SIGBUS）？
✓ 推演的触发条件 == 系统实际配置和状态？
✓ 推演的故障链路 == 实际的系统调用/日志时间序列？
```

**三条全 ✓ 才能判定"根因确认"**。若不通过，回到 Step 4 补充证据或构建新假设。

---

### Step 6：排除的替代假设

明确记录排除了哪些假设及其排除依据：

```
- 假设A2（物理内存不足）：排除原因 VmRSS=1408kB，MemFree 充足
- 假设A3（fd耗尽）：排除原因 Max open files=1,048,576，FDSize=64
- 假设A4（mlock超限）：排除原因 VmLck=0，RLIMIT_MEMLOCK=unlimited
```

---

### Step 7：置信度评级

| 等级 | 标识 | 含义 |
|------|------|------|
| 高置信 | 🟢 | 根因已明确，反事实验证全通过，排除所有替代假设 |
| 中置信 | 🟡 | 根因基本确认，但有 1-2 个维度依赖推断；或假设树未完全覆盖 |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 |

---

### Step 8：最终输出（按第七节报告模板落盘）

将 Step 4/5/6/7 的输出填入第七节报告结构，显式写清：根因、证据链、排除的替代假设、置信度、修复建议。

---

## 第五节：分场景深度分析

### 分支 A：vm.max_map_count 耗尽诊断

#### 触发条件

> **先执行专项采集脚本**，获得结构化摘要后再开始分析。

```bash
bash diagnose_mapcount.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00" [-p PID | -n 进程名]
```

#### 诊断依据

`vm.max_map_count` 是 Linux 内核限制一个进程可以拥有的最大虚拟内存区域（VMA）数量。默认值通常为 65530。

| 场景 | 典型进程 VMA 数 | 阈值 | 后果 |
|------|----------------|------|------|
| 正常 | 100-500 | < 65530 | 正常 |
| 偏高 | 1000-5000 | 接近上限 | 潜在风险 |
| ES 典型 | 20000-60000 | 常需调高 | ES 官方建议 262144 |
| 耗尽 | ≥ vm.max_map_count | 达到上限 | mmap 返回 ENOMEM |

**常见高 VMA 进程类型**：

| 进程类型 | 原因 | 典型 VMA 数 |
|---------|------|------------|
| Elasticsearch | 每个分片使用 mmap 映射索引文件 | 20000-60000+ |
| Java 应用 | NIO direct buffer + MappedByteBuffer | 5000-30000 |
| Node.js 应用 | Node.js 使用 mmap 管理大文件 | 2000-10000 |
| Chrome/Firefox | 每个 Tab 独立进程 + 大量 mmap | 3000-15000 |

**关键诊断命令**：

```bash
# 确认 VMA 数量
cat /proc/<PID>/maps | wc -l
cat /proc/sys/vm/max_map_count

# 定位高 VMA 来源
cat /proc/<PID>/maps | awk '{if ($NF != "") print $NF}' | sort | uniq -c | sort -rn | head -20

# 检查内核日志
dmesg -T | grep -i "max_map_count\|mmap.*failed\|ENOMEM"
journalctl -k --since="<start>" --until="<end>" | grep -i "max_map_count"

# Elasticsearch 专项
grep max_map_count /etc/elasticsearch/elasticsearch.yml 2>/dev/null
grep "vm.max_map_count" /etc/sysctl.conf /etc/sysctl.d/*.conf 2>/dev/null
```

#### 假设驱动排查

```
假设 A1: vm.max_map_count 耗尽
  → 检查方法: 对比 /proc/<PID>/maps 行数 与 vm.max_map_count
  → 判定条件: maps 行数 >= 0.9 * max_map_count → 高风险

假设 A2: 系统物理内存不足
  → 检查方法: 查看 VmRSS / MemFree / CommitLimit
  → 排除条件: VmRSS 远小于 MemTotal, overcommit=1

假设 A3: 文件描述符耗尽
  → 检查方法: 查看 Max open files / FDSize / /proc/<PID>/fd 数量
  → 排除条件: 当前 fd 使用 << 限制值

假设 A4: mlock 内存锁定超限
  → 检查方法: 查看 VmLck / RLIMIT_MEMLOCK
  → 排除条件: VmLck=0 或 VmLck << RLIMIT_MEMLOCK

假设 A5: overcommit 限制拒绝
  → 检查方法: 查看 vm.overcommit_memory 和 CommitLimit
  → 排除条件: overcommit_memory=0 或 1 时通常不触发
```

**内核源码路径**：`mm/mmap.c → do_mmap() → mmap_region() → -ENOMEM`（`mm->map_count > sysctl_max_map_count` 检查）

---

### 分支 B：SIGBUS on truncated file 诊断

#### 触发条件

> **先执行专项采集脚本**。

```bash
bash diagnose_sigbus.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00" [-p PID | -n 进程名]
```

#### 诊断依据

当进程通过 mmap 映射一个文件后，如果其他进程或操作将该文件截断（truncate）至映射范围以下，进程再访问映射区域内已截断的部分时，内核会向进程发送 SIGBUS 信号（信号 7）。

**关键特征**：

| 特征 | 说明 |
|------|------|
| 信号编号 | SIGBUS (7) |
| si_code | BUS_ADRERR — 总线地址错误 |
| Core dump | 默认生成 core 文件 |
| dmesg 关键词 | `bus error`、`SIGBUS` |
| 触发方式 | 访问文件映射中超出当前文件大小的页 |
| 内核路径 | `mm/filemap.c → filemap_fault() → do_sigbus()` |

**关键诊断命令**：

```bash
# 确认 SIGBUS
coredumpctl list 2>/dev/null | head -10
dmesg -T | grep -i "bus error\|SIGBUS\|segfault at.*ip.*sp.*error"

# 分析 core dump（如存在）
gdb <binary> <core> -ex "bt" -ex "info registers" -ex "quit"

# strace 追踪故障全链路
strace -p <PID> -e trace=mmap,ftruncate,msync,write,close -f -o /tmp/strace.log

# 检查文件映射范围与当前文件大小
cat /proc/<PID>/maps | column -t
ls -l /path/to/mapped/file
stat /path/to/mapped/file

# 定位文件截断者
lsof /path/to/mapped/file
journalctl -k --since="<start>" --until="<end>" | grep -i "truncate\|fallocate"
```

#### 假设驱动排查

```
假设 B1: mmap 映射后文件被 ftruncate
  → 检查方法: strace 追踪 ftruncate 调用 + 文件大小对比
  → 判定条件: strace 显示 ftruncate → 访问映射区域 → SIGBUS

假设 B2: close(fd) 后映射失效
  → 检查方法: 验证 mmap 引用计数机制（close 后 msync 是否成功）
  → 排除条件: close 不影响已有 mmap 映射（内核通过 fget 增加引用计数）

假设 B3: 文件被删除/重命名（logrotate）
  → 检查方法: 检查 /etc/logrotate.d/* 中目标文件的轮转配置
  → 判定条件: logrotate 使用 create 模式（删除重建 → inode 变更）

假设 B4: 硬件 I/O 错误
  → 检查方法: 检查 dmesg 中磁盘 I/O 错误 / EDAC 记录
  → 排除条件: 无硬件错误记录

假设 B5: mmap 映射参数错误
  → 检查方法: 检查 mmap flags/prot 组合有效性
  → 排除条件: mmap 成功返回合法地址
```

**内核源码路径**：`mm/filemap.c → filemap_fault() → do_sigbus()`

---

### 分支 C：mlock 超限诊断

#### 触发条件

> **先执行专项采集脚本**。

```bash
bash diagnose_mlock.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00" [-p PID | -n 进程名]
```

#### 诊断依据

`mlock()` / `mlockall()` 系统调用用于将虚拟内存锁定在物理 RAM 中。`RLIMIT_MEMLOCK`（`ulimit -l`）控制单个用户/进程可锁定的内存总量。

| 限制类型 | 查看方式 | 默认值 |
|---------|---------|--------|
| 软限制 | `ulimit -l` | 64 KB（某些发行版）或 8 KB |
| 硬限制 | `ulimit -H -l` | 同上 |
| systemd 配置 | `LimitMEMLOCK=` 在服务文件中 | 通常不设置（继承） |
| 容器配置 | cgroup memory.limit + memlock | 取决于运行时 |

**内核源码路径**：`mm/mlock.c → can_do_mlock() → rlimit(RLIMIT_MEMLOCK)`

**关键诊断命令**：

```bash
# 查看锁定限制
ulimit -l
ulimit -H -l
cat /proc/<PID>/limits | grep "max locked memory"
systemctl show <service> --property=LimitMEMLOCK

# 查看已锁定的内存量
cat /proc/<PID>/status | grep -i "VmLck"
grep -E "Unevictable|Mlocked" /proc/meminfo

# 检查内核日志
dmesg -T | grep -i "mlock\|mlockall\|locked memory\|RLIMIT_MEMLOCK"

# 检查 CapEff（root 可绕过）
cat /proc/<PID>/status | grep -i "CapEff"

# 检查系统配置
cat /etc/security/limits.conf | grep -v "^#\|^$"
cat /etc/security/limits.d/*.conf | grep memlock
```

#### 假设驱动排查

```
假设 C1: RLIMIT_MEMLOCK 默认值过小
  → 检查方法: 对比 ulimit -l 与应用所需锁定内存
  → 判定条件: 需要锁定内存 > ulimit -l

假设 C2: systemd LimitMEMLOCK 未配置
  → 检查方法: systemctl show <service> --property=LimitMEMLOCK
  → 判定条件: LimitMEMLOCK 未设置或过小

假设 C3: 容器内 memlock 继承限制
  → 检查方法: 对比宿主机与容器内 ulimit -l
  → 判定条件: 容器内限制小于应用需求

假设 C4: Root 权限绕过
  → 检查方法: 检查 CapEff 是否包含 CAP_SYS_RESOURCE
  → 注意: CAP_SYS_RESOURCE 可使 root 绕过 RLIMIT_MEMLOCK

假设 C5: 系统物理内存不足
  → 检查方法: 检查 MemAvailable + Mlocked
  → 排除条件: 内存充足
```

---

### 分支 D：共享内存映射 Permission denied 诊断

#### 触发条件

> **先执行专项采集脚本**。

```bash
bash diagnose_shm.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00" [-p PID | -n 进程名]
```

#### 诊断依据

共享内存映射失败通常涉及以下权限/配置问题：

| 错误码 | 场景 | 常见原因 |
|--------|------|---------|
| EACCES (13) | shmget/shmat 权限不足 | 共享内存段权限（066x）与进程权限不匹配 |
| EACCES (13) | mmap MAP_SHARED 写入已只读打开的文件 | fd 以 O_RDONLY 打开，但 MAP_SHARED 需要写入 |
| EPERM (1) | mmap MAP_SHARED 对 tmpfs 文件没有写入权限 | 文件属性禁止写入 |
| ENOMEM (12) | 共享内存超过 `kernel.shmall` 或 `kernel.shmmax` | 内核共享内存总量限制 |
| ENOSPC (28) | 共享内存段数量超过 `kernel.shmmni` | 已达系统最大共享内存段数 |

**关键诊断命令**：

```bash
# 查看共享内存限制
sysctl kernel.shmall
sysctl kernel.shmmax
sysctl kernel.shmmni
ipcs -u | grep -i "segments\|allocated"

# 查看目标共享内存段
ipcs -m -a
ipcs -m -i <shmid>

# 检查进程权限
getpcaps <PID> 2>/dev/null || cat /proc/<PID>/status | grep -i "CapEff"
cat /proc/<PID>/cgroup

# 检查内核日志
dmesg -T | grep -i "shm\|shared memory\|shmget\|shmat"

# 检查容器 shm 大小
df -h /dev/shm
mount | grep shm
```

---

### 分支 E：地址空间碎片化诊断

#### 触发条件

> **先执行专项采集脚本**。

```bash
bash diagnose_fragmentation.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00" [-p PID | -n 进程名]
```

#### 诊断依据

地址空间碎片化是指进程的虚拟地址空间不足以为大块 mmap 分配连续 VMA 范围。即使总地址空间充足，但被大量小 VMA 分割，大块映射仍然可能失败。

**关键指标**：

| 指标 | 正常 | 异常 | 说明 |
|------|------|------|------|
| VMA 数量 | < 1000 | > 10000（或近 max_map_count） | VMA 过多本身也是碎片化原因 |
| 最大连续空闲 | > 1GB | < 128MB | 进程地址空间最大空洞 |
| mmap 大块（>1GB） | 成功 | 失败 ENOMEM | 典型碎片化症状 |
| /proc/buddyinfo | 高阶可用 | 高阶不可用 | 物理碎片化会影响 hugepage |

**关键诊断命令**：

```bash
# 查找地址空间空洞
python3 -c "
import re
with open('/proc/<PID>/maps') as f:
    regions = []
    for line in f:
        m = re.match(r'([0-9a-f]+)-([0-9a-f]+)', line)
        if m:
            start, end = int(m.group(1), 16), int(m.group(2), 16)
            regions.append((start, end))
regions.sort()
max_gap = 0
for i in range(len(regions)-1):
    gap = regions[i+1][0] - regions[i][1]
    if gap > max_gap:
        max_gap = gap
print(f'Max contiguous free region: {max_gap / 1024 / 1024:.1f} MB')
print(f'Total VMA count: {len(regions)}')
"

# 检查 hugepage 状态
grep -E "HugePages_Total|HugePages_Free|Hugepagesize" /proc/meminfo
cat /sys/kernel/mm/transparent_hugepage/enabled

# 检查 ASLR 影响
cat /proc/sys/kernel/randomize_va_space
```

---

### 分支 F：通用 mmap 失败诊断

对不匹配 A-E 的 mmap 失败，按 errno 分类诊断：

| errno | 含义 | 排查方向 |
|-------|------|---------|
| EACCES (13) | 权限不足 | fd 权限 / MAP_SHARED + 只读 / /proc/sys/vm/mmap_min_addr |
| EAGAIN (11) | 资源临时不可用 | file seal / 文件被 memfd_seal 保护 |
| EINVAL (22) | 参数无效 | offset 未对齐 / length=0 / flags 组合无效 / fd 未打开 |
| ENFILE (23) | 系统 fd 表满 | `cat /proc/sys/fs/file-max`；`lsof \| wc -l` |
| ENODEV (19) | 底层 fs 不支持 | 检查文件系统类型（如 FAT32 不支持 MAP_SHARED） |
| ENOMEM (12) | 内存不足（通用） | `vm.overcommit_memory=2` 且超出 overcommit 限制 |
| EOVERFLOW (75) | 32位上的大文件 | `file` 过大导致偏移溢出 |
| EPERM (1) | 操作不允许 | `seccomp` 拦截 / SELinux 策略 / AppArmor |

---

## 第六节：注意事项与常见误判陷阱

### 常见误判陷阱

| 陷阱 | 说明 | 应对方式 |
|------|------|---------|
| 崩溃点不等于根因 | RIP/失败点只是异常传播的终点，根因可能在更早的操作或更高层帧中 | 从失败点向上追溯，找到首次引入异常的操作 |
| 容器的 max_map_count 迷惑 | 容器内看到的 max_map_count 可能和宿主机共享 | 在容器内外分别检查，确认 namespace 隔离情况 |
| root 绕过 mlock 限制 | root 持有 CAP_SYS_RESOURCE 可绕过 RLIMIT_MEMLOCK | 检查 CapEff，如含 CAP_SYS_RESOURCE 则限制失效 |
| logrotate create 模式 vs copytruncate | create 模式删除重建文件（inode 变更），copytruncate 截断原文件 | 明确区分两种模式下对 mmap 映射的不同影响 |
| 进程 VMA 快照滞后 | 进程退出后 /proc/<PID>/maps 消失，只能从日志回溯 | 优先在故障发生时采集，事后从内核日志/sysctl 获取系统级证据 |
| VmPeak 和 VmSize 的误区 | 虚拟地址空间巨大不意味物理内存占用高 | 重点关注 VmRSS 而非 VmPeak |

### 容器场景注意事项

- 容器内 `vm.max_map_count` 受 namespace 隔离影响（部分 kernel 版本行为不同）
- cgroup v2 `memory.max` 超出后触发 OOM kill 而非 mmap ENOMEM
- Kubernetes Pod 的 `sysctls` 配置需显式设置 `vm.max_map_count`
- 容器 `ulimit -l` 可能继承宿主机限制而非容器独立配置
- `/dev/shm` 大小由 `--shm-size` 控制，超出后 shmget 返回 ENOMEM

---

## 第七节：最终报告结构

```markdown
# 内存映射 / 虚拟地址空间故障诊断报告

## 一、故障概览
- 故障标题：<根因类型>
- 故障级别：[P0(严重) | P1(高) | P2(中) | P3(低)]
- 影响范围：<受影响的进程/服务/容器>
- 故障时段：<T0 ~ T1>
- 当前状态：[🔴 处理中 | 🟢 已恢复 | 🟡 待确认]
- 根因置信度：[🟢 高置信 | 🟡 中置信 | 🟠 低置信 | 🔴 未知]

### 置信度说明
| 等级 | 含义 | 示例 |
|------|------|------|
| 🟢 高置信 | 根因明确，反事实验证全通过，排除所有替代假设 | 本报告适用 |
| 🟡 中置信 | 根因基本确认，但有1-2个维度依赖推断 | — |
| 🟠 低置信 | 有多个可疑原因，尚未排除竞争 | — |
| 🔴 未知 | 现象无法解释，根因未定位 | — |

## 二、根因速览
**根本原因**：<一句话描述>

### 故障因果链
```
[触发条件]
    └─► [中间事件1]
            └─► [中间事件2]
                    └─► [最终故障]
```

### 事故时间线
| 时间点 | 事件 | 性质 | 证据来源 |
|--------|------|------|---------|
| T0 | <故障触发> | 🔴 故障 | <dmesg/应用日志> |
| T-N | <前置事件> | ⚠️ 隐患 | <监控/日志> |
| T+M | <恢复处理> | 🟢 恢复 | <人为介入> |

## 三、假设驱动排查
### 假设清单与验证结果
| 假设 | 验证操作 | 结果 | 排除依据 |
|------|---------|------|---------|
| <假设A1> | <具体验证方法> | 🎯 根因确认 | — |
| <假设A2> | <具体验证方法> | ❌ 已排除 | <排除依据> |
| <假设A3> | <具体验证方法> | ❌ 已排除 | <排除依据> |

## 四、关键证据
1. **证据1**：<描述> — 文件路径：`<path>` — 关键内容：`<line/content>`
2. **证据2**：<描述> — 文件路径：`<path>` — 关键内容：`<line/content>`

## 五、反事实验证
| 验证维度 | 推演结果 | 实际现象 | 是否吻合？ |
|---------|---------|---------|-----------|
| 失败原因 | <推演> | <实际> | □ 是 □ 否 |
| 触发条件 | <推演> | <实际> | □ 是 □ 否 |
| 故障链路 | <推演> | <实际> | □ 是 □ 否 |

## 六、排除的替代假设
- **假设X**（<名称>）：排除原因 <具体数据>

## 七、修复建议
### 应急处置（立即执行）
1. <操作步骤>
```bash
# 恢复命令
```

### 永久修复（根本解决）
1. <措施> — 负责人：<角色> — 完成时间：<时间>

### 预防措施
1. <措施>
2. <措施>

## 八、附件
- 诊断脚本输出：`<路径>`
- 系统配置快照：`<路径>`
- 内核日志摘要：`<路径>`
```

---

## 第八节：故障模式速查表

| 故障模式 | 关键指标 | 一键诊断 | 内核源码路径 |
|---------|---------|---------|------------|
| vm.max_map_count 耗尽 | `/proc/<PID>/maps \| wc -l` ≥ `vm.max_map_count` | `bash diagnose_mapcount.sh -p <PID>` | `mm/mmap.c: do_mmap()` |
| SIGBUS 文件截断 | 进程 signal 7（core dump）+ mmap 文件被 truncate | `bash diagnose_sigbus.sh -p <PID>` | `mm/filemap.c: filemap_fault()` |
| mlock 超限 | VmLck 接近或等于 `ulimit -l` | `bash diagnose_mlock.sh -p <PID>` | `mm/mlock.c: can_do_mlock()` |
| shm 权限拒绝 | `dmesg \| grep -i shm` + `ipcs -m` 权限检查 | `bash diagnose_shm.sh` | `ipc/shm.c: do_shmget()` |
| 地址空间碎片化 | VMA 数量多 + 最大空洞 < 所需映射大小 | `bash diagnose_fragmentation.sh -p <PID>` | `mm/mmap.c: arch_get_unmapped_area()` |

---

## 第九节：参考文件

- `references/mmap_fault_scenarios.md`：故障场景分类与关联性
- `references/mmap_scenario_analysis.md`：分场景深度分析指南
- `references/kernel_vma_reference.md`：内核 VMA 子系统参考资料
- `references/elasticsearch_mmap_guide.md`：Elasticsearch mmap 专项指南
- 内核源码：`mm/mmap.c`（VMA 分配）、`mm/filemap.c`（缺页 SIGBUS）、`mm/mlock.c`（mlock 限制）、`ipc/shm.c`（共享内存）
