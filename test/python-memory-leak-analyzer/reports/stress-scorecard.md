# python-memory-leak-analyzer verification scorecard

本文件记录 `python-memory-leak-analyzer` 测试套件的脚本级证据生成、正式 Xuanyuan 端到端报告和清理结果。stress 与 production 套件用于覆盖复杂诊断边界；端到端验证记录 6 个代表场景。

## 测试材料

| 类型 | 路径 | 用途 |
| --- | --- | --- |
| 基础故障注入 | `test/python-memory-leak-analyzer/fault-injection/*.py` | 全局容器、无界缓存、RSS/碎片化对照 |
| stress 故障注入 | `test/python-memory-leak-analyzer/fault-injection/advanced/*.py` | 闭包、回调、任务、线程局部、短窗口、多源竞争等复杂 Python 保留链 |
| production 故障注入 | `test/python-memory-leak-analyzer/fault-injection/production/*.py` | native/allocator、mmap/shmem、prefork、cgroup、瞬态峰值等线上边界 |
| 运行入口 | `test/python-memory-leak-analyzer/run.sh` | `run`、`run-stress`、`run-prod`、`status`、`clean` |
| 清理入口 | `test/python-memory-leak-analyzer/cleanup.sh` | 清理 `out/`、临时 PID 和运行态 |

## 脚本级验证

验证命令：

```bash
python -m compileall -q skills/python-memory-leak-analyzer test/python-memory-leak-analyzer
bash -n test/python-memory-leak-analyzer/run.sh test/python-memory-leak-analyzer/cleanup.sh

cd test/python-memory-leak-analyzer
bash ./run.sh clean
bash ./run.sh run global
bash ./run.sh run-stress multi_source_mismatch
bash ./run.sh run-stress closure_capture
bash ./run.sh run-stress live_pid_readonly
bash ./run.sh run-prod native_ctypes_malloc_growth
bash ./run.sh run-prod allocator_fragmentation_plateau
```

结果：

| 场景 | 证据目录 | `correlation.json` verdict | 置信度边界 |
| --- | --- | --- | --- |
| `global` | `out/global/` | `python_retained_leak_likely` | `medium_workload_only_without_live_rss_scope` |
| `multi_source_mismatch` | `out/stress/multi_source_mismatch/` | `python_retained_leak_likely` | `medium_workload_only_without_live_rss_scope` |
| `closure_capture` | `out/stress/closure_capture/` | `python_retained_leak_likely` | `medium_workload_only_without_live_rss_scope` |
| `live_pid_readonly` | `out/stress/live_pid_readonly/` | `readonly_insufficient` | `weak_without_reproducible_heap_evidence` |
| `native_ctypes_malloc_growth` | `out/production/native_ctypes_malloc_growth/` | `native_or_allocator_suspect` | `direction_only_without_native_allocator_stack` |
| `allocator_fragmentation_plateau` | `out/production/allocator_fragmentation_plateau/` | `allocator_reuse_or_fragmentation_possible` | `direction_only_without_longer_window` |

`live_pid_readonly` 会在 PID/RSS 监控后生成 `correlation.json`，用于报告引用只读证据边界；没有 Python heap、semantic 或 retention 证据时不得确认 Python 对象根因。`allocator_fragmentation_plateau` 在 live PID/snapshot 存在、瞬态峰值已释放且无语义保留者时输出 allocator/high-water 方向结论。

## Xuanyuan 端到端验证

正式验证使用 `challenge + codex-mediated`。启动提示只包含中性故障现象、粗故障范围和只读边界；`--skill-name`、`--scenario`、`--reproduce` 仅用于脚本侧输入生成、清理、归档和校验。

统一命令形态：

```powershell
python .agents\skills\witty-xuanyuan-test\scripts\xuanyuan_report_archive.py run `
  --mode challenge `
  --question-mode codex-mediated `
  --skill-name python-memory-leak-analyzer `
  --scenario <scenario> `
  --phenomenon "<中性故障现象>" `
  --scope "<workspace-root>\witty-diagnosis-agent\test\python-memory-leak-analyzer\out\<scenario-dir>" `
  --reproduce "<input-generation-command>" `
  --timeout 5400 `
  --json
```

| 场景 | run id | 输入生成命令 | 关键验收 | 结果 |
| --- | --- | --- | --- | --- |
| `global` | 已归档报告复核 | `bash ./run.sh run global` | `LEAK_BUCKET`、`module_global`、`python_retained_leak_likely` | pass |
| `multi_source_mismatch` | 已归档报告复核 | `bash ./run.sh run-stress multi_source_mismatch` | `LISTENERS`、`tenant_lookup`、`SMALL_GLOBAL`，小 global 不能作为唯一主因 | pass |
| `closure_capture` | `20260604_204035_97c1461c` | `bash ./run.sh run-stress closure_capture` | `TASK_TABLE`、closure、payload；不得引用 multi-source 术语 | pass |
| `live_pid_readonly` | `20260604_204804_0c1d223e` | `bash ./run.sh run-stress live_pid_readonly` | `readonly_insufficient`、`Private_Dirty`、direction-only 边界；不得仅凭 RSS 确认 Python 根因 | pass |
| `native_ctypes_malloc_growth` | `20260604_205528_7411a399` | `bash ./run.sh run-prod native_ctypes_malloc_growth` | `native_or_allocator_suspect`、`ctypes`、`Python heap / Private_Dirty ratio`；不得误报 Python retained root cause | pass |
| `allocator_fragmentation_plateau` | `20260604_210429_1bd0a8a3` | `bash ./run.sh run-prod allocator_fragmentation_plateau` | `allocator_reuse_or_fragmentation_possible`、`High-Water`、`非泄漏` | pass |

OpenCode 修复确认问题均按只读边界回复为不执行修复。每轮 `watch` 完成后执行 `bash ./run.sh clean`，随后 `bash ./run.sh status` 返回 `no output directory`。

## 归档报告

下列报告均位于 `test/python-memory-leak-analyzer/reports/` 根层，并通过 `--require-official-html` 校验：

| 场景 | Markdown/HTML |
| --- | --- |
| `global` | `Python内存全局容器泄漏分析_20260604_114200_report.{md,html}` |
| `multi_source_mismatch` | `Python多源竞争内存泄漏RCA_ses_20260604_20260604143000_report.{md,html}` |
| `closure_capture` | `Python服务闭包捕获内存泄漏_capture_20260604_205500_report.{md,html}` |
| `live_pid_readonly` | `Python进程内存持续上涨_20260604_205220_report.{md,html}` |
| `native_ctypes_malloc_growth` | `Python服务内存持续上涨_RCA_native_ctypes_malloc_growth_20260604_212000_report.{md,html}` |
| `allocator_fragmentation_plateau` | `allocator_fragmentation_plateau_20260604_210950_report.{md,html}` |

校验命令示例：

```powershell
python .agents\skills\witty-xuanyuan-test\scripts\xuanyuan_report_archive.py verify `
  --skill-name python-memory-leak-analyzer `
  --contains allocator_fragmentation_plateau `
  --term allocator_reuse_or_fragmentation_possible `
  --term High-Water `
  --term "非泄漏" `
  --require-official-html `
  --json
```

全部 6 个场景校验结果均为 `has_markdown=true`、`has_html=true`、`official_html_reports` 非空、`missing_terms=[]`。

## 负例边界

| 场景 | 检查项 | 结果 |
| --- | --- | --- |
| `closure_capture` | 报告不得包含 `multi_source_mismatch`、`LISTENERS`、`tenant_lookup`、`SMALL_GLOBAL` | pass |
| `live_pid_readonly` | 结论不得仅凭 RSS 写成已确认 Python retained leak | pass |
| `native_ctypes_malloc_growth` | 结论不得输出 `python_retained_leak_likely` | pass |
| `allocator_fragmentation_plateau` | 结论应排除 Python 保留泄漏并使用 allocator/high-water 边界 | pass |

## 已知限制

- 未执行 ptrace/attach、memray native stack 实采、线上进程内注入或修复动作。
