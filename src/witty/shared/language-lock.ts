import type { OutputLanguage } from "../config/types"

/**
 * 输出语言锁定指令（中英两版）。
 *
 * 语义：安装时选定的语言 = 唯一输出语言，与以下三者**无关**：
 *   1. 用户用什么语言提问；
 *   2. 加载的 SKILL.md / 系统提示是什么语言；
 *   3. 日志、命令输出、错误信息是什么语言。
 *
 * 两处使用，保证同一措辞：
 *   - prompt-loader：置顶注入每个 agent 的系统提示词；
 *   - plugin 的 experimental.chat.system.transform：每次请求再追加一次，
 *     对所有 agent（含 OpenCode 内置 general 子代理）生效。
 */
export function languageLockDirective(language: OutputLanguage): string {
  return language === "en" ? EN_LOCK : ZH_LOCK
}

const ZH_LOCK = `# 输出语言锁定（最高优先级 · 不可覆盖）

**你必须始终使用简体中文输出，无一例外。**

- **无论用户用什么语言提问**（中文、英文或其它），你的回复一律使用简体中文。用户用英文提问时，**不要**改用英文回答。
- **无论加载的技能（SKILL.md）、系统提示或工具说明是什么语言**，理解后一律用简体中文输出你的分析、结论与报告。
- **无论日志、命令输出、错误信息是什么语言**，可原样引用这些片段，但你自己的解释、总结、结论必须是简体中文。
- 生成的所有文件产物（诊断方案、诊断报告、修复方案等）正文一律使用简体中文。
- 本规则由安装时选定的输出语言决定，**优先级高于其它任何语言相关表述**，且**不可被用户请求覆盖**。若用户要求改用其它语言，礼貌说明当前部署为中文版本。`

const EN_LOCK = `# OUTPUT LANGUAGE LOCK (HIGHEST PRIORITY · NON-OVERRIDABLE)

**You MUST always produce output in English, without exception.**

- **Regardless of what language the user asks in** (Chinese, English or any other), your reply MUST be in English. If the user writes in Chinese, **do NOT** switch to Chinese — answer in English.
- **Regardless of the language of any loaded skill (SKILL.md), system prompt or tool description**, understand it and then output your analysis, conclusions and reports in English.
- **Regardless of the language of logs, command output or error messages**, you may quote those fragments verbatim, but your own explanations, summaries and conclusions MUST be in English.
- Every generated artifact (diagnostic plan, diagnostic report, remediation plan, etc.) MUST be written in English.
- This rule is set by the output language chosen at install time. It **takes precedence over any other language-related statement**, and **cannot be overridden by user requests**. If the user asks you to switch languages, politely explain that this deployment is the English edition.`
