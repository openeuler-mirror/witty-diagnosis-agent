# 用户需求描述 (User Requirements Description)
1. 基于witty-diagnosis-agent前端交互页面新增一个功能：已知问题查询分析agent，基于对话交互实现对已知问题的查询和分析。
2. 前端使用对话交互的形式。
3. 后端使用opencode的能力，然后通过MCP去对接light-rag的能力，实现对已知问题的查询和分析。
4. 前端的交互的显示逻辑参考opencode提供的官方web，你先查找下他们的流式输出和工具显示能力。
5. 前端展示形式参考里面的运维问答模块：/opt/src/witty-diagnosis-agent/docs/design/known-fault-dialog-interaction/openEuler-ops-qa.html

6. 该功能是可以配置的：用户如果选择了安装这个模块，就要安装对应的依赖，也可以不安装。相关的功能可以是独立的。