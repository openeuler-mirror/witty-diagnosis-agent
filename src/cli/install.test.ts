import { describe, expect, test, mock, beforeEach, afterEach, spyOn } from "bun:test"
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { join } from "node:path"
import { install } from "./install"
import * as configManager from "./config-manager"
import * as installValidators from "./install-validators"
import type { InstallArgs } from "./types"

// Mock console methods to capture output
const mockConsoleLog = mock(() => {})
const mockConsoleError = mock(() => {})

describe("install CLI - binary check behavior", () => {
  let tempDir: string
  let originalEnv: string | undefined
  let isOpenCodeInstalledSpy: ReturnType<typeof spyOn>
  let getOpenCodeVersionSpy: ReturnType<typeof spyOn>
  let checkAnsibleSpy: ReturnType<typeof spyOn>

  beforeEach(() => {
    // given temporary config directory
    tempDir = join(tmpdir(), `witty-test-${Date.now()}-${Math.random().toString(36).slice(2)}`)
    mkdirSync(tempDir, { recursive: true })

    originalEnv = process.env.OPENCODE_CONFIG_DIR
    process.env.OPENCODE_CONFIG_DIR = tempDir

    // Reset config context
    configManager.resetConfigContext()
    configManager.initConfigContext("opencode", null)

    // Capture console output
    console.log = mockConsoleLog
    mockConsoleLog.mockClear()

    // Default: Ansible is installed (so binary-check tests are not blocked)
    checkAnsibleSpy = spyOn(installValidators, "checkAnsibleInstalled").mockResolvedValue({
      installed: true,
      version: "ansible 2.18.0",
      path: "/usr/bin/ansible",
    })
  })

  afterEach(() => {
    if (originalEnv !== undefined) {
      process.env.OPENCODE_CONFIG_DIR = originalEnv
    } else {
      delete process.env.OPENCODE_CONFIG_DIR
    }

    if (existsSync(tempDir)) {
      rmSync(tempDir, { recursive: true, force: true })
    }

    isOpenCodeInstalledSpy?.mockRestore()
    getOpenCodeVersionSpy?.mockRestore()
    checkAnsibleSpy?.mockRestore()
  })

  test("non-TUI mode: should show warning but continue when OpenCode binary not found", async () => {
    // given OpenCode binary is NOT installed
    isOpenCodeInstalledSpy = spyOn(configManager, "isOpenCodeInstalled").mockResolvedValue(false)
    getOpenCodeVersionSpy = spyOn(configManager, "getOpenCodeVersion").mockResolvedValue(null)

    const args: InstallArgs = {
      tui: false,
      claude: "yes",
      openai: "no",
      gemini: "no",
      copilot: "no",
      opencodeZen: "no",
      zaiCodingPlan: "no",
    }

    // when running install
    const exitCode = await install(args)

    // then should return success (0), not failure (1)
    expect(exitCode).toBe(0)

    // then should have printed a warning (not error)
    const allCalls = mockConsoleLog.mock.calls.flat().join("\n")
    expect(allCalls).toContain("[!]") // warning symbol
    expect(allCalls).toContain("OpenCode")
  })

  test("non-TUI mode: should create opencode.json with plugin even when binary not found", async () => {
    // given OpenCode binary is NOT installed
    isOpenCodeInstalledSpy = spyOn(configManager, "isOpenCodeInstalled").mockResolvedValue(false)
    getOpenCodeVersionSpy = spyOn(configManager, "getOpenCodeVersion").mockResolvedValue(null)

    // given mock npm fetch
    globalThis.fetch = mock(() =>
      Promise.resolve({
        ok: true,
        json: () => Promise.resolve({ latest: "3.0.0" }),
      } as Response)
    ) as unknown as typeof fetch

    const args: InstallArgs = {
      tui: false,
      claude: "yes",
      openai: "no",
      gemini: "no",
      copilot: "no",
      opencodeZen: "no",
      zaiCodingPlan: "no",
    }

    // when running install
    const exitCode = await install(args)

    // then should create opencode.json
    const configPath = join(tempDir, "opencode.json")
    expect(existsSync(configPath)).toBe(true)

    // then opencode.json should have plugin entry
    const config = JSON.parse(readFileSync(configPath, "utf-8"))
    expect(config.plugin).toBeDefined()
    expect(config.plugin.some((p: string) => p.includes("witty-diagnosis-agent"))).toBe(true)

    // then exit code should be 0 (success)
    expect(exitCode).toBe(0)
  })

  test("non-TUI mode: should still succeed and complete all steps when binary exists", async () => {
    // given OpenCode binary IS installed
    isOpenCodeInstalledSpy = spyOn(configManager, "isOpenCodeInstalled").mockResolvedValue(true)
    getOpenCodeVersionSpy = spyOn(configManager, "getOpenCodeVersion").mockResolvedValue("1.0.200")

    // given mock npm fetch
    globalThis.fetch = mock(() =>
      Promise.resolve({
        ok: true,
        json: () => Promise.resolve({ latest: "3.0.0" }),
      } as Response)
    ) as unknown as typeof fetch

    const args: InstallArgs = {
      tui: false,
      claude: "yes",
      openai: "no",
      gemini: "no",
      copilot: "no",
      opencodeZen: "no",
      zaiCodingPlan: "no",
    }

    // when running install
    const exitCode = await install(args)

    // then should return success
    expect(exitCode).toBe(0)

    // then should have printed success (OK symbol)
    const allCalls = mockConsoleLog.mock.calls.flat().join("\n")
    expect(allCalls).toContain("[OK]")
    expect(allCalls).toContain("OpenCode 1.0.200")
  })
})

describe("install CLI - ansible check behavior", () => {
  let tempDir: string
  let originalEnv: string | undefined
  let checkAnsibleSpy: ReturnType<typeof spyOn>
  let isOpenCodeInstalledSpy: ReturnType<typeof spyOn>
  let getOpenCodeVersionSpy: ReturnType<typeof spyOn>

  const baseArgs: InstallArgs = {
    tui: false,
    claude: "yes",
    openai: "no",
    gemini: "no",
    copilot: "no",
    opencodeZen: "no",
    zaiCodingPlan: "no",
  }

  beforeEach(() => {
    tempDir = join(tmpdir(), `witty-test-ansible-${Date.now()}-${Math.random().toString(36).slice(2)}`)
    mkdirSync(tempDir, { recursive: true })
    originalEnv = process.env.OPENCODE_CONFIG_DIR
    process.env.OPENCODE_CONFIG_DIR = tempDir
    configManager.resetConfigContext()
    configManager.initConfigContext("opencode", null)
    console.log = mockConsoleLog
    mockConsoleLog.mockClear()
    // Default: OpenCode installed
    isOpenCodeInstalledSpy = spyOn(configManager, "isOpenCodeInstalled").mockResolvedValue(true)
    getOpenCodeVersionSpy = spyOn(configManager, "getOpenCodeVersion").mockResolvedValue("1.0.0")
  })

  afterEach(() => {
    if (originalEnv !== undefined) {
      process.env.OPENCODE_CONFIG_DIR = originalEnv
    } else {
      delete process.env.OPENCODE_CONFIG_DIR
    }
    if (existsSync(tempDir)) {
      rmSync(tempDir, { recursive: true, force: true })
    }
    checkAnsibleSpy?.mockRestore()
    isOpenCodeInstalledSpy?.mockRestore()
    getOpenCodeVersionSpy?.mockRestore()
  })

  test("non-TUI mode: should abort with exit code 1 when ansible is not installed", async () => {
    // given Ansible is NOT installed
    checkAnsibleSpy = spyOn(installValidators, "checkAnsibleInstalled").mockResolvedValue({
      installed: false,
      version: null,
      path: null,
    })

    // when running install
    const exitCode = await install(baseArgs)

    // then should return failure (1)
    expect(exitCode).toBe(1)

    // then should have printed an error mentioning Ansible
    const allOutput = mockConsoleLog.mock.calls.flat().join("\n")
    expect(allOutput).toContain("Ansible")
    expect(allOutput).toContain("[X]")
  })

  test("non-TUI mode: should continue installation when ansible is installed", async () => {
    // given Ansible IS installed
    checkAnsibleSpy = spyOn(installValidators, "checkAnsibleInstalled").mockResolvedValue({
      installed: true,
      version: "ansible 2.18.0",
      path: "/usr/bin/ansible",
    })

    // when running install
    const exitCode = await install(baseArgs)

    // then should return success (0)
    expect(exitCode).toBe(0)
  })

  test("non-TUI mode: should display ansible version when detected", async () => {
    // given Ansible IS installed with a specific version
    checkAnsibleSpy = spyOn(installValidators, "checkAnsibleInstalled").mockResolvedValue({
      installed: true,
      version: "ansible [core 2.18.1]",
      path: "/usr/local/bin/ansible",
    })

    // when running install
    await install(baseArgs)

    // then should display the ansible version in output
    const allOutput = mockConsoleLog.mock.calls.flat().join("\n")
    expect(allOutput).toContain("ansible [core 2.18.1]")
  })
})
