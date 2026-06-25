import * as p from "@clack/prompts"
import color from "picocolors"
import type { InstallArgs } from "./types"
import {
  addAuthPlugins,
  addPluginToOpenCodeConfig,
  addProviderConfig,
  detectCurrentConfig,
  ensureConfigContextInitialized,
  getOpenCodeVersion,
  isOpenCodeInstalled,
  writeWittyConfig,
} from "./config-manager"
import { detectedToInitialValues, formatConfigSummary, SYMBOLS, checkAnsibleInstalled } from "./install-validators"
import { promptInstallConfig } from "./tui-install-prompts"

import { installSkills } from "./install-skills"

export async function runTuiInstaller(args: InstallArgs, version: string): Promise<number> {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    console.error("Error: Interactive installer requires a TTY. Use --non-interactive or set environment variables directly.")
    return 1
  }

  const spinner = p.spinner()
  spinner.start("Checking Ansible installation")
  const ansibleCheck = await checkAnsibleInstalled()
  if (!ansibleCheck.installed) {
    spinner.stop(`Ansible not found ${color.red("[X]")}`)
    p.log.error("Ansible command not found. Please install Ansible before running this installer.")
    p.note("Installation guide: https://docs.ansible.com/ansible/latest/installation_guide/", "Install Ansible")
    p.outro(color.red("Installation aborted: missing prerequisite."))
    return 1
  }
  spinner.stop(`Ansible ${ansibleCheck.version ?? "installed"} ${color.green("[OK]")}`)

  // Detect OpenCode and initialize the config context before anything reads
  // config paths, so detectCurrentConfig() resolves against the real binary
  // instead of falling back to defaults.
  await ensureConfigContextInitialized()

  const detected = detectCurrentConfig()
  const isUpdate = detected.isInstalled

  p.intro(color.bgMagenta(color.white(isUpdate ? " wittyDiagnosisAgentMo... Update " : " wittyDiagnosisAgentMo... ")))

  if (isUpdate) {
    const initial = detectedToInitialValues(detected)
    p.log.info(`Existing configuration detected: Claude=${initial.claude}, Gemini=${initial.gemini}`)
  }

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

  spinner.start("Adding witty-diagnosis-agent to OpenCode config")
  const pluginResult = await addPluginToOpenCodeConfig(version)
  if (!pluginResult.success) {
    spinner.stop(`Failed to add plugin: ${pluginResult.error}`)
    p.outro(color.red("Installation failed."))
    return 1
  }
  spinner.stop(`Plugin added to ${color.cyan(pluginResult.configPath)}`)

  spinner.start("Bundling witty-diagnosis-agent skills")
  const skillsResult = await installSkills()
  if (!skillsResult.success) {
    spinner.stop(`Skills update skipped: ${skillsResult.error} ${color.yellow("[!]")}`)
  } else {
    spinner.stop(`Skills updated to ${color.cyan(skillsResult.targetPath ?? "")} ${color.green("[OK]")}`)
  }

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

  spinner.start("Writing witty-diagnosis-agent configuration")
  const wittyResult = writeWittyConfig(config)
  if (!wittyResult.success) {
    spinner.stop(`Failed to write config: ${wittyResult.error}`)
    p.outro(color.red("Installation failed."))
    return 1
  }
  spinner.stop(`Config written to ${color.cyan(wittyResult.configPath)}`)

  return 0
}
