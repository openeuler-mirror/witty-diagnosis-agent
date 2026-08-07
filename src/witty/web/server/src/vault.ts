import crypto from "node:crypto";

/**
 * 凭据「用完即焚」内存保险箱（对应 02 §1.2 D-003 / §2.2.3）。
 * - 仅驻留后端进程内存，以 taskId 为键，进程级密钥加密（启动生成、不落盘）
 * - 从不序列化入库 / 不写文件 / 不进日志 / 不回前端
 * - 任务终态 wipe（连同 taskHome 擦除——骨架无真实 taskHome，仅清内存）
 *
 * 注意：骨架的 stub runner 不真正使用密码（不连真实主机），
 * 这里完整实现保险箱以体现凭据治理的接缝与生命周期。
 */

export interface Credential {
  hostIp: string;
  sshUser: string;
  sshPort: number;
  sshPassword: string;
}

interface Entry {
  iv: Buffer;
  tag: Buffer;
  data: Buffer;
}

const KEY = crypto.randomBytes(32); // 进程级密钥，绝不落盘
const store = new Map<string, Entry>();

export function stage(taskId: string, cred: Credential): void {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", KEY, iv);
  const data = Buffer.concat([cipher.update(JSON.stringify(cred), "utf8"), cipher.final()]);
  store.set(taskId, { iv, tag: cipher.getAuthTag(), data });
}

export function reveal(taskId: string): Credential | null {
  const e = store.get(taskId);
  if (!e) return null;
  const decipher = crypto.createDecipheriv("aes-256-gcm", KEY, e.iv);
  decipher.setAuthTag(e.tag);
  const out = Buffer.concat([decipher.update(e.data), decipher.final()]).toString("utf8");
  return JSON.parse(out) as Credential;
}

/** 终态擦除（成功/失败/取消/超时/崩溃都必须调用）。 */
export function wipe(taskId: string): void {
  store.delete(taskId);
}
