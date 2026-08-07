import path from "node:path"

import type { Hooks, PluginInput } from "@opencode-ai/plugin"

import { loadWittyConfig } from "./config/load"
import { AGENT_DEFINITIONS } from "./agents/definitions"
import { applyAgentsToConfig, isWittyOwnedAgent } from "./agents/registry"
import { discoverSkills, exposeSkillsToOpenCode } from "./skills/discovery"
import {
  createMdOnlyGuard,
  createCompactionPreserver,
  createOutputTruncator,
  createSessionNotifier,
  type DiagnosisContextSnapshot,
} from "./guards"
import { createReportVisualizationTool, createLightragTool } from "./tools"
import { languageLockDirective } from "./shared/language-lock"
import { resolveSkillsDir } from "./shared/paths"
import { log } from "./shared/log"

/**
 * 装配器：把各模块组合成 OpenCode Hooks。
 *
 * 子代理委派由 OpenCode 原生 task 工具负责（本插件不自建委派层）。插件只做：
 * agent 注册、技能暴露、诊断工具（report/lightrag）、若干守护钩子。
 * 会话内状态只有两张小表（agent 映射、诊断快照），私有于本闭包，
 * 不做跨会话/跨进程共享，也不向会话注入内部消息。
 */
export async function createWittyHooks(input: PluginInput): Promise<Hooks> {
  const pluginConfig = loadWittyConfig(input.directory)
  log("plugin: 配置加载完成", { directory: input.directory })

  // 技能暴露（幂等）
  const skillsDir = resolveSkillsDir(pluginConfig.skills_dir)
  const skills = discoverSkills(skillsDir)
  const exposeResult = exposeSkillsToOpenCode(skills, input.directory)
  log("plugin: 技能暴露完成", {
    discovered: skills.length,
    exposed: exposeResult.exposed.length,
    skipped: exposeResult.skipped.length,
  })

  // 会话内状态
  const sessionAgents = new Map<string, string>()
  const diagnosisSnapshots = new Map<string, DiagnosisContextSnapshot>()

  // 守护钩子（agent 名为裸名，直接匹配）
  const mdOnlyGuard = pluginConfig.guards.md_only
    ? createMdOnlyGuard({
        definitions: AGENT_DEFINITIONS,
        resolveAgent: (sessionID) => sessionAgents.get(sessionID),
      })
    : undefined
  const compactionPreserver = pluginConfig.guards.compaction_preserve
    ? createCompactionPreserver({ snapshotFor: (id) => diagnosisSnapshots.get(id) })
    : undefined
  const outputTruncator = createOutputTruncator({
    maxChars: pluginConfig.guards.output_truncate_chars,
  })
  const sessionNotifier = pluginConfig.notification.enabled
    ? createSessionNotifier(pluginConfig.notification)
    : undefined

  const reportDir = path.join(input.directory, pluginConfig.report.output_dir)

  return {
    config: async (config) => {
      // 诊断流水线需要 2 层子代理嵌套（xuanyuan→fuxi/dayu→general/kuafu）。
      // OpenCode 顶层 subagent_depth 默认 1，会拦掉第 2 层委派；此处兜底放宽到 ≥3。
      // 仅在用户未显式设置或设置得比需要的小时提升，不覆盖用户更大的值。
      // 说明：subagent_depth 是全局单值配置，无法按 agent 隔离，这是 OpenCode 的
      // 架构约束——放宽它只影响"嵌套层数上限"，不改变任何其他插件 agent 的能力。
      ensureSubagentDepth(config, 3)

      // 权限不做全局兜底（那会影响其他插件的 agent）。诊断 agent 需要的
      // bash/external_directory/question 等放行，全部写在各自的 agent.permission 里，
      // 只作用于本插件的 7 个 agent。

      applyAgentsToConfig({
        target: config as { agent?: Record<string, never> },
        definitions: AGENT_DEFINITIONS,
        pluginConfig,
        promptContext: { projectDir: input.directory, reportDir },
      })
    },

    tool: {
      ...createReportVisualizationTool(input),
      ...createLightragTool(),
    },

    "chat.message": async (chatInput) => {
      if (chatInput.agent) sessionAgents.set(chatInput.sessionID, chatInput.agent)
    },

    "tool.execute.before": mdOnlyGuard,

    "tool.execute.after": async (toolInput, toolOutput) => {
      await outputTruncator(toolInput, toolOutput)
      trackDiagnosisArtifacts(diagnosisSnapshots, toolInput, reportDir)
    },

    // 语言锁定第二道闸：往系统消息追加一条锁定指令，比提示词更靠后、更难被忽略，
    // 覆盖“用户用另一种语言提问 / skill 是另一种语言”导致模型漂移的情况。
    //
    // 范围铁律：**只对本插件自己的 7 个 agent 生效**。这条指令自称“最高优先级·不可
    // 覆盖”，落到其他插件的 agent 上会直接跟人家自己的指令对打，所以必须限定范围。
    // 本钩子的入参没有 agent 字段，只有 sessionID，故复用 chat.message 维护的
    // sessionID→agent 映射来判定归属（与 md-only 守护同一套机制）。
    // sessionID 缺失时无法归因，按“不是本插件的”处理，不注入。
    //
    // 已知取舍：原生 task 委派出去的子代理（如内置 general）跑在自己的子会话里，
    // agent 名不在本插件名单内，因此拿不到这道闸，仅靠各 agent 提示词里置顶的同一
    // 指令兜底（prompt-loader）。覆盖子会话需按 parentID 追溯父会话，留待后续优化。
    "experimental.chat.system.transform": async (transformInput, transformOutput) => {
      const sessionID = transformInput.sessionID
      if (sessionID === undefined) return
      if (!isWittyOwnedAgent(sessionAgents.get(sessionID))) return
      transformOutput.system.push(languageLockDirective(pluginConfig.output_language))
    },

    "experimental.session.compacting": compactionPreserver,

    event: sessionNotifier,
  }
}

/**
 * 兜底放宽 OpenCode 顶层 subagent_depth（子代理嵌套深度上限）。
 * 诊断流水线是 xuanyuan→fuxi/dayu→general/kuafu 两层，默认值 1 会拦掉第二层。
 */
function ensureSubagentDepth(config: unknown, minDepth: number): void {
  if (typeof config !== "object" || config === null) return
  const record = config as Record<string, unknown>
  const current = record["subagent_depth"]
  if (typeof current !== "number" || current < minDepth) {
    record["subagent_depth"] = minDepth
    log("plugin: 已放宽 subagent_depth", { from: current ?? "(默认1)", to: minDepth })
  }
}

/** 从写文件类工具调用里识别诊断产物（故障描述/计划/报告），更新会话快照。 */
function trackDiagnosisArtifacts(
  snapshots: Map<string, DiagnosisContextSnapshot>,
  toolInput: { tool: string; sessionID: string; args: unknown },
  reportDir: string,
): void {
  // TODO(实现)：按文件路径约定（澄清文档/计划文档/reportDir 下产物）更新快照
  void snapshots
  void toolInput
  void reportDir
}
