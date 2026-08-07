import fs from "node:fs"
import path from "node:path"
import os from "node:os"
import { pathToFileURL } from "node:url"

import { select, isCancel } from "@clack/prompts"

import type { OutputLanguage } from "../config/types"
import { readJsoncFile } from "../shared/jsonc"
import { packageRootDir } from "../shared/paths"

/**
 * 安装命令：把插件注册进 OpenCode 用户配置，并初始化缺省插件配置。
 *
 * 注册语义：
 * - 本插件在 opencode.json 的 plugin 数组中以 file:// 绝对路径条目存在；
 * - 安装时把**所有**含本插件名的条目替换为当前入口的 file:// 条目，
 *   保证同一时刻只有一条生效；
 * - 已是目标条目则不重复写入（幂等）。
 */

export const PLUGIN_NAME = "witty-diagnosis-agent"

/** 诊断流水线需要 2 层子代理嵌套，OpenCode 顶层 subagent_depth 默认 1，须放宽。 */
export const REQUIRED_SUBAGENT_DEPTH = 3

export interface InstallOptions {
  /** 只打印将要做的变更，不写文件 */
  dryRun?: boolean
  /** 输出语言。命令行显式传入时跳过交互；未传且在 TTY 时弹选择菜单，非 TTY 默认 zh */
  language?: OutputLanguage
}

export interface InstallReport {
  opencodeConfigFile: string
  /** 本次写入（或已存在）的插件条目 */
  pluginEntry: string
  pluginRegistered: boolean
  pluginAlreadyRegistered: boolean
  /** 被替换掉的旧条目（如旧链路 dist/index.js） */
  replacedEntries: string[]
  /** 本次写入 opencode.json 的 subagent_depth（已放宽时为新值，未改动时为 null） */
  subagentDepthSet: number | null
  /** 本次选定并写入配置的输出语言 */
  outputLanguage: OutputLanguage
  pluginConfigFile: string
  pluginConfigCreated: boolean
}

export function opencodeConfigDir(): string {
  return path.join(os.homedir(), ".config", "opencode")
}

/** 插件入口的 file:// 条目（基于包根定位构建产物）。 */
export function pluginEntryUrl(): string {
  return pathToFileURL(path.join(packageRootDir(), "dist", "index.js")).href
}

export async function runInstall(options: InstallOptions = {}): Promise<InstallReport> {
  const configDir = opencodeConfigDir()
  const opencodeConfigFile = path.join(configDir, "opencode.json")
  const pluginConfigFile = path.join(configDir, `${PLUGIN_NAME}.jsonc`)
  const pluginEntry = pluginEntryUrl()

  const { already, replaced, subagentDepthSet } = registerPlugin(
    opencodeConfigFile,
    pluginEntry,
    options.dryRun ?? false,
  )

  // 语言选择：命令行显式传入优先；否则读已有配置里的值作默认；再交互/回退 zh
  const currentLang = readConfiguredLanguage(pluginConfigFile)
  const outputLanguage =
    options.language ?? (await promptOutputLanguage(currentLang ?? "zh"))

  const pluginConfigCreated = writePluginConfig(
    pluginConfigFile,
    configDir,
    outputLanguage,
    options.dryRun ?? false,
  )

  return {
    opencodeConfigFile,
    pluginEntry,
    pluginRegistered: true,
    pluginAlreadyRegistered: already,
    replacedEntries: replaced,
    subagentDepthSet,
    outputLanguage,
    pluginConfigFile,
    pluginConfigCreated,
  }
}

/** 读取现有插件配置里的 output_language（用作交互默认值），不存在返回 undefined。 */
function readConfiguredLanguage(pluginConfigFile: string): OutputLanguage | undefined {
  const raw = readJsoncFile(pluginConfigFile)
  const lang =
    typeof raw === "object" && raw !== null
      ? (raw as { output_language?: unknown }).output_language
      : undefined
  return lang === "zh" || lang === "en" ? lang : undefined
}

/**
 * 交互式语言选择（对齐旧版安装体验）。
 * 非交互终端（无 TTY，如 CI/管道）直接返回默认值，不阻塞。
 */
async function promptOutputLanguage(initial: OutputLanguage): Promise<OutputLanguage> {
  if (!process.stdin.isTTY) return initial

  const result = await select({
    message:
      "Select output language for Witty Diagnosis Agent / 选择 Witty Diagnosis Agent 的输出语言\n" +
      "  (This affects all agents' reasoning, response, and report / 影响所有 Agent 的思考、回复和生成的报告)",
    options: [
      { value: "zh", label: "简体中文 (zh)" },
      { value: "en", label: "English (en)" },
    ],
    initialValue: initial,
  })
  if (isCancel(result)) return initial
  return result as OutputLanguage
}

/**
 * 写入/更新插件配置文件。
 * - 不存在：用选定语言创建缺省配置，返回 true。
 * - 已存在：只更新其中的 output_language 字段（保留用户其它设置），返回 false。
 */
function writePluginConfig(
  pluginConfigFile: string,
  configDir: string,
  language: OutputLanguage,
  dryRun: boolean,
): boolean {
  if (!fs.existsSync(pluginConfigFile)) {
    if (!dryRun) {
      fs.mkdirSync(configDir, { recursive: true })
      fs.writeFileSync(pluginConfigFile, defaultPluginConfigJsonc(language))
    }
    return true
  }

  // 已存在：解析后只改 output_language，保留其它字段
  const raw = readJsoncFile(pluginConfigFile)
  const config: Record<string, unknown> =
    typeof raw === "object" && raw !== null && !Array.isArray(raw)
      ? { ...(raw as Record<string, unknown>) }
      : {}
  if (config["output_language"] !== language) {
    config["output_language"] = language
    if (!dryRun) fs.writeFileSync(pluginConfigFile, JSON.stringify(config, null, 2) + "\n")
  }
  return false
}

/**
 * 注册/切换插件条目（移除所有含插件名的旧条目，写入目标条目，幂等），
 * 并兜底放宽顶层 subagent_depth（诊断流水线的 2 层子代理委派需要 ≥2，写 3 留余量）。
 */
function registerPlugin(
  opencodeConfigFile: string,
  pluginEntry: string,
  dryRun: boolean,
): { already: boolean; replaced: string[]; subagentDepthSet: number | null } {
  const raw = readJsoncFile(opencodeConfigFile)
  const config: Record<string, unknown> =
    typeof raw === "object" && raw !== null && !Array.isArray(raw)
      ? { ...(raw as Record<string, unknown>) }
      : {}

  const pluginList: unknown[] = Array.isArray(config["plugin"]) ? [...(config["plugin"] as unknown[])] : []

  const ours = pluginList.filter(
    (entry): entry is string => typeof entry === "string" && entry.includes(PLUGIN_NAME),
  )
  const pluginAlready = ours.length === 1 && ours[0] === pluginEntry

  // subagent_depth 兜底：不覆盖用户更大的值。
  // （权限不写全局，改由各 agent 自己的 permission 承载，避免影响其他插件。）
  const currentDepth = config["subagent_depth"]
  const depthNeedsSet =
    typeof currentDepth !== "number" || currentDepth < REQUIRED_SUBAGENT_DEPTH
  const subagentDepthSet = depthNeedsSet ? REQUIRED_SUBAGENT_DEPTH : null

  if (pluginAlready && !depthNeedsSet) {
    return { already: true, replaced: [], subagentDepthSet: null }
  }

  const replaced = ours.filter((entry) => entry !== pluginEntry)
  if (!pluginAlready) {
    const kept = pluginList.filter(
      (entry) => !(typeof entry === "string" && entry.includes(PLUGIN_NAME)),
    )
    kept.push(pluginEntry)
    config["plugin"] = kept
  }
  if (depthNeedsSet) config["subagent_depth"] = REQUIRED_SUBAGENT_DEPTH

  if (!dryRun) {
    fs.mkdirSync(path.dirname(opencodeConfigFile), { recursive: true })
    fs.writeFileSync(opencodeConfigFile, JSON.stringify(config, null, 2) + "\n")
  }
  return { already: pluginAlready, replaced, subagentDepthSet }
}

function defaultPluginConfigJsonc(language: OutputLanguage): string {
  return `{
  // witty-diagnosis-agent 配置（JSONC，允许注释与尾逗号）
  // 完整键说明见 assets/witty-diagnosis-agent.schema.json
  // 输出语言：zh=简体中文 / en=English（影响所有 Agent 的思考、回复与报告）
  "output_language": "${language}",
  "agents": {},
  "guards": {
    "md_only": true,
  },
}
`
}
