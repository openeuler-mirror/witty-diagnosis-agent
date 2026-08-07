/**
 * 诊断 agent 定义契约。
 *
 * 提示词一律来自 agents/prompts/<name>.md（纯数据，迁移自原创内容），
 * 定义文件只声明元信息与权限，不内联长提示词。
 *
 * 注册键即 agent 名（裸名），因为 OpenCode 的 agent.name = 注册进 Config.agent 的键，
 * 且原生 task 工具按该键（agents[subagent_type]）委派子代理。提示词里的
 * subagent_type="fuxi" 必须能命中，故注册键用裸名，显示名后缀放进 description。
 */

export const WITTY_AGENT_NAMES = [
  "xuanyuan", // 轩辕：诊断总编排（primary）
  "fuxi",     // 伏羲：故障澄清与信息收集
  "dayu",     // 大禹：诊断方案规划（仅写 .md）
  "kuafu",    // 夸父：诊断执行（命令采集与分析）
  "baize",    // 白泽：RCA 报告生成
  "nuwa",     // 女娲：修复方案与止血建议
  "taiyi",    // 太乙：报告质检 + 知识库检索（lightrag）
  "shennong", // 神农：已知问题案例检索（opt-in，需配置 CASE_KB_ID）
] as const

export type WittyAgentName = (typeof WITTY_AGENT_NAMES)[number]

export type AgentMode = "primary" | "subagent" | "all"

/**
 * 权限表：键为 OpenCode 权限名（edit/bash/webfetch/question/task/...）。
 * question 是 OpenCode 原生的提问选项卡能力，须显式 allow 才会出现在会话中。
 * task 须 allow（或不 deny）该 agent 才能通过原生 task 工具委派子代理。
 */
export type AgentPermissionSpec = Record<string, "allow" | "deny" | "ask">

export interface AgentDefinition {
  /** agent 名 = 注册进 OpenCode Config.agent 的键 = 原生 task 的 subagent_type */
  name: WittyAgentName
  /** UI 显示名（中文），仅用于日志/描述前缀 */
  displayName: string
  /** 一句话职责描述（中文），用于 agent 选择器与子代理路由 */
  description: string
  /** 英文职责描述（output_language=en 时使用；缺省回退中文） */
  descriptionEn?: string
  mode: AgentMode
  /** agents/prompts/ 下的提示词文件名 */
  promptFile: `${WittyAgentName}.md`
  /** 缺省模型（可被用户配置覆盖），如 "anthropic/claude-sonnet-5" */
  defaultModel?: string
  permission?: AgentPermissionSpec
  /** 工具开关（按 OpenCode 工具名），未列出的按 OpenCode 默认 */
  tools?: Record<string, boolean>
  /** 是否受 md-only 守护（只允许写 .md 文件） */
  mdOnly?: boolean
  /**
   * 是否在 UI 主 agent 列表隐藏（hidden=true 时只能被 task 委派，不在选择器出现）。
   * 只暴露 xuanyuan/fuxi/taiyi，其余诊断 agent 隐藏为纯 subagent。
   */
  hidden?: boolean
  /** UI 主题色 */
  color?: string
  temperature?: number
  maxTokens?: number
}
