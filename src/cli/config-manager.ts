import { existsSync, readFileSync, writeFileSync, mkdirSync } from "node:fs"
import { join, dirname } from "node:path"
import { homedir } from "node:os"

export interface ConfigMergeResult {
  success: boolean
  configPath?: string
  error?: string
}

export function getConfigDir(): string {
  // Support XDG_CONFIG_HOME
  const xdgConfigHome = process.env.XDG_CONFIG_HOME
  if (xdgConfigHome) {
    return join(xdgConfigHome, "opencode")
  }
  return join(homedir(), ".config", "opencode")
}

export function getOpenCodeConfigPath(): string {
  const configDir = getConfigDir()
  const jsonPath = join(configDir, "config.json")
  const jsoncPath = join(configDir, "config.jsonc")
  
  if (existsSync(jsoncPath)) return jsoncPath
  // If json doesn't exist, we'll default to it anyway so we can create it
  return jsonPath
}

export function addPluginToOpenCodeConfig(pluginName: string): ConfigMergeResult {
  const configPath = getOpenCodeConfigPath()
  
  if (!existsSync(configPath)) {
    // Attempt to create it
    try {
        const configDir = dirname(configPath);
        if (!existsSync(configDir)) {
            mkdirSync(configDir, { recursive: true });
        }
        writeFileSync(configPath, JSON.stringify({ plugins: [] }, null, 2));
    } catch (e) {
        return {
          success: false,
          configPath,
          error: `OpenCode configuration file not found and could not be created: ${e instanceof Error ? e.message : String(e)}`
        }
    }
  }

  try {
    const content = readFileSync(configPath, "utf-8")
    let config: any
    
    try {
        config = JSON.parse(content)
    } catch (e) {
        return {
            success: false,
            configPath,
            error: "Failed to parse configuration file. It might contain comments."
        }
    }

    if (!config.plugins) {
      config.plugins = []
    }

    // Check if plugin already exists (ignoring version for duplicate check)
    const existingIndex = config.plugins.findIndex((p: string) => {
      // Handle cases where p is not a string (though it should be)
      if (typeof p !== 'string') return false;
      return p === pluginName || p.startsWith(`${pluginName}@`) || pluginName.startsWith(`${p}@`);
    })

    if (existingIndex !== -1) {
      // Update version if needed, or just skip
      config.plugins[existingIndex] = pluginName
    } else {
      config.plugins.push(pluginName)
    }

    writeFileSync(configPath, JSON.stringify(config, null, 2))
    return { success: true, configPath }
    
  } catch (error) {
    return {
      success: false,
      configPath,
      error: error instanceof Error ? error.message : String(error)
    }
  }
}
