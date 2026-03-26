import { existsSync } from "node:fs"
import { join } from "node:path"
import { pathToFileURL } from "node:url"

/**
 * 动态获取当前运行的 CLI 所在的包的入口(dist/index.js)的绝对路径 (URI)。
 * 这样 OpenCode 可以绕过按名解析，直接加载这个绝对路径的模块，避免全局安装时找不到包的问题。
 */
export function resolveLocalPluginPath(): string | null {
  try {
    // CLI is typically located at 'dist/cli.js' for a compiled environment
    const distIndex = join(import.meta.dirname, "index.js")
    if (existsSync(distIndex)) {
      return pathToFileURL(distIndex).href
    }

    // Fallback for development (e.g., executing tsx within src/cli/config-manager/)
    const devIndex = join(import.meta.dirname, "..", "..", "..", "dist", "index.js")
    if (existsSync(devIndex)) {
      return pathToFileURL(devIndex).href
    }

    return null
  } catch {
    return null
  }
}
