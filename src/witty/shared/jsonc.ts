import fs from "node:fs"
import { parse as parseJsonc } from "jsonc-parser"

/**
 * 读取 JSONC 文件。文件不存在返回 undefined；解析出错返回 undefined（调用方决定回退）。
 */
export function readJsoncFile(filePath: string): unknown {
  let text: string
  try {
    text = fs.readFileSync(filePath, "utf8")
  } catch {
    return undefined
  }
  const errors: { error: number; offset: number; length: number }[] = []
  const value: unknown = parseJsonc(text, errors, { allowTrailingComma: true })
  return errors.length > 0 ? undefined : value
}
