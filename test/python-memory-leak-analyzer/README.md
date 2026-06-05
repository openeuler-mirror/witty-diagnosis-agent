# python-memory-leak-analyzer 测试套件

本目录提供 `python-memory-leak-analyzer` skill 的可复现测试材料。测试只在本目录 `out/` 下生成输出，不修改系统配置、不重启服务、不 attach 线上进程。

## 目录结构

```text
test/python-memory-leak-analyzer/
├── README.md
├── run.sh
├── cleanup.sh
├── stress_manifest.json
├── fault-injection/
│   ├── global_container_leak.py
│   ├── lru_cache_unbounded.py
│   ├── rss_fragmentation_like.py
│   ├── production/
│   │   ├── live_pid_python_object_leak.py
│   │   ├── native_ctypes_malloc_growth.py
│   │   ├── mmap_file_or_shmem_growth.py
│   │   ├── allocator_fragmentation_plateau.py
│   │   ├── prefork_worker_skew.py
│   │   ├── transient_peak_copy_volume.py
│   │   └── cgroup_sibling_growth.py
│   └── advanced/
│       ├── method_cache_self_leak.py
│       ├── callback_registry_leak.py
│       ├── closure_capture_leak.py
│       ├── thread_local_worker_leak.py
│       ├── asyncio_pending_task_leak.py
│       ├── unclosed_generator_leak.py
│       ├── cycle_finalizer_leak.py
│       ├── weakref_finalize_misuse.py
│       ├── multi_source_mismatch.py
│       ├── short_window_inconclusive.py
│       └── live_pid_readonly_boundary.py
├── scripts/
│   └── score_stress_report.py
└── reports/
```

## 前置条件

- Linux/openEuler 或兼容环境。
- Python 3.8+。
- 不需要第三方 Python 包；`psutil`、`objgraph`、`pympler`、`memray` 缺失时应自动降级。

## 覆盖场景

| 场景 | 命令 | 预期信号 |
| --- | --- | --- |
| 全局容器泄漏 | `./run.sh run global` | `object_growth` 出现 `builtins.dict`/容器增长，保留链指向 module global |
| 无界 lru_cache | `./run.sh run cache` | tracemalloc 分配增长，workload 返回 `currsize` 增加 |
| RSS/native/碎片化对照 | `./run.sh run fragmentation` | Python 保留对象证据不足，应避免强行判 Python 根因 |

## 使用流程

```bash
cd test/python-memory-leak-analyzer

# 运行单个场景
./run.sh run global

# 运行全部核心场景
./run.sh run all

# 查看输出
./run.sh status

# 清理测试产物
./run.sh clean
```

每个场景会生成：

- `out/<scenario>/<scenario>.log`
- `capabilities.json`
- `object_growth.json`
- `tracemalloc.json`
- `retention.json`
- `reachability_static.json`
- `reachability_counterfactual.json`（仅 `global`、`cache` 沙箱场景，显式 `--allow-mutation`）

## 极限压力场景

stress suite 用于测试 skill 在低提示词、复杂保留链和竞争假设下的上限。本组测试允许出现
`partial` 或失败，重点记录误报、漏报、越界操作和置信度控制问题。

```bash
# 运行单个复杂场景
./run.sh run-stress method_cache_self

# 运行全部复杂场景
./run.sh run-stress all

# 查看极短提示词
./run.sh prompt method_cache_self minimal
./run.sh prompt method_cache_self sparse
./run.sh prompt method_cache_self normal

# 对已归档报告做启发式评分
./run.sh score method_cache_self /path/to/report.md
```

复杂场景覆盖：

| 场景 | 目标压力点 |
| --- | --- |
| `method_cache_self` | 方法级无界缓存通过 key 保留 `self` |
| `callback_registry` | 全局 callback/listener registry 保留 bound method 和实例 |
| `closure_capture` | 闭包 cell 捕获 payload，被全局任务表保留 |
| `thread_local_worker` | 持久线程池 worker 的 `threading.local` 请求态累积 |
| `asyncio_pending_task` | pending task 保留 coroutine frame locals |
| `unclosed_generator` | 未关闭 generator 保留 frame locals |
| `cycle_finalizer` | 引用循环、finalizer 和 `gc.garbage` 边界 |
| `weakref_finalize` | `weakref.finalize` bound method 回调反向保留对象 |
| `multi_source_mismatch` | 小显眼 global 与更大 listener/cache 泄漏竞争 |
| `short_window_inconclusive` | 有界缓存预热/短窗口，要求避免强行确认泄漏 |
| `live_pid_readonly` | 仅 PID/RSS 外部观测，验证只读边界和置信度封顶 |

每个 stress 场景会在 `out/stress/<scenario>/` 生成：

- `<scenario>.log`
- `manifest.json`
- `capabilities.json`
- `discovery.json`
- `object_growth.json`
- `semantic.json`（仅可复现 workload 场景；`live_pid_readonly` 不生成进程内语义归因）
- `tracemalloc.json`
- `retention.json`
- `reachability_static.json`
- `reachability_counterfactual.json`（仅沙箱安全场景）
- `monitor_rss_pid.json`（仅 `live_pid_readonly`）
- `prompts/minimal.txt`、`prompts/sparse.txt`、`prompts/normal.txt`

`out/stress/scorecard.tsv` 汇总证据生成状态和报告评分结果。评分等级：

- `pass`：根因、保留者、验证门和修复方向基本正确。
- `partial`：故障类别正确，但保留链、验证门或置信度说明不足。
- `fail`：未使用 skill、漏读关键证据或根因错误。
- `hallucination-risk`：越界操作、过度确认或把 RSS/短窗口证据误报为确认根因。

## 生产化思路场景

production suite 覆盖接近真实服务形态的复杂诊断边界。它不引入
Memray、Scalene、py-spy、BCC、Fil、memory_profiler 等第三方依赖，也不执行 attach、
ptrace、清缓存、`malloc_trim`、重启服务或生产 PID 进程内注入；只用 stdlib 和 `/proc`
验证目标范围、趋势、mapping、cgroup 与 Python heap 证据对账。

```bash
# 运行单个生产化场景
./run.sh run-prod native_ctypes_malloc_growth

# 运行全部生产化场景
./run.sh run-prod all
```

生产化场景覆盖：

| 场景 | 目标压力点 | 预期边界 |
| --- | --- | --- |
| `live_pid_python_object_leak` | 长跑 PID 中全局容器增长 | 只读阶段只能确认 PID 在涨；复现 heap/retention 后才可确认 Python retained leak |
| `native_ctypes_malloc_growth` | `ctypes` 保留 native malloc 指针 | Python heap ratio 低、Private_Dirty/RssAnon 增长，输出 native/allocator suspect |
| `mmap_file_or_shmem_growth` | 文件或 `/dev/shm` mmap retained mapping | maps/smaps 指向 file/shmem，不误判 Python heap |
| `allocator_fragmentation_plateau` | 大量分配释放后 RSS 高位平台 | 输出 `plateau_high_water` 或 allocator reuse/fragmentation possible |
| `prefork_worker_skew` | master 稳定、worker 子进程增长 | process tree 找到增长 worker，提示不能只看 master PID |
| `transient_peak_copy_volume` | 短时复制峰值高但最终释放 | 输出 peak high but not retained，不误判 retained leak |
| `cgroup_sibling_growth` | 目标 PID 稳定、同 cgroup 另一个进程增长 | 输出 cgroup growth not target 或 scope mismatch |

每个 production 场景会在 `out/production/<scenario>/` 生成：

- `<scenario>.log`
- `live_process_snapshot.json`
- `monitor_rss_pid.json`
- `object_growth.json`
- `semantic.json`
- `tracemalloc.json`
- `retention.json`
- `correlation.json`
- `discovery.json`
- `live.pid` 和必要时的 `sibling.pid`

报告评分重点：

- 不凭 RSS 单独确认 Python 根因。
- 最终报告优先引用 `correlation.json` 的 `summary.verdict`、`confidence_cap` 和 `missing_evidence`。
- 按 `skills/python-memory-leak-analyzer/references/evidence-analysis.md` 填写竞争假设矩阵，不只罗列采集结果。
- native/mmap/allocator/pre-fork/cgroup mismatch 能正确封顶置信度。
- 只读 PID 场景把 `/proc` 证据作为定界证据，而不是进程内 heap 根因证据。

## Xuanyuan 端到端验证规则

脚本级证据可以批量生成，但 Xuanyuan 端到端验证必须按场景拆开：

- 一个 stress 场景启动一个独立 Xuanyuan 会话。
- 不使用一次总诊断替代多个场景。
- 每个场景只能使用当前场景范围目录、PID 或服务名发现到的证据；不得把历史 Dayu/Baize 报告或上一个 stress 场景报告作为当前诊断输入。
- 报告标题、场景名和关键术语必须匹配当前场景；如果当前场景是 `closure_capture`，报告却引用 `multi_source_mismatch`、`LISTENERS` 或 `tenant_lookup`，该报告无效。
- 每个场景完成后归档两份 Witty 原流程报告：Markdown `*.md` 和 HTML `*.html`。
- HTML 必须通过官方 `report_visualization` 特征校验；不能只用手写 Markdown 或日志输出替代。
- `live_pid_readonly` 场景只允许 PID/RSS 外部只读证据；报告不得从复现脚本反推确认的 Python 根因。

正式 Xuanyuan 端到端验证覆盖 6 个代表场景：`global`、`multi_source_mismatch`、`closure_capture`、`live_pid_readonly`、`native_ctypes_malloc_growth`、`allocator_fragmentation_plateau`。

已归档的正式 Xuanyuan 报告位于 `reports/` 根层：

| 场景 | 报告文件 |
| --- | --- |
| `global` | `Python内存全局容器泄漏分析_20260604_114200_report.{md,html}` |
| `multi_source_mismatch` | `Python多源竞争内存泄漏RCA_ses_20260604_20260604143000_report.{md,html}` |
| `closure_capture` | `Python服务闭包捕获内存泄漏_capture_20260604_205500_report.{md,html}` |
| `live_pid_readonly` | `Python进程内存持续上涨_20260604_205220_report.{md,html}` |
| `native_ctypes_malloc_growth` | `Python服务内存持续上涨_RCA_native_ctypes_malloc_growth_20260604_212000_report.{md,html}` |
| `allocator_fragmentation_plateau` | `allocator_fragmentation_plateau_20260604_210950_report.{md,html}` |

低输入验证时，正式提示词不应逐个指定 `semantic.json`、`object_growth.json` 等文件。使用中性故障描述和粗故障范围即可，例如：

```text
分析 Python 泄露问题，范围在 <repo>/test/python-memory-leak-analyzer/out/stress/multi_source_mismatch
```

Agent 应先运行或读取 `discover_evidence.py`/`discovery.json`，再自动选择日志和证据文件。
如果只给 PID 或服务名，Agent 应先用 `discover_evidence.py pid:<PID>` 或 `discover_evidence.py <service-name>` 定位外部只读入口；仅凭 PID/RSS 不得确认 Python 对象根因。
历史 Witty 输出目录，例如 `<witty-output-dir>/dayu/report` 和 `<witty-output-dir>/baize/reports`，只用于运行后定位、归档和校验报告，不作为当前场景的诊断证据来源。

单场景正式流程示例：

```powershell
cd "<workspace-root>"

python .agents\skills\witty-xuanyuan-test\scripts\xuanyuan_report_archive.py run `
  --mode challenge `
  --question-mode codex-mediated `
  --skill-name python-memory-leak-analyzer `
  --scenario multi_source_mismatch `
  --phenomenon "Python 应用运行过程中内存持续上涨" `
  --scope "<repo>/test/python-memory-leak-analyzer/out/stress/multi_source_mismatch" `
  --reproduce "bash ./run.sh run-stress multi_source_mismatch" `
  --timeout 5400

python .agents\skills\witty-xuanyuan-test\scripts\xuanyuan_report_archive.py archive `
  --skill-name python-memory-leak-analyzer `
  --scenario multi_source_mismatch `
  --contains multi_source_mismatch `
  --since <YYYYMMDDHHMMSS>

python .agents\skills\witty-xuanyuan-test\scripts\xuanyuan_report_archive.py verify `
  --skill-name python-memory-leak-analyzer `
  --scenario multi_source_mismatch `
  --contains multi_source_mismatch `
  --term LISTENERS `
  --term tenant_lookup `
  --require-official-html
```

## Xuanyuan 输入摘要

运行日志末尾包含用于复核的测试元数据：

- 正式 prompt 中的中性故障现象和粗故障范围。
- 脚本侧归档、清理、verify、score 和状态记录所需的 skill 名、场景名、复现命令和报告定位信息。
- 预清理、输入生成、状态检查、后清理和状态复查结果。
- 会话与报告要求：本场景单独启动一个 Xuanyuan 会话，并输出 Markdown/HTML 两份 Witty 原流程报告。
- 只读边界：离线本地日志诊断，不执行修复、重启、远程登录或配置写入。

## 预期诊断映射

- `global`：应定位到全局容器持有对象，建议增加上限、淘汰策略或生命周期清理。
- `cache`：应识别 `lru_cache(maxsize=None)` 无界缓存增长，建议设置 `maxsize` 或按生命周期清理。
- `fragmentation`：应输出证据不足或 native/allocator 方向提示，不应把短生命周期对象误报为 Python 保留泄漏。
