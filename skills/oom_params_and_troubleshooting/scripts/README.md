# Case13_Oom_Params_And_Troubleshooting - Bash Scripts

本目录包含从参考文档中提取的数据采集和分析相关的bash脚本。

## 可用脚本

| 脚本 | 描述 |
|------|------|
| [collect_oom_diagnostics.sh](collect_oom_diagnostics.sh) | 采集OOM相关诊断信息，包括内核参数（panic_on_oom, oom_kill_allocating_task, oom_dump_tasks）、指定进程信息、特定进程的oom_score_adj值以及系统日志中的OOM记录。 |

## 使用说明

### 参数说明

脚本支持以下参数：

- `$1`: 要检查的进程名（可选，用于过滤进程列表）
- `$2`: 要检查的进程PID（可选，用于查看特定进程的oom_score_adj）

**使用示例：**

```bash
./collect_oom_diagnostics.sh test
./collect_oom_diagnostics.sh test 2939
./collect_oom_diagnostics.sh
```

### 执行脚本

```bash
# 查看脚本使用说明
./collect_oom_diagnostics.sh --help

# 执行脚本（根据脚本要求传入参数）
./collect_oom_diagnostics.sh [参数]
```

## 注意事项

- 脚本只包含数据采集和分析相关的命令（查看、检查、诊断、监控等）
- 脚本中的参数需要根据实际情况提供
- 单个命令失败不会中断整个脚本执行
- 所有命令都会尝试执行，失败时输出警告信息
- 脚本从参考文档中严格提取，不包含文档中未出现的命令

---

*由 BashExtractor 自动生成*