/**
 * 故障运维诊断 · 真实 opencode 驱动（对应设计 02 §D-001 / §D-002）。
 *
 * 每个任务：重定向 HOME/XDG_* 到每任务专属目录实现进程级隔离（D-001/BC-011）→ createOpencode
 * 拉起 opencode server → session.create → 订阅 event.subscribe → session.promptAsync
 * ({ agent:"xuanyuan", tools:{question:false} }) 注入「全部必填输入」的首条 prompt（D-002 前置注入，
 * 复刻 cli/run/runner.ts:95-105）→ 经 ./event-synthesizer 把 opencode 事件合成任务域事件流。
 *
 * 完成判定（双信号，02 §D-002）：
 *  ① 解析 Xuanyuan 最终叙述中的报告路径关键词（RCA报告路径：/ 报告已写入：）；
 *  ② 校验 baize/reports/ 下确有新生成的 .html。每任务 HOME 全新、该目录初始为空，取最新 .html 即本任务产物。
 *
 * 本文件依赖 @opencode-ai/sdk（仅真实路径），**不被 web/server 编译路径静态 import**
 * （web/server 经 ./index.ts 的运行时动态 import 加载本文件，typecheck 由 src/opencode 根工程覆盖）。
 *
 * ⚠ 隔离说明：createOpencode 不支持 per-call env，HOME/XDG 重定向经 process.env 完成；用模块级互斥
 * 串行化「改 env → 起 server」窗口，避免并发任务相互污染。若需更强隔离，应改为每任务独立 node 进程
 * spawn（与 D-001 原意一致），此处为首个可运行实现。
 */

import { createOpencode } from "@opencode-ai/sdk";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { withWorkingOpencodePath } from "../../../cli/run/opencode-binary-resolver.js";
import {
  initTaskSynthState,
  reduceTaskEvent,
  flushTaskSynth,
  type TaskSynthState,
} from "./event-synthesizer.js";
import type { OpencodeEventPayload, TaskDriver, TaskDriverEvent, TaskDriverInput } from "./types.js";

export interface OpencodeDriverConfig {
  /** 绑定到 xuanyuan 的模型（如 "anthropic/claude-opus-4-8"）；缺省走平台默认/已配置凭据。 */
  model?: string;
  /** 输出语言。 */
  outputLanguage?: "zh" | "en";
  /** server 启动超时（ms）。 */
  serverTimeoutMs?: number;
  /** opencode 二进制路径；留空=按 PATH/which 自动解析。 */
  opencodeBin?: string;
}

/** 控制器 agent 名回退值（实际名经 client.app.agents 动态解析；不同构建大小写可能不同）。 */
const AGENT_NAME_FALLBACK = "Xuanyuan";

/** 从运行中 server 的 agent 列表解析控制器 agent 的精确名（大小写/格式以注册为准）。 */
async function resolveAgentName(
  client: { app: { agents: (o: { query: { directory: string } }) => Promise<unknown> } },
  directory: string,
): Promise<string> {
  try {
    const res = await client.app.agents({ query: { directory } });
    const list = (res as { data?: Array<{ name?: string }> }).data ?? [];
    const match = list.find((a) => typeof a.name === "string" && a.name.toLowerCase().includes("xuanyuan"));
    if (match?.name) return match.name;
  } catch {
    /* ignore；回退到常量 */
  }
  return AGENT_NAME_FALLBACK;
}

/** 串行化「改 env → createOpencode」窗口的简单互斥。 */
let envLock: Promise<void> = Promise.resolve();
function withEnvLock<T>(fn: () => Promise<T>): Promise<T> {
  const run = envLock.then(fn, fn);
  envLock = run.then(
    () => {},
    () => {},
  );
  return run;
}

/** 组装注入 Xuanyuan 的首条 prompt：前置全部必填输入（D-002）。 */
function buildFirstPrompt(input: TaskDriverInput): string {
  const lines: string[] = [];
  lines.push("请以全链路智能运维诊断（autopilot 端到端模式）处理以下故障，自动串联 Fuxi→Dayu→Kuafu→Baize 并生成可视化 RCA 报告。");
  lines.push("");
  lines.push(`【故障现象】${input.title}`);
  lines.push(`【故障时间】${input.faultTime}`);
  lines.push(`【运维类型】${input.mode === "online" ? "在线诊断（连接目标主机自动采集）" : "离线分析（基于已提供日志）"}`);
  if (input.mode === "online" && input.online) {
    const o = input.online;
    lines.push(`【目标主机】IP=${o.hostIp} 端口=${o.sshPort} 账号=${o.sshUser} 密码=${o.sshPassword}`);
    lines.push("（请使用上述 SSH 凭据连接目标主机采集数据；凭据仅用于本次诊断。）");
  }
  if (input.mode === "offline" && input.offline) {
    lines.push(`【离线日志路径（绝对路径，请就地读取，勿向外请求）】`);
    for (const p of input.offline.logPaths) lines.push(`- ${p}`);
  }
  return lines.join("\n");
}

/** 在 baize/reports 下取最新的 .html（双信号②）。 */
function findLatestReportHtml(taskHome: string): string | null {
  const dir = path.join(taskHome, ".witty-diagnosis-agent", "baize", "reports");
  let entries: string[];
  try {
    entries = fs.readdirSync(dir).filter((f) => f.toLowerCase().endsWith(".html"));
  } catch {
    return null;
  }
  let best: { file: string; mtime: number } | null = null;
  for (const f of entries) {
    try {
      const st = fs.statSync(path.join(dir, f));
      if (!best || st.mtimeMs > best.mtime) best = { file: path.join(dir, f), mtime: st.mtimeMs };
    } catch {
      /* ignore */
    }
  }
  return best?.file ?? null;
}

/** 解析报告 HTML 路径（优先 state.reportPath 指向的 .html；否则取目录最新 .html）。 */
function resolveReportPath(taskHome: string, state: TaskSynthState): string | null {
  if (state.reportPath && state.reportPath.toLowerCase().endsWith(".html") && fs.existsSync(state.reportPath)) {
    return state.reportPath;
  }
  return findLatestReportHtml(taskHome);
}

/** 读取报告 HTML 内容。 */
function readReportHtml(taskHome: string, state: TaskSynthState): string | null {
  const candidate = resolveReportPath(taskHome, state);
  if (!candidate) return null;
  try {
    return fs.readFileSync(candidate, "utf8");
  } catch {
    return null;
  }
}

export function createOpencodeDriver(cfg: OpencodeDriverConfig = {}): TaskDriver {
  return {
    async *run(input: TaskDriverInput): AsyncGenerator<TaskDriverEvent> {
      const { signal, taskHome } = input;

      // 隔离策略：仅重定向 HOME（使 agent 的 ~/.witty-diagnosis-agent/{dayu,baize} 每任务独立，
      // 便于按任务采集报告），同时 **保留** XDG_DATA_HOME/XDG_CONFIG_HOME 指向真实用户目录——
      // 否则 opencode 的鉴权凭据（XDG_DATA_HOME/opencode/auth.json）与配置会丢失、LLM 调用失败。
      // 会话存储随真实 XDG_DATA 共享；并发上限收敛为 1 即可避免全局态竞争（见 README 隔离说明）。
      const origHome = process.env.HOME || os.homedir();
      const home = taskHome;
      const realData = process.env.XDG_DATA_HOME || path.join(origHome, ".local", "share");
      const realConfig = process.env.XDG_CONFIG_HOME || path.join(origHome, ".config");
      const xdgCache = path.join(taskHome, ".cache");
      for (const d of [home, xdgCache]) fs.mkdirSync(d, { recursive: true });

      const abort = new AbortController();
      const onAbort = () => abort.abort();
      if (signal.aborted) abort.abort();
      else signal.addEventListener("abort", onAbort, { once: true });

      // 改 env → 起 server（串行化窗口，起完即还原 env，子进程已在 spawn 时捕获）
      const saved: Record<string, string | undefined> = {};
      const setEnv = (k: string, v: string) => {
        saved[k] = process.env[k];
        process.env[k] = v;
      };
      // 显式指定二进制时直接返回它，否则按 PATH/which 解析（复刻 cli/run/server-connection.ts）
      const binFinder = cfg.opencodeBin ? async () => cfg.opencodeBin ?? null : undefined;
      const connection = await withEnvLock(async () => {
        setEnv("HOME", home);
        setEnv("XDG_DATA_HOME", realData); // 保留真实数据目录：opencode 鉴权/会话存储
        setEnv("XDG_CONFIG_HOME", realConfig); // 保留真实配置目录：opencode 配置
        setEnv("XDG_CACHE_HOME", xdgCache);
        setEnv("OPENCODE_CLI_RUN_MODE", "true"); // headless 契约（复刻 runner.ts:32）
        try {
          // withWorkingOpencodePath 把 opencode 二进制目录前置到 PATH，确保 createOpencode
          // spawn 的是本项目的 opencode（含 xuanyuan 等 agent），而非其它/内置 server。
          return await withWorkingOpencodePath(
            () =>
              createOpencode({
                hostname: "127.0.0.1",
                signal: abort.signal,
                timeout: cfg.serverTimeoutMs,
              }),
            binFinder,
          );
        } finally {
          for (const [k, v] of Object.entries(saved)) {
            if (v === undefined) delete process.env[k];
            else process.env[k] = v;
          }
        }
      });

      const { client, server } = connection;
      const directory = home;
      let state = initTaskSynthState();

      // 事件流 → 队列 桥接（generator 从队列产出）
      const queue: TaskDriverEvent[] = [];
      let wake: (() => void) | null = null;
      const bump = () => {
        wake?.();
        wake = null;
      };
      let streamEnded = false;

      // 完成判定状态（02 §D-002）：
      //  promptAsync 是 fire-and-forget（提交即 resolve），**不能**作为 turn 结束信号；
      //  真正的完成以「主会话由 busy 回到 idle 并稳定」或「报告 HTML 落地」为准，session.error 即失败。
      let mainSessionId: string | null = null;
      let sawBusy = false; // 主会话是否真正开始干活
      let mainBusy = false;
      let idleAt = 0;
      let sessionErr: string | null = null;

      const dbg = process.env.TASK_OC_DEBUG_EVENTS;
      const dump = (tag: string, obj: unknown) => {
        if (!dbg) return;
        try {
          fs.appendFileSync(dbg, `${tag} ${JSON.stringify(obj)}\n`);
        } catch {
          /* ignore */
        }
      };
      const pump = (async () => {
        try {
          const events = await client.event.subscribe({ query: { directory } });
          for await (const ev of events.stream as AsyncIterable<OpencodeEventPayload>) {
            if (abort.signal.aborted) break;
            dump("EV", { type: ev.type, props: ev.properties });

            // 主会话生命周期（仅本会话）：busy/idle/error
            const sid = (ev.properties as { sessionID?: string } | undefined)?.sessionID;
            const isMain = !!mainSessionId && sid === mainSessionId;
            if (isMain && ev.type === "session.status") {
              const st = (ev.properties as { status?: { type?: string } } | undefined)?.status?.type;
              if (st === "busy") {
                sawBusy = true;
                mainBusy = true;
              } else if (st === "idle") {
                mainBusy = false;
                idleAt = Date.now();
              }
            } else if (isMain && ev.type === "session.idle") {
              mainBusy = false;
              idleAt = Date.now();
            } else if (isMain && ev.type === "session.error") {
              const e = (ev.properties as { error?: { data?: { message?: string } } } | undefined)?.error;
              sessionErr = e?.data?.message || "会话执行错误";
            }

            const r = reduceTaskEvent(state, ev);
            state = r.state;
            if (r.emits.length) {
              queue.push(...r.emits);
            }
            bump();
          }
        } catch (e) {
          dump("STREAM_ERR", e instanceof Error ? e.message : String(e));
          /* 流中断按结束处理 */
        } finally {
          streamEnded = true;
          bump();
        }
      })();

      // 建会话（question 一律 deny，复刻 session-resolver.ts:30-33）
      let sessionId: string;
      try {
        const res = await client.session.create({
          body: {
            title: `witty-diagnosis ${input.taskId.slice(0, 8)}`,
            permission: [{ permission: "question", action: "deny" as const, pattern: "*" }],
          } as Record<string, unknown>,
          query: { directory },
        });
        dump("SESSION_CREATE", res);
        const id = (res as { data?: { id?: string } }).data?.id;
        if (!id) throw new Error("session.create 未返回会话 ID");
        sessionId = id;
        mainSessionId = id; // 让 pump 据此识别主会话的 busy/idle/error
      } catch (err) {
        abort.abort();
        await pump.catch(() => {});
        server.close();
        signal.removeEventListener("abort", onAbort);
        throw err;
      }

      // 解析控制器 agent 的精确名（避免大小写不匹配，如 "Xuanyuan" vs "xuanyuan"）
      const agentName = await resolveAgentName(client as Parameters<typeof resolveAgentName>[0], directory);
      dump("AGENT", agentName);

      // 提交诊断 prompt（fire-and-forget：resolve 仅表示已受理，**非** turn 结束）；question 关闭（复刻 runner.ts:99）
      client.session
        .promptAsync({
          path: { id: sessionId },
          body: {
            agent: agentName,
            tools: { question: false },
            parts: [{ type: "text", text: buildFirstPrompt(input) }],
          },
          query: { directory },
        })
        .then(
          (res: unknown) => {
            dump("PROMPT_DONE", res);
            const e = (res as { error?: { data?: { message?: string }; message?: string } } | undefined)?.error;
            if (e) sessionErr = e.data?.message || e.message || "prompt 提交失败";
            bump();
          },
          (e: unknown) => {
            dump("PROMPT_ERR", e instanceof Error ? e.message : String(e));
            sessionErr = e instanceof Error ? e.message : String(e);
            bump();
          },
        );

      // 完成判定阈值
      const STABILIZE_MS = 5000; // 主会话回到 idle 后的稳定窗口（容忍子代理边界的瞬时 idle）
      const STARTUP_MS = 180000; // 首次进入 busy 前的最长等待（opencode 起会话 + 首个产出）
      const startAt = Date.now();

      try {
        // 流式产出事件；按「报告落地 / 主会话稳定 idle / 出错」收敛，runner 的任务超时为硬兜底
        while (true) {
          if (queue.length) {
            yield queue.shift()!;
            continue;
          }
          if (abort.signal.aborted) break;
          if (sessionErr) break;
          if (streamEnded) break;
          if (resolveReportPath(taskHome, state)) break; // 成功信号①：报告 HTML 已落地
          if (sawBusy && !mainBusy && Date.now() - idleAt > STABILIZE_MS) break; // 信号②：主会话稳定 idle
          if (!sawBusy && Date.now() - startAt > STARTUP_MS) break; // 启动看门狗
          await Promise.race([
            new Promise<void>((resolve) => {
              wake = resolve;
            }),
            new Promise<void>((resolve) => setTimeout(resolve, 1500)),
          ]);
        }

        for (const e of flushTaskSynth(state)) yield e;

        if (sessionErr) {
          throw new Error(`Xuanyuan 执行失败：${sessionErr}`);
        }

        // 双信号完成判定：读取报告 HTML（turn 结束后报告文件可能仍在落盘，短暂重试）
        let html = readReportHtml(taskHome, state);
        for (let i = 0; i < 10 && !html && !abort.signal.aborted; i++) {
          await new Promise((r) => setTimeout(r, 300));
          html = readReportHtml(taskHome, state);
        }
        if (html) {
          yield { type: "report", html };
          yield { type: "log", text: "诊断完成，报告已生成 ✓" };
        } else {
          // 未拿到报告：不算成功（runner 据「是否产出 report」判定终态）
          yield { type: "log", text: "未检测到可视化报告产物（baize/reports/*.html 为空）。" };
          throw new Error("诊断结束但未生成 RCA 报告（report_visualization 未产出 HTML）。");
        }
      } finally {
        abort.abort();
        await pump.catch(() => {});
        try {
          server.close();
        } catch {
          /* ignore */
        }
        signal.removeEventListener("abort", onAbort);
      }
    },
  };
}
