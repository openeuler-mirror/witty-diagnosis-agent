import type { Hooks } from "@opencode-ai/plugin"

/**
 * 工具输出截断：诊断采集命令（dmesg、journalctl、perf 等）输出可能极大，
 * 超过阈值时保留头尾并提示 agent 用过滤命令复查，防止上下文爆炸。
 */
export function createOutputTruncator(args: {
  /** 超过该字符数则截断；0 表示禁用 */
  maxChars: number
}): NonNullable<Hooks["tool.execute.after"]> {
  const { maxChars } = args
  return async (_input, output) => {
    if (maxChars <= 0) return
    if (typeof output.output !== "string" || output.output.length <= maxChars) return

    const headChars = Math.floor(maxChars * 0.6)
    const tailChars = maxChars - headChars
    const omitted = output.output.length - maxChars
    output.output =
      output.output.slice(0, headChars) +
      `\n\n…（输出过长，中间省略 ${omitted} 字符；如需完整内容请用 grep/awk 过滤后重新执行）…\n\n` +
      output.output.slice(-tailChars)
  }
}
