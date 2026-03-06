import { existsSync } from "node:fs"
import { dirname, join } from "node:path"
import { pathToFileURL } from "node:url"

/**
 * 当通过「仓库内编译的二进制」执行 install 时，返回指向本地 dist/index.js 的 file:// URL，
 * 这样 OpenCode 会加载本仓库的插件（含 wittywork、start-dayu 等），而不是通过包名解析到 CLI 入口。
 * 若不在仓库二进制环境或 dist 不存在，返回 null。
 */
export function resolveLocalPluginPath(): string | null {
  try {
    const execPath = process.execPath
    // 二进制路径形如: .../witty-diagnosis-agent/packages/darwin-x64/bin/witty-diagnosis-agent
    if (!execPath || !execPath.includes("packages")) return null

    const binDir = dirname(execPath)
    const platformDir = dirname(binDir)
    const packagesDir = dirname(platformDir)
    if (dirname(packagesDir) === packagesDir) return null // 避免根目录误判
    const repoRoot = dirname(packagesDir)

    const distIndex = join(repoRoot, "dist", "index.js")
    if (!existsSync(distIndex)) return null

    return pathToFileURL(distIndex).href
  } catch {
    return null
  }
}
