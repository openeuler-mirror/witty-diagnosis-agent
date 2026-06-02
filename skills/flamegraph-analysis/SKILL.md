---
name: flamegraph-analysis
description: |
  火焰图分析 Skill。当用户提供折叠栈(.folded)、火焰图SVG、perf script输出、Chrome cpuprofile、Go pprof、AsyncProfiler输出等性能采样数据，并提出"CPU为什么高"、"哪里是瓶颈"、"分析锁竞争"、"对比两次采样"、"GC压力"等分析意图时，必须使用此skill。支持多格式输入适配、SVG反向解析、自然语言意图识别、性能模式检测、On-CPU+Off-CPU联合分析，输出Markdown分析报告和可交互HTML火焰图。
---

# 火焰图分析 Skill (flamegraph-analysis)

## 概述

本 skill 提供完整的火焰图分析能力，支持多种性能采样格式输入，通过统一折叠栈中间表示进行规范化，结合自然语言意图识别和性能模式检测，输出结构化根因分析报告与交互式 HTML 火焰图。

### 核心功能

- **多格式适配**：支持 folded/perf/cpuprofile/pprof/async-profiler/svg 等十余种格式
- **SVG 反向解析**：从已有火焰图 SVG 还原折叠栈进行分析
- **意图驱动分析**：自然语言问题映射到分析剧本
- **模式检测**：识别锁竞争、GC 压力、I/O 等待等性能反模式
- **差分分析**：对比两份采样的差异
- **联合分析**：On-CPU + Off-CPU 联合定位瓶颈

---

## 分析策略（多剧本并行 + 交叉验证）

**当用户意图匹配多个剧本时，各剧本应并行执行，最终通过交叉验证收敛到高置信度结论。**

```
┌─────────────────────────────────────────────────────────────────┐
│                    多剧本并行分析模型                             │
│                                                                 │
│  轨道一：On-CPU 分析                  轨道二：Off-CPU 分析       │
│  ────────────────────                ──────────────────────    │
│  热点函数、CPU 归属、                  阻塞原因、调度延迟、      │
│  模式检测（GC/锁/序列化）              I/O等待、上下文切换        │
│                                                                 │
│            ↓                                   ↓               │
│            └────────────── 交叉验证 ────────────┘               │
│                              │                                  │
│                    轨道三：专项深度分析                          │
│                    差分对比 / 内存分配 / 深栈检测                 │
│                              │                                  │
│                              ↓                                  │
│                      反事实验证 → 报告                          │
└─────────────────────────────────────────────────────────────────┘
```

**各轨道的分工与互补**：

| | On-CPU 轨道 | Off-CPU 轨道 |
|--|------------|-------------|
| **回答的问题** | CPU 时间花在哪里？哪些函数是热点？ | 线程为什么不在运行？等待什么？|
| **优势** | 精确函数级耗时、调用链完整、模式可检测 | 揭示锁/IO/调度真正瓶颈、墙钟时间可见 |
| **局限** | 看不到阻塞时间、无法区分忙等与有效计算 | 栈可能不完整、受采样频率限制 |
| **典型盲区** | 自旋锁 CPU 空转被误判为有效计算 | I/O 完成后的唤醒路径短，难以捕获根因调用 |

**何时组合多剧本（联合分析必须做）**：

| 用户意图 | 剧本组合 | 原因 |
|---------|---------|------|
| "为什么慢" + 双采样文件 | `joint-on-off-cpu` 强制联合 | On-CPU + Off-CPU 数据同时存在 |
| "CPU 高 + 响应慢" | `why-cpu-high` + `scheduler-latency` | 需同时看计算端和等待端 |
| "GC 压力" | `gc-pressure` + `why-mem-high` | GC 根因常来自内存分配速率 |
| "锁竞争" + CPU 高 | `lock-contention` + `why-cpu-high` | 锁等待 vs 锁持有需要双视角 |
| "帮我分析/综合诊断" | 所有相关剧本同时执行 | 全面覆盖所有可能瓶颈 |

**何时可单剧本（不做交叉验证）**：目标明确且数据类型单一，如仅问"哪个函数 CPU 最高"（纯热点），或仅问"是否内存泄漏"（纯 alloc profile）。

> 执行约束：所有分析脚本的默认超时时间为 **3 分钟（180s）**。

---

## 触发条件

**同时满足以下两个条件时触发：**

1. **存在性能/采样数据**：用户提供 `.folded`、`.svg`、`.perf`、`.cpuprofile`、`.pprof`、`.jfr`、`.collapsed`、`.etl` 等文件，或上传含栈结构的文本日志
2. **存在分析/诊断意图**：用户提问包含"为什么 CPU 高"、"哪里是瓶颈"、"找出热点函数"、"对比两次采样"、"分析锁竞争"、"GC 压力"、"I/O 等待"等表达

**不触发场景：**
- 仅询问火焰图概念、工具用法
- 仅有性能日志但无诊断诉求
- 内存泄漏分析（除非是 alloc profile）

---

## 统一分析流程（基线收集 → 多剧本并行 → 交叉验证 → 反事实验证 → 输出）

### Step 1：启动（创建输出目录 + 基线信息收集）

```bash
OUTPUT_DIR="/tmp/flamegraph-analysis-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"
echo "Output directory: $OUTPUT_DIR"
```

记录基线信息（后续所有步骤都围绕它们推进）：
- 原始输入文件名（用于 HTML 火焰图"采样文件"字段展示，Step 8 会用到）
- 采样时长、事件类型、样本总数
- 输入文件列表和格式
- 用户分析意图（1 个或多个）
- 置信度初始评估（High/Medium/Low）

### Step 2：解析用户输入

从用户描述中提取，并显式输出以下结构（供后续交叉验证使用）：

```
分析意图：[热点定位 | 差分对比 | 锁竞争 | GC 压力 | I/O 等待 | 联合分析 | 综合诊断]
输入文件：<file1> [<file2> ...]
时间窗口：<开始-结束 | 无>
特定目标：[进程名 | 线程 | 模块 | 无]
```

### Step 3：格式探测与适配

调用 `scripts/detect_format.py` 探测输入文件格式：

| 格式 | 探测特征 | 适配器 |
|------|----------|--------|
| Folded Stack | 行尾整数 + `;` 分隔栈帧 | 直接使用 |
| DTrace | `unix\`fn+0x?` 栈块，空行分隔 | `adapters/dtrace_to_folded.py` |
| Perf script | `comm pid tid CPU TIMESTAMP: cycles:` | `adapters/perf_to_folded.py`（使用 `--all` 启用内核/JIT 注解） |
| cpuprofile | JSON 含 `nodes/samples/timeDeltas` | `adapters/cpuprofile_to_folded.py` |
| Go pprof | protobuf magic 或 `-collapsed` 文本 | `adapters/pprof_to_folded.py` |
| AsyncProfiler | `.jfr`/`.html`/`.collapsed` | `adapters/asyncprofiler_to_folded.py` |
| BCC/bpftrace | `-` 分隔栈、末尾计数 | `adapters/bcc_to_folded.py` |
| V8 --prof | `code-creation,` / `tick,` tag | `adapters/v8log_to_folded.py` |
| SVG 火焰图 | XML + `<rect>` + `<title>` 含样本数 | `adapters/svg_to_folded.py` |

**适配器调用规范：**

所有适配器脚本均支持以下调用方式：
1. **位置参数**（推荐）：`python adapters/xxx_to_folded.py input.txt`
2. **--input 参数**：`python adapters/xxx_to_folded.py --input input.txt`
3. **管道输入**：`cat input.txt | python adapters/xxx_to_folded.py`

**常用适配器调用示例：**

```bash
# Perf script → folded（推荐使用 --all 启用所有注解）
python adapters/perf_to_folded.py --input perf-output.txt --all --output output.folded

# cpuprofile → folded
python adapters/cpuprofile_to_folded.py profile.cpuprofile --output output.folded

# pprof → folded
python adapters/pprof_to_folded.py profile.pprof --output output.folded

# AsyncProfiler → folded
python adapters/asyncprofiler_to_folded.py profile.jfr --output output.folded

# SVG → folded
python adapters/svg_to_folded.py flamegraph.svg --output output.folded

# DTrace → folded
python adapters/dtrace_to_folded.py --input dtrace.out --output output.folded

# BCC/eBPF → folded
python adapters/bcc_to_folded.py bcc-output.txt --output output.folded

# bpftrace → folded
python adapters/bpftrace_to_folded.py --input bpftrace.out --output output.folded

# SystemTap → folded
python adapters/stap_to_folded.py --input stap.out --output output.folded

# V8 log → folded
python adapters/v8log_to_folded.py v8.log --output output.folded

# Java jstack → folded（需要多次采集）
python adapters/jstack_to_folded.py --input jstacks.txt --output output.folded

# FreeBSD pmcstat → folded
python adapters/pmc_to_folded.py --input pmcstat.out --output output.folded

# Windows ETW → folded
python adapters/etw_to_folded.py --input etw.etl --output output.folded

# Python faulthandler → folded
python adapters/faulthandler_to_folded.py --input faulthandler.log --output output.folded

# GDB backtrace → folded
python adapters/gdb_to_folded.py --input gdb-backtrace.txt --output output.folded

# Java exceptions → folded
python adapters/java_exceptions_to_folded.py --input exceptions.log --output output.folded

# LuaJIT profile → folded
python adapters/ljp_to_folded.py --input ljp-profile.txt --output output.folded

# Intel VTune → folded
python adapters/vtune_to_folded.py --input vtune.csv --output output.folded

# Xdebug trace → folded
python adapters/xdebug_to_folded.py --input xdebug-trace.txt --output output.folded
```

**注意事项：**
- 所有适配器均支持 `--input`/`-i` 和 `--output`/`-o` 参数
- 若无 `--output`，结果输出到标准输出
- 可通过 `--help` 查看各适配器的完整参数说明
- `perf_to_folded.py` 使用 `--all` 可同时启用内核/JIT/内联注解

**SVG 反向解析特殊处理：**
- 识别生成器（flamegraph.pl / async-profiler / speedscope）
- 解析 `<title>` 获取样本数和百分比
- 按 `<rect>` 几何关系重建栈层次
- 输出覆盖率报告和置信度标注

### Step 4：意图识别与剧本选择（分支决策）

根据用户问题映射到对应 playbook。若匹配多个分支必须按顺序全部执行，不可只选其一：

```
用户意图
  ├─ "CPU 高/瓶颈在哪/top 函数"                         → playbooks/why-cpu-high.md
  ├─ "变慢/回归/before-after"                             → playbooks/compare-two-profiles.md
  ├─ "锁竞争/互斥/同步"                                    → playbooks/lock-contention.md
  ├─ "GC/垃圾回收/内存抖动"                               → playbooks/gc-pressure.md
  ├─ "I/O/阻塞/等待/慢 syscall"                           → playbooks/io-wait.md
  ├─ "递归/死循环/深栈"                                    → playbooks/deep-stack.md
  ├─ "上下文切换高/cs 高/线程多"                          → playbooks/why-context-switch.md
  ├─ "内存高/RSS/OOM/分配速率"                            → playbooks/why-mem-high.md
  ├─ "序列化慢/JSON 慢/Protobuf 慢"                      → playbooks/serialization-cost.md
  ├─ "HTTPS 慢/TLS 慢/加密慢"                             → playbooks/crypto-ssl-cost.md
  ├─ "数据库慢/SQL 慢/连接池"                              → playbooks/db-driver-cost.md
  ├─ "sleep 多/调度延迟/响应慢"                            → playbooks/scheduler-latency.md
  ├─ "swap/换入/缺页/page fault"                          → playbooks/page-fault-swap.md
  ├─ "为什么慢" + 双采样                                    → playbooks/joint-on-off-cpu.md
  └─ "帮我分析/有什么问题"                                 → 综合所有 relevant playbooks
```

**模糊意图处理**：先做概览扫描（hotspot top 10 + 基础统计），再向用户提澄清问题。

### Step 5：分析引擎处理（逐剧本证据收集）

按 playbook 调用对应分析器，输出到 `$OUTPUT_DIR`。每个分析器必须产出明确的证据条目：

```bash
# 统计分析 → 产出：样本总数、唯一栈数、深度分布、Top N 占比
python scripts/analyzers/stats.py --input folded.folded --output $OUTPUT_DIR/stats.json

# 热点函数分析 → 产出：函数名、样本数、占比%、调用者/被调用者
python scripts/analyzers/hotspot.py --input folded.folded --top 20 --output $OUTPUT_DIR/hotspot.json

# 模式匹配分析 → 产出：匹配模式名、匹配栈、置信度、样本数
python scripts/analyzers/pattern_match.py --input folded.folded --patterns-file references/analysis-patterns.md --output $OUTPUT_DIR/patterns.json

# CPU 归属分析 → 产出：模块/子系统级 CPU 占比
python scripts/analyzers/attribution.py --input folded.folded --output $OUTPUT_DIR/attribution.json

# 整合分析结果生成 findings → 产出：F-001..F-N 结构化发现列表
python scripts/analyzers/findings_generator.py \
    --input folded.folded \
    --patterns-file references/analysis-patterns.md \
    --hotspots $OUTPUT_DIR/hotspot.json \
    --attribution $OUTPUT_DIR/attribution.json \
    --output $OUTPUT_DIR/findings.json

# 差分分析 → 产出：增长/下降函数列表、差异量、占比变化
python scripts/analyzers/diff.py --baseline baseline.folded --target target.folded

# Off-CPU 分析 → 产出：叶帧分类、阻塞原因分布
python scripts/analyzers/offcpu_classifier.py --input offcpu.folded
python scripts/analyzers/bottleneck_classifier.py --on-cpu oncpu.folded --off-cpu offcpu.folded
```

**Step 5 必须输出的证据清单**（供后续交叉验证使用）：

```
E1 热点 Top N：[函数名, 样本数, 占比%]
E2 CPU 归属：[用户态/内核态/GC/空闲 占比]
E3 模式匹配命中：[模式名, 匹配栈路径, 置信度]
E4 Findings 列表：[F-001..F-N，每个含 title/description/evidence/causal_chain]
E5（如适用）差分增长：[函数名, 基线样本数, 目标样本数, Δ%]
E6（如适用）Off-CPU 分类：[阻塞类型, 样本数, 占比%]
```

### Step 6：交叉验证（多剧本结果汇合，冲突仲裁，置信度收敛）

**当执行了多个 playbook 时，必须做交叉验证。** 对每个证据对齐检查：

| 验证维度 | 剧本 A 结论 | 剧本 B 结论 | 是否吻合？ |
|---------|-----------|-----------|-----------|
| 瓶颈定位 | 热点在 `<func_A>` | 阻塞在 `<func_B>` | □ 吻合 □ 不符 |
| CPU 归属 | CPU 热点占比 X% | 模块/子系统占比 Y% | □ 吻合 □ 不符 |
| 时间构成 | On-CPU 占比 X% | Off-CPU 占比 Y%，X+Y≈100%？ | □ 吻合 □ 不符 |
| 因果链 | A→B→C 瓶颈路径 | 根因在 D→A 上游 | □ 吻合 □ 不符 |
| 触发条件 | 在负载 Z 时触发 | 在并发度 W 时触发 | □ 吻合 □ 不符 |

不一致时的仲裁原则：

```
热点/占比数据：优先信任 On-CPU 采样（精确计数）
阻塞原因：优先信任 Off-CPU 采样（直接观测阻塞点）
根因归属：On-CPU 与 Off-CPU 矛盾时，Off-CPU 根因层级更深（阻塞才是真瓶颈）
```

置信度收敛：

- 高：多剧本结论完全一致 + 反事实验证通过
- 中：多剧本基本吻合，但有 1 个维度依赖推断；或仅完成单剧本
- 低：多剧本存在矛盾且无法解释；或证据链缺失超过两环节
- 数据受限：SVG 还原 / 样本稀疏导致分析降级

### Step 7：反事实验证（强制；不能止步于"找到热点函数"）

用分析假设正向推演，并与数据现象逐条对齐：

```
✓ 假设的瓶颈函数是否在热点 Top 10 中？
✓ 假设的瓶颈占比 == 数据中观测到的占比？
✓ 假设的调用路径 == 数据中观测到的栈路径？
✓ 因果链中每个环节都有对应的证据栈支撑？
```

四条全 ✓ 才能判定"根因确认"。否则需回到 Step 5 补证据或调整假设。

### Step 8：生成报告与可视化 + 输出交付物

> **【关键步骤，必须执行】** 此步骤按顺序执行：生成根因总结 → 预处理 findings → 生成火焰图层级 JSON → 生成 HTML → 打印 Markdown 报告。
>
> **注意**：HTML 火焰图保存为文件，Markdown 报告**不落盘**，在对话中直接输出。

**1. 生成根因总结（大模型分析，灵活生成）**

读取 `$OUTPUT_DIR/findings.json` 中的 findings 列表，综合分析后生成一句根因总结文本（中文，50-200 字），覆盖：主要瓶颈是什么、根因追溯、严重程度总览。

> 此步骤由大模型完成，无需脚本。

**2. 预处理 findings.json（注入 causal_analysis，供 HTML 和 Markdown 共用）**

将上一步生成的根因总结传入脚本，由脚本完成固定的结构化处理（推断关系、生成修复优先级、写回 findings.json）：

```bash
python scripts/findings_finalize.py \
    --input $OUTPUT_DIR/findings.json \
    --summary "<大模型生成的根因总结文本>" \
    --output $OUTPUT_DIR/findings.json
```

**3. 转换为火焰图层级 JSON**

```bash
python scripts/render/folded_to_hierarchy.py \
    --input folded.folded \
    --findings $OUTPUT_DIR/findings.json \
    --output-dir $OUTPUT_DIR
```

**4. 生成交互式 HTML 火焰图（保存到文件）**
> `--filename` 必须使用用户在输入中指定的原始性能文件路径/名称（来自 Step 2 解析结果），而非中间产物 `folded.folded`。`--duration`、`--confidence` 等元数据也使用 Step 1 基线信息中记录的实际值。

```bash
python scripts/render/render_html.py \
    --input $OUTPUT_DIR/profile-data.json \
    --findings $OUTPUT_DIR/findings.json \
    --title "Flame Graph" \
    --filename "<用户在输入中指定的原始性能文件名>" \
    --format "<Step 3 探测到的原始格式>" \
    --event "<Step 1 记录的事件类型>" \
    --duration "<Step 1 记录的采样时长>" \
    --confidence "<Step 1 记录的置信度>" \
    --output-dir $OUTPUT_DIR
```

**验证检查**：执行完上述命令后，务必确认在 `$OUTPUT_DIR` 目录下存在：
- `flamegraph.html` 已生成且非空，页面中的"采样文件"字段显示的是用户指定的原始文件名

**5. 生成 Markdown 分析报告（直接打印到屏幕，不落盘）**

根据 `templates/analysis-report.md` 模版格式，读取 `$OUTPUT_DIR/findings.json`（已含 causal_analysis.summary/relations/fix_priority）动态生成报告内容，**直接在对话中输出**：
- 报告中的关键发现（F-001、F-002...）必须直接复用 findings.json 中已有的 findings，保持原有 ID/数量/title/description/evidence，只可补充分析解释
- **将报告文本直接打印在对话中**，不写入文件

**最终交付**：
- 通过 `present_files` 交付 `$OUTPUT_DIR/flamegraph.html` - 可交互 HTML 火焰图
- Markdown 格式分析报告 **直接在对话中输出**，不保存为文件

> 如果缺少 flamegraph.html，需要回到 Step 5 / Step 8 重新生成。
## 常见误判陷阱（复核结论质量时必查）

- **热点函数 ≠ 瓶颈根因**：Top 1 函数可能只是无辜的被调用者，真正的瓶颈是其上游调用者的低效循环或过多的调用次数
- **采样偏差掩盖短函数**：低于采样频率的短函数（<10ms）可能完全不出现在栈中，但其累积效应可能很大
- **自旋锁 vs 有效计算混淆**：`pthread_spin_lock` / `__mutex_lock` 内部自旋的 CPU 时间在 On-CPU 火焰图中看起来像有效计算，实为等待
- **JIT 内联导致栈缺失**：JIT 编译的内联函数在栈中不可见，导致调用链不完整，无法还原真实调用路径
- **Off-CPU 采样盲区**：极短时间的阻塞（< 采样间隔）可能被遗漏，高频锁竞争可能被低估
- **系统空闲被误判为瓶颈**：On-CPU 火焰图中的 `idle`/`swapper` 占比高不代表问题，需结合负载判断
- **内存分配路径不等于内存泄漏**：alloc profile 中热点分配路径只是分配速率高，不一定导致泄漏；需配合 RSS 趋势判断
- **单次采样的偶然性**：一次 30s 采样可能恰好捕获异常峰值或低谷，结论需标注时间窗口局限性

---

## JIT/编译器优化陷阱

火焰图中的栈信息受编译优化影响，以下情况可能导致栈轨迹失真：

| 优化行为 | 现象 | 应对方式 |
|---------|------|---------|
| JIT 方法内联 | 栈中缺少中间调用帧，热点集中在父帧 | 用 `-XX:+UnlockDiagnosticVMOptions -XX:+PrintInlining` 查看内联决策 |
| 尾调用优化 | 调用方帧被复用，bt 中少一层 | 结合源码判断是否尾调用场景 |
| 编译优化消除 | 不产生调用帧（如短小方法直接展开） | 看父帧的代码行数 / 调用次数是否异常 |
| DWARF 栈展开失败 | perf 栈中出现 `[unknown]` 或截断 | 使用 `--call-graph dwarf` 或 `lbr`，安装 debuginfo |
| Frame Pointer 省略 | 使用 `--call-graph fp` 时栈不完整 | 优先使用 `dwarf` 或 `lbr` 栈展开 |
| 内联 + 采样频率共振 | 周期性出现在同一个内联帧 | 改用质数采样频率（如 97 Hz / 103 Hz）避免与周期任务对齐 |

---

## 边界与失败处理

### 置信度等级

| 等级 | 条件 | 限制 |
|------|------|------|
| High | 原始 folded 格式输入，样本数充足 | 无功能限制 |
| Medium | SVG 还原 / 百分比-only 数据 | diff 功能降级，样本数相关分析受限 |
| Low | SVG 解析覆盖率 < 70% / 数据严重稀疏 | 仅支持基础 hotspot，模式检测结果需标注低置信 |

### 降级有声策略

任何过滤、裁剪、还原决策必须显式记录在报告中：
- "SVG 解析覆盖率 85%，丢失原因为 minwidth 过滤"
- "差分分析降级：百分比-only 数据，无法计算绝对差值"

### 失败处理

| 失败场景 | 处理方式 |
|----------|----------|
| 格式无法识别 | 展示文件前 20 行，请求用户确认格式 |
| SVG 解析失败 | 降级为仅解析 `<title>` 文本，标注低置信 |
| 样本数过少 (< 10) | 拒绝分析，返回"样本数不足" |
| 差分 SVG | 识别并拒绝，提示"差分图原始数据不可还原" |

---

## 报告结构概要

最终报告应覆盖以下结构（完整格式参考 `templates/analysis-report.md`）：

```
## 性能分析概要
  采样文件：<files>
  采样时长：<duration>
  样本数：<N>
  置信度：<高/中/低>
  分析轨道：[单剧本 | 多剧本并行（剧本A + 剧本B） | 联合] 

## 一句话结论
  <根因总结，关联多个 finding>

## CPU 时间去向
  <总览分布图>

## 关键发现（按严重程度排序）
  F-001 · <finding title>
    结论：<一句话>
    证据链：<调用栈路径 + 样本占比>
    根因分析：<为什么会出现这个现象>
    修复建议：<分级建议>
  F-002 · ...

## 根因分析：因果关系图
  <多个 finding 之间的因果关联 ASCII 图>

## 交叉验证结果（多剧本时填写）
  瓶颈定位吻合：□ 是  □ 否（差异说明：<...>）
  CPU 归属吻合：□ 是  □ 否（差异说明：<...>）
  因果链吻合：  □ 是  □ 否（差异说明：<...>）
  综合判断：<多剧本结论是否一致，若有矛盾如何解释>

## 排除的替代假设
  - <假设X>：排除原因 <...>

## 立即可执行的清单
  <分级行动项>

## 需要进一步采样验证的问题
  <补充采样建议>

## 附录
  采样命令、数据来源说明、阈值参数、术语速查
```

---

## 参考文件索引

- `references/analysis-patterns.md`：性能反模式特征库（锁竞争/GC/IO 等模式的栈特征）
- `references/offcpu-patterns.md`：Off-CPU 叶帧分类特征（futex_wait/epoll_wait/sleep 等阻塞模式）
- `templates/analysis-report.md`：Markdown 分析报告模板
- `templates/flamegraph-viewer.html`：HTML 火焰图查看器模板
- `playbooks/*.md`：各场景的分析剧本（参数配置 + 分析思路 + 典型栈模式）
---

## 目录结构

```
flamegraph-analysis/
├── SKILL.md                              主入口
├── references/
│   ├── analysis-patterns.md              性能反模式特征库
│   └── offcpu-patterns.md                Off-CPU 叶帧分类特征
├── scripts/
│   ├── detect_format.py                  格式探测
│   ├── findings_finalize.py              findings 预处理（注入 causal_analysis）
│   ├── adapters/                         格式适配器
│   │   ├── dtrace_to_folded.py          DTrace 转折叠栈
│   │   ├── perf_to_folded.py            perf script 转折叠栈
│   │   ├── cpuprofile_to_folded.py      Chrome cpuprofile 转折叠栈
│   │   ├── pprof_to_folded.py           Go pprof 转折叠栈
│   │   ├── asyncprofiler_to_folded.py   AsyncProfiler 转折叠栈
│   │   ├── bcc_to_folded.py             BCC/bpftrace 转折叠栈
│   │   ├── v8log_to_folded.py           V8 --prof 日志转折叠栈
│   │   ├── etw_to_folded.py             ETW 转折叠栈
│   │   └── svg_to_folded.py             SVG 火焰图反向解析为折叠栈
│   ├── detect_format.py                  格式探测
│   ├── adapters/                         格式适配器
│   │   ├── dtrace_to_folded.py          DTrace 转折叠栈
│   │   ├── perf_to_folded.py            perf script 转折叠栈
│   │   ├── cpuprofile_to_folded.py      Chrome cpuprofile 转折叠栈
│   │   ├── pprof_to_folded.py           Go pprof 转折叠栈
│   │   ├── asyncprofiler_to_folded.py   AsyncProfiler 转折叠栈
│   │   ├── bcc_to_folded.py             BCC/bpftrace 转折叠栈
│   │   ├── v8log_to_folded.py           V8 --prof 日志转折叠栈
│   │   ├── etw_to_folded.py             ETW 转折叠栈
│   │   └── svg_to_folded.py             SVG 火焰图反向解析为折叠栈
│   ├── analyzers/                        分析引擎
│   │   ├── hotspot.py                    热点函数分析
│   │   ├── pattern_match.py              性能模式匹配
│   │   ├── diff.py                       差分分析
│   │   ├── attribution.py                CPU 时间归属分析
│   │   ├── stats.py                      基础统计分析
│   │   ├── offcpu_classifier.py          Off-CPU 分类
│   │   ├── bottleneck_classifier.py      瓶颈分类
│   │   └── findings_generator.py         整合分析结果生成 findings
│   └── render/
│       ├── folded_to_hierarchy.py         折叠栈转火焰图层级 JSON
│       └── render_html.py                 生成交互式 HTML 火焰图
├── templates/
│   ├── flamegraph-viewer.html            HTML 火焰图模板
│   └── analysis-report.md               Markdown 分析报告模板
└── playbooks/
    ├── why-cpu-high.md                   CPU 热点定位剧本
    ├── compare-two-profiles.md            差分对比分析剧本
    ├── lock-contention.md                 锁竞争专项剧本
    ├── gc-pressure.md                     GC 压力专项剧本
    ├── io-wait.md                        I/O 等待专项剧本
    ├── deep-stack.md                      深栈检测剧本
    ├── why-context-switch.md             上下文切换专项剧本
    ├── why-mem-high.md                    内存分配与泄漏专项剧本
    ├── serialization-cost.md              序列化反序列化专项剧本
    ├── crypto-ssl-cost.md                 加解密与 TLS 专项剧本
    ├── db-driver-cost.md                  数据库驱动层专项剧本
    ├── scheduler-latency.md               Off-CPU 调度延迟专项剧本
    ├── page-fault-swap.md                 页错误与 swap 专项剧本
    └── joint-on-off-cpu.md               On/Off-CPU 联合分析剧本
```
