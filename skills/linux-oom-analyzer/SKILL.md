---
name: linux-oom-analyzer
description: |
  专业的 Linux 内存 OOM（Out of Memory）故障分析 skill。当用户提到 OOM、内存溢出、内存不足、进程被 kill、oom-killer、内存泄漏、系统内存问题、cgroup内存限制、slab内存异常、tmpfs内存占用高、内核内存问题等相关故障时，必须使用此 skill。支持全系统级 OOM 分析和特定进程级 OOM 分析两种模式，支持用户提供故障时间点进行精准定位，支持可选的内核源码级根因分析。用户描述任何 Linux 内存相关故障、系统 OOM、进程异常终止、内存持续增长等问题时都应触发此 skill。
---

# Linux 内存 OOM 故障分析 Skill

## 概述

本 skill 提供系统化的 Linux OOM 故障分析方法论，覆盖用户态和内核态所有常见 OOM 场景，支持：
- **系统级 OOM**：整机内存耗尽触发 OOM killer
- **进程级 OOM**：特定进程内存异常或被 OOM killer 杀死
- **cgroup OOM**：容器/cgroup 内存限制触发 OOM
- **内核态 OOM**：slab/shmem/内核模块等内核内存异常

---

## 第一步：解析用户输入，自动判断分析场景

**直接从用户的故障描述中提取关键信息，不询问用户，自主判断后立即进入分析流程。**

### 1.1 自动识别分析模式

根据用户描述中的关键词，按以下规则判断场景，**直接路由，无需询问**：

| 用户描述关键词 | 判断场景 | 分析路径 |
|--------------|----------|----------|
| 系统变慢/无响应/整机OOM/大量进程被杀/服务全部挂掉 | 系统级 OOM | → 路径 A |
| 某进程名/PID/进程被kill/exit 137/进程崩溃/内存持续增长 | 进程级 OOM | → 路径 B |
| 容器/Docker/K8s/cgroup/Pod OOM/memory limit | cgroup OOM | → 路径 C |
| slab异常/dentry/inode/tmpfs/内核内存/模块泄漏/crashkernel | 内核态 OOM | → 路径 D |

> 如果描述同时命中多个场景（如"容器内某进程OOM"），优先以更具体的场景为主（进程级），同时参考 cgroup 路径。

### 1.2 自动提取故障时间和目标进程

从用户输入中直接解析以下信息，**已有则直接使用，缺失才补充询问**：

- **故障时间**：用户已提供时间点时（如"14:30"、"昨天下午两点半"、"2024-01-15 14:30:00"），直接作为时间锚点使用；**未提供时才询问**
- **目标进程**：用户已提到进程名/PID 时直接使用；进程级故障**未提供时才询问**；系统级故障无需询问

> ⚠️ **时间点是所有后续分析的锚点**，所有日志查询、指标分析都应以此为基准，时间窗口默认取故障时间前后各 30 分钟。

---

## 第二步：信息收集（Step 1 - 基础信息收集）

### 2.1 执行信息收集脚本（基础信息 + 日志 一体化）

**将以下脚本提供给用户，在目标机器上执行**。参数直接从用户已提供的信息中填入，**无需二次询问**。

📄 **脚本**：`scripts/collect_basic_info.sh`

#### 参数说明

| 参数 | 含义 | 是否必填 |
|------|------|---------|
| `-S <时间>` | 故障时间段**开始时间**，格式 `YYYY-MM-DD HH:MM:SS` | 强烈建议 |
| `-E <时间>` | 故障时间段**结束时间**，未填则默认 +1 小时 | 可选 |
| `-p <PID>` | **精确进程 ID**，直接定位单个进程 | 三选一 |
| `-n <名称>` | **模糊进程名**，匹配命令行中包含该字符串的所有进程 | 三选一 |
| `-s <服务>` | **systemd 服务名**，通过 systemctl 定位进程 | 三选一 |

> `-p` / `-n` / `-s` 互斥，只选其一；系统级分析不填进程参数。

#### 调用示例（根据用户提供的信息直接生成命令）

```bash
# 系统级 OOM，给出完整时间段
bash collect_basic_info.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00"

# 精确 PID（用户已提供 PID）
bash collect_basic_info.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00" -p 12345

# 模糊进程名（用户描述"java 进程"）
bash collect_basic_info.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00" -n java

# 服务名（用户描述"nginx 服务"）
bash collect_basic_info.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00" -s nginx

# 只有开始时间（结束时间自动设为 +1h）
bash collect_basic_info.sh -S "2024-01-15 14:30:00" -n tomcat
```

该脚本**一次性完成**以下所有收集，无需分步执行：
- 系统内存快照与诊断指标（/proc/meminfo 自动判断异常）
- CPU & 内存压力指标（vmstat/sar）
- OOM 内核参数
- **时间段内 OOM 日志**（journalctl + /var/log/messages，以 `-S`/`-E` 为范围）
- OOM kill 事件完整上下文（含进程内存快照列表）
- 进程内存排名 Top 30 + OOM score 排名
- 目标进程详细内存分布（smaps_rollup / fd 泄漏检测）
- Slab 详情（dentry/inode/sock 重点对象）
- cgroup 内存使用与 failcnt 告警
- 内核模块列表（标记非发行版原生模块）
- NUMA 拓扑 & 内存碎片（buddyinfo）
- 历史监控数据（atop / sar，如已部署）

### 2.2 时间段日志筛查（脚本已内置）

脚本通过 `-S` / `-E` 参数直接限定日志提取范围，**无需额外手动筛查**。以下命令仅在用户想单独验证时使用：

```bash
# 手动验证：从 messages 中提取时间段内 OOM 关键字
START="2024-01-15 14:00:00"
END="2024-01-15 15:00:00"

journalctl -k --since="$START" --until="$END" --no-pager \
    | grep -E "Out of memory|oom_kill|Killed process"

# 或从文件日志提取（ISO 时间戳格式）
awk -v s="$START" -v e="$END" '
    match($0,/[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}/) {
        ts=substr($0,RSTART,19)
        if(ts>=s && ts<=e) print
    }
' /var/log/messages | grep -E "Out of memory|oom_kill"
```

> 如果用户**未提供故障时间段**，则在此步骤前询问开始时间（结束时间可自动 +1h），获取后再生成脚本命令。

---

## 第三步：分场景详细分析（Step 2 - 深度分析）

根据第一步**自动判断的场景**，直接跳转到对应分析路径，无需等待用户确认：

### 路径 A：系统级 OOM 分析

> **先执行专项采集脚本**，获得结构化摘要后再开始分析，避免逐条执行命令。

```bash
bash system_oom.sh -S "故障开始时间" -E "故障结束时间"
# 示例
bash system_oom.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00"
```

脚本输出包含 **[SUMMARY]** 节（模型优先阅读）：
- `S1` OOM kill 事件列表：时间 / 被杀进程 / score / anon-rss（结构化表格）
- `S2` 内存归因分类表：用户态(anon/cache/shmem) vs 内核态(slab/pt/vmalloc)，自动标记异常项
- `S3` 内存压力指标：oom_kill次数 / allocstall / kswapd回收量 / swap换入换出
- `S4` OOM 关键内核参数快照（panic_on_oom / overcommit 等）
- `S5` 超额提交评估（CommitLimit vs Committed_AS）

详细分析方法论见 `references/system-oom-analysis.md`

**分析要点**：
1. 读 S1 确认 OOM killer 触发次数和被杀进程
2. 读 S2 判断内存主要消耗方向（用户态 or 内核态）
3. 读 S3 评估 OOM 前内存压力程度
4. 检查 S4 参数是否符合预期配置

---

### 路径 B：进程级 OOM 分析

> **先执行专项采集脚本**，参数来源于用户已提供的进程信息，直接代入。

```bash
# 精确 PID
bash process_oom.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00" -p 12345
# 模糊进程名
bash process_oom.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00" -n java
# 服务名
bash process_oom.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00" -s nginx
```

脚本输出包含 **[SUMMARY]** 节（模型优先阅读）：
- `S1` 进程退出方式确认：dmesg OOM kill 记录 / journalctl exit code / 当前进程状态与峰值 RSS
- `S2` 进程内存分布汇总：heap / stack / anonymous_mmap / shared_lib 各段 RSS，附泄漏指标（匿名mmap段数 / fd数 / heap虚拟大小）
- `S3` 历史内存趋势：atop/sar 时间段内进程内存变化曲线
- `S4` 同类进程对比：判断是单进程异常还是所有同类进程均高

详细分析方法论见 `references/process-oom-analysis.md`

**分析要点**：
1. 读 S1 确认是否真为 OOM kill（exit code 137 / SIGKILL）
2. 读 S2 定位主要内存消耗段，查看泄漏指标是否告警
3. 读 S3 判断内存是单调递增（泄漏）还是随负载波动（正常）
4. 匿名 mmap 段 > 500 或 fd > 1000 需重点排查

---

### 路径 C：cgroup OOM 分析

> **先执行专项采集脚本**，可选传入容器 ID 或 cgroup 路径片段缩小范围。

```bash
# 全量扫描（自动找出有 failcnt > 0 的 cgroup）
bash cgroup_oom.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00"
# 指定容器 ID 或 cgroup 路径片段
bash cgroup_oom.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00" -g "abc123def456"
```

脚本输出包含 **[SUMMARY]** 节（模型优先阅读）：
- `S1` 存在 OOM 事件的 cgroup 汇总表：路径 / limit / usage / 使用率% / failcnt（自动过滤 failcnt=0）
- `S2` 所有有限制的 cgroup 视图（按使用率排序）
- `S3` 目标 cgroup 内进程内存分布（per-process RSS + OOM score）
- `S4` 容器运行时元数据（docker stats / docker inspect / kubectl top）
- `S5` 时间段内 cgroup OOM 内核日志

详细分析方法论见 `references/cgroup-oom-analysis.md`

**分析要点**：
1. 读 S1 快速定位哪个 cgroup 发生了 OOM（failcnt > 0）
2. 读 S3 确认 cgroup 内哪个进程消耗了最多内存
3. 读 S4 确认容器 memory limit 配置是否过小
4. 检查 oom_kill_disable 是否意外设置为 1（阻塞进程而非 kill）

---

### 路径 D：内核态 OOM 分析

> **先执行专项采集脚本**，脚本自动完成 D1~D4 四个子场景的判断，直接输出诊断结论。

```bash
bash kernel_oom.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00"
```

脚本输出包含 **[SUMMARY]** 节（模型优先阅读）：
- `S1` 内存归因精确计算：逐项列出各内存类型占用，并计算**未归因内存**（>512MB 告警）
- `S2` D1~D4 子场景自动诊断：
  - **D1** crashkernel 预留量 vs MemTotal，自动判断是否过大
  - **D2** 未归因内存分析 + vmalloc 主要消耗者 + 非原生内核模块列表
  - **D3** Shmem 占比 + tmpfs 挂载占用 + /dev/shm 大文件列表，自动判断是否异常
  - **D4** Slab 占比 + dentry/inode/proc_inode/sock 各对象大小，自动标注偏高项及可能触发原因
- `S3` 内存碎片化评估：buddyinfo 高阶空闲页是否充足

详细分析方法论见 `references/kernel-oom-analysis.md`

**分析要点**：
1. 读 S2 的 D1~D4 自动诊断结论，**已告警的子场景即为重点排查方向**
2. 未归因内存 > 512MB → 优先排查 D2（内核模块）
3. Slab > 15% → 读 D4 细项，按最大的 slab 对象类型判断触发行为
4. Shmem > 10% → 读 D3，定位 tmpfs 大文件来源进程

---

## 第四步：根因分析与反思（Step 3 - 根因定位）

### 4.1 根因分析框架

按以下维度逐一确认：

```
【时间链路确认】
- OOM 事件发生时间 T0
- 内存持续增长开始时间 T-N（N分钟/小时前）
- 触发阈值的时间 T-X
- 异常行为（操作/部署/配置变更）时间 T-Y

【因果链路确认】
- 直接原因（谁耗尽了内存）
- 根本原因（为什么会耗尽内存）
- 加速因素（什么让问题更快发生）
- 防护缺失（哪些机制没有拦住这个问题）
```

### 4.2 反思与交叉验证

在得出根因结论前，**必须执行以下反思检查**：

```
□ 时间线是否自洽？（内存增长时间点 → OOM时间点 是否连贯）
□ 证据是否充分？（至少2个独立来源印证根因）
□ 是否排除了其他可能？（逐一列举并说明排除理由）
□ 结论是否与系统配置一致？（OOM参数、cgroup限制等）
□ 如有源码分析，代码逻辑是否支持此根因？
```

### 4.3 输出标准化报告

使用以下模板输出报告：

```markdown
# OOM 故障分析报告

## 基本信息
- 故障时间：
- 分析时间：
- 影响范围：（系统级/进程名/cgroup路径）

## 故障根因
**根因类型**：（用户态泄漏 / cgroup OOM / slab膨胀 / shmem异常 / 内核模块 / kdump预留）

**根因描述**：
[一句话描述核心原因]

**置信度**：高/中/低
**置信依据**：[列出2-3条支撑证据]

## 故障链路
[触发动作] → [内存持续增长] → [触发阈值] → [OOM killer激活] → [进程被杀/系统异常]

## 时间链路
| 时间点 | 事件 | 证据来源 |
|--------|------|----------|
| T-Xm   | 异常行为开始 | messages/监控 |
| T-Ym   | 内存超过阈值 | /proc/meminfo |
| T0     | OOM killer触发 | dmesg |
| T+Zm   | 系统恢复/崩溃 | messages |

## 影响分析
- 被杀进程列表：
- 业务影响：
- 数据损失风险：

## 修复建议
### 临时措施（立即执行）
1.
2.

### 永久措施（根本解决）
1.
2.

### 预防措施
1.
2.

## 排除项
以下可能性已排除：
- [可能性1]：排除原因...
- [可能性2]：排除原因...
```

---

## 第五步：源码级分析（可选项）

> 当用户明确要求 "源码分析" 或 "代码级定位" 时执行此步骤。

详见 `references/kernel-source-analysis.md`

### 5.1 源码分析原则

- **禁止浅层分析**：不能只定位到某个函数名就停止
- **必须展示因果链**：从触发点 → 中间路径 → 最终效果，完整代码调用链
- **版本对齐**：先确认内核版本（`uname -r`），使用对应版本源码

### 5.2 源码分析框架

```
1. 确认内核版本和发行版
2. 在 https://elixir.bootlin.com/linux/ 定位相关源码
3. 从报错信息/调用栈反向追溯
4. 建立完整调用链（不少于3层）
5. 识别关键的数据结构变化
6. 说明为何此代码路径导致了OOM
```

### 5.3 常见源码分析入口

| OOM 场景 | 源码入口 | 关键文件 |
|----------|----------|----------|
| OOM killer 触发 | `out_of_memory()` | mm/oom_kill.c |
| 页面分配失败 | `__alloc_pages_nodemask()` | mm/page_alloc.c |
| slab 分配失败 | `kmem_cache_alloc()` | mm/slub.c |
| cgroup OOM | `mem_cgroup_oom()` | mm/memcontrol.c |
| mmap 内存申请 | `do_mmap()` | mm/mmap.c |
| 内存回收 | `try_to_free_pages()` | mm/vmscan.c |

---

## 常见 OOM 场景速查表

| 场景 | 关键特征 | 快速定位命令 |
|------|----------|-------------|
| 用户态进程泄漏 | RES持续增长，OOM kill特定进程 | `ps aux --sort=-%mem` |
| cgroup OOM | memory.failcnt增加，特定容器OOM | `cat /sys/fs/cgroup/memory/*/memory.failcnt` |
| Slab膨胀 | Slab >> 正常值，dentry/inode异常 | `slabtop -o` |
| Shmem异常 | Shmem >> 正常值，tmpfs大文件 | `df -h /dev/shm; lsof +D /tmp` |
| kdump预留 | MemTotal远小于物理内存 | `dmesg | grep -i "reserved\|crashkernel"` |
| 内核模块泄漏 | total >> anon+file+slab之和 | `lsmod; cat /proc/vmallocinfo` |

---

## 注意事项

1. **时间优先原则**：有故障时间点时，所有分析以时间为锚，避免分析噪音
2. **证据驱动**：每个结论必须有日志/指标/源码作为支撑
3. **区分现象与根因**：进程被杀是现象，内存泄漏才是根因
4. **不要过早收敛**：在排除其他可能性之前，不要断言唯一根因
5. **量化表达**：报告中的内存数据尽量给出具体数值，不用"较高"等模糊表述
