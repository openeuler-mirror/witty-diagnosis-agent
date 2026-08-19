import { execFileSync } from "node:child_process"

import { select, isCancel } from "@clack/prompts"

/**
 * 安装目标框架的探测与选择。
 *
 * 本插件可装进两种宿主：OpenCode（软链技能，插件形态）与 xiaoO（拷贝技能，配置形态）。
 * install.sh 一直有这个二选一菜单，但 rpm 不附带 install.sh，导致 rpm 装完只能用
 * OpenCode——xiaoO 的资源明明打进了包却无从安装。本模块把该能力补进 CLI。
 */

export type InstallTarget = "opencode" | "xiaoo"

export const ALL_TARGETS: readonly InstallTarget[] = ["opencode", "xiaoo"]

const TARGET_LABEL: Record<InstallTarget, string> = {
  opencode: "OpenCode",
  xiaoo: "xiaoO",
}

/** 命令是否在 PATH 上。 */
function hasCommand(cmd: string): boolean {
  try {
    execFileSync("command", ["-v", cmd], { stdio: "ignore", shell: "/bin/sh" })
    return true
  } catch {
    return false
  }
}

/** 探测本机已安装的宿主框架。 */
export function detectAvailableTargets(): InstallTarget[] {
  return ALL_TARGETS.filter((t) => hasCommand(t === "opencode" ? "opencode" : "xiaoo"))
}

export function targetLabel(t: InstallTarget): string {
  return TARGET_LABEL[t]
}

/**
 * 决定本次安装的目标。
 *
 * - 显式指定：直接采用，不做探测（允许装到当前未安装的框架，便于先装配置后装框架）
 * - 未指定：按探测结果决定；两个都在且是 TTY 时弹菜单；非 TTY 回退 OpenCode
 */
export async function resolveInstallTargets(explicit?: InstallTarget | "both"): Promise<InstallTarget[]> {
  if (explicit === "both") return [...ALL_TARGETS]
  if (explicit) return [explicit]

  const available = detectAvailableTargets()
  if (available.length === 1) return available
  if (available.length === 0) return ["opencode"] // 都没装：按主路径给出 OpenCode 配置

  if (!process.stdin.isTTY) return ["opencode"]

  const result = await select({
    message: "检测到多个宿主框架，选择安装目标 / Multiple hosts detected, select install target",
    options: [
      { value: "opencode", label: "OpenCode" },
      { value: "xiaoo", label: "xiaoO" },
      { value: "both", label: "两者都装 / Both" },
    ],
    initialValue: "opencode",
  })
  if (isCancel(result)) return ["opencode"]
  return result === "both" ? [...ALL_TARGETS] : [result as InstallTarget]
}
