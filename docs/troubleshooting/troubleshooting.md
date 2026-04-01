# 常见问题 (Troubleshooting & FAQ)

**Q: Agent需要配套什么样的大模型？**

A: Agent 对大模型的工具调用、逻辑推理能力有较高要求，推荐使用 GLM-4.6、MiniMax-2.5、DeepSeek-Chat-V3.2 等具备强推理与函数调用能力的模型。

**Q: Agent 支持在线诊断还是离线诊断？**

A: 视具体诊断任务而定，不同任务对网络的依赖不同，详细支持情况请参见[功能列表](../reference/features.md)。

**Q: Agent 需要 root 权限吗？**

A: 视具体诊断任务而定。读取系统日志、内核数据等操作通常需要 root 或 sudo 权限，普通用户执行此类任务可能会受到权限限制，导致数据采集失败。
