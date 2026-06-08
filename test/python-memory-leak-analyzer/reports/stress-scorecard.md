# Python Memory Leak Analyzer E2E Scorecard

本文件只记录本轮 Xuanyuan 端到端测试与报告归档结果。报告正文以同目录下对应 Markdown/HTML 原文件为准。

## Test Run

- 测试日期：2026-06-07
- 运行模式：Xuanyuan `challenge + codex-mediated`
- 模型：`opencode/deepseek-v4-flash-free`
- 报告来源：Witty 原流程 Markdown/HTML 输出
- 归档目录：`D:\develop\Trae\OpenEuler\witty-diagnosis-agent\test\python-memory-leak-analyzer\reports`
- 清理状态：测试后已执行 `bash ./run.sh clean && bash ./run.sh status`，`out/` 目录无残留输出。

## Official Reports

| 场景 | Xuanyuan run id | Markdown | HTML | 官方页面校验 | 结论核对 |
| --- | --- | --- | --- | --- | --- |
| `global` | `20260607_202914_6c6323b2` | `Python服务RSS持续增长全局容器泄漏_global_20260607_122912_report.md` | `Python服务RSS持续增长全局容器泄漏_global_20260607_122912_report.html` | 通过 | 指向全局容器保留增长，符合预期。 |
| `multi_source_mismatch` | `20260607_204008_280988c5` | `Python多源竞争内存泄漏RCA_multi_source_mismatch_20260607_204137_report.md` | `Python多源竞争内存泄漏RCA_multi_source_mismatch_20260607_204137_report.html` | 通过 | 未被小规模全局干扰项误导，主方向为 listeners 与 tenant lookup 保留。 |
| `closure_capture` | `20260607_204606_9b412b53` | `Python服务闭包捕获内存泄漏RCA_closure_capture_20260607_205500_report.md` | `Python服务闭包捕获内存泄漏RCA_closure_capture_20260607_205500_report.html` | 通过 | 指向闭包捕获导致的任务表保留，符合预期。 |
| `live_pid_readonly` | `20260607_205445_60fa0c2e` | `Python服务内存增长RCA_default_20260607_report.md` | `Python服务内存增长RCA_default_20260607_report.html` | 通过 | 保持只读证据边界，未确认 Python retained leak；桥接收尾曾超时，报告与清理均完成。 |
| `native_ctypes_malloc_growth` | `20260607_223407_a2273236` | `Python服务RSS持续增长ctypes原生内存泄漏_20260607_RCA_report.md` | `Python服务RSS持续增长ctypes原生内存泄漏_20260607_RCA_report.html` | 通过 | 指向 native/allocator 方向，未归因为 Python retained root cause。 |
| `mmap_file_or_shmem_growth` | `20260607_224751_4eb575d2` | `Python服务RSS持续增长疑似内存泄漏_20260607_230000_report.md` | `Python服务RSS持续增长疑似内存泄漏_20260607_230000_report.html` | 通过 | 指向 mmap/file-backed/shmem RSS 表面，未归因为 Python heap retained leak。 |
| `allocator_fragmentation_plateau` | `20260607_230401_82e50ade` | `Python服务RSS高位平台疑似内存问题_20260607_231200_report.md` | `Python服务RSS高位平台疑似内存问题_20260607_231200_report.html` | 通过 | 指向 allocator high-water/platform behavior，未确认持续泄漏。 |

## Scope Notes

- 本轮正式归档只保留上表 7 对 Markdown/HTML 报告以及本 scorecard。
- 旧样例、旧调试报告和本轮中间报告已从该目录移除，避免混入社区 PR。
- 诊断阶段未执行 ptrace/attach，未执行修复、重启、删除或配置写入。
- 本轮没有创建 PR、push、提交、暂存或评论 GitCode。
