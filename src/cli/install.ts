import { existsSync, readFileSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import { homedir } from "node:os"
import * as p from "@clack/prompts"
import color from "picocolors"
import { addPluginToOpenCodeConfig, getOpenCodeConfigPath } from "./config-manager"
import type { InstallArgs } from "./cli-program"

export async function install(args: InstallArgs): Promise<void> {
  // TUI Header
  if (args.tui) {
    p.intro(color.bgCyan(color.black(" Witty Diagnosis Agent Installer ")))
  } else {
    console.log("Installing Witty Diagnosis Agent...")
  }

  // 1. Check OpenCode Environment
  const configPath = getOpenCodeConfigPath()
  const isInstalled = existsSync(configPath)
  
  if (args.tui) {
    const s = p.spinner()
    s.start("Checking OpenCode installation")
    await new Promise((resolve) => setTimeout(resolve, 500)) // Simulation
    if (isInstalled) {
      s.stop("OpenCode detected")
    } else {
      s.stop("OpenCode config not found")
      p.note("OpenCode configuration file not found. We will attempt to create it or you might need to install OpenCode first.", "Warning")
    }
  } else {
     if (isInstalled) {
         console.log("✓ OpenCode detected")
     } else {
         console.warn("! OpenCode config not found")
     }
  }

  // 2. Add Plugin to Config
  if (args.tui) {
      const s = p.spinner()
      s.start("Registering plugin")
      const result = addPluginToOpenCodeConfig("witty-diagnosis-agent@latest")
      if (result.success) {
          s.stop(`Plugin registered at ${result.configPath}`)
      } else {
          s.stop("Failed to register plugin")
          p.cancel(`Error: ${result.error}`)
          return
      }
  } else {
      const result = addPluginToOpenCodeConfig("witty-diagnosis-agent@latest")
      if (result.success) {
          console.log(`✓ Plugin registered at ${result.configPath}`)
      } else {
          console.error(`x Failed to register plugin: ${result.error}`)
          process.exit(1)
      }
  }

  // 3. Local Configuration (Witty Diagnosis specific)
  // Ask user for preferences if in TUI mode
  let autoAnalysis = true
  
  if (args.tui) {
      const analysis = await p.confirm({
          message: "Enable automatic root cause analysis on failure?",
          initialValue: true,
      })
      
      if (p.isCancel(analysis)) {
          p.cancel("Installation cancelled")
          return
      }
      autoAnalysis = analysis as boolean
  }

  // Write local config file
  const localConfigPath = join(process.cwd(), "witty-diagnosis.jsonc")
  const localConfigContent = {
      $schema: "./node_modules/witty-diagnosis-agent/schema.json",
      auto_analysis: autoAnalysis,
      log_level: "info",
      modules: {
          commander: { enabled: true },
          investigator: { concurrency: 5 },
          analyst: { model: "default" }
      }
  }
  
  if (args.tui) {
      const s = p.spinner()
      s.start("Generating local configuration")
      writeFileSync(localConfigPath, JSON.stringify(localConfigContent, null, 2))
      s.stop(`Configuration created at ${localConfigPath}`)
  } else {
      writeFileSync(localConfigPath, JSON.stringify(localConfigContent, null, 2))
      console.log(`✓ Configuration created at ${localConfigPath}`)
  }

  // 4. Post-install Summary
  if (args.tui) {
      p.outro(color.green("Installation Complete! Run 'opencode' to start."))
  } else {
      console.log("Installation Complete!")
  }
}
