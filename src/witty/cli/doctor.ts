import fs from "node:fs"
import path from "node:path"
import { execFileSync } from "node:child_process"

import { wittyConfigSchema } from "../config/schema"
import { readJsoncFile } from "../shared/jsonc"
import { packageRootDir, resolveSkillsDir } from "../shared/paths"
import { discoverSkills } from "../skills/discovery"
import { PLUGIN_NAME, REQUIRED_SUBAGENT_DEPTH, opencodeConfigDir } from "./install"

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
  const registered = pluginList.some(
    (entry) => typeof entry === "string" && entry.includes(PLUGIN_NAME),
  )
  return registered
    ? { name: "plugin-registered", status: "pass", detail: `已登记于 ${configFile}` }
    : {
        name: "plugin-registered",
        status: "fail",
        detail: `${configFile} 的 plugin 列表中未找到 ${PLUGIN_NAME}`,
        remedy: `运行 ${PLUGIN_NAME} install`,
      }
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
