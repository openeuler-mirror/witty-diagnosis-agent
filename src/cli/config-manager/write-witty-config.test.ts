import { afterEach, beforeEach, describe, expect, it } from "bun:test"
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"

import { parseJsonc } from "../../shared/jsonc-parser"
import type { InstallConfig } from "../types"
import { resetConfigContext } from "./config-context"
<<<<<<<< HEAD:src/cli/config-manager/write-witty-config.test.ts
import { generateWittyConfig } from "./generate-witty-config"
import { writeWittyConfig } from "./write-witty-config"
========
import { generateWdaConfig } from "./generate-wda-config"
import { writeWdaConfig } from "./write-wda-config"
>>>>>>>> origin/master:src/cli/config-manager/write-wda-config.test.ts

const installConfig: InstallConfig = {
  hasClaude: true,
  isMax20: true,
  hasOpenAI: true,
  hasGemini: true,
  hasCopilot: false,
  hasOpencodeZen: false,
  hasZaiCodingPlan: false,
  hasKimiForCoding: false,
}

function getRecord(value: unknown): Record<string, unknown> {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>
  }

  return {}
}

<<<<<<<< HEAD:src/cli/config-manager/write-witty-config.test.ts
describe("writeWittyConfig", () => {
========
describe("writeWdaConfig", () => {
>>>>>>>> origin/master:src/cli/config-manager/write-wda-config.test.ts
  let testConfigDir = ""
  let testConfigPath = ""

  beforeEach(() => {
<<<<<<<< HEAD:src/cli/config-manager/write-witty-config.test.ts
    testConfigDir = join(tmpdir(), `witty-write-config-${Date.now()}-${Math.random().toString(36).slice(2)}`)
========
    testConfigDir = join(tmpdir(), `wda-write-config-${Date.now()}-${Math.random().toString(36).slice(2)}`)
>>>>>>>> origin/master:src/cli/config-manager/write-wda-config.test.ts
    testConfigPath = join(testConfigDir, "witty-diagnosis-agent.json")

    mkdirSync(testConfigDir, { recursive: true })
    process.env.OPENCODE_CONFIG_DIR = testConfigDir
    resetConfigContext()
  })

  afterEach(() => {
    rmSync(testConfigDir, { recursive: true, force: true })
    resetConfigContext()
    delete process.env.OPENCODE_CONFIG_DIR
  })

  it("preserves existing user values while adding new defaults", () => {
    // given
    const existingConfig = {
      agents: {
        sisyphus: {
          model: "custom/provider-model",
        },
      },
      disabled_hooks: ["comment-checker"],
    }
    writeFileSync(testConfigPath, JSON.stringify(existingConfig, null, 2) + "\n", "utf-8")

<<<<<<<< HEAD:src/cli/config-manager/write-witty-config.test.ts
    const generatedDefaults = generateWittyConfig(installConfig)

    // when
    const result = writeWittyConfig(installConfig)
========
    const generatedDefaults = generateWdaConfig(installConfig)

    // when
    const result = writeWdaConfig(installConfig)
>>>>>>>> origin/master:src/cli/config-manager/write-wda-config.test.ts

    // then
    expect(result.success).toBe(true)

    const savedConfig = parseJsonc<Record<string, unknown>>(readFileSync(testConfigPath, "utf-8"))
    const savedAgents = getRecord(savedConfig.agents)
    const savedSisyphus = getRecord(savedAgents.sisyphus)
    expect(savedSisyphus.model).toBe("custom/provider-model")
    expect(savedConfig.disabled_hooks).toEqual(["comment-checker"])

    for (const defaultKey of Object.keys(generatedDefaults)) {
      expect(savedConfig).toHaveProperty(defaultKey)
    }
  })
})
