import { Command } from "commander"
import { install } from "./install"
import { run } from "./run"
import { getLocalVersion } from "./get-local-version"
import { doctor } from "./doctor"
import { createMcpOAuthCommand } from "./mcp-oauth"
import type { InstallArgs } from "./types"
import type { RunOptions } from "./run"
import type { GetLocalVersionOptions } from "./get-local-version/types"
import type { DoctorOptions } from "./doctor"
import packageJson from "../../package.json" with { type: "json" }

const VERSION = packageJson.version

const program = new Command()

program
  .name("witty-diagnosis-agent")
  .description("The ultimate OpenCode plugin - multi-model orchestration, LSP tools, and more")
  .version(VERSION, "-v, --version", "Show version number")
  .enablePositionalOptions()

program
  .command("install")
  .description("Install and configure witty-diagnosis-agent")
  .addHelpText("after", `
Examples:
  $ bunx witty-diagnosis-agent install
`)
  .action(async () => {
    const args: InstallArgs = {
      tui: true,
      skipAuth: false,
    }
    const exitCode = await install(args)
    process.exit(exitCode)
  })

program
   .command("run <message>")
   .allowUnknownOption()
   .passThroughOptions()
  .description("Run opencode with todo/background task completion enforcement")
  .option("-a, --agent <name>", "Agent to use (default: from CLI/env/config, fallback: Sisyphus)")
  .option("-d, --directory <path>", "Working directory")
  .option("-p, --port <port>", "Server port (attaches if port already in use)", parseInt)
  .option("--attach <url>", "Attach to existing opencode server URL")
  .option("--on-complete <command>", "Shell command to run after completion")
  .option("--json", "Output structured JSON result to stdout")
  .option("--no-timestamp", "Disable timestamp prefix in run output")
  .option("--verbose", "Show full event stream (default: messages/tools only)")
  .option("--session-id <id>", "Resume existing session instead of creating new one")
  .addHelpText("after", `
Examples:
  $ bunx witty-diagnosis-agent run "Fix the bug in index.ts"
  $ bunx witty-diagnosis-agent run --agent Sisyphus "Implement feature X"
  $ bunx witty-diagnosis-agent run --port 4321 "Fix the bug"
  $ bunx witty-diagnosis-agent run --attach http://127.0.0.1:4321 "Fix the bug"
  $ bunx witty-diagnosis-agent run --json "Fix the bug" | jq .sessionId
  $ bunx witty-diagnosis-agent run --on-complete "notify-send Done" "Fix the bug"
  $ bunx witty-diagnosis-agent run --session-id ses_abc123 "Continue the work"

Agent resolution order:
  1) --agent flag
  2) OPENCODE_DEFAULT_AGENT
  3) witty-diagnosis-agent.json "default_run_agent"
  4) Sisyphus (fallback)

Available core agents:
  Sisyphus, Hephaestus, Prometheus, Atlas

Unlike 'opencode run', this command waits until:
  - All todos are completed or cancelled
  - All child sessions (background tasks) are idle
`)
  .action(async (message: string, options) => {
    if (options.port && options.attach) {
      console.error("Error: --port and --attach are mutually exclusive")
      process.exit(1)
    }
    const runOptions: RunOptions = {
      message,
      agent: options.agent,
      directory: options.directory,
      port: options.port,
      attach: options.attach,
      onComplete: options.onComplete,
      json: options.json ?? false,
      timestamp: options.timestamp ?? true,
      verbose: options.verbose ?? false,
      sessionId: options.sessionId,
    }
    const exitCode = await run(runOptions)
    process.exit(exitCode)
  })

program
  .command("get-local-version")
  .description("Show current installed version and check for updates")
  .option("-d, --directory <path>", "Working directory to check config from")
  .option("--json", "Output in JSON format for scripting")
  .addHelpText("after", `
Examples:
  $ bunx witty-diagnosis-agent get-local-version
  $ bunx witty-diagnosis-agent get-local-version --json
  $ bunx witty-diagnosis-agent get-local-version --directory /path/to/project

This command shows:
  - Current installed version
  - Latest available version on npm
  - Whether you're up to date
  - Special modes (local dev, pinned version)
`)
  .action(async (options) => {
    const versionOptions: GetLocalVersionOptions = {
      directory: options.directory,
      json: options.json ?? false,
    }
    const exitCode = await getLocalVersion(versionOptions)
    process.exit(exitCode)
  })

program
  .command("doctor")
  .description("Check witty-diagnosis-agent installation health and diagnose issues")
  .option("--status", "Show compact system dashboard")
  .option("--verbose", "Show detailed diagnostic information")
  .option("--json", "Output results in JSON format")
  .addHelpText("after", `
Examples:
  $ bunx witty-diagnosis-agent doctor            # Show problems only
  $ bunx witty-diagnosis-agent doctor --status   # Compact dashboard
  $ bunx witty-diagnosis-agent doctor --verbose  # Deep diagnostics
  $ bunx witty-diagnosis-agent doctor --json     # JSON output
`)
  .action(async (options) => {
    const mode = options.status ? "status" : options.verbose ? "verbose" : "default"
    const doctorOptions: DoctorOptions = {
      mode,
      json: options.json ?? false,
    }
    const exitCode = await doctor(doctorOptions)
    process.exit(exitCode)
  })

program
  .command("version")
  .description("Show version information")
  .action(() => {
    console.log(`witty-diagnosis-agent v${VERSION}`)
  })

program.addCommand(createMcpOAuthCommand())

export function runCli(): void {
  program.parse()
}
