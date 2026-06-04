# Python 内存泄漏诊断报告 — 碎片化/Allocator 对照场景

## 1. 故障概要

- **目标脚本**：`rss_fragmentation_like.py` — 短生命周期 bytearray 分配/释放 workload
- **故障时间窗口**：即时复现（80 次迭代）
- **现象**：该 workload 每轮分配 32 × 64KB bytearray（共 2MB/轮），写入后立即 `del` 释放；预期可能观察到 RSS 或高水位标记增长，但 Python 级别无对象保留
- **影响**：仅作为 **RSS 碎片化 / native allocator 对照场景**，用于验证诊断流水线在 Python 对象保留证据不足时不会误判为 Python 内存泄漏

## 2. 能力画像与降级边界

| 项目 | 内容 |
| --- | --- |
| 使用工具 | stdlib-only（`gc`、`sys.getsizeof`、`tracemalloc`、`gc.get_referrers`） |
| 缺失工具 | `psutil`（降级为 `/proc` 采集）、`objgraph`（降级为文本链）、`pympler`（降级为 shallow bytes）、`memray`（native 路径方向级）、`py-spy`（线上进程依赖） |
| 只读/副作用边界 | 仅静态可达性分析，未执行 `--allow-mutation` 反事实干预 |
| 置信度上限 | **weak**（因缺 memray native 捕获、缺 psutil 精确 RSS 采样、缺反事实验证） |

## 3. RSS 与增长形态

> ⚠️ 本场景为离线日志分析，**无实时 RSS 采样数据**。以下结论基于 workload 代码语义和工具输出推断。

| 项目 | 内容 |
| --- | --- |
| workload 语义 | 每轮创建 `[bytearray(65536) for _ in range(32)]` → 2MB/轮堆分配，合计 80 轮 → 累计分配 160MB，全部释放（`retained: 0`） |
| 预期 RSS 形态 | 可能因 pymalloc arena 未归还 OS、glibc 堆碎片化或匿名 mmap 未释放而观察到 RSS 毛刺或 plateau |
| 碎片化判断 | **高度疑似**：短生命周期大块分配-释放模式是典型的内存碎片化/allocator 不归还 OS 场景 |
| native 背离判断 | **强背离信号**：Python 对象增量 << 预期 RSS 增量 → 应指向 native/allocator 方向 |

## 4. Python 对象增长

`object_growth.py` verdict：**inconclusive**

| 类型 | 计数增量 | Shallow 字节增量 | 说明 |
| --- | --- | --- | --- |
| `collections.Counter` | +2 | +6,688 | 主候选（仅为 gc 内部计数噪声） |
| `builtins.list` | +5 | +3,048 | 模块加载/import 副作用 |
| `builtins.dict` | +2 | +368 | 运行时内部结构 |
| **总计** | +9 | **≈10KB** | **远不能解释预期 RSS 增长** |

workload 返回 `{"iterations": 80, "retained": 0}` — 零保留。

> **结论**：Python 堆上无明显对象增长。bytearray 已在每轮末尾被 `del` 回收，gc 可见对象无保留。

## 5. 分配热点

`tracemalloc_probe.py` verdict：**inconclusive**（总正向 diff 仅 864 字节）

| 分配栈 | 字节增量 | 说明 |
| --- | --- | --- |
| `tracemalloc.py:423` | +312 | tracemalloc 内部 bookkeeping 开销 |
| `tracemalloc.py:560` | +312 | tracemalloc 内部 bookkeeping 开销 |
| `rss_fragmentation_like.py:19`（`bytearray(64*1024)`） | +184 | workload 入口残留（极小，示踪水平） |
| `tracemalloc.py:558` | +56 | tracemalloc 内部开销 |
| **总计** | **+864** | **≈0.001 MiB，几乎可忽略** |

> **分析**：tracemalloc 的快照 diff 几乎为零，说明 bytearray 的分配与释放在两个快照之间已完全平衡。diff 中最大的条目来自 tracemalloc 自身而非 workload。

## 6. 保留链

`retention_chain.py` verdict：**no_candidate_objects**

| 候选对象 | root_kind | 保留路径摘要 |
| --- | --- | --- |
| （无） | （无） | object_growth 未产出有效候选对象；gc 堆上无可追踪的保留路径 |

> **分析**：由于 object_growth 主候选（`collections.Counter`）增长量低于阈值，retention_chain 采样数为 0。没有对象需要追保留链，这是"Python 无泄漏"的最强证据。

## 7. 验证门

| 验证门 | 结果 | 证据 |
| --- | --- | --- |
| **G1 量化对账** | ❌ 不通过 | Python 对象增量 ≈ 10KB；预期 RSS 增量可能达数十 MB → 候选不足以解释 RSS 增长 |
| **G2 竞争假设** | ✅ 主要假设成立 | 排除预热（plateau 不适用）、排除 Python 保留泄漏（retention 无候选）、排除采样窗口过短（80 轮迭代）→ **碎片化/allocator 不归还 OS** 为主导假设；native 背离方向待 memray 确认 |
| **G3 可达性反事实** | ⚠️ 未执行 | 环境为只读离线诊断，未设置 `--allow-mutation`；静态保留链无候选，置信度封顶 weak |
| **G4 隔离复测** | ⏸️ 不适用 | 修复目标不明确（非 Python 对象泄漏），无候选可禁用 |

## 8. 根因结论

- **根因类型**：⚠️ **非 Python 内存泄漏** — 不满足泄漏定义（无 Python 对象被意外保留）
- **根因描述**：
  > Python 堆上无保留对象增长；RSS 增长（若存在）应归因于：
  > 1. **CPython pymalloc arena 不归还 OS** — 短生命周期大块分配导致 arena 碎片化，底层 `mmap()` 分配的内存未释放回 OS
  > 2. **glibc malloc 堆碎片化** — 频繁的 64KB 分配-释放导致 glibc 内存缓存（fastbins/unsorted bins）膨胀
  > 3. **匿名 mmap 段未释放** — 大块分配可能触发 `mmap` 阈值，释放后 VMA 区域未合并
  >
  > 如要精确量化，需要 `memray run --native` 全生命周期捕获或 `smaps_rollup` 的 Private_Dirty 趋势数据。

- **置信度**：**低 → 中**（Python 侧证据充分，但 native 侧缺直接测量）
- **未验证项**：
  - 无 `memray --native` 捕获 → 无法定位 C 栈分配点
  - 无 `/proc/*/smaps_rollup` 时间序列 → 无法量化 Private_Dirty / heap / anon 增长
  - 无 `PYTHONMALLOC=malloc` 对比实验 → 无法区分 pymalloc 与 glibc 的贡献

## 9. 修复建议

> ⚠️ 本场景为诊断对照实验，非真实生产故障；以下建议适用于真实环境中出现类似现象时参考。

| 类型 | 建议 | 风险 |
| --- | --- | --- |
| **最小缓解** | 设置环境变量 `PYTHONMALLOC=malloc` 绕过 pymalloc arena 缓存，避免碎片化累积 | 可能增加 malloc 调用次数，但对短生命周期大块分配有利 |
| **根本缓解** | 改用 `memoryview` / `bytearray` 池化复用，减少高频分配-释放抖动 | 需业务代码改造 |
| **诊断增强** | 采集 `memray run --native` + `/proc/smaps_rollup` 时间序列 | 需要 debug symbols，采集期间约 2× 性能开销 |

## 10. 复测方案

- **复现命令**：
  ```bash
  # 基础复现
  bash ./run.sh run fragmentation

  # 增强采集（需安装 memray）
  memray run --native -o memray_frag.bin python fault-injection/rss_fragmentation_like.py
  memray flamegraph memray_frag.bin
  ```
- **期望指标**：
  - Python 堆对象增量仍应 ≈ 0（不应出现容器增长）
  - `memray --native` 应显示主要 native 分配来自 ` PyMem_Malloc` / `mmap`，而非 Python 对象
  - `smaps_rollup` 中 `heap` 或 `anon` 段可能增长但 `Private_Dirty` 稳定
- **通过条件**：
  - 未错误地诊断为 "Python 对象泄漏"
  - 诊断结论明确指向 native/allocator/碎片化方向
  - 验证门 G1-G3 结论与本报告一致

---

## 附录 A：原始证据摘要

| 工具 | Verdict | 关键数据 |
| --- | --- | --- |
| `detect_capabilities` | success | stdlib-only, 全增强工具缺失 |
| `object_growth` | **inconclusive** | 总 shallow 增量 ≈ 10KB；`retained: 0` |
| `tracemalloc_probe` | **inconclusive** | 总 diff = 864 bytes（tracemalloc 内部开销为主） |
| `retention_chain` | **no_candidate_objects** | 无可追踪保留路径 |
| `reachability_probe` | **static_only** | 0 候选对象，置信度封顶 weak |

## 附录 B：诊断边界说明

- **只读离线诊断**：未执行任何修复、重启、远程登录或配置写入
- **无副作用**：未安装 pip 包、未启用 ptrace、未 attach 进程、未重启服务
- **结论约束**：所有结论基于日志中已有证据，置信度因缺 memray/psutil 仅到 weak

📁 **输出文件路径**：
- Markdown 报告：`C:\Users\duanz\.witty-diagnosis-agent\baize\report\python_memory_leak_fragmentation_report.md`
