import { Command } from "commander"
import { install } from "./install"

export interface InstallArgs {
  tui: boolean
  skipAuth?: boolean
}

const program = new Command()

program
  .name("witty-diagnosis-agent")
  .description("Witty Diagnosis Agent - OpenCode Plugin")
  .version("1.0.0")

program
  .command("install")
  .description("Install witty-diagnosis-agent")
  .option("--no-tui", "Run in non-interactive mode (requires all options)")
  .option("--skip-auth", "Skip authentication setup hints")
  .action(async (options) => {
    const args: InstallArgs = {
      tui: options.tui !== false,
      skipAuth: options.skipAuth,
    }
    await install(args)
  })

export function runCli(): void {
  program.parse()
}
