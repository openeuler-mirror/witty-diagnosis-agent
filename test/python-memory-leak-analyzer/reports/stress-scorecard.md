# python-memory-leak-analyzer stress scorecard

本文件记录 complex stress suite 的可复现性和 Xuanyuan 低提示词验证结果。stress suite 的目标是暴露 skill 上限，不要求所有场景一次性通过。

## 脚本级证据生成

验证命令：

```bash
cd test/python-memory-leak-analyzer
bash ./run.sh run-stress all
```

结果：11 个 stress 场景均生成核心证据包，`out/stress/<scenario>/` 下包含 `capabilities.json`、`object_growth.json`、`tracemalloc.json`、`retention.json`、`reachability_static.json`、`metadata.json` 和三档 prompt 文件。

2026-06-04 增强轮新增 `semantic_probe.py` 后，复杂可复现场景还会生成 `semantic.json`，用于直接暴露模块全局容器、无界 cache、bound method registry、闭包 cell、generator/task frame 等语义信号。`live_pid_readonly` 保持只读 PID/RSS 边界，不生成进程内语义归因。

2026-06-04 低输入增强轮新增并强化 `discover_evidence.py`，用于从范围目录、PID、服务名或日志包自动发现证据入口。测试 runner 每轮清理旧 `discovery.json` 和临时 `discovery.manual.json`，避免复用上一轮发现结果。

2026-06-04 本轮修复 discovery 自污染：`discovery.initial.json` 仅标记为初始扫描记录，不参与最终推荐评分；当 `discover_evidence.py --output <scope>/discovery.json` 重新写出发现结果时，本轮输出文件会从扫描结果中排除，避免旧 `discovery.json` 的推荐影响新判断。

| 场景 | 目标压力点 | 脚本结果 |
| --- | --- | --- |
| `method_cache_self` | 方法级无界缓存通过 key 保留 `self` | generated |
| `callback_registry` | 全局 listener registry 保留 bound method 和实例 | generated |
| `closure_capture` | 闭包 cell 捕获 payload，被全局任务表保留 | generated |
| `thread_local_worker` | 持久 worker 的 `threading.local` 请求态累积 | generated |
| `asyncio_pending_task` | pending task 保留 coroutine frame locals | generated |
| `unclosed_generator` | 未关闭 generator 保留 frame locals | generated |
| `cycle_finalizer` | 引用循环、finalizer 与 `gc.garbage` 边界 | generated |
| `weakref_finalize` | `weakref.finalize` bound method 回调反向保留对象 | generated |
| `multi_source_mismatch` | 小 global 与更大 listener/cache 泄漏竞争 | generated |
| `short_window_inconclusive` | 有界缓存预热/短窗口，避免强行确认泄漏 | generated, expected inconclusive |
| `live_pid_readonly` | 仅 PID/RSS 外部观测，只读边界和置信度封顶 | generated |

## 低输入自动发现验证

验证命令：

```bash
cd test/python-memory-leak-analyzer
bash ./run.sh run-stress multi_source_mismatch
bash ./run.sh run-stress closure_capture
bash ./run.sh run-stress live_pid_readonly
python skills/python-memory-leak-analyzer/scripts/discover_evidence.py <out/stress/<scenario>>
```

结果：

| 场景 | 输入形态 | 自动发现结论 | 关键边界 |
| --- | --- | --- | --- |
| `multi_source_mismatch` | 仅范围目录 | `offline_evidence_bundle`，发现 `semantic.json`、`object_growth.json`、`retention.json`、`tracemalloc.json` 和日志 | 无需用户列出 JSON；应优先比较 `LISTENERS`、`tenant_lookup` 和 `SMALL_GLOBAL` |
| `closure_capture` | 仅范围目录 | `offline_evidence_bundle`，发现 `semantic.json`、`object_growth.json`、`retention.json`、`tracemalloc.json` 和日志 | 无需用户列出 JSON；应定位 `TASK_TABLE` 保存闭包函数 |
| `live_pid_readonly` | 仅范围目录/PID 外部证据 | 初始只发现日志和 metadata；采样后发现 `monitor_rss_pid.json` 并推荐 `logs_only_or_external_rss` | 不生成 `semantic.json`、`object_growth.json`、`tracemalloc.json`、`retention.json`；仅凭 RSS 不确认 Python 根因 |

该验证只证明 skill 脚本和文档路由支持低输入自动发现。完整 Agent 智能验证仍需逐场景启动 Xuanyuan，并归档 Markdown 与 HTML 两份 Witty 原流程报告。

本轮复核命令还覆盖了直接重写最终发现文件：

```bash
python skills/python-memory-leak-analyzer/scripts/discover_evidence.py test/python-memory-leak-analyzer/out/stress/multi_source_mismatch --output test/python-memory-leak-analyzer/out/stress/multi_source_mismatch/discovery.json
python skills/python-memory-leak-analyzer/scripts/discover_evidence.py test/python-memory-leak-analyzer/out/stress/closure_capture --output test/python-memory-leak-analyzer/out/stress/closure_capture/discovery.json
python skills/python-memory-leak-analyzer/scripts/discover_evidence.py test/python-memory-leak-analyzer/out/stress/live_pid_readonly --output test/python-memory-leak-analyzer/out/stress/live_pid_readonly/discovery.json
```

复核结果：两个离线复杂场景推荐保持 `offline_evidence_bundle`，只读 PID 场景推荐保持 `logs_only_or_external_rss`；三者的 `discovery_recommendations` 均为空，说明没有复用旧发现文件的推荐。

## 低提示词验证

> 注意：本节记录的是修复 OpenCode agent 暴露问题之前的历史运行结果。当前环境已经通过
> `witty-xuanyuan-test doctor --json` 确认 `opencode agent list` 可直接选择
> `Xuanyuan (Controller)`；因此下方 “agent not found / fallback to default agent” 只作为历史问题记录，
> 不能作为当前 Xuanyuan/Baize E2E 结论。stress suite 的 post-fix 官方报告尚未重跑。

已执行：

```powershell
python .agents\skills\witty-xuanyuan-test\scripts\xuanyuan_report_archive.py run `
  --skill-name python-memory-leak-analyzer `
  --scenario method_cache_self `
  --summary "stress sparse prompt: method cache self retention" `
  --log-file "D:\develop\Trae\OpenEuler\witty-diagnosis-agent\test\python-memory-leak-analyzer\out\stress\method_cache_self\method_cache_self.log" `
  --reproduce "bash ./run.sh run-stress method_cache_self" `
  --prompt "这个 Python 进程内存一直涨，日志在 D:\develop\Trae\OpenEuler\witty-diagnosis-agent\test\python-memory-leak-analyzer\out\stress\method_cache_self\method_cache_self.log" `
  --timeout 900
```

历史结果：OpenCode CLI 当时提示 `agent "Xuanyuan (Controller)" not found. Falling back to default agent`，但默认 agent 仍触发 `python-memory-leak-analyzer`，并正确定位 `@lru_cache(maxsize=None)` 实例方法缓存持有 `self` 的根因。该轮没有生成 Witty 官方 Baize Markdown/HTML，因此不计为完整 Xuanyuan E2E pass。当前环境已修复 agent 暴露问题，需要重跑后才能更新评分。

已执行：

```powershell
python .agents\skills\witty-xuanyuan-test\scripts\xuanyuan_report_archive.py run `
  --agent xuanyuan `
  --skill-name python-memory-leak-analyzer `
  --scenario callback_registry `
  --summary "stress sparse prompt: callback registry retention" `
  --log-file "D:\develop\Trae\OpenEuler\witty-diagnosis-agent\test\python-memory-leak-analyzer\out\stress\callback_registry\callback_registry.log" `
  --reproduce "bash ./run.sh run-stress callback_registry" `
  --prompt "这个 Python 进程内存一直涨，日志在 D:\develop\Trae\OpenEuler\witty-diagnosis-agent\test\python-memory-leak-analyzer\out\stress\callback_registry\callback_registry.log" `
  --timeout 300
```

历史结果：OpenCode CLI 当时同样提示 `agent "xuanyuan" not found. Falling back to default agent`，随后进入 `Xuanyuan (Controller)` 编排流程并生成 Dayu 计划：

```text
C:\Users\duanz\.witty-diagnosis-agent\dayu\plans\20260604_101208_python_memory_leak.md
```

该轮在 300 秒内停留在计划阶段，未产出 Baize 最终 Markdown/HTML 报告。结论记为 `partial/fail-for-e2e`: 低提示词能触发编排和 Fuxi 计划，但旧环境的 OpenCode CLI agent 暴露/回退行为与短超时导致完整 Xuanyuan 报告未完成。当前不再把该记录视为 agent 暴露限制的现状。

2026-06-04 低输入 `multi_source_mismatch` 正式重跑使用单句范围提示：

```powershell
python .agents\skills\witty-xuanyuan-test\scripts\xuanyuan_report_archive.py run `
  --skill-name python-memory-leak-analyzer `
  --scenario multi_source_mismatch-low-input `
  --summary "low-input scope-only multi-source Python memory leak" `
  --prompt "分析 Python 泄漏问题，范围在 D:\develop\Trae\OpenEuler\witty-diagnosis-agent\test\python-memory-leak-analyzer\out\stress\multi_source_mismatch" `
  --timeout 5400
```

结果：Xuanyuan 能直接读取范围目录、`discovery.json`、`capabilities.json` 和 `metadata.json`，证明低输入自动发现入口已生效；但随后 Fuxi 将“故障时间窗口”作为阻塞问题并尝试调用当前 OpenCode 工具集中不可用的 `question` 工具，导致未生成 Baize Markdown/HTML。该轮记为 `partial`: 自动发现成功，流程继续性失败。已据此补充规则：离线证据包已有 discovery/metadata/log/结构化证据时，缺少故障时间窗口不得中断分析，只能在报告中标注“未提供/按证据时间近似”。

修正规则后再次以范围目录低输入运行，并关闭 question bridge 以避免当前 OpenCode 工具集缺少 `question` 时中断：

```powershell
python .agents\skills\witty-xuanyuan-test\scripts\xuanyuan_report_archive.py run `
  --skill-name python-memory-leak-analyzer `
  --scenario multi_source_mismatch-low-input-v2 `
  --summary "low-input scope-only multi-source Python memory leak" `
  --prompt "分析 Python 泄漏问题，范围在 D:\develop\Trae\OpenEuler\witty-diagnosis-agent\test\python-memory-leak-analyzer\out\stress\multi_source_mismatch。若未提供故障时间窗口，请按范围目录内 discovery、metadata、日志和结构化证据继续分析，不要中断追问时间窗口；只读诊断，不执行修复、重启、远程登录、attach、ptrace 或配置写入。" `
  --timeout 5400 `
  --no-question-bridge `
  --json
```

结果：完整 Xuanyuan 流程通过，Fuxi/Dayu/Kuafu/Baize 均执行完成，Baize 生成 Witty 原流程 Markdown 和 `report_visualization` HTML：

```text
D:\develop\Trae\OpenEuler\witty-diagnosis-agent\test\python-memory-leak-analyzer\reports\Python内存泄漏分析_multi_source_mismatch_20260604_123057_report.md
D:\develop\Trae\OpenEuler\witty-diagnosis-agent\test\python-memory-leak-analyzer\reports\Python内存泄漏分析_multi_source_mismatch_20260604_123057_report.html
```

归档校验：

```powershell
python .agents\skills\witty-xuanyuan-test\scripts\xuanyuan_report_archive.py verify `
  --skill-name python-memory-leak-analyzer `
  --report-dir "D:\develop\Trae\OpenEuler\witty-diagnosis-agent\test\python-memory-leak-analyzer\reports" `
  --contains "Python内存泄漏分析" `
  --term LISTENERS `
  --term tenant_lookup `
  --term SMALL_GLOBAL `
  --require-official-html `
  --json
```

验证结论：`has_markdown=true`、`has_html=true`、`official_html_reports` 非空、`missing_terms=[]`。报告正确识别 `LISTENERS` bound method registry 与 `tenant_lookup` 无界缓存为双主因，并排除 `SMALL_GLOBAL` 干扰项。报告尾部仍包含“是否执行故障修复”的交互提示，但本轮未执行修复；已补充 skill 规则，低输入/只读验证场景默认只输出诊断结论、修复建议和复测方案，不发起自动修复交互。

随后启动 `closure_capture` 低输入单场景验证时，Xuanyuan 未生成新的 closure 报告，而是复用了历史 `multi_source_mismatch` 报告并重新可视化。运行痕迹显示它读取了历史输出：

```text
C:\Users\duanz\.witty-diagnosis-agent\dayu\report\kuafu_T1_20260604_122605.md
C:\Users\duanz\.witty-diagnosis-agent\baize\reports\Python内存泄漏分析_multi_source_mismatch_20260604_123057_report.md
```

该轮记为 `fail-for-e2e`: 自动发现能力本身可用，但 Agent 发生跨场景历史报告污染。已据此补充当前范围隔离规则：本轮诊断只能使用用户给出的范围目录、PID 或服务名发现到的证据；历史 Dayu/Baize 报告只用于归档和校验，不能作为本轮根因输入。评分脚本也新增跨场景术语拦截：按 `closure_capture` 评分时，包含 `multi_source_mismatch`、`LISTENERS`、`tenant_lookup` 或 `SMALL_GLOBAL` 的报告直接判为无效。

## 端到端报告验收规则

后续 Xuanyuan/Baize 验证按场景拆分：

- 一个 stress 场景对应一个独立 Xuanyuan 会话。
- 每个场景分别执行 `run`、`archive`、`verify`。
- 每个场景必须归档两份 Witty 原流程报告：Markdown `*.md` 和 HTML `*.html`。
- `verify` 默认使用 `--require-official-html`；没有官方 HTML 时，该场景不能记为完整 E2E pass。
- 多个场景不得合并为一次总诊断，也不得用脚本日志或单份 Markdown 替代最终报告。
- 每个场景的报告标题、正文关键术语和根因必须匹配当前范围；历史 Dayu/Baize 报告、归档目录旧报告和上一个 stress 场景报告不能作为本轮诊断输入。
- 若当前场景是 `closure_capture`，报告必须包含 `TASK_TABLE`、`global_table_retains_closures` 或 closure/payload 证据；若报告引用 `multi_source_mismatch`、`LISTENERS`、`tenant_lookup` 或 `SMALL_GLOBAL`，该场景判为无效。

首轮小测场景：

| 场景 | 小测目标 | 当前脚本级结果 | E2E 状态 |
| --- | --- | --- | --- |
| `multi_source_mismatch` | 多源竞争，避免把小 `SMALL_GLOBAL` 误判为唯一根因 | `semantic.json` 同时列出 `LISTENERS` bound method registry、`tenant_lookup` 无界 cache 和小 global 干扰项；范围目录 discovery 推荐 `offline_evidence_bundle` | `pass`，已归档 `Python内存泄漏分析_multi_source_mismatch_20260604_123057_report.{md,html}` |
| `closure_capture` | 分配点和保留点分离，识别闭包 cell 捕获 payload | `semantic.json` 列出 `TASK_TABLE` 增长和 `function_with_closure`，并展示 closure cell 中的 payload dict；范围目录 discovery 推荐 `offline_evidence_bundle` | `fail-for-e2e`，首轮复用历史 `multi_source_mismatch` 报告；已补范围隔离规则，待 v2 重跑 |
| `live_pid_readonly` | 线上/PID 外部只读边界，避免仅凭 RSS 确认 Python 根因 | 仅保留 `monitor_rss_pid.json` 和弱置信度边界，不生成进程内语义归因；采样后 discovery 推荐 `logs_only_or_external_rss` | 待单独低输入 Xuanyuan 会话生成 Markdown/HTML |

## 后续优化点

- `minimal` 提示 `python 泄露，请你分析找出原因` 不携带范围，适合测试 skill 触发；根因定位验证应使用一句话故障描述加范围目录、PID 或服务名。
- `sparse` 提示已改为“分析 Python 泄漏问题，范围在 <目录>”，不再直接给日志路径；正式低输入 E2E 使用 `--phenomenon` 加 `--scope`，不使用 `--prompt` 覆盖正式输入。
- stress 日志不写入标准答案；标准答案只保存在 `metadata.json` 和 `stress_manifest.json`，用于人工复核和评分。
- 下一轮 skill 优化应重点减少低提示词下的澄清需求：当日志已包含完整证据包、复现命令和只读边界时，Xuanyuan/Fuxi 应直接进入离线本地证据分析。
