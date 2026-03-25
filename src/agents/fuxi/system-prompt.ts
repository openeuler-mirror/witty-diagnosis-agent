import { FUXI_IDENTITY_CONSTRAINTS } from "./identity-constraints"
import { FUXI_INTERVIEW_MODE } from "./interview-mode"
import { FUXI_PLAN_GENERATION } from "./plan-generation"
import { FUXI_PLAN_TEMPLATE } from "./plan-template"
import { FUXI_BEHAVIORAL_SUMMARY } from "./behavioral-summary"
import { isGptModel, isGeminiModel } from "../types"
import { exec } from "child_process"
import { promisify } from "util"
import * as fs from "fs"
import * as path from "path"
import * as os from "os"

const execAsync = promisify(exec)

/**
 * Combined Fuxi system prompt (Claude-optimized, default).
 * Assembled from modular sections for maintainability.
 */
export const FUXI_SYSTEM_PROMPT = `${FUXI_IDENTITY_CONSTRAINTS}
${FUXI_INTERVIEW_MODE}
${FUXI_PLAN_GENERATION}
${FUXI_PLAN_TEMPLATE}
${FUXI_BEHAVIORAL_SUMMARY}`

/**
 * Fuxi planner permission configuration.
 * Allows write/edit for plan files (.md only, enforced by fuxi-md-only hook).
 * Question permission allows agent to ask user questions via OpenCode's QuestionTool.
 */
export const FUXI_PERMISSION = {
  edit: "allow" as const,
  bash: "allow" as const,
  webfetch: "allow" as const,
  question: "allow" as const,
}

export type FuxiPromptSource = "default" | "gpt" | "gemini"

/**
 * Determines which Fuxi prompt to use based on model.
 */
export function getFuxiPromptSource(model?: string): FuxiPromptSource {
  if (model && isGptModel(model)) {
    return "gpt"
  }
  if (model && isGeminiModel(model)) {
    return "gemini"
  }
  return "default"
}

/**
 * Gets the appropriate Fuxi prompt based on model.
 * GPT models → GPT-5.2 optimized prompt (XML-tagged, principle-driven)
 * Gemini models → Gemini-optimized prompt (aggressive tool-call enforcement, thinking checkpoints)
 * Default (Claude, etc.) → Claude-optimized prompt (modular sections)
 */
export async function getFuxiPrompt(model?: string): Promise<string> {
  // Check environment to avoid redundant tool calls
  let extraPrompt = "\n\n# 环境预检查结果 (Pre-check Results)\n";
  extraPrompt += "在每次交互前，系统已自动探测了本地环境状态：\n";

  try {
    await execAsync("which ansible");
    extraPrompt += "- **Ansible**: 已安装 (Command exists).\n";
  } catch (e) {
    extraPrompt += "- **Ansible**: 未安装 (Command not found).\n";
  }

  const hostsFile = path.join(os.homedir(), ".witty-diagnosis-agent", "ansible", "hosts.ini");
  if (fs.existsSync(hostsFile)) {
    try {
      const hostsConfig = await fs.promises.readFile(hostsFile, "utf8");
      if (hostsConfig.trim()) {
        extraPrompt += `- **Ansible Inventory**: 配置文件存在 (\`${hostsFile}\`)，内容如下：\n\`\`\`ini\n${hostsConfig.trim()}\n\`\`\`\n`;
      } else {
        extraPrompt += `- **Ansible Inventory**: 配置文件存在 (\`${hostsFile}\`)，但内容为空。\n`;
      }
    } catch (e) {
      extraPrompt += `- **Ansible Inventory**: 配置文件存在 (\`${hostsFile}\`)，但读取失败。\n`;
    }
  } else {
    extraPrompt += `- **Ansible Inventory**: 配置文件不存在 (\`${hostsFile}\`)。\n`;
  }

  extraPrompt += "\n**注意：如果上述预检查信息显示 Ansible 已安装，或 inventory 配置文件已存在且内容符合你的要求，请你在 1.3 诊断可行性评估阶段（或后续任何环节中）直接使用上述信息，切勿再反复调用 bash 执行 `ansible --version` 或使用工具读取 `hosts.ini`。只有当确实缺少必要信息或环境不符合要求时，才进行补充操作或向用户追问。**\n";

  const currentTime = new Date().toISOString();
  extraPrompt += `\n# 当前系统时间\n当前时间为: ${currentTime}\n`;

  const wittyHomeDir = path.join(os.homedir(), ".witty-diagnosis-agent");
  extraPrompt += `\n# 用户工作目录\n当前 ~/.witty-diagnosis-agent/ 对应的绝对路径为: ${wittyHomeDir}\n请在生成计划、草稿以及后续需要写文件的步骤中，严格使用该绝对路径代替 ~\n`;

  // Currently forcing the modular prompt for all models to ensure compliance with Dayu/Fuxi requirements.
  return FUXI_SYSTEM_PROMPT + extraPrompt;
}
