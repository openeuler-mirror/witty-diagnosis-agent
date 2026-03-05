import * as p from "@clack/prompts"
import color from "picocolors"
import type { InstallArgs } from "./types"
import {
  addAuthPlugins,
  addPluginToOpenCodeConfig,
  addProviderConfig,
  detectCurrentConfig,
  getOpenCodeVersion,
  isOpenCodeInstalled,
  writeOmoConfig,
} from "./config-manager"
import { detectedToInitialValues, formatConfigSummary, SYMBOLS } from "./install-validators"
import { promptInstallConfig } from "./tui-install-prompts"

export async function runTuiInstaller(args: InstallArgs, version: string): Promise<number> {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    console.error("Error: Interactive installer requires a TTY. Use --non-interactive or set environment variables directly.")
    return 1
  }

  const detected = detectCurrentConfig()
  const isUpdate = detected.isInstalled

  p.intro(color.bgMagenta(color.white(isUpdate ? " oMoMoMoMo... Update " : " oMoMoMoMo... ")))

  if (isUpdate) {
    const initial = detectedToInitialValues(detected)
    p.log.info(`Existing configuration detected: Claude=${initial.claude}, Gemini=${initial.gemini}`)
  }

  const spinner = p.spinner()
  spinner.start("Checking OpenCode installation")

  const installed = await isOpenCodeInstalled()
  const openCodeVersion = await getOpenCodeVersion()
  if (!installed) {
    spinner.stop(`OpenCode binary not found ${color.yellow("[!]")}`)
    p.log.warn("OpenCode binary not found. Plugin will be configured, but you'll need to install OpenCode to use it.")
    p.note("Visit https://opencode.ai/docs for installation instructions", "Installation Guide")
  } else {
    spinner.stop(`OpenCode ${openCodeVersion ?? "installed"} ${color.green("[OK]")}`)
  }

  const config = await promptInstallConfig(detected)
  if (!config) return 1

  spinner.start("Adding oh-my-opencode to OpenCode config")
  const pluginResult = await addPluginToOpenCodeConfig(version)
  if (!pluginResult.success) {
    spinner.stop(`Failed to add plugin: ${pluginResult.error}`)
    p.outro(color.red("Installation failed."))
    return 1
  }
  spinner.stop(`Plugin added to ${color.cyan(pluginResult.configPath)}`)

  if (config.hasGemini) {
    spinner.start("Adding auth plugins (fetching latest versions)")
    const authResult = await addAuthPlugins(config)
    if (!authResult.success) {
      spinner.stop(`Failed to add auth plugins: ${authResult.error}`)
      p.outro(color.red("Installation failed."))
      return 1
    }
    spinner.stop(`Auth plugins added to ${color.cyan(authResult.configPath)}`)

    spinner.start("Adding provider configurations")
    const providerResult = addProviderConfig(config)
    if (!providerResult.success) {
      spinner.stop(`Failed to add provider config: ${providerResult.error}`)
      p.outro(color.red("Installation failed."))
      return 1
    }
    spinner.stop(`Provider config added to ${color.cyan(providerResult.configPath)}`)
  }

  spinner.start("Writing oh-my-opencode configuration")
  const omoResult = writeOmoConfig(config)
  if (!omoResult.success) {
    spinner.stop(`Failed to write config: ${omoResult.error}`)
    p.outro(color.red("Installation failed."))
    return 1
  }
  spinner.stop(`Config written to ${color.cyan(omoResult.configPath)}`)

  return 0
}
