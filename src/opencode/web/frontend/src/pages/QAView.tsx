import { useEffect, useRef, useState } from "react";
import { useStore } from "../store";
import {
  ApiError,
  createQaSession,
  deleteQaSession,
  listQaSessions,
  postQaMessage,
  putQaFeedback,
  renameQaSession,
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

// 与服务端 CONVERSATION_QUESTION_MAX_CHARS 保持一致
const MAX_CHARS = 4000;

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
  const [renamingId, setRenamingId] = useState<string | null>(null);
  const [renameText, setRenameText] = useState("");
  const [renaming, setRenaming] = useState(false); // 重命名请求中
  const [menuOpenId, setMenuOpenId] = useState<string | null>(null);
  const [menuPos, setMenuPos] = useState<{ x: number; y: number } | null>(null);

  const streamRef = useRef<HTMLDivElement>(null);
  const scrollRef = useRef(false); // 仅发送消息时滚动，AI 回复时不滚动
  const taRef = useRef<HTMLTextAreaElement>(null);
  const renameRef = useRef<HTMLInputElement>(null);
  // 追踪 send() 已创建但可能 SSE 先到的消息 ID，避免 upsert 静默丢弃
  const pendingMsgIds = useRef(new Set<string>());
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

    // upsert：消息已存在则更新，不存在但属于待发消息则创建
    const upsert = (id: string, patch: (m: QaMessage) => QaMessage) =>
      setMessages((prev) => {
        const i = prev.findIndex((m) => m.id === id);
        if (i === -1) {
          // SSE 先于 send() 的 setMessages 到达时，自动创建消息
          if (pendingMsgIds.current.has(id)) {
            pendingMsgIds.current.delete(id);
            return [...prev, patch(newAssistant(id, sessionId))];
          }
          return prev;
        }
        const next = prev.slice();
        next[i] = patch(next[i]);
        return next;
      });

    const close = streamQa(sessionId, (e: QaStreamEvent) => {
      switch (e.type) {
        case "qa_snapshot":
          setMessages(e.messages);
          scrollRef.current = true; // 打开历史会话时滚到底部
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
          refreshSessions();
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

  // ---- 自动滚动到底：发送消息 / 打开历史会话时触发 ----
  useEffect(() => {
    if (!scrollRef.current) return;
    scrollRef.current = false;
    const el = streamRef.current;
    if (el) requestAnimationFrame(() => (el.scrollTop = el.scrollHeight));
  }, [messages]);

  // 点击菜单外关闭下拉
  useEffect(() => {
    if (!menuOpenId) return;
    const handler = (e: MouseEvent) => {
      const target = e.target as HTMLElement;
      if (!target.closest(".qa-menu, .qa-edit-btn")) {
        setMenuOpenId(null);
        setMenuPos(null);
      }
    };
    document.addEventListener("mousedown", handler);
    return () => document.removeEventListener("mousedown", handler);
  }, [menuOpenId]);

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
      // 注册待发消息 ID，允许 upsert 在 SSE 先到时自动创建
      pendingMsgIds.current.add(userMessageId);
      pendingMsgIds.current.add(assistantMessageId);
      setBusy(true);
      scrollRef.current = true;
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

  // 失败/中断消息重试：找到最近一条 user 消息重新发送
  const onRetry = (assistantMessageId: string) => {
    const idx = messages.findIndex((m) => m.id === assistantMessageId);
    if (idx < 0) return;
    // 向前查找最近的 user 消息
    for (let i = idx - 1; i >= 0; i--) {
      if (messages[i].role === "user" && messages[i].text) {
        send(messages[i].text);
        return;
      }
    }
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
    setRenamingId(null);
    setMenuOpenId(null);
  };
  const startRename = (id: string, currentTitle: string) => {
    setRenamingId(id);
    setRenameText(currentTitle);
    setTimeout(() => renameRef.current?.focus(), 50);
  };
  const submitRename = async (id: string) => {
    const title = renameText.trim();
    if (!title || !id || renaming) {
      setRenamingId(null);
      return;
    }
    setRenaming(true);
    try {
      await renameQaSession(id, title);
      await refreshSessions();
      setRenamingId(null);
    } catch {
      toast("重命名失败");
      setRenamingId(null);
    } finally {
      setRenaming(false);
    }
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
            <div
              key={s.id}
              className={`qa-sitem${s.id === sessionId ? " active" : ""}`}
              onClick={() => selectSession(s.id)}
            >
              {renamingId === s.id ? (
                <input
                  ref={renameRef}
                  className="qa-rename-input"
                  value={renameText}
                  onChange={(e) => setRenameText(e.target.value)}
                  onBlur={() => submitRename(s.id)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") submitRename(s.id);
                    if (e.key === "Escape") setRenamingId(null);
                  }}
                  onClick={(e) => e.stopPropagation()}
                />
              ) : (
                <span className="qa-stitle">
                  {s.title || "新会话"}
                </span>
              )}
              <div className="qa-menu-wrap">
                <button className="qa-edit-btn" title="更多" onClick={(e) => {
                  e.stopPropagation();
                  if (menuOpenId === s.id) {
                    setMenuOpenId(null);
                    setMenuPos(null);
                  } else {
                    const rect = (e.currentTarget as HTMLElement).getBoundingClientRect();
                    setMenuPos({ x: rect.left, y: rect.bottom + 4 });
                    setMenuOpenId(s.id);
                  }
                }}>
                  ⋮
                </button>
                {menuOpenId === s.id && menuPos && (
                  <div className="qa-menu" style={{ left: menuPos.x, top: menuPos.y, position: "fixed" }}>
                    <button onClick={(e) => {
                      e.stopPropagation();
                      setMenuOpenId(null);
                      startRename(s.id, s.title);
                    }}>
                      <span className="mi">✎</span> 重命名
                    </button>
                    <button className="qa-menu-del" onClick={(e) => {
                      e.stopPropagation();
                      setMenuOpenId(null);
                      removeSession(s.id, e);
                    }}>
                      <span className="mi">✕</span> 删除
                    </button>
                  </div>
                )}
              </div>
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
              <QAMessage
                key={m.id}
                message={m}
                onCite={onCite}
                onShowSources={onShowSources}
                onFollowup={send}
                onFeedback={onFeedback}
                onRetry={onRetry}
              />
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
                maxLength={MAX_CHARS}
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
              <kbd>Enter</kbd> 发送 · <kbd>Shift</kbd>+<kbd>Enter</kbd> 换行
              <span className="char-counter">
                {input.length}/{MAX_CHARS}
              </span>
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
