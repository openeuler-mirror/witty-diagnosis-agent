import { afterEach, beforeEach, describe, expect, it } from "bun:test"
import { mkdirSync, rmSync, writeFileSync } from "fs"
import { join } from "path"
import { tmpdir } from "os"
import type { WittyDiagnosisAgentConfig } from "../config"
import { createSkillContext } from "./skill-context"

const TEST_DIR = join(tmpdir(), `skill-context-host-skills-test-${Date.now()}`)

function writeSkill(path: string, name: string, description: string): void {
  mkdirSync(path, { recursive: true })
  writeFileSync(
    join(path, "SKILL.md"),
    `---\nname: ${name}\ndescription: ${description}\n---\nBody\n`,
  )
}

/** Write a host opencode.json into the project-level `.opencode` dir. */
function writeProjectHostConfig(directory: string, config: unknown): void {
  const dir = join(directory, ".opencode")
  mkdirSync(dir, { recursive: true })
  writeFileSync(join(dir, "opencode.json"), JSON.stringify(config))
}

const pluginConfig = { output_language: "zh" } as unknown as WittyDiagnosisAgentConfig

describe("createSkillContext host skills.paths inheritance", () => {
  beforeEach(() => {
    mkdirSync(TEST_DIR, { recursive: true })
  })

  afterEach(() => {
    rmSync(TEST_DIR, { recursive: true, force: true })
  })

  it("includes skills from the host opencode config skills.paths", async () => {
    // given — the reported repro: skills.paths set in the host opencode.json
    const customSkillsDir = join(TEST_DIR, "custom-skills")
    writeSkill(join(customSkillsDir, "xxx"), "xxx", "Custom host-configured skill")
    writeProjectHostConfig(TEST_DIR, { skills: { paths: [customSkillsDir] } })

    // when
    const context = await createSkillContext({
      directory: TEST_DIR,
      pluginConfig,
    })

    // then — visible in mergedSkills, which backs both `skill` and `skill_mcp`
    const merged = context.mergedSkills.find((skill) => skill.name === "xxx")
    expect(merged).toBeDefined()
    expect(merged?.definition.description).toContain("Custom host-configured skill")

    // and — advertised to agents via availableSkills
    expect(context.availableSkills.map((skill) => skill.name)).toContain("xxx")
  })

  it("does not require the opencode client to build a context", async () => {
    // when — no client is passed at all (plugin load time has no usable client)
    const context = await createSkillContext({ directory: TEST_DIR, pluginConfig })

    // then — builtin skills remain, no throw
    expect(context.mergedSkills.length).toBeGreaterThan(0)
  })

  it("lets project-scoped skills win over host config skills of the same name", async () => {
    // given
    const customSkillsDir = join(TEST_DIR, "custom-skills")
    writeSkill(join(customSkillsDir, "shared"), "shared", "From host config")
    writeSkill(join(TEST_DIR, ".opencode", "skills", "shared"), "shared", "From project")
    writeProjectHostConfig(TEST_DIR, { skills: { paths: [customSkillsDir] } })

    // when
    const context = await createSkillContext({
      directory: TEST_DIR,
      pluginConfig,
    })

    // then
    const shared = context.mergedSkills.find((skill) => skill.name === "shared")
    expect(shared?.definition.description).toContain("From project")
  })
})
