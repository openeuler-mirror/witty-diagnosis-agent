import { describe, it, expect } from "bun:test"
import { applyToolConfig } from "./tool-config-handler"
import type { WittyDiagnosisAgentConfig } from "../config"

function createParams(overrides: {
  taskSystem?: boolean
  agents?: string[]
}) {
  const agentResult: Record<string, { permission?: Record<string, unknown> }> = {}
  for (const agent of overrides.agents ?? []) {
    agentResult[agent] = { permission: {} }
  }

  return {
    config: { tools: {}, permission: {} } as Record<string, unknown>,
    pluginConfig: {
      experimental: { task_system: overrides.taskSystem ?? false },
    } as WittyDiagnosisAgentConfig,
    agentResult: agentResult as Record<string, unknown>,
  }
}

describe("applyToolConfig", () => {
  describe("#given task_system is enabled", () => {
    describe("#when applying tool config", () => {
      it("#then should deny todowrite and todoread globally", () => {
        const params = createParams({ taskSystem: true })

        applyToolConfig(params)

        const tools = params.config.tools as Record<string, unknown>
        expect(tools.todowrite).toBe(false)
        expect(tools.todoread).toBe(false)
      })

      it.each([
        "atlas",
        "sisyphus",
        "hephaestus",
        "prometheus",
        "sisyphus-junior",
      ])("#then should deny todo tools for %s agent", (agentName) => {
        const params = createParams({
          taskSystem: true,
          agents: [agentName],
        })

        applyToolConfig(params)

        const agent = params.agentResult[agentName] as {
          permission: Record<string, unknown>
        }
        expect(agent.permission.todowrite).toBe("deny")
        expect(agent.permission.todoread).toBe("deny")
      })
    })
  })

  describe("#given task_system is disabled", () => {
    describe("#when applying tool config", () => {
      it.each([
        "atlas",
        "sisyphus",
        "hephaestus",
        "prometheus",
        "sisyphus-junior",
      ])("#then should NOT deny todo tools for %s agent", (agentName) => {
        const params = createParams({
          taskSystem: false,
          agents: [agentName],
        })

        applyToolConfig(params)

        const agent = params.agentResult[agentName] as {
          permission: Record<string, unknown>
        }
        expect(agent.permission.todowrite).toBeUndefined()
        expect(agent.permission.todoread).toBeUndefined()
      })
    })
  })

  describe("#given fuxi agent is configured", () => {
    it("#then should allow question outside cli run mode", () => {
      const previousCliRunMode = process.env.OPENCODE_CLI_RUN_MODE
      delete process.env.OPENCODE_CLI_RUN_MODE

      try {
        const params = createParams({
          taskSystem: false,
          agents: ["fuxi"],
        })

        applyToolConfig(params)

        const agent = params.agentResult.fuxi as {
          permission: Record<string, unknown>
        }
        expect(agent.permission.question).toBe("allow")
      } finally {
        if (previousCliRunMode === undefined) {
          delete process.env.OPENCODE_CLI_RUN_MODE
        } else {
          process.env.OPENCODE_CLI_RUN_MODE = previousCliRunMode
        }
      }
    })

    it("#then should deny question in cli run mode", () => {
      const previousCliRunMode = process.env.OPENCODE_CLI_RUN_MODE
      process.env.OPENCODE_CLI_RUN_MODE = "true"

      try {
        const params = createParams({
          taskSystem: false,
          agents: ["fuxi"],
        })

        applyToolConfig(params)

        const agent = params.agentResult.fuxi as {
          permission: Record<string, unknown>
        }
        expect(agent.permission.question).toBe("deny")
      } finally {
        if (previousCliRunMode === undefined) {
          delete process.env.OPENCODE_CLI_RUN_MODE
        } else {
          process.env.OPENCODE_CLI_RUN_MODE = previousCliRunMode
        }
      }
    })
  })
})
