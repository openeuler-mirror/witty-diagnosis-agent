import { existsSync, mkdirSync } from "node:fs"
import { join } from "node:path"
import { homedir } from "node:os"

export function ensureAgentDirectoryExists(): string {
  const targetDir = join(homedir(), ".witty-diagnosis-agent")
  if (!existsSync(targetDir)) {
    mkdirSync(targetDir, { recursive: true })
  }
  return targetDir
}
