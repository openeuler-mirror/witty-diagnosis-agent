import type { Hooks } from "@opencode-ai/plugin"

import type { NotificationConfig } from "../config/types"
import { log } from "../shared/log"

/**
 * 会话通知：诊断会话空闲（完成）或出错时发系统通知。
 * 仅在 config.notification.enabled 时接线。实现按平台调用系统通知命令
 * （macOS osascript / Linux notify-send），失败静默。
 */
export function createSessionNotifier(
  config: Required<NotificationConfig>,
): NonNullable<Hooks["event"]> {
  return async ({ event }) => {
    if (!config.enabled) return

    if (event.type === "session.idle") {
      notify("诊断完成", "会话已空闲，诊断流程结束")
    } else if (event.type === "session.error") {
      notify("诊断出错", "会话出现错误，请回到终端查看")
    }
  }
}

function notify(title: string, body: string): void {
  // TODO(实现)：按平台调用 osascript / notify-send / powershell toast
  log("notifier: (stub) 系统通知", { title, body })
}
