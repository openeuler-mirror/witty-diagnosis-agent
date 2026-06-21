import { useState, type ReactNode } from "react";
import type { QaMessage } from "../types";

/**
 * 单条消息渲染（FR-001/002/003）：
 *  - user：右侧气泡
 *  - assistant：检索 trace 折叠卡片 + 流式答复（[n] 引用角标 / 行内 code / **bold** / 有序列表）
 *    + 操作行（复制 / 有用·不准 / 查看来源）+ 建议追问
 * 答复用受控 React 渲染（不 dangerouslySetInnerHTML），[n] 角标可点击定位右侧证据。
 */

// 行内：把 [n] / `code` / **bold** 解析为元素，其余为纯文本
function renderInline(s: string, onCite: (n: number) => void, keyBase: string): ReactNode[] {
  const out: ReactNode[] = [];
  const re = /(\[\d+\])|(`[^`]+`)|(\*\*[^*]+\*\*)/g;
  let last = 0;
  let m: RegExpExecArray | null;
  let i = 0;
  while ((m = re.exec(s)) !== null) {
    if (m.index > last) out.push(s.slice(last, m.index));
    const tok = m[0];
    if (m[1]) {
      const n = parseInt(tok.slice(1, -1), 10);
      out.push(
        <span key={`${keyBase}-c${i}`} className="cite" onClick={() => onCite(n)}>
          {n}
        </span>,
      );
    } else if (m[2]) {
      out.push(
        <code key={`${keyBase}-k${i}`}>{tok.slice(1, -1)}</code>,
      );
    } else if (m[3]) {
      out.push(<strong key={`${keyBase}-b${i}`}>{tok.slice(2, -2)}</strong>);
    }
    last = re.lastIndex;
    i++;
  }
  if (last < s.length) out.push(s.slice(last));
  return out;
}

function renderAnswer(text: string, onCite: (n: number) => void): ReactNode[] {
  const blocks: ReactNode[] = [];
  let list: ReactNode[] = [];
  const flush = () => {
    if (list.length) {
      blocks.push(
        <ol key={`ol${blocks.length}`}>{list}</ol>,
      );
      list = [];
    }
  };
  text.split("\n").forEach((ln, idx) => {
    if (!ln.trim()) {
      flush();
      return;
    }
    const lm = ln.match(/^(\d+)\.\s+(.*)$/);
    if (lm) {
      list.push(<li key={`li${idx}`}>{renderInline(lm[2], onCite, `li${idx}`)}</li>);
    } else {
      flush();
      blocks.push(<p key={`p${idx}`}>{renderInline(ln, onCite, `p${idx}`)}</p>);
    }
  });
  flush();
  return blocks;
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
            renderAnswer(message.text, (n) => onCite(message.id, n))
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
