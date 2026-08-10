/** 诊断技能的发现结果（对应仓库顶层 skills/<name>/SKILL.md）。 */
export interface DiscoveredSkill {
  /** 技能名 = 目录名，如 "dns-resolution-diagnosis" */
  name: string
  /** 技能目录绝对路径 */
  dir: string
  /** SKILL.md 绝对路径 */
  skillFile: string
  /** SKILL.md frontmatter 中的 description（如有） */
  description?: string
}

export interface SkillExposeResult {
  exposed: DiscoveredSkill[]
  /** 因目标已存在且非本插件所建而跳过的技能 */
  skipped: DiscoveredSkill[]
  /** 因门控未开启而未暴露、且已回收旧链接的技能名 */
  withheld: string[]
}
