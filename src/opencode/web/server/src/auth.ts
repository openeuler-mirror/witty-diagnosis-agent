import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import * as repo from "./repositories.js";

/**
 * 认证（骨架，对应 FR-001 / BC-009）。
 * 本期为 dev 占位单用户：表单登录 → 签名 Cookie 承载会话身份。
 * 生产形态：把 /api/auth/login 换成外部 IdP（OIDC/OAuth2/LDAP）重定向 + 回调建会话，
 * 其余「按 owner 鉴权」逻辑不变（owner 由会话解析得到）。
 */

const COOKIE = "wd_session";

export interface SessionUser {
  id: string;
  subject: string;
  displayName: string;
}

export async function getUser(req: FastifyRequest): Promise<SessionUser | null> {
  const raw = req.cookies?.[COOKIE];
  if (!raw) return null;
  const unsigned = req.unsignCookie(raw);
  if (!unsigned.valid || !unsigned.value) return null;
  let parsed: { s?: string; d?: string };
  try {
    parsed = JSON.parse(decodeURIComponent(unsigned.value));
  } catch {
    return null;
  }
  const subject = parsed.s;
  if (!subject) return null;
  const displayName = parsed.d || subject;
  const id = await repo.ensureUser(subject, displayName);
  return { id, subject, displayName };
}

/** preHandler：未认证拦截所有任务 API（返回 401）。 */
export async function requireUser(req: FastifyRequest, reply: FastifyReply): Promise<SessionUser | undefined> {
  const user = await getUser(req);
  if (!user) {
    reply.code(401).send({ error: "unauthorized" });
    return undefined;
  }
  return user;
}

export function registerAuthRoutes(app: FastifyInstance): void {
  // dev 登录：接受 {username, password?}；password 不校验（占位），仅用于演示账号
  app.post("/api/auth/login", async (req, reply) => {
    const body = (req.body ?? {}) as { username?: string };
    const username = (body.username || "").trim() || "demo-user";
    const displayName = username.split("@")[0];
    const value = encodeURIComponent(JSON.stringify({ s: username, d: displayName }));
    reply.setCookie(COOKIE, value, {
      path: "/",
      httpOnly: true,
      sameSite: "lax",
      signed: true,
      maxAge: 60 * 60 * 24 * 7,
    });
    const id = await repo.ensureUser(username, displayName);
    return { id, subject: username, displayName };
  });

  app.get("/api/auth/me", async (req, reply) => {
    const user = await getUser(req);
    if (!user) {
      reply.code(401);
      return { error: "unauthorized" };
    }
    return user;
  });

  app.post("/api/auth/logout", async (_req, reply) => {
    reply.clearCookie(COOKIE, { path: "/" });
    return { ok: true };
  });
}
