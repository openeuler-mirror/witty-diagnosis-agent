# Python 内存泄漏诊断报告

## 1. 故障概要

- 目标进程/脚本：
- 故障时间窗口：未提供时写“未提供；本报告按证据文件生成时间和日志内容分析”，不要因缺少该字段中断离线证据包诊断。
- 现象：
- 影响：
- 当前状态：只读诊断完成时写“诊断完成，根因/边界已定位，修复未执行”；不得写“已恢复/已修复”，除非本轮已获授权、执行修复并完成复测。

## 2. 证据与边界

- 已读取证据：
- `correlation.json` verdict：
- confidence_cap：
- missing_evidence：
- memory_surface：
- 运行边界：`/proc` / `smaps_rollup` / cgroup / ptrace 边界：
- 只读/副作用边界：
- 未执行动作：attach/ptrace、修复、重启、配置写入、副作用反事实：
- 结论边界：
- 置信度上限：

## 3. Live PID 只读定界

- 目标 PID / 进程树：
- cgroup 口径：
- 子进程/worker 偏斜：
- mapping 组成：
- 只读定界结论：

## 4. 证据对账总闸门

- `correlation.json` verdict：
- confidence_cap：
- missing_evidence：
- Python heap / Private_Dirty ratio：
- tracked object / Private_Dirty ratio：
- memory_surface：
- coverage_warning：
- peak vs final：
- 报告结论边界：
- 已按 `references/evidence-analysis.md` 完成 verdict 措辞检查：是/否

## 5. RSS 与增长形态

- RSS 净增长：
- Private_Dirty 净增长：
- cgroup memory 净增长：
- 增长形态：
- plateau/预热/碎片化判断：
- 内存表面判断：file/shmem/mmap、anonymous/private dirty、native/allocator 或 mixed
- native/allocator 背离判断：

## 6. Python 对象增长

| 类型 | 计数增量 | 字节增量 | 说明 |
| --- | --- | --- | --- |

## 7. 语义保留信号

| 信号 | 保留者 | 增量/规模 | 说明 |
| --- | --- | --- | --- |

## 8. 分配热点

| 分配栈 | 字节增量 | 说明 |
| --- | --- | --- |

## 9. 保留链

| 候选对象 | root_kind | 保留路径摘要 |
| --- | --- | --- |

## 10. 验证门

| 验证门 | 结果 | 证据 |
| --- | --- | --- |
| G0 目标范围和口径确认 |  |  |
| G1 量化对账 |  |  |
| G2 竞争假设 |  |  |
| G3 可达性 |  |  |
| G4 隔离复测 |  |  |

## 10.1 竞争假设矩阵

| 假设 | 支持证据 | 反证/缺口 | 当前判断 |
| --- | --- | --- | --- |
| Python retained leak |  |  |  |
| native/allocator |  |  |  |
| mmap/file/shmem |  |  |  |
| plateau/high-water |  |  |  |
| short-window |  |  |  |
| scope mismatch |  |  |  |

## 11. 根因结论

- 根因类型：
- 根因描述：
- 置信度：
- 未验证项：
- 禁止越级说明：若 verdict 为只读、native、mmap 或 high-water，说明为何不确认 Python 根因。

## 12. 修复建议

- 本轮执行状态：未执行修复/已授权并执行修复（选择其一，必须与证据一致）
- 最小修复：
- 根本修复：
- 风险：

> 只读诊断报告中的修复内容是建议，不是已执行操作；不得把 `clear()`、重启、代码修改、attach/ptrace 或配置写入写成已完成动作。

## 13. 复测方案

- 复现命令：
- 期望指标：
- 通过条件：
