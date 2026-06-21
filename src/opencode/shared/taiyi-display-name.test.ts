import { describe, expect, it } from "bun:test"
import { getAgentConfigKey, getAgentDisplayName } from "./agent-display-names"

describe("taiyi display name mapping", () => {
  it("returns the visible display name for taiyi", () => {
    expect(getAgentDisplayName("taiyi")).toBe("taiyi")
  })

  it("resolves the display name back to the config key", () => {
    expect(getAgentConfigKey("taiyi")).toBe("taiyi")
  })
})
