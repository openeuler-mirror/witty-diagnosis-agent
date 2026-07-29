import { promises as fs } from "fs"
import { homedir } from "os"
import { isAbsolute, join } from "path"
import { parseJsoncSafe } from "../../shared/jsonc-parser"
import { deduplicateSkillsByName } from "./skill-deduplication"
import { loadSkillsFromDir } from "./skill-directory-loader"
import type { LoadedSkill } from "./types"

/**
 * Host OpenCode config shape (`opencode.json` / `opencode.jsonc`).
 * Only the parts we consume are modelled here.
 */
type HostSkillsConfig = {
  paths?: string[]
  urls?: string[]
}

function isHttpUrl(path: string): boolean {
  return path.startsWith("http://") || path.startsWith("https://")
}

export function extractHostSkillPaths(config: unknown): string[] {
  const skills = (config as { skills?: HostSkillsConfig } | undefined)?.skills
  if (!skills || Array.isArray(skills) || typeof skills !== "object") return []

  const paths = skills.paths
  if (!Array.isArray(paths)) return []

  return paths.filter(
    (path): path is string => typeof path === "string" && path.trim().length > 0,
  )
}

/**
 * Candidate host config files, in the order OpenCode itself layers them.
 *
 * Read from disk rather than via `client.config.get()`: skill discovery runs
 * while the plugin is still loading, and `config.get()` resolves config by
 * invoking this plugin's own `config` hook — awaiting it at load time
 * deadlocks startup.
 */
export function getHostConfigPaths(directory: string): string[] {
  const paths: string[] = []

  const envConfigDir = process.env.OPENCODE_CONFIG_DIR?.trim()
  if (envConfigDir) {
    paths.push(join(envConfigDir, "opencode.json"), join(envConfigDir, "opencode.jsonc"))
  }

  // System-wide install (e.g. /etc/opencode/opencode.json).
  if (process.platform !== "win32") {
    paths.push("/etc/opencode/opencode.json", "/etc/opencode/opencode.jsonc")
  }

  const xdgConfig = process.env.XDG_CONFIG_HOME || join(homedir(), ".config")
  paths.push(
    join(xdgConfig, "opencode", "opencode.json"),
    join(xdgConfig, "opencode", "opencode.jsonc"),
  )

  if (process.platform === "win32") {
    const appData = process.env.APPDATA
    if (appData) {
      paths.push(
        join(appData, "opencode", "opencode.json"),
        join(appData, "opencode", "opencode.jsonc"),
      )
    }
  }

  paths.push(
    join(directory, ".opencode", "opencode.json"),
    join(directory, ".opencode", "opencode.jsonc"),
  )

  return paths
}

async function readHostSkillPaths(directory: string): Promise<string[]> {
  const configPaths = getHostConfigPaths(directory)

  const perFile = await Promise.all(
    configPaths.map(async (configPath) => {
      const content = await fs.readFile(configPath, "utf-8").catch(() => null)
      if (content === null) return []

      const parsed = parseJsoncSafe<unknown>(content)
      if (!parsed.data) return []

      return extractHostSkillPaths(parsed.data)
    }),
  )

  return [...new Set(perFile.flat())]
}

/**
 * Discover skills from the host OpenCode config's `skills.paths`.
 *
 * The plugin's own `skills.sources` config is a different shape from the host's
 * `skills.paths`, so without this the plugin silently drops any skill folder the
 * user registered in `opencode.json`. Loaded at `opencode` scope so they rank
 * alongside `~/.config/opencode/skills` rather than overriding project skills.
 */
export async function discoverHostConfigSkills(options: {
  /** Already-resolved host config, when the caller has it (skips the disk scan). */
  hostConfig?: unknown
  directory: string
}): Promise<LoadedSkill[]> {
  const paths =
    options.hostConfig !== undefined
      ? extractHostSkillPaths(options.hostConfig)
      : await readHostSkillPaths(options.directory)

  if (paths.length === 0) return []

  const loadedByPath = await Promise.all(
    paths.map((path) => {
      // `urls` are fetched by the host itself; remote sources are out of scope here.
      if (isHttpUrl(path)) return Promise.resolve([])

      const absolutePath = isAbsolute(path) ? path : join(options.directory, path)
      // Default depth matches how `~/.config/opencode/skills` is scanned.
      return loadSkillsFromDir({ skillsDir: absolutePath, scope: "opencode" })
    }),
  )

  return deduplicateSkillsByName(loadedByPath.flat())
}
