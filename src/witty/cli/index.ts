#!/usr/bin/env node
import { Command, InvalidArgumentError } from "commander"

import { runInstall } from "./install"
import { runXiaooInstall } from "./install-xiaoo"
import { resolveInstallTargets, targetLabel, type InstallTarget } from "./target"
import { runDoctor } from "./doctor"

/**
 * witty-diagnosis-agent CLI 入口。
 * tsup 的 cli 入口指向本文件。
 */
const program = new Command()

program
  .name("witty-diagnosis-agent")
  .description("Witty 智能诊断 Agent - OpenCode 插件")

program
  .command("install")
  .description("安装到宿主框架（OpenCode / xiaoO）并初始化配置")
  .option("--dry-run", "只显示将要做的变更，不写文件")
  .option(
    "--target <target>",
    "安装目标 opencode|xiaoo|both（不传则按已安装框架决定，两者都在时交互选择）",
    (value: string) => {
      if (value !== "opencode" && value !== "xiaoo" && value !== "both") {
        throw new InvalidArgumentError("只能是 opencode / xiaoo / both")
      }
      return value
    },
  )
  .option(
    "--language <lang>",
    "输出语言 zh|en（不传则交互选择，非交互终端默认 zh）",
    (value: string) => {
      if (value !== "zh" && value !== "en") {
        throw new InvalidArgumentError("只能是 zh 或 en")
      }
      return value
    },
  )
  .action(
    async (options: {
      dryRun?: boolean
      language?: "zh" | "en"
      target?: InstallTarget | "both"
    }) => {
      const targets = await resolveInstallTargets(options.target)
      const report: Record<string, unknown> = { targets: targets.map(targetLabel) }

      for (const target of targets) {
        if (target === "opencode") {
          report.opencode = await runInstall({ dryRun: options.dryRun, language: options.language })
        } else {
          report.xiaoo = runXiaooInstall({ dryRun: options.dryRun })
        }
      }
      console.log(JSON.stringify(report, null, 2))
    },
  )

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
