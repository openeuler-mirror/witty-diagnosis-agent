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

  // 把 [n] 转为可点击的 HTML <cite>（rehype-raw 将其解析为真实 DOM 元素）
  const processed = text.replace(/\[(\d+)\]/g, '<cite class="cite" data-cite="$1">$1</cite>');

  return (
    <div ref={ref} className="markdown-answer">
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        rehypePlugins={[rehypeRaw]}
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
}: {
  message: QaMessage;
  onCite: (messageId: string, n: number) => void;
  onShowSources: (messageId: string) => void;
  onFollowup: (text: string) => void;
  onFeedback: (messageId: string, feedback: "useful" | "inaccurate") => void;
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
  const sourceCount = message.citations?.length ?? 0;
  const hasTrace = message.status !== null; // assistant 一定有 trace 区

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
