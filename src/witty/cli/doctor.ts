import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { execFileSync } from "node:child_process"

import { wittyConfigSchema } from "../config/schema"
import { readJsoncFile } from "../shared/jsonc"
import { packageRootDir, resolveSkillsDir } from "../shared/paths"
import { discoverSkills, gatedSkillsDir, inspectSkillExposure } from "../skills/discovery"
import { PLUGIN_NAME, REQUIRED_SUBAGENT_DEPTH, opencodeConfigDir, pluginEntryUrl } from "./install"

/**
 * doctor 命令：环境自检（doctor-lite）。
 * 每项返回 pass/warn/fail + 修复建议；任一 fail 时 CLI 以退出码 1 结束。
 */

export type CheckStatus = "pass" | "warn" | "fail"

export interface CheckResult {
  name: string
  status: CheckStatus
  detail: string
  /** fail/warn 时的修复建议 */
  remedy?: string
}

export async function runDoctor(): Promise<CheckResult[]> {
  return [
    checkNodeVersion(),
    checkOpencodeCli(),
    checkPluginRegistered(),
    checkSubagentDepth(),
    checkPluginConfig(),
    checkSkillsDir(),
    checkSkillExposure(),
  ]
}

function checkSubagentDepth(): CheckResult {
  const configFile = path.join(opencodeConfigDir(), "opencode.json")
  const raw = readJsoncFile(configFile)
  const depth =
    typeof raw === "object" && raw !== null
      ? (raw as { subagent_depth?: unknown }).subagent_depth
      : undefined
  const effective = typeof depth === "number" ? depth : 1
  return effective >= REQUIRED_SUBAGENT_DEPTH
    ? { name: "subagent-depth", status: "pass", detail: `subagent_depth = ${effective}（诊断流水线需 ≥2）` }
    : {
        name: "subagent-depth",
        status: "fail",
        detail: `subagent_depth = ${effective}，会拦截第二层子代理委派（fuxi→general / dayu→kuafu）`,
        remedy: `运行 ${PLUGIN_NAME} install（会写入 subagent_depth: ${REQUIRED_SUBAGENT_DEPTH}）`,
      }
}

function checkNodeVersion(): CheckResult {
  const major = Number(process.versions.node.split(".")[0])
  return major >= 20
    ? { name: "node-version", status: "pass", detail: `Node ${process.versions.node}` }
    : {
        name: "node-version",
        status: "fail",
        detail: `Node ${process.versions.node} 低于要求`,
        remedy: "安装 Node.js >= 20",
      }
}

function checkOpencodeCli(): CheckResult {
  try {
    const version = execFileSync("opencode", ["--version"], {
      encoding: "utf8",
      timeout: 10_000,
    }).trim()
    return { name: "opencode-cli", status: "pass", detail: `opencode ${version}` }
  } catch {
    return {
      name: "opencode-cli",
      status: "fail",
      detail: "opencode 命令不可用",
      remedy: "安装 OpenCode：https://opencode.ai/（或确认其在 PATH 中）",
    }
  }
}

function checkPluginRegistered(): CheckResult {
  const configFile = path.join(opencodeConfigDir(), "opencode.json")
  const raw = readJsoncFile(configFile)
  const pluginList =
    typeof raw === "object" && raw !== null && Array.isArray((raw as { plugin?: unknown }).plugin)
      ? ((raw as { plugin: unknown[] }).plugin)
      : []
  const ours = pluginList.filter(
    (entry): entry is string => typeof entry === "string" && entry.includes(PLUGIN_NAME),
  )
  if (ours.length === 0) {
    return {
      name: "plugin-registered",
      status: "fail",
      detail: `${configFile} 的 plugin 列表中未找到 ${PLUGIN_NAME}`,
      remedy: `运行 ${PLUGIN_NAME} install`,
    }
  }

  // 仅登记还不够：条目指向的构建产物必须真实存在，
  // 否则 OpenCode 会静默跳过该插件（表现为看不到任何 agent）。
  const expected = pluginEntryUrl()
  const stale = ours.filter((entry) => {
    if (!entry.startsWith("file://")) return false
    try {
      return !fs.existsSync(fileURLToPath(entry))
    } catch {
      return false
    }
  })
  if (stale.length > 0) {
    return {
      name: "plugin-registered",
      status: "fail",
      detail: `plugin 条目指向的文件不存在: ${stale.join(", ")}（应为 ${expected}）`,
      remedy: `运行 npm run build 后再执行 ${PLUGIN_NAME} install`,
    }
  }

  return { name: "plugin-registered", status: "pass", detail: `已登记于 ${configFile}` }
}

function checkPluginConfig(): CheckResult {
  const configFile = path.join(opencodeConfigDir(), `${PLUGIN_NAME}.jsonc`)
  if (!fs.existsSync(configFile)) {
    return {
      name: "plugin-config",
      status: "warn",
      detail: `${configFile} 不存在，将使用默认配置`,
      remedy: `运行 ${PLUGIN_NAME} install 生成缺省配置`,
    }
  }
  const raw = readJsoncFile(configFile)
  if (raw === undefined) {
    return {
      name: "plugin-config",
      status: "fail",
      detail: `${configFile} 无法解析（JSONC 语法错误）`,
      remedy: "修正配置文件语法",
    }
  }
  const parsed = wittyConfigSchema.safeParse(raw)
  return parsed.success
    ? {
        name: "plugin-config",
        status: "pass",
        detail: `${configFile} 校验通过（输出语言: ${parsed.data.output_language}）`,
      }
    : {
        name: "plugin-config",
        status: "fail",
        detail: `配置校验失败: ${parsed.error.issues.map((i) => `${i.path.join(".")}: ${i.message}`).join("; ")}`,
        remedy: "按 schema 修正配置键",
      }
}

/**
 * 检查当前项目实际在用哪一份 skill。
 *
 * 这一项回答排查中最关键、此前却无从得知的问题：项目级 `.opencode/skills` 指向哪里、
 * 是否就是当前安装。历史上出现过「插件已换到新 checkout、技能却仍加载旧仓库」且
 * 长期无人察觉的情况，正是因为没有任何一条命令能给出这个答案。
 */
function checkSkillExposure(): CheckResult {
  const name = "skill-exposure"
  const projectDir = process.cwd()
  const skillsDir = resolveSkillsDir("skills")
  const main = discoverSkills(skillsDir)
  // 已知集合需含门控技能，否则 per-skill 形态下会把门控技能误判为孤儿
  const known = new Set([...main, ...discoverSkills(gatedSkillsDir(skillsDir))].map((s) => s.name))
  const st = inspectSkillExposure(projectDir, skillsDir, known)

  if (st.mode === "absent") {
    return {
      name,
      status: "warn",
      detail: `当前项目尚未暴露技能: ${st.targetRoot} 不存在`,
      remedy: "在本项目目录启动一次 opencode，插件加载时会自动建立",
    }
  }

  if (st.mode === "foreign") {
    return {
      name,
      status: "warn",
      detail: `${st.targetRoot} 为用户自有内容，插件未接管（${st.detail}）`,
      remedy: "如需由插件托管，请移走该目录后重启 opencode",
    }
  }

  if (st.mode === "directory") {
    if (st.danglingCount > 0) {
      return {
        name,
        status: "fail",
        detail: `技能目录软链已悬空: ${st.targetRoot} -> ${st.target}（目标不存在）`,
        remedy: "重启 opencode 由插件重建，或确认安装根未被移动/删除",
      }
    }
    return st.matchesInstall
      ? {
          name,
          status: "pass",
          detail: `目录级软链 -> ${st.target}（与当前安装一致，${main.length} 个技能；门控技能未暴露）`,
        }
      : {
          name,
          status: "fail",
          detail: `技能来自其他安装: ${st.target}，当前安装为 ${skillsDir}`,
          remedy: "重启 opencode，插件会自动重指到当前安装",
        }
  }

  // per-skill 形态
  const problems: string[] = []
  if (st.danglingCount > 0) problems.push(`悬空 ${st.danglingCount}`)
  if (st.foreignCount > 0) problems.push(`非当前安装 ${st.foreignCount}`)
  if (st.orphanCount > 0) problems.push(`孤儿 ${st.orphanCount}`)
  return problems.length === 0
    ? { name, status: "pass", detail: `逐技能软链 ${st.linkCount} 条，均来自当前安装（因门控扣留技能而采用此形态）` }
    : {
        name,
        status: "fail",
        detail: `逐技能软链 ${st.linkCount} 条存在问题: ${problems.join("、")}`,
        remedy: "重启 opencode，插件会自动重指并清理",
      }
}

function checkSkillsDir(): CheckResult {
  const skillsDir = resolveSkillsDir("skills")
  if (!fs.existsSync(skillsDir)) {
    return {
      name: "skills-dir",
      status: "warn",
      detail: `技能目录不存在: ${skillsDir}（包根: ${packageRootDir()}）`,
      remedy: "确认包安装完整，或在配置中指定 skills_dir",
    }
  }
  const skills = discoverSkills(skillsDir)
  return skills.length > 0
    ? { name: "skills-dir", status: "pass", detail: `发现 ${skills.length} 个诊断技能` }
    : {
        name: "skills-dir",
        status: "warn",
        detail: `${skillsDir} 下未发现含 SKILL.md 的技能`,
        remedy: "确认 skills/ 目录内容完整",
      }
}
