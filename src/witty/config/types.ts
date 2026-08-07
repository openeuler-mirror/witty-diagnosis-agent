/**
 * 插件配置契约。
 *
 * 设计原则：只声明诊断产品需要的键。所有键 snake_case，
 * 与用户配置文件 .opencode/witty-diagnosis-agent.jsonc 保持兼容。
 */

/** 单个 agent 的用户覆盖项 */
export interface AgentOverride {
  /** 覆盖默认模型，如 "anthropic/claude-sonnet-5" */
  model?: string
  /** 禁用该 agent */
  disable?: boolean
  /** 追加到系统提示词末尾的自定义指令 */
  extra_instructions?: string
}

export interface ReportConfig {
  /** 诊断报告输出目录（相对项目根），默认 "baize/reports" */
  output_dir?: string
  /** 报告格式，默认 ["md", "html"] */
  formats?: Array<"md" | "html">
}

export interface GuardsConfig {
  /** 规划类 agent 仅允许写 .md 文件，默认 true */
  md_only?: boolean
  /** 工具输出超过该字符数则截断，默认 30000；0 表示不截断 */
  output_truncate_chars?: number
  /** 压缩时保留诊断上下文，默认 true */
  compaction_preserve?: boolean
}

export interface OrchestrationConfig {
  /** 并行子代理上限，默认 2 */
  max_parallel_subagents?: number
  /** 单个子代理超时（分钟），默认 30 */
  subagent_timeout_minutes?: number
}

export interface NotificationConfig {
  /** 会话完成/出错时发送系统通知，默认 false */
  enabled?: boolean
}

/** 输出语言：中文 / 英文 */
export type OutputLanguage = "zh" | "en"

/** 插件顶层配置（用户可见契约） */
export interface WittyConfig {
  /** JSON Schema 引用，允许但忽略 */
  $schema?: string
  /** 输出语言，默认 "zh"。影响 agent 提示词语言指令与描述文案 */
  output_language?: OutputLanguage
  /** 按 agent 名的覆盖表 */
  agents?: Record<string, AgentOverride>
  /** 全局禁用的 agent 名列表 */
  disabled_agents?: string[]
  /** 技能根目录（相对项目根或绝对路径），默认仓库顶层 "skills" */
  skills_dir?: string
  report?: ReportConfig
  guards?: GuardsConfig
  orchestration?: OrchestrationConfig
  notification?: NotificationConfig
}

/** 填充默认值后的运行时配置 */
export type ResolvedWittyConfig = Required<
  Pick<WittyConfig, "output_language" | "agents" | "disabled_agents" | "skills_dir">
> & {
  report: Required<ReportConfig>
  guards: Required<GuardsConfig>
  orchestration: Required<OrchestrationConfig>
  notification: Required<NotificationConfig>
}
