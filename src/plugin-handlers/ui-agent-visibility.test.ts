import { describe, expect, it } from "bun:test"
import { applyUiAgentVisibility } from "./ui-agent-visibility"

describe("applyUiAgentVisibility", () => {
  it("keeps native OpenCode build agent visible (not hidden)", () => {
    const result = applyUiAgentVisibility({
      build: { mode: "primary", temperature: 0.1 },
      dayu: { mode: "all" },
    })
    expect(result.build).toEqual({ mode: "primary", temperature: 0.1 })
    expect(result.dayu).toMatchObject({ hidden: true, mode: "subagent" })
  })

  it("keeps xuanyuan and fuxi visible in the UI", () => {
    const result = applyUiAgentVisibility({
      xuanyuan: { mode: "all", color: "#2196F3" },
      fuxi: { mode: "all", color: "#FF5722" },
    })

    expect(result).toEqual({
      xuanyuan: { mode: "all", color: "#2196F3" },
      fuxi: { mode: "all", color: "#FF5722" },
    })
  })

  it("demotes all other agents to hidden subagents while preserving their config", () => {
    const result = applyUiAgentVisibility({
      dayu: { mode: "all", color: "#2196F3" },
      kuafu: { mode: "all", permission: { task: "allow" } },
      build: { mode: "primary", temperature: 0.1 },
      "custom-agent": { mode: "all", description: "custom" },
    })

    expect(result).toEqual({
      dayu: { mode: "subagent", color: "#2196F3", hidden: true },
      kuafu: {
        mode: "subagent",
        permission: { task: "allow" },
        hidden: true,
      },
      build: { mode: "primary", temperature: 0.1 },
      "custom-agent": {
        mode: "subagent",
        description: "custom",
        hidden: true,
      },
    })
  })

  it("supports already-remapped display names when applying the allowlist", () => {
    const result = applyUiAgentVisibility({
      "Xuanyuan (Controller)": { mode: "all" },
      "Fuxi (Diagnostic Planner)": { mode: "all" },
      "Baize (Root Cause Analysis)": { mode: "all" },
    })

    expect(result).toEqual({
      "Xuanyuan (Controller)": { mode: "all" },
      "Fuxi (Diagnostic Planner)": { mode: "all" },
      "Baize (Root Cause Analysis)": { mode: "subagent", hidden: true },
    })
  })
})
