import fs from "node:fs"
import path from "node:path"
import os from "node:os"

import { packageRootDir } from "../shared/paths"

/**
 * xiaoO 安装：把技能库与 agent 资源装进 xiaoO 用户目录，并合并 witty 配置段。
 *
 * 与 OpenCode 路径的区别：OpenCode 靠软链把仓库 skills/ 挂进项目技能目录，
 * 而 xiaoO 没有等价机制，只能把技能**拷贝**进 ~/.xiaoo/skills。拷贝形态的
 * 固有风险是腐化——源中删除的技能不会消失、可执行位会丢——故本模块必须
 * 做两件裸拷贝不做的事：保留权限位、按清单对账删除已移除的技能。
 *
 * 本模块是 install.sh 中 install_xiaoo() / sync_skills() /
 * replace_xiaoo_witty_config() 的等价实现，供 rpm 安装路径使用
 * （rpm 不附带 install.sh）。
 */

/** 记录上次安装写入的技能名，用于识别“本次应当移除”的技能。 */
const SKILLS_MANIFEST = ".witty-skills-manifest"

/** witty 在 xiaoO 配置中占用的 TOML 表，合并时整体替换。 */
const WITTY_AGENTS = ["fuxi", "kuafu", "dayu", "xuanyuan", "baize"] as const
const WITTY_SECTIONS = new Set<string>(
  WITTY_AGENTS.flatMap((a) => [
    `agent.${a}`,
    `agent.${a}.tools`,
    `subagent.${a}`,
    `subagent.${a}.tools`,
  ]),
)

/** 配置合并的包裹标记，用于下次安装时整段剔除旧内容。 */
const MARKER_BEGIN = "# >>> witty-diagnosis-agent xiaoO config >>>"
const MARKER_END = "# <<< witty-diagnosis-agent xiaoO config <<<"

/** 归属于 witty、但不在表内的散行（注释），同样需要识别。 */
const WITTY_LOOSE_LINES = [/WittyDiagnosisAgent/, /Predefined subagent roles for Xuanyuan delegation/]

export interface XiaooInstallOptions {
  /** 只计算将要做的变更，不写文件 */
  dryRun?: boolean
}

export interface XiaooInstallReport {
  xiaooHome: string
  configFile: string
  /** 已同步的常规技能数 */
  skills: number
  /** 已同步的门控技能数 */
  gatedSkills: number
  /** 源中已删除、本次从目标目录移除的技能名 */
  removedSkills: string[]
  /** true=首次写入模板；false=在已有配置上合并 witty 段 */
  configCreated: boolean
}

export function xiaooHome(): string {
  return process.env.XIAOO_HOME || path.join(os.homedir(), ".xiaoo")
}

export function xiaooConfigDir(): string {
  return process.env.XIAOO_CONFIG_DIR || path.join(os.homedir(), ".config", "xiaoo")
}

/** xiaoO 资源目录（command / tools / config 模板），随包发布。 */
function xiaooAssetsDir(): string {
  return path.join(packageRootDir(), "src", "xiaoO")
}

/**
 * 把源技能目录同步到目标目录。
 *
 * 相比裸拷贝多做两件事，二者缺一都会让目标目录逐次腐化：
 * 1. 保留权限位——skills/ 下有 20 余个 .sh/.py 需要可执行位；
 * 2. 按清单对账，移除上次装过、本次源中已不存在的技能。归属只认清单，
 *    不靠“目录里有 SKILL.md”判断，否则会误删用户自行放入的技能。
 */
function syncSkills(src: string, dst: string, dryRun: boolean): { count: number; removed: string[] } {
  const removed: string[] = []
  if (!fs.existsSync(src)) return { count: 0, removed }

  const manifestFile = path.join(dst, SKILLS_MANIFEST)
  const current = fs
    .readdirSync(src, { withFileTypes: true })
    .filter((e) => e.isDirectory() && fs.existsSync(path.join(src, e.name, "SKILL.md")))
    .map((e) => e.name)

  // 1) 对账：清单中存在、但源中已无的技能予以移除
  if (fs.existsSync(manifestFile)) {
    for (const name of fs.readFileSync(manifestFile, "utf8").split("\n")) {
      const skill = name.trim()
      if (!skill || skill.includes("/") || skill === "." || skill === "..") continue
      if (current.includes(skill)) continue
      if (!fs.existsSync(path.join(dst, skill))) continue
      if (!dryRun) fs.rmSync(path.join(dst, skill), { recursive: true, force: true })
      removed.push(skill)
    }
  }

  if (dryRun) return { count: current.length, removed }

  // 2) 拷贝（cpSync 逐文件走 copyFile，保留权限位）
  fs.mkdirSync(dst, { recursive: true })
  fs.cpSync(src, dst, { recursive: true, force: true })

  // 3) 写入本次清单
  fs.writeFileSync(manifestFile, current.join("\n") + "\n")
  return { count: current.length, removed }
}

/** 该行是否切换 TOML 多行字符串状态（''' 或 """）。 */
function togglesMultiline(line: string): boolean {
  return line.includes("'''") || line.includes('"""')
}

/** 形如 [a.b.c] 的合法表头则返回表名，否则返回 undefined。 */
function tableName(line: string): string | undefined {
  const m = /^\[([A-Za-z0-9_.-]+)\]/.exec(line)
  return m?.[1]
}

/**
 * 按表切分 TOML 文本。
 * @param keepWitty true=只保留 witty 的表与散行（提取片段）；false=剔除 witty 内容（清理旧配置）
 */
function filterWittySections(text: string, keepWitty: boolean): string {
  const out: string[] = []
  let inMultiline = false
  let inMarker = false
  let inWitty = false

  for (const line of text.split("\n")) {
    if (!keepWitty) {
      // 旧的标记包裹段整体丢弃，避免重复累积
      if (line === MARKER_BEGIN) {
        inMarker = true
        continue
      }
      if (line === MARKER_END) {
        inMarker = false
        continue
      }
      if (inMarker) continue
    }

    if (inMultiline) {
      if (inWitty === keepWitty) out.push(line)
      if (togglesMultiline(line)) inMultiline = false
      continue
    }

    const name = tableName(line)
    if (name !== undefined) {
      inWitty = WITTY_SECTIONS.has(name)
    } else if (!keepWitty && line.startsWith("[")) {
      continue // 非法表头行，丢弃（与 install.sh 行为一致）
    }

    const looseWitty = WITTY_LOOSE_LINES.some((re) => re.test(line))
    const keep = keepWitty ? inWitty || looseWitty : !inWitty && !looseWitty
    if (keep) out.push(line)
    if (togglesMultiline(line)) inMultiline = true
  }
  return out.join("\n")
}

/**
 * 在已有 xiaoO 配置上合并 witty 段：先剔除旧的 witty 内容，再把模板中的
 * witty 段以标记包裹追加到末尾。用户自有配置（如 [llm]、[hooker]）原样保留。
 */
function mergeWittyConfig(configFile: string, templateFile: string, dryRun: boolean): void {
  const existing = fs.readFileSync(configFile, "utf8")
  const template = fs.readFileSync(templateFile, "utf8")
  const merged =
    filterWittySections(existing, false).replace(/\n+$/, "") +
    "\n\n" +
    MARKER_BEGIN +
    "\n" +
    filterWittySections(template, true).replace(/\n+$/, "") +
    "\n" +
    MARKER_END +
    "\n"
  if (!dryRun) fs.writeFileSync(configFile, merged)
}

/** 把技能与资源装进 xiaoO 用户目录，并写入/合并配置。 */
export function runXiaooInstall(options: XiaooInstallOptions = {}): XiaooInstallReport {
  const dryRun = options.dryRun ?? false
  const root = packageRootDir()
  const assets = xiaooAssetsDir()
  const home = xiaooHome()
  const configDir = xiaooConfigDir()
  const configFile = path.join(configDir, "config.toml")
  const template = path.join(assets, "config", "config.toml")

  for (const [label, dir] of [
    ["技能目录", path.join(root, "skills")],
    ["xiaoO command", path.join(assets, "command")],
    ["xiaoO tools", path.join(assets, "tools")],
  ] as const) {
    if (!fs.existsSync(dir)) throw new Error(`${label}不存在: ${dir}（包安装可能不完整）`)
  }
  if (!fs.existsSync(template)) throw new Error(`xiaoO 配置模板不存在: ${template}`)

  if (!dryRun) {
    for (const d of [path.join(home, "command"), path.join(home, "tools"), configDir]) {
      fs.mkdirSync(d, { recursive: true })
    }
  }

  const skills = syncSkills(path.join(root, "skills"), path.join(home, "skills"), dryRun)
  const gated = syncSkills(path.join(root, "skills-gated"), path.join(home, "skills-gated"), dryRun)

  if (!dryRun) {
    fs.cpSync(path.join(assets, "command"), path.join(home, "command"), { recursive: true, force: true })
    fs.cpSync(path.join(assets, "tools"), path.join(home, "tools"), { recursive: true, force: true })
  }

  const configCreated = !fs.existsSync(configFile)
  if (configCreated) {
    if (!dryRun) fs.copyFileSync(template, configFile)
  } else {
    mergeWittyConfig(configFile, template, dryRun)
  }

  return {
    xiaooHome: home,
    configFile,
    skills: skills.count,
    gatedSkills: gated.count,
    removedSkills: [...skills.removed, ...gated.removed],
    configCreated,
  }
}
