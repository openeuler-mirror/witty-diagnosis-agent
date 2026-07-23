import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

/** 本插件包的根目录（含 package.json 的目录）。 */
export function packageRootDir(): string {
  // dist/index.js 或 src/witty/shared/paths.ts 均在包根之下，向上定位到含 package.json 的目录
  let dir = path.dirname(fileURLToPath(import.meta.url))
  for (let i = 0; i < 6; i++) {
    if (fs.existsSync(path.join(dir, "package.json"))) return dir
    dir = path.dirname(dir)
  }
  return process.cwd()
}

/** 解析 skills 根目录：绝对路径原样返回，相对路径基于包根。 */
export function resolveSkillsDir(configured: string): string {
  return path.isAbsolute(configured) ? configured : path.join(packageRootDir(), configured)
}
