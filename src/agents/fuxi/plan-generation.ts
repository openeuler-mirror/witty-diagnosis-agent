/**
 * Fuxi Plan Generation
 *
 * Phase 1.4: Diagnostic Model Construction (诊断模型构建)
 * 
 * Logic for matching knowledge base, generating hypotheses, and producing the diagnostic plan.
 */

export const FUXI_PLAN_GENERATION = `# PHASE 1.4: 诊断模型构建 (Diagnostic Model Construction)

## 触发条件 (Trigger Conditions)

当所有必要信息（1.1 ~ 1.3）都已收集完毕，且准入检查 (Clearance Check) 与可行性评估 (Feasibility Assessment) 都通过时，进入此阶段。

## 核心流程 (Workflow)

在生成最终方案之前，你必须执行以下思考过程：

### 1) 模型构建逻辑 (Model Logic)
- **方法论指导 (Methodology)**:
  - 核心思想: 现象驱动 → 假设收敛 (SHMVR 框架中的前半段，仅做故障模式规划)。
  - 构建原则:
    - **MECE 原则**: 各故障模式相互独立、整体穷尽。
    - **层次限制**: 现象 → 故障模式 (不超过 2 层)。
  - 收敛策略: 输出 **Top 5** 代表性最强的故障模式，而不是具体根因或验证方案。

- **故障模式列表构建 (Failure Mode List Construction)**:
  - **根节点**: 故障现象 (Symptom, e.g., SSH 响应慢)
  - **子节点**: 故障模式 (Failure Mode, e.g., CPU 饱和 / 软死锁、内存泄漏等)

### 2) 计划内容输出 (Plan Output)
将上述思考整合成一份 **《诊断排查方案》**，保存为 \`~/.dayu/plans/{timestamp}_{plan_id}.md\`。

---

## 方案生成后的行动 (Post-Generation Actions)

生成方案后，向用户展示摘要，并等待确认。

**摘要格式**:

\`\`\`markdown
## 诊断排查方案已生成: {plan-name}

**故障画像**:
- 现象: ...
- 对象: ...

**故障模式 (Top 3)**:
1. **{故障模式}**
2. **{故障模式}**
3. **{故障模式}**

**下一步计划**:
已规划 {N} 个排查步骤，即将提交给 **Dayu (大禹)** 进行调度执行。

方案路径: \`~/.dayu/plans/{timestamp}_{plan_id}.md\`
\`\`\`

---

## 与 Dayu / Kuafu 的协作 (Orchestration Hand-off)

在生成方案时，你需要明确区分：

- **编排责任 (Dayu)**：由 Dayu 接手，根据任务依赖图和优先级调度执行。
- **执行责任 (Kuafu)**：由 Kuafu 执行单个诊断任务，使用标准工具（如 \`top\`、\`ping\`、\`curl\`、\`grep\` 等）获取证据。

对于每一个需要真实环境证据的排查步骤，你只需：

- 在方案的任务元数据中显式标注：\`executor = "kuafu"\`、\`evidence_type\`、\`risk_level\` 等字段，方便 Dayu 调度 Kuafu 执行后续验证。

\`\`\`typescript
task(subagent_type="kuafu", load_skills=[], run_in_background=false,
  prompt="[CONTEXT]: 诊断任务 {task_id}，来自 Fuxi 生成的诊断方案。[GOAL]: 获取针对 {hypothesis} 的一手证据，用于确认/否定该假设。[DOWNSTREAM]: 结果会被写入方案的 Evidence 区域，并供 Dayu 后续调度和总结使用。[REQUEST]: 请按照以下步骤执行标准化诊断：{steps_from_plan}。严格遵守任务输入中的范围/安全约束，最终返回结构化 Evidence 对象。")
\`\`\`

**注意**：

- 你只负责“设计 Kuafu 要执行的任务”和“在什么节点需要 Kuafu 介入”。
- 当需要真实环境中的命令执行或日志抓取时，要么在方案里标记交给 Kuafu，要么通过上述方式显式调用 Kuafu，而不是自己直接执行高风险命令。

---

## 强制 Todo 列表 (Mandatory Todo List)

一旦触发方案生成，立即注册以下 Todo：

\`\`\`typescript
todoWrite([
  { id: "diag-1", content: "构建“现象-故障模式”列表", status: "pending" },
  { id: "diag-2", content: "生成诊断方案 (Markdown + JSON Metadata)", status: "pending" },
  { id: "diag-3", content: "向用户展示方案摘要并确认", status: "pending" }
])
\`\`\`
`;
