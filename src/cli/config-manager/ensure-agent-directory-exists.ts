import { existsSync, mkdirSync } from "node:fs"
import { join } from "node:path"
import { homedir } from "node:os"

export function ensureAgentDirectoryExists(): string {
  const targetDir = join(homedir(), ".witty-diagnosis-agent")
  
  // 核心子目录列表
  const subDirs = [
    "ansible",
    "fuxi",
    "dayu/plans",
    "dayu/drafts",
    "dayu/report",
    "kuafu",
    "baize/reports"
  ]

  if (!existsSync(targetDir)) {
    mkdirSync(targetDir, { recursive: true })
  }

  // 遍历并创建所有必需的子目录
  for (const subDir of subDirs) {
    const fullPath = join(targetDir, subDir)
    if (!existsSync(fullPath)) {
      mkdirSync(fullPath, { recursive: true })
    }
  }

  return targetDir
}
