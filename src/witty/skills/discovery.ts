import fs from "node:fs"
import path from "node:path"

import type { DiscoveredSkill, SkillExposeResult } from "./types"
import { log } from "../shared/log"

/**
 * 技能发现与暴露。
 *
 * 策略：不自建 skill 执行器，完全复用 OpenCode 原生 skill 机制——
 * 把仓库顶层 skills/<name>/ 以 symlink 形式挂到 OpenCode 的技能发现路径
 * （项目级 .opencode/skills/），由 OpenCode 原生 skill 工具加载执行。
 * （.opencode/plugins/witty-diagnosis-agent.js 引导脚本已验证该路线可行。）
 */

/** 扫描技能根目录，返回所有含 SKILL.md 的子目录。 */
export function discoverSkills(skillsRootDir: string): DiscoveredSkill[] {
  let entries: fs.Dirent[]
  try {
    entries = fs.readdirSync(skillsRootDir, { withFileTypes: true })
  } catch {
    log("skills: 技能根目录不可读", { skillsRootDir })
    return []
  }

  const skills: DiscoveredSkill[] = []
  for (const entry of entries) {
    if (!entry.isDirectory()) continue
    const dir = path.join(skillsRootDir, entry.name)
    const skillFile = path.join(dir, "SKILL.md")
    if (!fs.existsSync(skillFile)) continue
    skills.push({
      name: entry.name,
      dir,
      skillFile,
      description: readFrontmatterDescription(skillFile),
    })
  }
  return skills
}

/** 把发现的技能 symlink 到 OpenCode 项目级技能目录。幂等：已是本插件所建链接则跳过。 */
export function exposeSkillsToOpenCode(
  skills: DiscoveredSkill[],
  projectDir: string,
): SkillExposeResult {
  const targetRoot = path.join(projectDir, ".opencode", "skills")
  fs.mkdirSync(targetRoot, { recursive: true })

  const exposed: DiscoveredSkill[] = []
  const skipped: DiscoveredSkill[] = []
  for (const skill of skills) {
    const target = path.join(targetRoot, skill.name)
    try {
      const existing = fs.lstatSync(target, { throwIfNoEntry: false })
      if (existing) {
        if (existing.isSymbolicLink() && fs.readlinkSync(target) === skill.dir) {
          exposed.push(skill)
        } else {
          skipped.push(skill)
        }
        continue
      }
      fs.symlinkSync(skill.dir, target, "dir")
      exposed.push(skill)
    } catch (error) {
      log("skills: symlink 失败", { skill: skill.name, error: String(error) })
      skipped.push(skill)
    }
  }
  return { exposed, skipped }
}

/** 读取 SKILL.md YAML frontmatter 的 description 字段（无 frontmatter 返回 undefined）。 */
function readFrontmatterDescription(skillFile: string): string | undefined {
  try {
    const text = fs.readFileSync(skillFile, "utf8")
    if (!text.startsWith("---")) return undefined
    const end = text.indexOf("\n---", 3)
    if (end === -1) return undefined
    const frontmatter = text.slice(3, end)
    const match = frontmatter.match(/^description:\s*(.+)$/m)
    return match?.[1]?.trim()
  } catch {
    return undefined
  }
}
