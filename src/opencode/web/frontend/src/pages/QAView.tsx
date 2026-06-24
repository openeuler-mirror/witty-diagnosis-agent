import { useEffect, useRef, useState } from "react";
import { useStore } from "../store";
import {
  ApiError,
  createQaSession,
  deleteQaSession,
  listQaSessions,
  postQaMessage,
  putQaFeedback,
  stopQa,
  streamQa,
} from "../api";
import type { QaMessage, QaSession, QaStreamEvent } from "../types";
import QAMessage from "../components/QAMessage";
import QAEvidence from "../components/QAEvidence";

/** 推荐问题（本期前端硬编码，FR-007；对齐参考页 SUGGESTS）。 */
const SUGGESTS = [
  "firewalld reload 后容器断网",
  "升级 docker 后容器全部启动失败",
  "Java 容器 Exited(137) 反复重启",
];

interface EvidenceFocus {
  msgId: string | null;
  cite: number | null;
  tab: "src" | "graph";
  nonce: number;
}

function newAssistant(id: string, sessionId: string): QaMessage {
  return {
    id,
    sessionId,
    role: "assistant",
    status: "generating",
    text: "",
    retrieval: null,
    citations: null,
    graph: null,
    followups: null,
    feedback: null,
    createdAt: Date.now(),
  };
}

export default function QAView() {
  const storeSessionId = useStore((s) => (s.view.name === "qa" ? s.view.sessionId : undefined));
  const toast = useStore((s) => s.toast);

  const [sessions, setSessions] = useState<QaSession[]>([]);
  const [sessionId, setSessionId] = useState<string | null>(null);
  const [messages, setMessages] = useState<QaMessage[]>([]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const [ev, setEv] = useState<EvidenceFocus>({ msgId: null, cite: null, tab: "src", nonce: 0 });

  const streamRef = useRef<HTMLDivElement>(null);
  const taRef = useRef<HTMLTextAreaElement>(null);

  const refreshSessions = () => listQaSessions().then(setSessions).catch(() => {});

  // ---- 初始装载：列表 + 选定（store 指定 → 最近一个 → 新建） ----
  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const list = await listQaSessions();
        if (!alive) return;
        setSessions(list);
        if (storeSessionId) setSessionId(storeSessionId);
        else if (list.length > 0) setSessionId(list[0].id);
        else {
          const created = await createQaSession();
          if (!alive) return;
          setSessionId(created.id);
          setSessions(await listQaSessions());
        }
      } catch {
        if (alive) toast("加载会话失败");
      }
    })();
    return () => {
      alive = false;
    };
  }, [storeSessionId, toast]);

  // ---- SSE 订阅：切换会话即重连；qa_snapshot 首帧重建历史（回看，FR-006） ----
  useEffect(() => {
    if (!sessionId) return;
    setMessages([]);
    setEv({ msgId: null, cite: null, tab: "src", nonce: 0 });
    setBusy(false);

    const upsert = (id: string, patch: (m: QaMessage) => QaMessage) =>
      setMessages((prev) => {
        const i = prev.findIndex((m) => m.id === id);
        if (i === -1) return [...prev, patch(newAssistant(id, sessionId))];
        const next = prev.slice();
        next[i] = patch(next[i]);
        return next;
      });

    const close = streamQa(sessionId, (e: QaStreamEvent) => {
      switch (e.type) {
        case "qa_snapshot":
          setMessages(e.messages);
          if (e.messages.some((m) => m.status === "generating")) setBusy(true);
          break;
        case "qa_token":
          upsert(e.messageId, (m) => ({ ...m, text: m.text + e.text, status: "generating" }));
          break;
        case "qa_trace_start":
          upsert(e.messageId, (m) => ({ ...m, status: "generating" }));
          break;
        case "qa_trace":
          upsert(e.messageId, (m) => ({ ...m, retrieval: e.retrieval ?? m.retrieval }));
          break;
        case "qa_evidence":
          upsert(e.messageId, (m) => ({ ...m, citations: e.citations, graph: e.graph ?? null, followups: e.followups ?? m.followups }));
          setEv((cur) => (cur.msgId ? cur : { msgId: e.messageId, cite: null, tab: "src", nonce: cur.nonce }));
          break;
        case "qa_done":
          upsert(e.messageId, (m) => ({ ...m, status: e.status }));
          setBusy(false);
          refreshSessions(); // 标题/排序可能更新
          break;
        case "qa_error":
          if (e.messageId) upsert(e.messageId, (m) => ({ ...m, status: "failed" }));
          setBusy(false);
          toast(e.message || "生成失败");
          break;
      }
    });
    return close;
  }, [sessionId, toast]);

  // ---- 自动滚动到底 ----
  useEffect(() => {
    const el = streamRef.current;
    if (el) requestAnimationFrame(() => (el.scrollTop = el.scrollHeight));
  }, [messages]);

  const autosize = () => {
    const ta = taRef.current;
    if (!ta) return;
    ta.style.height = "auto";
    ta.style.height = Math.min(ta.scrollHeight, 120) + "px";
  };

  const send = async (text: string) => {
    const q = text.trim();
    if (!q || busy || !sessionId) return;
    setInput("");
    requestAnimationFrame(autosize);
    try {
      const { userMessageId, assistantMessageId } = await postQaMessage(sessionId, q);
      setBusy(true);
      setMessages((prev) => {
        const withUser = prev.some((m) => m.id === userMessageId)
          ? prev
          : [...prev, { ...newAssistant(userMessageId, sessionId), role: "user" as const, status: null, text: q }];
        return withUser.some((m) => m.id === assistantMessageId) ? withUser : [...withUser, newAssistant(assistantMessageId, sessionId)];
      });
      setEv((cur) => ({ msgId: assistantMessageId, cite: null, tab: "src", nonce: cur.nonce + 1 }));
    } catch (err) {
      toast(err instanceof ApiError ? err.message : "发送失败");
    }
  };

  const onStop = () => {
    if (sessionId) stopQa(sessionId).catch(() => {});
  };

  const onCite = (messageId: string, n: number) => setEv((cur) => ({ msgId: messageId, cite: n, tab: "src", nonce: cur.nonce + 1 }));
  const onShowSources = (messageId: string) => setEv((cur) => ({ msgId: messageId, cite: null, tab: "src", nonce: cur.nonce + 1 }));

  const onFeedback = (messageId: string, feedback: "useful" | "inaccurate") => {
    if (!sessionId) return;
    setMessages((prev) => prev.map((m) => (m.id === messageId ? { ...m, feedback } : m)));
    putQaFeedback(sessionId, messageId, feedback).catch(() => toast("反馈提交失败"));
  };

  // ---- 会话操作 ----
  const newSession = async () => {
    try {
      const created = await createQaSession();
      setSessionId(created.id);
      await refreshSessions();
    } catch {
      toast("新建会话失败");
    }
  };
  const selectSession = (id: string) => {
    if (id !== sessionId) setSessionId(id);
  };
  const removeSession = async (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    if (!window.confirm("删除该会话及其全部消息？")) return;
    try {
      await deleteQaSession(id);
      const rest = sessions.filter((s) => s.id !== id);
      setSessions(rest);
      if (id === sessionId) {
        if (rest.length > 0) setSessionId(rest[0].id);
        else await newSession();
      }
    } catch {
      toast("删除会话失败");
    }
  };

  const evMessage =
    messages.find((m) => m.id === ev.msgId) ??
    [...messages].reverse().find((m) => m.role === "assistant" && (m.citations?.length ?? 0) > 0) ??
    null;

  return (
    <div className="qa-body">
      <aside className="qa-sessions">
        <button className="qa-new" onClick={newSession}>
          ＋ 新建会话
        </button>
        <div className="qa-slist">
          {sessions.length === 0 && <div className="qa-sempty">暂无历史会话</div>}
          {sessions.map((s) => (
            <div key={s.id} className={`qa-sitem${s.id === sessionId ? " active" : ""}`} onClick={() => selectSession(s.id)} title={s.title}>
              <span className="qa-stitle">{s.title || "新会话"}</span>
              <button className="qa-sdel" title="删除会话" onClick={(e) => removeSession(s.id, e)}>
                ✕
              </button>
            </div>
          ))}
        </div>
      </aside>

      <section className="chat">
        <div className="stream" ref={streamRef}>
          <div className="stream-inner">
            {messages.length === 0 && (
              <div className="intro">
                <span className="ic">◈</span>
                <div>
                  <b>检索增强问答（RAG）</b> —— 回答均来自运维知识库（官方文档 / 内部案例 / 运维 Skill）。
                  <p>正文中的引用角标可点击，右侧将定位到对应原文与出处。试试下面的推荐问题或直接提问。</p>
                </div>
              </div>
            )}
            {messages.map((m) => (
              <QAMessage key={m.id} message={m} onCite={onCite} onShowSources={onShowSources} onFollowup={send} onFeedback={onFeedback} />
            ))}
          </div>
        </div>

        <div className="composer">
          <div className="composer-inner">
            <div className="suggest-row">
              {SUGGESTS.map((s) => (
                <button key={s} className="schip" disabled={busy} onClick={() => send(s)}>
                  ＋ {s}
                </button>
              ))}
            </div>
            <div className="input-wrap">
              <textarea
                ref={taRef}
                rows={1}
                placeholder="描述你遇到的运维问题，例如：升级 docker 后所有容器启动失败……"
                value={input}
                onChange={(e) => {
                  setInput(e.target.value);
                  autosize();
                }}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && !e.shiftKey) {
                    e.preventDefault();
                    send(input);
                  }
                }}
              />
              {busy ? (
                <button className="send stop" title="停止生成" onClick={onStop}>
                  ■
                </button>
              ) : (
                <button className="send" title="发送（Enter）" disabled={!input.trim()} onClick={() => send(input)}>
                  ➤
                </button>
              )}
            </div>
            <div className="composer-hint">
              <kbd>Enter</kbd> 发送 · <kbd>Shift</kbd>+<kbd>Enter</kbd> 换行 · 回答由知识库检索生成，请结合现场核实
            </div>
          </div>
        </div>
      </section>

      <QAEvidence
        message={evMessage}
        activeCite={ev.cite}
        focusNonce={ev.nonce}
        tab={ev.tab}
        onTab={(t) => setEv((cur) => ({ ...cur, tab: t }))}
      />
    </div>
  );
}
