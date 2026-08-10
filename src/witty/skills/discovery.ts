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

/**
 * 条件暴露的技能：键为技能名，值为「该技能是否应当暴露」的判定。
 *
 * 绝大多数诊断技能是无条件暴露的；只有依赖外部服务、且该服务未配置时
 * 用了反而有害的技能才登记在此。
 *
 * `euler-rag-json-search` 依附于神农（已知问题检索）链路：它自带可独立运行的
 * Python CLI，若在未配置知识库时照样暴露，任何 agent 都能加载它去打一个并不存在
 * 的 RAG 服务——这会绕过 agent / MCP / 提示词那三层 opt-in 门控。故与它们对齐，
 * 只有 CASE_KB_ID 配置且 case_search 未被禁用时才暴露。
 */
export type SkillGate = (context: SkillGateContext) => boolean

export interface SkillGateContext {
  /** 神农（已知问题检索）是否启用，与 agent/MCP/提示词门控同源 */
  knownIssueEnabled: boolean
}

export const GATED_SKILLS: Readonly<Record<string, SkillGate>> = {
  "euler-rag-json-search": (ctx) => ctx.knownIssueEnabled,
}

/**
 * 把发现的技能 symlink 到 OpenCode 项目级技能目录。幂等：已是本插件所建链接则跳过。
 *
 * 门控未通过的技能不仅不暴露，还会**回收**上一次留下的旧链接——否则用户取消配置后，
 * 磁盘上的软链依然存在，技能会继续对所有 agent 可见（只回收本插件建的软链，
 * 用户自己放的同名目录一律不动）。
 */
export function exposeSkillsToOpenCode(
  skills: DiscoveredSkill[],
  projectDir: string,
  gateContext: SkillGateContext = { knownIssueEnabled: false },
): SkillExposeResult {
  const targetRoot = path.join(projectDir, ".opencode", "skills")
  fs.mkdirSync(targetRoot, { recursive: true })

  const exposed: DiscoveredSkill[] = []
  const skipped: DiscoveredSkill[] = []
  const withheld: string[] = []
  for (const skill of skills) {
    const target = path.join(targetRoot, skill.name)

    const gate = GATED_SKILLS[skill.name]
    if (gate && !gate(gateContext)) {
      retractSkillLink(target, skill.dir)
      withheld.push(skill.name)
      continue
    }

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
  return { exposed, skipped, withheld }
}

/**
 * 回收本插件此前建立的技能软链（门控关闭时调用）。
 *
 * 安全边界：只删「指向本仓库该技能目录的软链」。用户自己创建的同名目录、
 * 或指向别处的软链，一律保留不动——删错了会破坏用户配置。
 */
function retractSkillLink(target: string, skillDir: string): void {
  try {
    const existing = fs.lstatSync(target, { throwIfNoEntry: false })
    if (!existing) return
    if (!existing.isSymbolicLink() || fs.readlinkSync(target) !== skillDir) {
      log("skills: 门控关闭但目标非本插件所建，保留不动", { target })
      return
    }
    fs.unlinkSync(target)
    log("skills: 门控关闭，已回收技能链接", { target })
  } catch (error) {
    log("skills: 回收技能链接失败", { target, error: String(error) })
  }
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
