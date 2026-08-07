import fs from "node:fs"
import os from "node:os"
import path from "node:path"

const LOG_FILE = path.join(os.tmpdir(), "witty-diagnosis-agent.log")
const MAX_BYTES = 10 * 1024 * 1024

/** 追加式文件日志。写失败静默（日志不应影响诊断主流程）。 */
export function log(message: string, data?: Record<string, unknown>): void {
  try {
    rotateIfNeeded()
    const line = `${new Date().toISOString()} ${message}${data ? " " + JSON.stringify(data) : ""}\n`
    fs.appendFileSync(LOG_FILE, line)
  } catch {
    // 日志失败不打断主流程
  }
}

function rotateIfNeeded(): void {
  try {
    const stat = fs.statSync(LOG_FILE)
    if (stat.size > MAX_BYTES) fs.renameSync(LOG_FILE, `${LOG_FILE}.1`)
  } catch {
    // 文件不存在等，无需轮转
  }
}
