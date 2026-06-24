/**
 * QA repositories 集成测试（03 T206）：owner 隔离、消息 CRUD、反馈落库、级联删除、崩溃恢复。
 * 用临时 sqlite 文件 + 真实迁移；运行：npm test。
 */

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import os from "node:os";
import path from "node:path";
import fs from "node:fs";

// 必须在 import knex/repo 之前设定，knexfile.cjs / config.ts 在 import 期读取 env
const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "qa-repo-"));
process.env.DB_CLIENT = "sqlite";
process.env.DB_SQLITE_PATH = path.join(tmpDir, "t.db");

const knex = await import("./db/knex.js");
const repo = await import("./repositories.js");

let ownerA = "";
let ownerB = "";

before(async () => {
  await knex.migrateToLatest();
  ownerA = await repo.ensureUser("user-a", "A");
  ownerB = await repo.ensureUser("user-b", "B");
});

after(async () => {
  await knex.closeDb();
  fs.rmSync(tmpDir, { recursive: true, force: true });
});

test("owner 隔离：非 owner 读会话返回 null（不泄露存在性）", async () => {
  const s = await repo.createQaSession(ownerA, "A 的会话");
  assert.ok(await repo.getQaSessionForOwner(s.id, ownerA));
  assert.equal(await repo.getQaSessionForOwner(s.id, ownerB), null);
  const listB = await repo.listQaSessions(ownerB);
  assert.ok(!listB.some((x) => x.id === s.id));
});

test("消息 CRUD + 快照解析", async () => {
  const s = await repo.createQaSession(ownerA, "t");
  const uid = await repo.appendQaMessage({ sessionId: s.id, role: "user", text: "firewalld reload 后断网" });
  const aid = await repo.appendQaMessage({ sessionId: s.id, role: "assistant", status: "generating", text: "" });
  await repo.updateQaMessage(aid, {
    status: "done",
    text: "根因是规则被清空[1]。",
    retrieval: { low: ["firewalld"], high: ["容器网络中断"] },
    citations: [
      { id: 1, type: "doc", badge: "官方文档", title: "T", origin: "o", url: "u", excerpt: "e", entities: ["firewalld"], relations: ["a→b"], rel: 96 },
    ],
    graph: { nodes: [{ id: "firewalld", x: 1, y: 2, t: "ent" }], edges: [] },
    followups: ["怎么避免？"],
  });

  const msgs = await repo.listQaMessages(s.id);
  assert.equal(msgs.length, 2);
  assert.equal(msgs[0].id, uid);
  const a = msgs[1];
  assert.equal(a.status, "done");
  assert.equal(a.citations?.length, 1);
  assert.equal(a.retrieval?.low[0], "firewalld");
  assert.equal(a.graph?.nodes[0].id, "firewalld");
  assert.deepEqual(a.followups, ["怎么避免？"]);
});

test("反馈落库：仅命中本会话 assistant 消息", async () => {
  const s = await repo.createQaSession(ownerA, "t");
  const aid = await repo.appendQaMessage({ sessionId: s.id, role: "assistant", status: "done", text: "x" });
  assert.equal(await repo.setQaFeedback(aid, s.id, "useful"), true);
  assert.equal(await repo.setQaFeedback(aid, "other-session", "useful"), false); // 跨会话不命中
  const msgs = await repo.listQaMessages(s.id);
  assert.equal(msgs.find((m) => m.id === aid)?.feedback, "useful");
});

test("级联删除：删除会话连带删除消息", async () => {
  const s = await repo.createQaSession(ownerA, "t");
  await repo.appendQaMessage({ sessionId: s.id, role: "user", text: "q" });
  await repo.deleteQaSession(s.id);
  assert.equal(await repo.getQaSessionForOwner(s.id, ownerA), null);
  assert.equal((await repo.listQaMessages(s.id)).length, 0);
});

test("崩溃恢复：残留 generating 置 failed", async () => {
  const s = await repo.createQaSession(ownerA, "t");
  await repo.appendQaMessage({ sessionId: s.id, role: "assistant", status: "generating", text: "" });
  const n = await repo.failOrphanQaGenerating();
  assert.ok(n >= 1);
  const msgs = await repo.listQaMessages(s.id);
  assert.equal(msgs[0].status, "failed");
});
