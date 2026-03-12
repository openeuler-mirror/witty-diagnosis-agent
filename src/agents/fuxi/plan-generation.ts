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
  - 收敛策略:
    - 若用户描述中已经**明确给出了故障模式名称集合**（例如仅给出“硬盘故障”“OOM”等少量模式），则**直接以这些明确故障模式为主进行收敛**，一般情况下**不再额外发散生成新的模式**，只需在方案中对这些模式进行结构化整理与排序（数量可以少于 5 个）。
    - 若用户只提供现象级描述、未给出明确故障模式名称，则基于现象进行发散，构建候选故障模式集合，并按代表性和相关度进行收敛，**最多输出 Top 5** 代表性最强的故障模式，而不是具体根因或验证方案。

- **故障模式列表构建 (Failure Mode List Construction)**:
  - **根节点**: 故障现象 (Symptom, e.g., 应用卡顿)
  - **子节点**: 故障模式 (Failure Mode, e.g., CPU 冲高 / 软死锁、内存不足/OOM、网络不通等)
  - **故障模式识别规则**:
    - 第一步：**扫描用户提供的全部描述**（包含原始描述及后续澄清问答），找出其中**已经明确出现的故障模式词汇**（例如“硬盘故障”“OOM”“网络不通”“CPU 冲高”“TCP 丢包”等，可适当包含常见近义表述，如“内存不够”“磁盘坏块”等）。
    - 如果存在这类**明确的故障模式表述**，则**只将这些条目作为故障模式写入列表**，并在后续排序中完整保留；不需要再对这些模式本身做拆分或重新命名，**严禁基于这些已给出的模式再派生出“子模式”或“相关模式”**，也不强制补齐到 Top 5。
    - 第二步：仅对于用户描述中**没有出现任何明确故障模式名、只有“现象级”表达**的部分（如“应用卡顿”“系统偶尔无响应”“接口超时变多”“节点不定时掉线”等），才需要结合对象、时间窗口、上下文信息，**推断出可能的故障模式候选集**。
    - 推断时遵循 SHMVR/MECE 原则，常见的候选模式可以包括（但不限于）：
      - 资源瓶颈类：CPU 冲高/线程饱和、内存不足/OOM、磁盘 I/O 抖动、文件句柄/连接数耗尽等；
      - 网络与连通性类：网络不通、网络抖动、TCP 丢包、DNS 解析异常、负载均衡配置异常导致部分节点不可达；
      - 存储与硬件类：硬盘故障、文件系统损坏等。
    - 最终输出的故障模式列表**必须只包含“故障模式名称”这一列**，不附带“具体命令/验证步骤/根因描述”；列表中的每一项都应是“某种可能的故障形态”，而不是“结论性诊断”。
    - 对于由**现象级推断得到的候选模式集合**，按代表性和相关度进行排序，**最多选取 Top 5** 写入诊断方案和任务元数据；若用户已给出的显式故障模式数量少于 5 个，则以这些显式模式为主，不强制补齐数量。
    - **特别强调**：当用户明确给出故障模式时（如“硬盘故障”），必须严格遵守“只使用用户给出的故障模式，不派生新模式”的原则，确保故障模式列表与用户输入保持一致。

### 2) 计划内容输出 (Plan Output)
将上述思考整合成一份 **《诊断排查方案》**，保存为 \`~/.dayu/plans/{timestamp}_{plan_id}.md\`。

**重要约束**：
- 只生成到故障模式列表（第6节）为止的内容
- 严禁生成以下内容：
  - 诊断步骤规划（如阶段1-5的详细步骤）
  - 预期输出
  - 风险与约束
- 这些内容应由后续的Dayu和Baize Agent生成
- 方案的章节结构必须严格遵守 \`FUXI_PLAN_TEMPLATE\`，**只允许出现以下顶层章节**：
  - \`## 1. 故障场景 (Fault Scenario)\`
  - \`## 2. 故障澄清 (Issue Clarification)\`
  - \`## 3. 前期检测结果 (Pre-check Results)\`
  - \`## 4. 诊断模型 (Diagnostic Model - Failure Modes, *up to* Top 5)\`
  - \`## 5. 任务元数据 (JSON Metadata)\`
- **严禁新增任何其他一级/二级章节**，包括但不限于：
  - 诊断步骤规划（如“## 诊断步骤规划”“## 6. 诊断步骤规划”等）
  - 预期输出（如“## 预期输出 (Expected Output)”）
  - 风险与约束（如“## 风险与约束 (Risks & Constraints)”）

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

- **编排责任 (Dayu)**：由 Dayu 接手，根据任务依赖图调度执行。
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
