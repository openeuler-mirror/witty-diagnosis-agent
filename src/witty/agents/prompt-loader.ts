import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

import type { OutputLanguage } from "../config/types"
import type { AgentDefinition } from "./types"
import { languageLockDirective } from "../shared/language-lock"
import { log } from "../shared/log"

/**
 * 提示词加载器：从 agents/prompts/<name>.md 读取纯数据提示词。
 *
 * 语言：优先加载 `<name>.<lang>.md`（如 xuanyuan.en.md）；不存在则回退到基础
 * `<name>.md`。无论走哪条路径，都会在正文**最前面**无条件注入语言锁定指令，
 * 确保输出语言只由安装时选定的语言决定，不随用户提问语言或 skill 语言漂移。
 *
 * 支持占位符插值（{{PROJECT_DIR}} / {{REPORT_DIR}}）。文件全缺失时用降级提示词。
 */

export interface PromptContext {
  /** 当前项目目录 */
  projectDir: string
  /** 报告输出目录 */
  reportDir: string
  /** 输出语言 */
  language: OutputLanguage
  /** 用户附加指令（来自 AgentOverride.extra_instructions） */
  extraInstructions?: string
}

const PROMPTS_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), "prompts")

export function loadAgentPrompt(definition: AgentDefinition, context: PromptContext): string {
  const base = definition.promptFile.replace(/\.md$/, "")
  const localizedFile = path.join(PROMPTS_DIR, `${base}.${context.language}.md`)
  const defaultFile = path.join(PROMPTS_DIR, definition.promptFile)

  let template: string
  try {
    template = fs.readFileSync(localizedFile, "utf8")
  } catch {
    try {
      template = fs.readFileSync(defaultFile, "utf8")
    } catch {
      log("prompt-loader: 提示词文件缺失，使用降级提示词", { agent: definition.name })
      template =
        context.language === "en"
          ? `You are ${definition.name}. Responsibility: ${definition.description}`
          : `你是 ${definition.displayName}。职责：${definition.description}`
    }
  }

  let prompt = template
    .replaceAll("{{PROJECT_DIR}}", context.projectDir)
    .replaceAll("{{REPORT_DIR}}", context.reportDir)

  // 语言锁定指令无条件置顶注入：即便正文已是目标语言，也要显式压住
  // “跟随用户提问语言 / 跟随 skill 语言”的默认倾向。
  prompt = `${languageLockDirective(context.language)}\n\n---\n\n${prompt}`

  if (context.extraInstructions) {
    const heading = context.language === "en" ? "## Additional user instructions" : "## 用户附加指令"
    prompt += `\n\n${heading}\n\n${context.extraInstructions}`
  }
  return prompt
}
