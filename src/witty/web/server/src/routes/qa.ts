import type { FastifyInstance } from "fastify";
import { requireUser } from "../auth.js";
import * as repo from "../repositories.js";
import * as qaScheduler from "../qaScheduler.js";
import * as qaRunner from "../qaRunner.js";
import { subscribe } from "../streamHub.js";
import { desensitize } from "../desensitize.js";
import { config } from "../config.js";
import type { StreamEvent } from "../types.js";

/**
 * QA 模块 REST + SSE（对应 02 §6.1）。仅在 config.conversation.enabled 时由 index.ts 注册。
 * 所有读写强制 owner == 当前用户；越权统一 404（不泄露存在性，BC-004）。
 */

export function registerQaRoutes(app: FastifyInstance): void {
  // ---- 新建会话 ----
  app.post("/api/qa/sessions", async (req, reply) => {
    const user = await requireUser(req, reply);
    if (!user) return;
    const body = (req.body ?? {}) as { title?: string };
    const title = (body.title || "").trim() || "新会话";
    const session = await repo.createQaSession(user.id, title);
    reply.code(201);
    return { id: session.id, createdAt: session.createdAt };
  });

  // ---- 会话列表（按 owner 隔离） ----
  app.get("/api/qa/sessions", async (req, reply) => {
    const user = await requireUser(req, reply);
    if (!user) return;
    return repo.listQaSessions(user.id);
  });

  // ---- 会话详情 + 历史消息（回看重建，FR-006） ----
  app.get("/api/qa/sessions/:id", async (req, reply) => {
    const user = await requireUser(req, reply);
    if (!user) return;
    const id = (req.params as { id: string }).id;
    const session = await repo.getQaSessionForOwner(id, user.id);
    if (!session) {
      reply.code(404);
      return { error: "not found" };
    }
    const messages = await repo.listQaMessages(id);
    return { session, messages };
  });

  // ---- 重命名会话 ----
  app.put("/api/qa/sessions/:id", async (req, reply) => {
    const user = await requireUser(req, reply);
    if (!user) return;
    const id = (req.params as { id: string }).id;
    const session = await repo.getQaSessionForOwner(id, user.id);
    if (!session) {
      reply.code(404);
      return { error: "not found" };
    }
    const body = (req.body ?? {}) as { title?: string };
    const title = (body.title || "").trim();
    if (!title) {
      reply.code(400);
      return { error: "标题不能为空" };
    }
    await repo.touchQaSession(id, { title });
    return { ok: true };
  });

  // ---- 删除会话（级联消息） ----
  app.delete("/api/qa/sessions/:id", async (req, reply) => {
    const user = await requireUser(req, reply);
    if (!user) return;
    const id = (req.params as { id: string }).id;
    const session = await repo.getQaSessionForOwner(id, user.id);
    if (!session) {
      reply.code(404);
      return { error: "not found" };
    }
    qaScheduler.abort(id); // 若进行中先中止
    await repo.deleteQaSession(id);
    return { ok: true };
  });
  // ---- 发送消息（提问 / 追问；入队，single-flight） ----
  app.post("/api/qa/sessions/:id/messages", async (req, reply) => {
    const user = await requireUser(req, reply);
    if (!user) return;
    const id = (req.params as { id: string }).id;
    const sessionRaw = await repo.getQaSessionRawForOwner(id, user.id);
    if (!sessionRaw) {
      reply.code(404);
      return { error: "not found" };
    }

    // 输入边界（DC-003 / AC-009）
    const raw = ((req.body ?? {}) as { text?: string }).text ?? "";
    const text = raw.trim();
    if (!text) {
      reply.code(400);
      return { error: "问题不能为空" };
    }
    if (text.length > config.conversation.questionMaxChars) {
      reply.code(400);
      return { error: `问题过长（上限 ${config.conversation.questionMaxChars} 字符）` };
    }

    // single-flight：同会话已有进行中生成 → 409
    if (qaScheduler.isActive(id)) {
      reply.code(409);
      return { error: "该会话有生成进行中，请等待完成或停止后再试" };
    }

    // 落库（脱敏后）user 消息 + assistant 占位（generating）
    const safe = desensitize(text);
    const userMessageId = await repo.appendQaMessage({ sessionId: id, role: "user", text: safe });
    const assistantMessageId = await repo.appendQaMessage({ sessionId: id, role: "assistant", status: "generating", text: "" });

    // 首条问题生成会话标题
    const prior = await repo.listQaMessages(id);
    if (prior.filter((m) => m.role === "user").length <= 1) {
      await repo.touchQaSession(id, { title: safe.slice(0, 30) });
    }

    const ok = qaScheduler.enqueue({
      conversationId: id,
      run: (signal) =>
        qaRunner.run(
          { conversationId: id, ocSessionId: sessionRaw.oc_session_id ?? null, question: text, assistantMessageId },
          signal,
        ),
    });
    if (!ok) {
      // 理论上已被 isActive 拦截；兜底防竞态
      await repo.updateQaMessage(assistantMessageId, { status: "aborted" });
      reply.code(409);
      return { error: "该会话有生成进行中，请稍后再试" };
    }

    reply.code(202);
    return { userMessageId, assistantMessageId };
  });

  // ---- 答复反馈（有用/不准，落库供质量回流，FR-008） ----
  app.put("/api/qa/sessions/:id/messages/:mid/feedback", async (req, reply) => {
    const user = await requireUser(req, reply);
    if (!user) return;
    const { id, mid } = req.params as { id: string; mid: string };
    const session = await repo.getQaSessionForOwner(id, user.id);
    if (!session) {
      reply.code(404);
      return { error: "not found" };
    }
    const feedback = ((req.body ?? {}) as { feedback?: string }).feedback;
    if (feedback !== "useful" && feedback !== "inaccurate") {
      reply.code(400);
      return { error: "feedback 取值须为 useful | inaccurate" };
    }
    const hit = await repo.setQaFeedback(mid, id, feedback);
    if (!hit) {
      reply.code(404);
      return { error: "not found" };
    }
    return { ok: true };
  });

  // ---- 停止生成（abort，保留已生成） ----
  app.post("/api/qa/sessions/:id/stop", async (req, reply) => {
    const user = await requireUser(req, reply);
    if (!user) return;
    const id = (req.params as { id: string }).id;
    const session = await repo.getQaSessionForOwner(id, user.id);
    if (!session) {
      reply.code(404);
      return { error: "not found" };
    }
    qaScheduler.abort(id);
    return { ok: true };
  });

  // ---- 实时流式（SSE）：token / trace / evidence / done ----
  app.get("/api/qa/sessions/:id/stream", async (req, reply) => {
    const user = await requireUser(req, reply);
    if (!user) return;
    const id = (req.params as { id: string }).id;
    const session = await repo.getQaSessionForOwner(id, user.id);
    if (!session) {
      reply.code(404);
      return { error: "not found" };
    }

    reply.hijack();
    reply.raw.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
      "X-Accel-Buffering": "no",
    });

    const send = (event: StreamEvent) => {
      reply.raw.write(`data: ${JSON.stringify(event)}\n\n`);
    };

    // 首帧快照：历史消息（含 trace/引用/图谱快照），供断连重连/回看对齐
    const messages = await repo.listQaMessages(id);
    send({ type: "qa_snapshot", messages });

    const unsubscribe = subscribe(id, send);
    const heartbeat = setInterval(() => reply.raw.write(": ping\n\n"), 15000);

    req.raw.on("close", () => {
      clearInterval(heartbeat);
      unsubscribe();
    });
  });
}
