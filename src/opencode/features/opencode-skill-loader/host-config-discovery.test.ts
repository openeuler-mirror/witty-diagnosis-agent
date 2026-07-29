import { afterEach, beforeEach, describe, expect, it } from "bun:test"
import { mkdirSync, rmSync, writeFileSync } from "fs"
import { join } from "path"
import { tmpdir } from "os"
import {
  discoverHostConfigSkills,
  extractHostSkillPaths,
  getHostConfigPaths,
} from "./host-config-discovery"

const TEST_DIR = join(tmpdir(), `host-config-discovery-test-${Date.now()}`)

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

describe("host config skill discovery", () => {
  beforeEach(() => {
    mkdirSync(TEST_DIR, { recursive: true })
  })

  afterEach(() => {
    rmSync(TEST_DIR, { recursive: true, force: true })
  })

  describe("extractHostSkillPaths", () => {
    it("reads paths from host skills config", () => {
      // given
      const config = { skills: { paths: ["/data/custom-skills", "/opt/more"] } }

      // when
      const paths = extractHostSkillPaths(config)

      // then
      expect(paths).toEqual(["/data/custom-skills", "/opt/more"])
    })

    it("returns empty for configs without skills.paths", () => {
      // then
      expect(extractHostSkillPaths(undefined)).toEqual([])
      expect(extractHostSkillPaths({})).toEqual([])
      expect(extractHostSkillPaths({ skills: {} })).toEqual([])
      expect(extractHostSkillPaths({ skills: { urls: ["https://x/"] } })).toEqual([])
    })

    it("ignores non-string and blank entries", () => {
      // given
      const config = { skills: { paths: ["/ok", "", "   ", 42, null] } }

      // when
      const paths = extractHostSkillPaths(config)

      // then
      expect(paths).toEqual(["/ok"])
    })
  })

  describe("getHostConfigPaths", () => {
    it("includes the system-wide /etc/opencode config on posix", () => {
      // when
      const paths = getHostConfigPaths(TEST_DIR)

      // then
      if (process.platform !== "win32") {
        expect(paths).toContain("/etc/opencode/opencode.json")
      }
    })

    it("includes the project-level .opencode config", () => {
      // when
      const paths = getHostConfigPaths(TEST_DIR)

      // then
      expect(paths).toContain(join(TEST_DIR, ".opencode", "opencode.json"))
    })

    it("honours OPENCODE_CONFIG_DIR", () => {
      // given
      const previous = process.env.OPENCODE_CONFIG_DIR
      process.env.OPENCODE_CONFIG_DIR = "/custom/cfg"

      try {
        // when
        const paths = getHostConfigPaths(TEST_DIR)

        // then
        expect(paths).toContain(join("/custom/cfg", "opencode.json"))
      } finally {
        if (previous === undefined) delete process.env.OPENCODE_CONFIG_DIR
        else process.env.OPENCODE_CONFIG_DIR = previous
      }
    })
  })

  it("discovers skills from a host config file on disk", async () => {
    // given — the reported repro, via the project-level host config
    const customDir = join(TEST_DIR, "custom-skills")
    writeSkill(join(customDir, "xxx"), "xxx", "Host configured skill")
    writeProjectHostConfig(TEST_DIR, { skills: { paths: [customDir] } })

    // when
    const skills = await discoverHostConfigSkills({ directory: TEST_DIR })

    // then
    const found = skills.find((skill) => skill.name === "xxx")
    expect(found).toBeDefined()
    expect(found?.scope).toBe("opencode")
    expect(found?.definition.description).toContain("Host configured skill")
  })

  it("parses jsonc host configs with comments and trailing commas", async () => {
    // given
    const customDir = join(TEST_DIR, "jsonc-skills")
    writeSkill(join(customDir, "jsonc-skill"), "jsonc-skill", "From jsonc")
    const dir = join(TEST_DIR, ".opencode")
    mkdirSync(dir, { recursive: true })
    writeFileSync(
      join(dir, "opencode.jsonc"),
      `{\n  // custom skills\n  "skills": { "paths": ["${customDir}"], },\n}\n`,
    )

    // when
    const skills = await discoverHostConfigSkills({ directory: TEST_DIR })

    // then
    expect(skills.map((skill) => skill.name)).toContain("jsonc-skill")
  })

  it("uses a pre-resolved host config without touching disk", async () => {
    // given — no config file written; only the in-memory config has the path
    const customDir = join(TEST_DIR, "preresolved")
    writeSkill(join(customDir, "pre-skill"), "pre-skill", "Pre-resolved")

    // when
    const skills = await discoverHostConfigSkills({
      hostConfig: { skills: { paths: [customDir] } },
      directory: TEST_DIR,
    })

    // then
    expect(skills.map((skill) => skill.name)).toContain("pre-skill")
  })

  it("resolves relative paths against the project directory", async () => {
    // given
    writeSkill(join(TEST_DIR, "rel-skills", "rel-skill"), "rel-skill", "Relative path skill")

    // when
    const skills = await discoverHostConfigSkills({
      hostConfig: { skills: { paths: ["./rel-skills"] } },
      directory: TEST_DIR,
    })

    // then
    expect(skills.map((skill) => skill.name)).toContain("rel-skill")
  })

  it("skips http urls and missing directories without throwing", async () => {
    // when
    const skills = await discoverHostConfigSkills({
      hostConfig: {
        skills: { paths: ["https://example.com/.well-known/skills/", join(TEST_DIR, "nope")] },
      },
      directory: TEST_DIR,
    })

    // then
    expect(skills).toEqual([])
  })

  it("returns empty when no host config declares skill paths", async () => {
    // when — TEST_DIR has no .opencode config
    const skills = await discoverHostConfigSkills({ directory: TEST_DIR })

    // then
    expect(skills).toEqual([])
  })

  it("ignores malformed host config files", async () => {
    // given
    const dir = join(TEST_DIR, ".opencode")
    mkdirSync(dir, { recursive: true })
    writeFileSync(join(dir, "opencode.json"), "{ this is not valid json")

    // when
    const skills = await discoverHostConfigSkills({ directory: TEST_DIR })

    // then
    expect(skills).toEqual([])
  })

  it("deduplicates skills with the same name across paths", async () => {
    // given
    const first = join(TEST_DIR, "a")
    const second = join(TEST_DIR, "b")
    writeSkill(join(first, "dup"), "dup", "First wins")
    writeSkill(join(second, "dup"), "dup", "Second loses")

    // when
    const skills = await discoverHostConfigSkills({
      hostConfig: { skills: { paths: [first, second] } },
      directory: TEST_DIR,
    })

    // then
    expect(skills.filter((skill) => skill.name === "dup")).toHaveLength(1)
  })
})
