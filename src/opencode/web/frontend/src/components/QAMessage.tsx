import { useState, useRef, useEffect } from "react";
import type { QaMessage } from "../types";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import rehypeRaw from "rehype-raw";
/**
 * 单条消息渲染（FR-001/002/003）：
 *  - user：右侧气泡
 *  - assistant：检索 trace 折叠卡片 + 流式答复（完整 Markdown 渲染）
 *    + 操作行（复制 / 有用·不准 / 查看来源）+ 建议追问
 * 答复用 react-markdown 渲染，[n] 角标可点击定位右侧证据。
 */

/** 修复 LLM 生成的路径重复问题：/docs/guide/docs/guide/... → /docs/guide/ */
function fixDupPath(url: string): string {
  try {
    const u = new URL(url, "http://localhost");
    const fixed = u.pathname.replace(/(\/[^/]+\/)(?:\1)+/g, "$1");
    if (fixed !== u.pathname) {
      u.pathname = fixed;
      return u.toString();
    }
  } catch {
    /* ignore invalid URLs */
  }
  return url;
}

/** 用 react-markdown 渲染 AI 答复，[n] 角标转为可点击的 <cite> 元素。 */
function MarkdownAnswer({ text, onCite }: { text: string; onCite: (n: number) => void }) {
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const handler = (e: MouseEvent) => {
      const citeEl = (e.target as HTMLElement).closest("[data-cite]");
      if (citeEl) {
        const n = parseInt(citeEl.getAttribute("data-cite")!, 10);
        if (Number.isFinite(n)) onCite(n);
      }
    };
    el.addEventListener("click", handler);
    return () => el.removeEventListener("click", handler);
  }, [onCite]);

  // 把 [n] 转为可点击的 HTML <cite>（跳过代码块和内联代码中的 [n]）
  const processed = text.replace(/(```[\s\S]*?```|`[^`]*`)|\[(\d+)\]/g, (_, code, num) => {
    if (code) return code; // 代码块/内联代码，原样返回
    return `<cite class="cite" data-cite="${num}">${num}</cite>`;
  });

  return (
    <div ref={ref} className="markdown-answer">
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        rehypePlugins={[rehypeRaw]}
        components={{
          a: ({ href, children }) => {
            const url = href ? fixDupPath(href) : "";
            return (
              <a href={url} target="_blank" rel="noopener noreferrer">
                {children}
              </a>
            );
          },
        }}
      >
        {processed}
      </ReactMarkdown>
    </div>
  );
}

function Trace({ message }: { message: QaMessage }) {
  const [open, setOpen] = useState(false);
  const r = message.retrieval;
  const loading = message.status === "generating" && !r;
  const sourceCount = message.citations?.length ?? 0;

  return (
    <div className="trace">
      <div className={`trace-head${open ? " open" : ""}`} onClick={() => r && setOpen((v) => !v)}>
        <span className="tg">▶</span>
        {loading && <span className="spin" />}
        <span className="lab">{loading ? "正在检索知识图谱…" : "检索过程 · 双层图谱检索"}</span>
        {!loading && <span className="meta">命中 {sourceCount} 处来源</span>}
      </div>
      {r && (
        <div className={`trace-body${open ? " open" : ""}`}>
          <div className="rlevel">
            <div className="rl-head">
              <span className="rl-tag rl-low">低层检索 Local</span>
              <span className="desc">精确实体与关系</span>
            </div>
            <div className="chips">
              {r.low.map((x, i) => (
                <span key={i} className={`gchip ${x.includes("→") ? "rel" : "ent"}`}>
                  {x}
                </span>
              ))}
            </div>
          </div>
          <div className="rlevel">
            <div className="rl-head">
              <span className="rl-tag rl-high">高层检索 Global</span>
              <span className="desc">主题与概念</span>
            </div>
            <div className="chips">
              {r.high.map((x, i) => (
                <span key={i} className="gchip">
                  {x}
                </span>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default function QAMessage({
  message,
  onCite,
  onShowSources,
  onFollowup,
  onFeedback,
  onRetry,
}: {
  message: QaMessage;
  onCite: (messageId: string, n: number) => void;
  onShowSources: (messageId: string) => void;
  onFollowup: (text: string) => void;
  onFeedback: (messageId: string, feedback: "useful" | "inaccurate") => void;
  onRetry?: (messageId: string) => void;
}) {
  const [feedback, setFeedback] = useState<"useful" | "inaccurate" | null>(message.feedback);
  const [copied, setCopied] = useState(false);

  const sendFeedback = (fb: "useful" | "inaccurate") => {
    setFeedback(fb);
    onFeedback(message.id, fb);
  };

  if (message.role === "user") {
    return (
      <div className="msg user fade-in">
        <div className="bubble">{message.text}</div>
      </div>
    );
  }

  const generating = message.status === "generating";
  const failed = message.status === "failed";
  const aborted = message.status === "aborted";
  const maxCiteId = (message.citations ?? []).reduce((max, c) => Math.max(max, c.id), 0);
  const citedIds = new Set<number>();
  if (message.text && maxCiteId > 0) {
    for (const m of message.text.matchAll(/\[(\d+)\]/g)) {
      const id = Number(m[1]);
      if (id >= 1 && id <= maxCiteId) citedIds.add(id);
    }
  }
  const sourceCount = citedIds.size > 0
    ? (message.citations ?? []).filter((c) => citedIds.has(c.id)).length
    : (message.status === "generating" ? (message.citations?.length ?? 0) : 0);
  const hasTrace = message.status !== null;

  const copy = () => {
    navigator.clipboard?.writeText(message.text).catch(() => {});
    setCopied(true);
    setTimeout(() => setCopied(false), 1400);
  };

  return (
    <div className="msg ai fade-in">
      <div className="ai-av">e</div>
      <div className="ai-body">
        {hasTrace && <Trace message={message} />}

        <div className="answer">
          {failed && message.text === "" ? (
            <div className="qa-degraded">⚠ 知识检索服务暂不可用，请稍后重试。</div>
          ) : (
            <MarkdownAnswer text={message.text} onCite={(n) => onCite(message.id, n)} />
          )}
          {generating && <span className="qa-caret" />}
        </div>

        {!generating && (message.text || sourceCount > 0) && (
          <div className="ai-foot">
            <div className="act-row">
              <button
                className={`iact${feedback === "useful" ? " done" : ""}`}
                disabled={feedback !== null}
                onClick={() => sendFeedback("useful")}
              >
                {feedback === "useful" ? "✓ 已标记有用" : "▲ 有用"}
              </button>
              <button
                className={`iact${feedback === "inaccurate" ? " done" : ""}`}
                disabled={feedback !== null}
                onClick={() => sendFeedback("inaccurate")}
              >
                {feedback === "inaccurate" ? "✓ 已反馈" : "▼ 不准"}
              </button>
              <button className="iact" onClick={copy}>
                {copied ? "✓ 已复制" : "⧉ 复制"}
              </button>
              {sourceCount > 0 && (
                <button className="iact" onClick={() => onShowSources(message.id)}>
                  ◳ 查看 {sourceCount} 处来源
                </button>
              )}
              {(failed || aborted) && onRetry && (
                <button className="iact retry" onClick={() => onRetry(message.id)}>
                  ↻ 重新生成
                </button>
              )}
              {aborted && <span className="qa-stopped">· 已停止</span>}
            </div>
            {message.followups && message.followups.length > 0 && (
              <div className="followups">
                <div className="fu-label">建议追问</div>
                {message.followups.map((q, i) => (
                  <button key={i} className="fu" onClick={() => onFollowup(q)}>
                    <span>{q}</span>
                    <span className="ar">→</span>
                  </button>
                ))}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
