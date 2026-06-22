import { promises as fsPromises } from "fs";
import { existsSync, readFileSync } from "fs"
import { join } from "path"
import { homedir } from "os"
import { getClaudeConfigDir } from "../../shared"
import type {
  ClaudeCodeMcpConfig,
  LoadedMcpServer,
  McpLoadResult,
  McpScope,
} from "./types"
import { transformMcpServer } from "./transformer"
import { log } from "../../shared/logger"

interface McpConfigPath {
  path: string
  scope: McpScope
}

function normalizeMcpServerName(name: string): string {
  const normalized = name.trim().toLowerCase()
  if (normalized === "lightrag-mcp") return "lightrag"
  return name
}

function getMcpConfigPaths(): McpConfigPath[] {
  const claudeConfigDir = getClaudeConfigDir()
  const cwd = process.cwd()

  return [
    { path: join(homedir(), ".claude.json"), scope: "user" },
    { path: join(claudeConfigDir, ".mcp.json"), scope: "user" },
    { path: join(homedir(), ".witty-diagnosis-agent", "mcp-config.json"), scope: "user" },
    { path: join(cwd, ".mcp.json"), scope: "project" },
    { path: join(cwd, ".claude", ".mcp.json"), scope: "local" },
  ]
}

async function loadMcpConfigFile(
  filePath: string
): Promise<ClaudeCodeMcpConfig | null> {
  if (!existsSync(filePath)) {
    return null
  }

  try {
    const content = await fsPromises.readFile(filePath, 'utf-8')
    return JSON.parse(content) as ClaudeCodeMcpConfig
  } catch (error) {
    log(`Failed to load MCP config from ${filePath}`, error)
    return null
  }
}

export function getSystemMcpServerNames(): Set<string> {
  const names = new Set<string>()
  const paths = getMcpConfigPaths()

  for (const { path } of paths) {
    if (!existsSync(path)) continue

    try {
      const content = readFileSync(path, "utf-8")
      const config = JSON.parse(content) as ClaudeCodeMcpConfig
      if (!config?.mcpServers) continue

      for (const [name, serverConfig] of Object.entries(config.mcpServers)) {
        const resolvedName = normalizeMcpServerName(name)
        if (serverConfig.disabled) continue
        names.add(resolvedName)
      }
    } catch {
      continue
    }
  }

  return names
}

export async function loadMcpConfigs(
  disabledMcps: string[] = []
): Promise<McpLoadResult> {
  const servers: McpLoadResult["servers"] = {}
  const loadedServers: LoadedMcpServer[] = []
  const paths = getMcpConfigPaths()
  const disabledSet = new Set(disabledMcps)

  for (const { path, scope } of paths) {
    const config = await loadMcpConfigFile(path)
    if (!config?.mcpServers) continue

    for (const [name, serverConfig] of Object.entries(config.mcpServers)) {
      const resolvedName = normalizeMcpServerName(name)
      if (disabledSet.has(resolvedName)) {
        log(`Skipping MCP "${resolvedName}" (in disabled_mcps)`, { path, originalName: name })
        continue
      }

      if (serverConfig.disabled) {
        log(`Disabling MCP server "${resolvedName}"`, { path, originalName: name })
        delete servers[resolvedName]
        const existingIndex = loadedServers.findIndex((s) => s.name === resolvedName)
        if (existingIndex !== -1) {
          loadedServers.splice(existingIndex, 1)
          log(`Removed previously loaded MCP server "${resolvedName}"`, { path, originalName: name })
        }
        continue
      }

      try {
        const transformed = transformMcpServer(resolvedName, serverConfig)
        servers[resolvedName] = transformed

        const existingIndex = loadedServers.findIndex((s) => s.name === resolvedName)
        if (existingIndex !== -1) {
          loadedServers.splice(existingIndex, 1)
        }

        loadedServers.push({ name: resolvedName, scope, config: transformed })

        log(`Loaded MCP server "${resolvedName}" from ${scope}`, { path, originalName: name })
      } catch (error) {
        log(`Failed to transform MCP server "${resolvedName}"`, error)
      }
    }
  }

  return { servers, loadedServers }
}

export function formatLoadedServersForToast(
  loadedServers: LoadedMcpServer[]
): string {
  if (loadedServers.length === 0) return ""

  return loadedServers
    .map((server) => `${server.name} (${server.scope})`)
    .join(", ")
}
