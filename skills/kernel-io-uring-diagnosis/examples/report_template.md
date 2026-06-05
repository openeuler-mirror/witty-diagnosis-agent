# io_uring 领域细节示例

最终报告版式以 `skills/fault-rca-report-generation/SKILL.md` 的通用 RCA 模板为准。本文件只列出 io_uring 诊断报告在通用 RCA 大板块内应补充的领域信息。

| 通用 RCA 大板块 | io_uring 领域信息 |
| --- | --- |
| 故障概览 | 案例编号、主机、内核版本、目标进程/PID、故障时间窗口、故障模式、置信度边界。 |
| 根因速览 | 应用侧异常表现、异常阶段、关键 errno、触发条件、完整因果链。 |
| 排查过程 | 已执行命令、采集脚本输出、证据来源、候选假设、排除依据、缺失证据。 |
| io_uring 领域深度分析 | setup、submit、complete、register、worker、SQPOLL、Direct I/O 或 feature 兼容性的运行证据和内核语义解释。 |
| 风险与影响 | 受影响 workload、数据一致性风险、性能风险、继续运行风险。 |
| 修复方案 | 只读建议、需要明确审批的操作、变更风险和回滚方式。 |
| 验证建议 | 复现或确认命令、期望现象、通过条件、清理命令和清理结果。 |
