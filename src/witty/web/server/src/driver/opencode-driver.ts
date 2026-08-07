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
 * （web/server 经 ./index.ts 的运行时动态 import 加载本文件，typecheck 由根工程覆盖）。
 *
 * ⚠ 隔离说明：createOpencode 不支持 per-call env，HOME/XDG 重定向经 process.env 完成；用模块级互斥
 * 串行化「改 env → 起 server」窗口，避免并发任务相互污染。若需更强隔离，应改为每任务独立 node 进程
 * spawn（与 D-001 原意一致），此处为首个可运行实现。
 */

import { createOpencode } from "@opencode-ai/sdk";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { withWorkingOpencodePath } from "./opencode-binary-resolver.js";
import { getAvailableServerPort } from "./port-utils.js";
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

/**
 * 报告扫描目录（双信号②候选，仅在 state.reportPath 没捕获到绝对路径时才用作兜底）。
 *  - 隔离 taskHome 下的 baize/reports（原设计假设）；
 *  - **真实用户 HOME** 下的 baize/reports —— 驱动为保住 opencode 凭据而保留了真实 XDG，
 *    baize 用「~ / os.homedir()」解析报告路径，实际可能把 .html 写到了这里（只扫隔离目录
 *    会「未检测到报告」的真正原因）。
 * 真实目录会累积历史会话文件，故调用侧务必用 taskId / sinceMs 收敛，避免读到旧报告。
 */
function reportScanDirs(taskHome: string): string[] {
  return [
    path.join(taskHome, ".witty-diagnosis-agent", "baize", "reports"),
    path.join(os.homedir(), ".witty-diagnosis-agent", "baize", "reports"),
  ];
}

/**
 * 在 baize/reports 下取本任务的最新 .html（双信号②兜底）。
 * 收敛规则（避免读到共享目录里的历史报告）：
 *  - 文件名含 taskId 短码 → 强匹配，优先；
 *  - 否则只认「mtime ≥ sinceMs」的文件（本任务开始后才落地的产物）。
 */
function findLatestReportHtml(taskHome: string, taskId?: string, sinceMs?: number): string | null {
  const shortId = taskId ? taskId.slice(0, 8).toLowerCase() : null;
  let best: { file: string; mtime: number; idMatch: boolean } | null = null;
  for (const dir of reportScanDirs(taskHome)) {
    let entries: string[];
    try {
      entries = fs.readdirSync(dir).filter((f) => f.toLowerCase().endsWith(".html"));
    } catch {
      continue;
    }
    for (const f of entries) {
      const full = path.join(dir, f);
      let mtime: number;
      try {
        mtime = fs.statSync(full).mtimeMs;
      } catch {
        continue;
      }
      const idMatch = !!shortId && f.toLowerCase().includes(shortId);
      // 无 id 命中时，必须晚于任务起点才可信（隔离 taskHome 每任务全新，不受此限）
      if (!idMatch && sinceMs != null && mtime < sinceMs) continue;
      // 优先级：id 命中 > 更新的 mtime
      const better =
        !best ||
        (idMatch && !best.idMatch) ||
        (idMatch === best.idMatch && mtime > best.mtime);
      if (better) best = { file: full, mtime, idMatch };
    }
  }
  return best?.file ?? null;
}

/**
 * 解析报告 HTML 路径：
 *  ① 优先 state.reportPath —— 由事件合成器从 report_visualization 输出
 *     「Successfully converted to HTML: <abs>」捕获的绝对路径（最可靠，远程 d9c0bf4 引入）；
 *  ② 兜底：在 taskHome + 真实 HOME 的 baize/reports 里按 taskId/时间取本任务最新 .html。
 */
function resolveReportPath(taskHome: string, state: TaskSynthState, taskId?: string, sinceMs?: number): string | null {
  if (state.reportPath && state.reportPath.toLowerCase().endsWith(".html") && fs.existsSync(state.reportPath)) {
    return state.reportPath;
  }
  return findLatestReportHtml(taskHome, taskId, sinceMs);
}

/** 读取报告 HTML 内容。 */
function readReportHtml(taskHome: string, state: TaskSynthState, taskId?: string, sinceMs?: number): string | null {
  const candidate = resolveReportPath(taskHome, state, taskId, sinceMs);
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
      // 报告时间下限：本任务开始时刻，留 5s 余量容忍时钟/落盘抖动。用于在共享的真实
      // baize/reports 目录里把「本任务产出」和历史报告区分开（配合文件名 taskId 强匹配）。
      const runStartedAt = Date.now() - 5000;

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
      // 为每个任务分配唯一端口，避免并发时端口冲突
      let serverPort = 4096;
      try {
        const result = await getAvailableServerPort(4096, "127.0.0.1");
        serverPort = result.port;
      } catch {
        // 端口范围全满时回退到默认 4096
      }
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
                port: serverPort,
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
      // 将 server.close 注册给调用方（runner），替换全局 pkill 为定点进程清理
      input.onServerReady?.(() => server.close());
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
      let lastSubError: string | null = null; // 子会话最后一次报错（兜底失败说明用，非立即判失败）
      // 事件流「最后活动」时间戳：opencode server 若在一次 turn 中途死掉，SSE 流会静默（既不产出下一条、
      // 也不抛错），for await 无法被 abort 打断。用它给主循环/关流兜一个静默看门狗，避免任务永久卡死。
      let lastEventAt = Date.now();

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
            lastEventAt = Date.now(); // 有活动就刷新，静默看门狗据此判断 server 是否中途死掉
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
            } else if (ev.type === "session.error") {
              // 子会话（子 agent）报错：不立即判失败（opencode 可能自行重试/降级），仅记为兜底原因；
              // 若整轮最终没产出报告，用它给出比「未生成报告」更具体的失败说明。
              const e = (ev.properties as { error?: { data?: { message?: string } } } | undefined)?.error;
              const msg = e?.data?.message;
              if (msg) lastSubError = msg;
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
        // 同 finally：先关 server 让 SSE 流收尾，再对 await pump 加超时，避免早失败路径也永久挂起。
        try {
          server.close();
        } catch {
          /* ignore */
        }
        await Promise.race([
          pump.catch(() => {}),
          new Promise<void>((resolve) => setTimeout(resolve, 3000)),
        ]);
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
      // 静默看门狗：已经 busy 过、但事件流长时间一条都不来 —— opencode server 多半在一次 turn 中途
      // 死掉（进程退出/崩溃），SSE 流不会抛错也不会结束，靠它兜底跳出，避免 runner 卡在 running 直到硬超时。
      // 阈值取得比模型单步产出间隔宽松（DeepSeek 等长思考/工具调用间可能几十秒无事件），避免误杀。
      const SILENCE_MS = 120000;
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
          if (resolveReportPath(taskHome, state, input.taskId, runStartedAt)) break; // 成功信号①：报告 HTML 已落地
          if (sawBusy && !mainBusy && Date.now() - idleAt > STABILIZE_MS) break; // 信号②：主会话稳定 idle
          if (!sawBusy && Date.now() - startAt > STARTUP_MS) break; // 启动看门狗
          if (sawBusy && Date.now() - lastEventAt > SILENCE_MS) {
            // 静默看门狗命中：server 中途死掉。标记为错误，让下方按失败收敛（而非误判成功）。
            sessionErr = sessionErr || lastSubError || "opencode 事件流中断（server 可能在诊断中途退出）";
            break;
          }
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
        let html = readReportHtml(taskHome, state, input.taskId, runStartedAt);
        for (let i = 0; i < 10 && !html && !abort.signal.aborted; i++) {
          await new Promise((r) => setTimeout(r, 300));
          html = readReportHtml(taskHome, state, input.taskId, runStartedAt);
        }
        if (html) {
          yield { type: "report", html };
          yield { type: "log", text: "诊断完成，报告已生成 ✓" };
        } else {
          // 未拿到报告：不算成功（runner 据「是否产出 report」判定终态）
          yield { type: "log", text: "未检测到可视化报告产物（baize/reports/*.html 为空）。" };
          const detail = lastSubError ? `；最后一次子会话报错：${lastSubError}` : "";
          throw new Error(`诊断结束但未生成 RCA 报告（report_visualization 未产出 HTML）${detail}。`);
        }
      } finally {
        abort.abort();
        // ⚠ 先关 server，再等 pump。event.subscribe 的 SSE 流在 server 存活时不会因 abort 而结束，
        // 若先 `await pump` 会永久挂起 → generator 永不返回 → runner 卡在 running（本次 hang 根因）。
        // 关掉 server 通常会让流收尾；再对 await pump 加超时兜底，确保无论如何都能返回。
        try {
          server.close();
        } catch {
          /* ignore */
        }
        await Promise.race([
          pump.catch(() => {}),
          new Promise<void>((resolve) => setTimeout(resolve, 3000)),
        ]);
        signal.removeEventListener("abort", onAbort);
      }
    },
  };
}
