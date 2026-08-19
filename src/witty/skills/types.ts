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

/**
 * 技能暴露形态。
 * - directory：`.opencode/skills` 整体软链到安装根的 skills/，每项目仅 1 条链接（默认）
 * - per-skill：`.opencode/skills` 为本插件独占的真实目录，内含逐技能软链
 *   （仅当有技能因门控需要被扣留时使用——目录级软链无法扣留单个技能）
 */
export type SkillExposureMode = "directory" | "per-skill"

export interface SkillExposeResult {
  /** 本次实际采用的暴露形态 */
  mode: SkillExposureMode
  exposed: DiscoveredSkill[]
  /** 因目标已存在且非本插件所建而跳过的技能 */
  skipped: DiscoveredSkill[]
  /** 因门控未开启而未暴露、且已回收旧链接的技能名 */
  withheld: string[]
  /** 原本指向本项目其他 checkout、已重指到当前安装的条目 */
  repointed: string[]
  /** 已清理的陈旧条目（孤儿链接、或形态切换时回收的旧链接） */
  pruned: string[]
  /** 目标被用户自有内容占用、插件未接管时为 true */
  unmanaged: boolean
}

/** `witty doctor` 用的技能暴露现状（只读检查结果）。 */
export interface SkillExposureStatus {
  /** 项目级技能目录路径 */
  targetRoot: string
  /** absent=尚未暴露；foreign=被用户自有内容占用；其余为实际形态 */
  mode: SkillExposureMode | "absent" | "foreign"
  /** directory 形态下的软链目标 */
  target?: string
  /** foreign 时的说明 */
  detail?: string
  /**
   * per-skill 形态下：目录缺少独占标记，即由旧版本插件建立的遗留目录。
   * 当前插件只在「有门控技能需暴露」时才用 per-skill，且必写标记；
   * 无标记说明是旧版遗留，下次插件加载会自动迁移为目录级软链。
   */
  legacy?: boolean
  /** 暴露内容是否确实来自当前安装 */
  matchesInstall: boolean
  linkCount: number
  danglingCount: number
  orphanCount: number
  foreignCount: number
}
