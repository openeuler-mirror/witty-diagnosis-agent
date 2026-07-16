/**
 * 已知问题问答（QA）模块 · 真实 opencode 驱动。
 *
 * 单常驻 opencode server（DQ-001）+ 每会话一 session 续跑。
 * 经 createOpencode 拉起 headless server → session.create → promptAsync
 * ({ agent: "taiyi", tools: { question: false } }) → event.subscribe
 * 产出 opencode 同构事件流，供 qaEventSynthesizer 消费。
 *
 * 本文件依赖 @opencode-ai/sdk（仅真实路径），不被 web/server 编译路径静态 import
 * （经 driver/index.ts 的运行时动态 import 加载）。
 */

import { createOpencode } from "@opencode-ai/sdk";
import type { OpencodeClient } from "@opencode-ai/sdk";
import { execSync } from "node:child_process";
import type { QaDriver, QaDriverInput, OpencodeEventPayload } from "./types.js";

export interface OpencodeDriverConfig {
  model?: string;
  serverTimeoutMs?: number;
}

let _instance: Awaited<ReturnType<typeof createOpencode>> | null = null;
let _instancePromise: Promise<{ client: OpencodeClient; server: { url: string; close(): void; } }> | null = null;

async function ensureInstance(cfg: OpencodeDriverConfig) {
  if (_instance) return _instance;
  if (_instancePromise) return _instancePromise;
  _instancePromise = (async () => {
    // 检查 4096 端口占用，仅清理 opencode 进程
    try {
      const portProc = execSync("lsof -ti :4096 2>/dev/null", { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
      if (portProc) {
        const procInfo = execSync(`ps -p ${portProc} -o comm= 2>/dev/null`, { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] }).trim();
        if (!procInfo.includes("opencode")) {
          console.warn(`[opencode-driver] 端口 4096 被 ${procInfo} (PID ${portProc}) 占用，尝试释放...`);
        }
        execSync(`kill -9 ${portProc} 2>/dev/null`, { stdio: "ignore" });
      }
    } catch { /* 无占用或命令不可用，忽略 */ }
    const inst = await createOpencode({ timeout: cfg.serverTimeoutMs ?? 60000 });
    _instance = inst;
    return inst;
  })();
  return _instancePromise;
}

async function resolveTaiyiAgentName(client: { app: { agents: (o: { query: { directory: string } }) => Promise<unknown> } }): Promise<string> {
  try {
    const res = await client.app.agents({ query: { directory: "" } });
    const list = (res as { data?: Array<{ name?: string }> }).data ?? [];
    const match = list.find((a) => typeof a.name === "string" && (a.name.toLowerCase().includes("taiyi") || a.name.toLowerCase().includes("运维问答")));
    if (match?.name) return match.name;
  } catch { /* fallback */ }
  return "taiyi";
}

/** 包装事件流，使 abort 信号能立即中断等待，无需等下一个事件到达。 */
async function* abortableIterator(
  stream: any,
  signal: AbortSignal,
): any {
  const it = stream[Symbol.asyncIterator]();
  const wait = (): Promise<IteratorResult<any>> =>
    new Promise((resolve) => {
      if (signal.aborted) return resolve({ done: true, value: undefined } as IteratorResult<any>);
      const onAbort = () => resolve({ done: true, value: undefined } as IteratorResult<any>);
      signal.addEventListener("abort", onAbort, { once: true });
      it.next().then((result: any) => {
        signal.removeEventListener("abort", onAbort);
        resolve(result);
      });
    });
  while (true) {
    const result = await wait();
    if (result.done) break;
    yield result.value;
  }
}

export function createOpencodeDriver(cfg: OpencodeDriverConfig): QaDriver {
  return {
    async ensureSession(sessionId?: string): Promise<{ sessionId: string; contextReset: boolean }> {
      const { client } = (await ensureInstance(cfg))!;
      if (sessionId) {
        try {
          await (client.session as any).status({ query: { directory: "" } });
          return { sessionId, contextReset: false };
        } catch { /* session invalid, recreate */ }
      }
      const session = await client.session.create({});
      const sessionData = (session as any);
      const sid = sessionData?.data?.id ?? sessionData?.id;
      if (!sid) throw new Error("Failed to create opencode session");
      return { sessionId: sid, contextReset: true };
    },

    async *run(input: QaDriverInput): AsyncGenerator<OpencodeEventPayload> {
      const { client } = (await ensureInstance(cfg))!;
      const { signal } = input;

      const agent = await resolveTaiyiAgentName(client);

      // Subscribe first (to not miss events), then prompt
      const subResult = await client.event.subscribe({ query: { directory: "" } });
      const eventStream = (subResult as any).stream;

      await client.session.promptAsync({
        path: { id: input.sessionId! },
        body: {
          agent,
          tools: { question: false },
          parts: [{ type: "text" as any, text: input.question }],
        },
      });

      for await (const rawEvent of abortableIterator(eventStream as any, signal)) {
        const payload = rawEvent?.data ?? rawEvent;
        const type = payload?.type ?? payload?.event ?? "";
        const properties = payload?.properties ?? {};
        yield { type, properties } as OpencodeEventPayload;
        if (type === "session.idle" || type === "session.error") return;
      }
    },
  };
}
