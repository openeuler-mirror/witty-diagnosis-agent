#!/usr/bin/env node
import { Command } from "commander"

import { runInstall } from "./install"
import { runDoctor } from "./doctor"

/**
 * witty-diagnosis-agent CLI 入口。
 * 净室重写完成后，tsup.config.ts 的 cli 入口指向本文件（替代 src/opencode/cli/index.ts）。
 */
const program = new Command()

program
  .name("witty-diagnosis-agent")
  .description("Witty 智能诊断 Agent - OpenCode 插件")

program
  .command("install")
  .description("注册插件到 OpenCode 并初始化配置")
  .option("--dry-run", "只显示将要做的变更，不写文件")
  .option(
    "--language <lang>",
    "输出语言 zh|en（不传则交互选择，非交互终端默认 zh）",
    (value: string) => {
      if (value !== "zh" && value !== "en") {
        throw new Error(`--language 只能是 zh 或 en，收到: ${value}`)
      }
      return value
    },
  )
  .action(async (options: { dryRun?: boolean; language?: "zh" | "en" }) => {
    const report = await runInstall({ dryRun: options.dryRun, language: options.language })
    console.log(JSON.stringify(report, null, 2))
  })

program
  .command("doctor")
  .description("环境自检")
  .action(async () => {
    const results = await runDoctor()
    for (const r of results) {
      const mark = r.status === "pass" ? "✓" : r.status === "warn" ? "!" : "✗"
      console.log(`${mark} ${r.name}: ${r.detail}${r.remedy ? `（建议: ${r.remedy}）` : ""}`)
    }
    if (results.some((r) => r.status === "fail")) process.exitCode = 1
  })

program.parseAsync(process.argv)
