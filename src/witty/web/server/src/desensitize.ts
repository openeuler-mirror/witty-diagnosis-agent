/**
 * 脱敏器（对应 02 §2.2.3 / FR-014 / NFR-002）。
 * 作用于「事件流（日志）」与「报告文本」，在持久化与推送之前完成。
 * 骨架实现：字段 + 已知敏感模式（IP / 密码 / ansible_ssh_pass / 账号上下文）双策略。
 */

const PATTERNS: { re: RegExp; replace: string }[] = [
  // ansible_ssh_pass=xxx / password: xxx / passwd xxx
  { re: /(ansible_ssh_pass|password|passwd|pwd)\s*[=:]\s*\S+/gi, replace: "$1=***" },
  { re: /(-p\s*)(\S+)/g, replace: "$1***" },
  // IPv4
  { re: /\b(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})\b/g, replace: "***.***.***.***" },
];

/** 脱敏一段文本。 */
export function desensitize(text: string): string {
  if (!text) return text;
  let out = text;
  for (const { re, replace } of PATTERNS) out = out.replace(re, replace);
  return out;
}

/** 针对特定凭据值做精确遮蔽（密码/账号原文出现即抹除）。 */
export function desensitizeWith(text: string, secrets: (string | undefined)[]): string {
  let out = desensitize(text);
  for (const s of secrets) {
    if (s && s.length >= 2) out = out.split(s).join("***");
  }
  return out;
}
