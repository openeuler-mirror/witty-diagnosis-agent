import type { Plugin } from "@opencode-ai/plugin"

const WittyDiagnosisAgentPlugin: Plugin = async (ctx) => {
  console.log("[WittyDiagnosisAgentPlugin] Plugin loading", {
    directory: ctx.directory,
  })

  return {} as any
}

export default WittyDiagnosisAgentPlugin
