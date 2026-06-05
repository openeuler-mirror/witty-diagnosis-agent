# 工具选择与降级路径

本文件只负责选择工具和说明降级能力。证据字段判读、竞争假设和根因措辞统一写在 `evidence-analysis.md`。

| 档位 | 工具 | 能力 | 缺失时 |
| --- | --- | --- | --- |
| Tier 0 | stdlib `os/pathlib/json`、`gc`、`tracemalloc`、`weakref`、`sys`、`inspect`、`asyncio`、`/proc` | 范围内证据自动发现、Live PID 只读定界、复现脚本级对象增长、模块全局语义信号、分配热点、保留链、RSS/cgroup/worker 趋势和证据对账 | 最低档，必须可运行 |
| Tier 1 | `psutil`、`objgraph`、`pympler` | 更可移植采样、引用图、深度 size | 使用 `/proc`、`gc.get_referrers`、`sys.getsizeof` 和 `semantic_probe.py` |
| Tier 2 | 已有外部 profiler 产物，例如 memray 文本报告或 capture | Python/native allocation 方向增强 | 只能做 RSS-vs-Python 堆背离方向判断 |
| Tier 3 | py-spy/pyrasite/gdb/ptrace 等线上注入或 attach 工具 | 线上进程运行栈和 C 栈深挖 | 本 skill 默认不执行；需要单独审批和风险说明 |

路由原则：

- 可复现可重启：优先用 `--script` 跑完整 Python 堆路径。
- 低输入但有范围目录、PID、服务名或日志包：先运行 `discover_evidence.py <scope>`，再按 `recommendation.recommended_path` 路由；不得首轮要求用户列出全部日志和 JSON。
- 低输入且没有明确路径：在当前目录运行 `discover_evidence.py .`，同时检查 `logs/`、`out/`、`reports/`、`snapshots/`、`test/`；仍无发现时才追问故障范围。
- 已运行线上 PID：先用 `live_process_snapshot.py --pid` 只读定界，再用 `monitor_rss.py --pid` 外部观测；attach 需要单独审批。
- 报告前：运行或读取 `correlate_evidence.py` 产物，把 `verdict`、`confidence_cap` 和 `missing_evidence` 作为根因措辞总闸门。
- 依赖状态为 unknown 时按缺失处理，避免误判能力。

工具升级判断：

- `objgraph` 适合在保留链复杂时生成更直观 backref graph，但不是默认依赖；无图形环境或无 `dot` 时仍用文本链。
- `pympler` 适合补深度 size，对“浅层对象计数增长但真实 payload 在嵌套结构里”的场景更有价值；缺失时报告要标注 `sys.getsizeof` 低估嵌套对象。
- `memray` 适合 native/C 扩展、allocator 背离和可控可重启场景；它能跟踪 Python、native extension 和解释器自身的 allocation，并生成 flamegraph/table/summary 等报告。当前官方实现不支持 Windows，因此在 Witty/openEuler/Linux 测试环境中作为 Tier 2 增强，在 Windows 本地只保留解析已有报告或给采集建议。
- `py-spy` 更偏采样 profiling，不直接替代 heap 保留链；只在需要低侵入了解运行栈或确认进程活跃路径时作为辅助。
- `Scalene` 适合需要行级 CPU/内存归因、区分 Python 与 native/library 消耗的可重启程序；它偏 profiler，不直接回答“谁仍持有对象”，因此只能作为分配线增强，不能替代 `semantic_probe.py`、`retention_chain.py` 和验证门。
- `memory_profiler` 适合快速生成函数/行级 RSS 曲线，支持 `psutil`、`psutil_pss`、`psutil_uss`、`posix`、`tracemalloc` 等 backend；它主要是观测内存用量变化，不是保留根因工具。其维护活跃度弱于 Memray/py-spy，默认只作为兼容已有日志的解析线索。
- `guppy3/heapy` 可作为 CPython heap 深挖工具，但接口复杂、依赖和解释成本较高；只有 stdlib、`objgraph`、`pympler` 仍无法解释复杂 heap 时再列为人工增强项。
- `Fil` 更适合批处理、科学计算或数据处理程序的峰值内存归因；对长生命周期服务的“对象为什么不释放”仍需要保留链验证。

依赖结论：

- 默认工具链仍保持 stdlib + `/proc` + `discover_evidence.py` + `live_process_snapshot.py` + `monitor_rss.py` + `correlate_evidence.py` + 结构化证据分析。
- 默认不引入 Memray、Scalene、py-spy、BCC memleak、Fil、memory_profiler 等第三方工具依赖；只吸收它们背后的诊断思想：先确认目标范围、记录时间序列趋势、区分 Python/native/mmap、比较 peak 与 final、看 outstanding/retained 增长。
- 任何外部 profiler 输出只能增强“分配线”或“运行栈线”；最终 Python 泄漏根因仍按 `evidence-analysis.md` 和 `validation-gates.md` 判定。
