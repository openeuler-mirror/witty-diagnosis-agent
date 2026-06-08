# 核心路径与可选升级

本文件说明默认诊断路径和可选升级边界。证据字段判读、竞争假设和根因措辞统一写在 `evidence-analysis.md`。

## 默认核心路径

默认路径只依赖 Python 标准库、`/proc` 和本 skill 生成的结构化证据：

| 环节 | 默认实现 | 作用 |
| --- | --- | --- |
| 范围发现 | `discover_evidence.py`、`os`、`pathlib`、`json` | 从目录、PID、服务名或日志包发现当前证据，不复用历史报告作为当前根因证据 |
| 运行边界 | `detect_capabilities.py`、`/proc`、cgroup 文件 | 判断 `/proc`、`smaps_rollup`、cgroup 和 ptrace 只读边界 |
| RSS 定界 | `live_process_snapshot.py`、`monitor_rss.py`、`/proc/<pid>` | 定位 PID、worker、mapping、Private_Dirty、RssAnon/File/Shmem 和 cgroup 口径 |
| Python 对象 | `object_growth.py`、`gc`、`sys.getsizeof` | 对可复现 workload 做对象类型增长和浅层 size 估算 |
| 语义信号 | `semantic_probe.py`、`gc`、`inspect`、`asyncio` | 识别全局容器、无界缓存、回调、闭包、线程局部、任务和生成器等保留语义 |
| 分配热点 | `tracemalloc_probe.py`、`tracemalloc` | 识别 Python 分配栈和 peak/final 差异 |
| 保留链 | `retention_chain.py`、`gc.get_referrers` | 输出文本保留链和 root_kind |
| 证据对账 | `correlate_evidence.py` | 生成 `verdict`、`confidence_cap`、`missing_evidence` 和报告措辞总闸门 |

## 路由原则

- 可复现可重启：优先用 `--script` 跑完整 Python 堆路径，再用 `correlate_evidence.py` 对账。
- 低输入但有范围目录、PID、服务名或日志包：先运行 `discover_evidence.py <scope>`，再按 `recommendation.recommended_path` 路由。
- 低输入且没有明确路径：在当前目录运行 `discover_evidence.py .`，同时检查 `logs/`、`out/`、`reports/`、`snapshots/`、`test/`；仍无发现时才追问故障范围。
- 已运行线上 PID：先用 `live_process_snapshot.py --pid` 只读定界，再用 `monitor_rss.py --pid` 外部观测；没有 heap/semantic/retention 证据时不得确认 Python retained leak。
- 报告前：运行或读取 `correlate_evidence.py` 产物，把 `verdict`、`confidence_cap` 和 `missing_evidence` 作为根因措辞总闸门。

## 可选升级

可选升级不属于默认依赖，也不进入最终报告验收。只有已有产物可解析，或用户单独授权采集时才使用。

- `pympler`：仅作为 `object_growth.py` 的深度 size backend。未启用时使用 `sys.getsizeof` 浅层估算，流程不中断；报告只说明 size 可能低估嵌套对象。
- memray：用于解析已有 capture/report，或在可复现、已授权的 Linux/openEuler 环境中采集 native allocation 线索。默认不要求安装；没有 memray 证据时，native/allocator 结论保持方向级。
- gdb、allocator stats、BCC memleak 等 native 深挖：只作为单独授权的升级建议。执行前必须说明权限、debug symbols、ptrace 风险和可能暂停进程的影响。

## 报告边界

- 报告只写证据缺口和只读边界，不输出外部依赖清单。
- 缺少 `monitor_rss_pid.json`、`live_process_snapshot.json`、`object_growth.json`、`tracemalloc.json`、`semantic.json`、`retention.json`、native allocation stack 或 allocator stats 是证据缺口，不是工具缺失。
- 可选增强工具只在已有产物解析或单独授权升级建议中出现，不写入“缺失工具”“缺失证据”“直接证据缺失”或验收失败项。
- RSS-only、PID-only、`readonly_insufficient` 或 `direction-only` 场景应说明当前只能做 scope/trend/direction 结论。
- 外部 profiler 输出只能增强分配线或 native 方向线；最终 Python 泄漏根因仍按 `evidence-analysis.md` 和 `validation-gates.md` 判定。
