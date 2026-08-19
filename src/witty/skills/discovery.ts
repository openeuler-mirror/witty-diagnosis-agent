import fs from "node:fs"
import path from "node:path"

import type {
  DiscoveredSkill,
  SkillExposeResult,
  SkillExposureMode,
  SkillExposureStatus,
} from "./types"
import { log } from "../shared/log"

/**
 * 技能发现与暴露。
 *
 * 策略：不自建 skill 执行器，完全复用 OpenCode 原生 skill 机制——
 * 把仓库顶层 skills/ 挂到 OpenCode 的技能发现路径（项目级 .opencode/skills/），
 * 由 OpenCode 原生 skill 工具加载执行。
 *
 * 暴露形态有两种（见 exposeSkillsToOpenCode）：
 * - directory：`.opencode/skills` 整体软链到安装根的 skills/，每项目仅 1 条链接；
 * - per-skill：`.opencode/skills` 是本插件独占的真实目录，内含逐技能软链。
 *
 * 之所以保留 per-skill，是因为 GATED_SKILLS 需要在门控关闭时**扣留单个技能**，
 * 而目录级软链是"全有或全无"的，做不到。默认（无技能被扣留）一律用 directory。
 */

/** 本包名，用于识别「指向本项目某个 checkout 的技能软链」。与 package.json 的 name 一致。 */
const PACKAGE_NAME = "witty-diagnosis-agent"

/** 独占标记：per-skill 模式下写入目标目录，声明该目录由本插件托管、可被无条件重建。 */
const MANAGED_MARKER = ".witty-managed"

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
 * 门控技能所在目录名（与 skills/ 同级）。
 *
 * 之所以独立成目录：目录级软链是「全有或全无」的，无法在软链出去的目录里扣留
 * 单个技能。若门控技能与普通技能混放，只要有一个被扣留就必须退回逐技能模式——
 * 而门控默认关闭，等于目录级软链永远不会启用。拆开后 skills/ 恒可整体软链，
 * 只有用户显式开启门控（配置 CASE_KB_ID）时才退回逐技能模式。
 */
export const GATED_SKILLS_DIRNAME = "skills-gated"

/** 门控技能目录：与传入的 skills 根目录同级。 */
export function gatedSkillsDir(skillsRootDir: string): string {
  return path.join(path.dirname(skillsRootDir), GATED_SKILLS_DIRNAME)
}

/**
 * 条件暴露的技能：键为技能名，值为「该技能是否应当暴露」的判定。
 *
 * 绝大多数诊断技能是无条件暴露的（放在 skills/）；只有依赖外部服务、且该服务
 * 未配置时用了反而有害的技能才放进 skills-gated/ 并登记在此。
 *
 * `euler-rag-json-search` 依附于神农（已知问题检索）链路：它自带可独立运行的
 * Python CLI，若在未配置知识库时照样暴露，任何 agent 都能加载它去打一个并不存在
 * 的 RAG 服务——这会绕过 agent / MCP / 提示词那三层 opt-in 门控。故与它们对齐，
 * 只有 CASE_KB_ID 配置且 case_search 未被禁用时才暴露。
 *
 * **失败关闭**：位于 skills-gated/ 但未在此登记的技能一律不暴露。门控目录本身
 * 就意味着「默认不可用」，漏登记时保守处理，不能默认放行。
 */
export type SkillGate = (context: SkillGateContext) => boolean

export interface SkillGateContext {
  /** 神农（已知问题检索）是否启用，与 agent/MCP/提示词门控同源 */
  knownIssueEnabled: boolean
}

export const GATED_SKILLS: Readonly<Record<string, SkillGate>> = {
  "euler-rag-json-search": (ctx) => ctx.knownIssueEnabled,
}

/* ────────────────────────── 归属判定 ────────────────────────── */

/** 从给定目录向上查找 package.json，返回其 name（找不到返回 undefined）。 */
function readPackageName(startDir: string): string | undefined {
  let dir = startDir
  for (let i = 0; i < 4; i++) {
    const pkgFile = path.join(dir, "package.json")
    if (fs.existsSync(pkgFile)) {
      try {
        return JSON.parse(fs.readFileSync(pkgFile, "utf8"))?.name
      } catch {
        return undefined
      }
    }
    const parent = path.dirname(dir)
    if (parent === dir) break
    dir = parent
  }
  return undefined
}

/**
 * 判断软链目标是否落在本项目（任意 checkout）的 skills/ 下。
 *
 * 用户可能先后从多个 checkout 安装本插件。旧 checkout 留下的软链若不重指，
 * 该项目会永远加载旧仓库的技能内容——插件已是新的、技能却停在旧版，且不会自愈。
 * 这类链接必须接管；用户自己放的真实目录、或指向第三方的软链一律不动。
 *
 * @param expectSkillChild true 表示目标应形如 <checkout>/skills/<技能名>；
 *                         false 表示目标应形如 <checkout>/skills。
 */
function isPathInThisPackage(target: string, expectSkillChild: boolean): boolean {
  const skillsDir = expectSkillChild ? path.dirname(target) : target
  if (path.basename(skillsDir) !== "skills") return false
  // 悬空（旧 checkout 已被删除/移动）：形状匹配即认定为本插件遗留，接管总比留着强
  if (!fs.existsSync(target)) return true
  return readPackageName(path.dirname(skillsDir)) === PACKAGE_NAME
}

/** `.opencode/skills` 当前的归属状态。 */
type RootState =
  | { kind: "absent" }
  /** 目录级软链，且指向本项目某个 checkout 的 skills/ */
  | { kind: "ours-link"; target: string }
  /** 真实目录，带独占标记 */
  | { kind: "ours-managed-dir" }
  /** 真实目录，空或条目全是指向本项目的软链（旧版本遗留，可安全接管） */
  | { kind: "ours-legacy-dir" }
  /** 用户自有：真实内容、或指向第三方的软链 —— 一律不动 */
  | { kind: "foreign"; detail: string }

function inspectRoot(targetRoot: string): RootState {
  const st = fs.lstatSync(targetRoot, { throwIfNoEntry: false })
  if (!st) return { kind: "absent" }

  if (st.isSymbolicLink()) {
    const target = fs.readlinkSync(targetRoot)
    return isPathInThisPackage(target, false)
      ? { kind: "ours-link", target }
      : { kind: "foreign", detail: `软链指向本项目之外: ${target}` }
  }

  if (!st.isDirectory()) return { kind: "foreign", detail: "目标既非目录也非软链" }

  if (fs.existsSync(path.join(targetRoot, MANAGED_MARKER))) return { kind: "ours-managed-dir" }

  // 旧版本遗留：本插件早期只建逐技能软链、不写标记。此时条目应当全是指向本项目的软链。
  let entries: string[]
  try {
    entries = fs.readdirSync(targetRoot)
  } catch {
    return { kind: "foreign", detail: "目录不可读" }
  }
  for (const name of entries) {
    const p = path.join(targetRoot, name)
    if (!fs.lstatSync(p, { throwIfNoEntry: false })?.isSymbolicLink()) {
      return { kind: "foreign", detail: `含非软链条目: ${name}` }
    }
    if (!isPathInThisPackage(fs.readlinkSync(p), true)) {
      return { kind: "foreign", detail: `含指向本项目之外的软链: ${name}` }
    }
  }
  return { kind: "ours-legacy-dir" }
}

/* ────────────────────────── 暴露 ────────────────────────── */

/**
 * 把发现的技能暴露到 OpenCode 项目级技能目录。幂等，且每次调用都做对账。
 *
 * 对账内容：
 * - 指向本项目其他 checkout 的陈旧链接 → 重指到当前安装（repointed）
 * - 当前安装已无、但链接仍在的技能 → 清理（pruned）
 * - 两种暴露形态之间的残留 → 互相清理
 *
 * 安全边界：只接管「本插件建立的」目标（目录级软链、带独占标记的目录、
 * 或全部条目都是本项目软链的遗留目录）。用户自有内容一律不动，并置 unmanaged。
 */
export function exposeSkillsToOpenCode(
  skills: DiscoveredSkill[],
  projectDir: string,
  skillsRootDir: string,
  gateContext: SkillGateContext = { knownIssueEnabled: false },
): SkillExposeResult {
  const targetRoot = path.join(projectDir, ".opencode", "skills")

  // 门控技能来自独立的 skills-gated/，不参与 skills/ 的整体软链
  const gated = discoverSkills(gatedSkillsDir(skillsRootDir))
  const gatedToExpose = gated.filter((s) => GATED_SKILLS[s.name]?.(gateContext) === true)
  const withheld = gated.filter((s) => !gatedToExpose.includes(s)).map((s) => s.name)

  // 目录级软链是「全有或全无」的：只有当没有门控技能需要暴露时才能用
  const mode: SkillExposureMode = gatedToExpose.length === 0 ? "directory" : "per-skill"

  const empty: SkillExposeResult = {
    mode,
    exposed: [],
    skipped: [],
    withheld,
    repointed: [],
    pruned: [],
    unmanaged: false,
  }

  if (skills.length === 0) {
    log("skills: 未发现任何技能，跳过暴露", { skillsRootDir })
    return empty
  }

  try {
    fs.mkdirSync(path.dirname(targetRoot), { recursive: true })
  } catch (error) {
    log("skills: 无法创建 .opencode 目录", { targetRoot, error: String(error) })
    return { ...empty, skipped: [...skills], unmanaged: true }
  }

  const state = inspectRoot(targetRoot)
  if (state.kind === "foreign") {
    log("skills: 技能目录为用户自有，保留不动", { targetRoot, detail: state.detail })
    return { ...empty, skipped: [...skills], unmanaged: true }
  }

  return mode === "directory"
    ? exposeAsDirectoryLink(skills, targetRoot, skillsRootDir, state, empty)
    : exposeAsPerSkillLinks([...skills, ...gatedToExpose], targetRoot, state, empty)
}

/** directory 模式：`.opencode/skills` → 安装根的 skills/，每项目仅 1 条链接。 */
function exposeAsDirectoryLink(
  skills: DiscoveredSkill[],
  targetRoot: string,
  skillsRootDir: string,
  state: RootState,
  base: SkillExposeResult,
): SkillExposeResult {
  const repointed: string[] = []
  const pruned: string[] = []

  try {
    if (state.kind === "ours-link") {
      if (state.target === skillsRootDir) {
        return { ...base, exposed: [...skills] }
      }
      fs.unlinkSync(targetRoot)
      repointed.push(path.basename(targetRoot))
      log("skills: 目录级软链已重指", { from: state.target, to: skillsRootDir })
    } else if (state.kind === "ours-managed-dir" || state.kind === "ours-legacy-dir") {
      // 从 per-skill 形态迁移到 directory 形态：回收本插件建立的逐技能链接
      for (const name of fs.readdirSync(targetRoot)) {
        if (name !== MANAGED_MARKER) pruned.push(name)
      }
      fs.rmSync(targetRoot, { recursive: true, force: true })
      log("skills: 已回收逐技能链接，改用目录级软链", { targetRoot, count: pruned.length })
    }

    fs.symlinkSync(skillsRootDir, targetRoot, "dir")
    log("skills: 已建立目录级软链", { targetRoot, to: skillsRootDir })
    return { ...base, exposed: [...skills], repointed, pruned }
  } catch (error) {
    log("skills: 目录级软链失败", { targetRoot, error: String(error) })
    return { ...base, skipped: [...skills], repointed, pruned, unmanaged: true }
  }
}

/** per-skill 模式：`.opencode/skills` 为本插件独占的真实目录，内含逐技能软链。 */
function exposeAsPerSkillLinks(
  skills: DiscoveredSkill[],
  targetRoot: string,
  state: RootState,
  base: SkillExposeResult,
): SkillExposeResult {
  const exposed: DiscoveredSkill[] = []
  const skipped: DiscoveredSkill[] = []
  const repointed: string[] = []
  const pruned: string[] = []

  try {
    // 从 directory 形态迁移回来：先拆掉目录级软链，换成本插件独占的真实目录
    if (state.kind === "ours-link") {
      fs.unlinkSync(targetRoot)
      log("skills: 已拆除目录级软链，改用逐技能链接（存在被扣留的技能）", { targetRoot })
    }
    fs.mkdirSync(targetRoot, { recursive: true })
    fs.writeFileSync(
      path.join(targetRoot, MANAGED_MARKER),
      "此目录由 witty-diagnosis-agent 插件托管，内容会在每次加载时按安装源重建。\n",
    )
  } catch (error) {
    log("skills: 无法初始化技能目录", { targetRoot, error: String(error) })
    return { ...base, skipped: [...skills], unmanaged: true }
  }

  for (const skill of skills) {
    const target = path.join(targetRoot, skill.name)
    try {
      const existing = fs.lstatSync(target, { throwIfNoEntry: false })
      if (existing) {
        if (!existing.isSymbolicLink()) {
          skipped.push(skill) // 用户自己放的真实目录/文件，一律不动
          continue
        }
        const current = fs.readlinkSync(target)
        if (current === skill.dir) {
          exposed.push(skill)
          continue
        }
        if (!isPathInThisPackage(current, true)) {
          skipped.push(skill)
          continue
        }
        fs.unlinkSync(target)
        fs.symlinkSync(skill.dir, target, "dir")
        log("skills: 已重指陈旧技能链接", { skill: skill.name, from: current, to: skill.dir })
        repointed.push(skill.name)
        exposed.push(skill)
        continue
      }
      fs.symlinkSync(skill.dir, target, "dir")
      exposed.push(skill)
    } catch (error) {
      log("skills: symlink 失败", { skill: skill.name, error: String(error) })
      skipped.push(skill)
    }
  }

  pruned.push(...pruneOrphanLinks(targetRoot, new Set(skills.map((s) => s.name))))
  return { ...base, exposed, skipped, repointed, pruned }
}

/**
 * 清理孤儿链接：指向本项目某个 checkout、但当前安装中已不存在的技能。
 *
 * 旧 checkout 若比当前安装多出若干技能，其软链会滞留在 .opencode/skills/ 下，
 * 让已被删除/改名的技能继续对所有 agent 可见。
 */
function pruneOrphanLinks(targetRoot: string, currentNames: Set<string>): string[] {
  const pruned: string[] = []
  let entries: string[]
  try {
    entries = fs.readdirSync(targetRoot)
  } catch {
    return pruned
  }

  for (const name of entries) {
    if (name === MANAGED_MARKER || currentNames.has(name)) continue
    const target = path.join(targetRoot, name)
    try {
      if (!fs.lstatSync(target, { throwIfNoEntry: false })?.isSymbolicLink()) continue
      const current = fs.readlinkSync(target)
      if (!isPathInThisPackage(current, true)) continue
      fs.unlinkSync(target)
      pruned.push(name)
      log("skills: 已清理孤儿技能链接", { skill: name, from: current })
    } catch (error) {
      log("skills: 清理孤儿技能链接失败", { target, error: String(error) })
    }
  }
  return pruned
}

/* ────────────────────────── 自检 ────────────────────────── */

/**
 * 检查某项目的技能暴露现状，供 `witty doctor` 使用。只读，不做任何修改。
 *
 * 这一项回答的是排查中最关键、此前却无从得知的问题：**当前项目到底在用哪一份 skill**。
 */
export function inspectSkillExposure(
  projectDir: string,
  skillsRootDir: string,
  knownNames: ReadonlySet<string>,
): SkillExposureStatus {
  const targetRoot = path.join(projectDir, ".opencode", "skills")
  const state = inspectRoot(targetRoot)

  const status: SkillExposureStatus = {
    targetRoot,
    mode: "absent",
    matchesInstall: false,
    linkCount: 0,
    danglingCount: 0,
    orphanCount: 0,
    foreignCount: 0,
  }

  if (state.kind === "absent") return status
  if (state.kind === "foreign") {
    return { ...status, mode: "foreign", detail: state.detail }
  }

  if (state.kind === "ours-link") {
    return {
      ...status,
      mode: "directory",
      target: state.target,
      matchesInstall: state.target === skillsRootDir,
      danglingCount: fs.existsSync(state.target) ? 0 : 1,
      linkCount: 1,
    }
  }

  // per-skill 形态：逐条统计
  let entries: string[] = []
  try {
    entries = fs.readdirSync(targetRoot)
  } catch {
    /* 忽略：不可读时按空目录处理 */
  }
  let link = 0
  let dangling = 0
  let orphan = 0
  let foreign = 0
  for (const name of entries) {
    if (name === MANAGED_MARKER) continue
    const p = path.join(targetRoot, name)
    if (!fs.lstatSync(p, { throwIfNoEntry: false })?.isSymbolicLink()) {
      foreign++
      continue
    }
    link++
    const current = fs.readlinkSync(p)
    if (!fs.existsSync(current)) dangling++
    if (!knownNames.has(name)) orphan++
    if (path.dirname(current) !== skillsRootDir) foreign++
  }
  return {
    ...status,
    mode: "per-skill",
    legacy: state.kind === "ours-legacy-dir",
    matchesInstall: foreign === 0 && dangling === 0,
    linkCount: link,
    danglingCount: dangling,
    orphanCount: orphan,
    foreignCount: foreign,
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
