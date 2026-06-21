import { useEffect, useRef } from "react";
import type { Citation, GraphSubview, QaMessage } from "../types";

/**
 * 证据面板（右栏，FR-003/FR-004）：引用来源卡片 + 检索图谱（内联 SVG）双 tab。
 * 点正文 [n] → activeCite 变化 → 对应来源卡片滚动定位 + flash 高亮；缺字段优雅降级（S-009）。
 * 复刻 openEuler-ops-qa.html 的 renderSources / renderGraph / focusSource。
 */

const BADGE_CLASS: Record<Citation["type"], string> = { doc: "b-doc", kb: "b-kb", inc: "b-inc", skill: "b-skill" };

function SourceCard({ s, active, refCb }: { s: Citation; active: boolean; refCb: (el: HTMLDivElement | null) => void }) {
  return (
    <div className={`src${active ? " flash" : ""}`} ref={refCb}>
      <div className="src-top">
        <div className="src-idx">{s.id}</div>
        <div className="src-hd">
          <span className={`src-badge ${BADGE_CLASS[s.type] ?? "b-kb"}`}>{s.badge}</span>
          <div className="src-title">{s.title}</div>
        </div>
      </div>
      {s.url && (
        <div className="src-origin">
          <span className="ic">⌖ 出处</span>
          <a href="#" onClick={(e) => e.preventDefault()}>
            {s.url}
          </a>
        </div>
      )}
      {s.excerpt && <div className="src-excerpt">{s.excerpt}</div>}
      {(s.entities.length > 0 || s.relations.length > 0) && (
        <div className="src-kg">
          <div className="kg-lab">关联实体 / 关系（来自知识图谱）</div>
          <div className="chips">
            {s.entities.map((e, i) => (
              <span key={`e${i}`} className="gchip ent">
                {e}
              </span>
            ))}
            {s.relations.map((r, i) => (
              <span key={`r${i}`} className="gchip rel">
                {r}
              </span>
            ))}
          </div>
        </div>
      )}
      <div className="src-foot">
        <a href="#" onClick={(e) => e.preventDefault()}>
          ↗ 打开原文
        </a>
        <span className="relevance">
          相关度 {s.rel}%
          <span className="relbar">
            <i style={{ width: `${s.rel}%` }} />
          </span>
        </span>
      </div>
    </div>
  );
}

function GraphView({ graph }: { graph: GraphSubview }) {
  const W = 360;
  const H = 330;
  const pos = new Map(graph.nodes.map((n) => [n.id, n]));
  return (
    <div className="graph-wrap">
      <div className="graph-cap">本次回答检索到的子图：实体（节点）经由关系（边）连接，回答正是沿这些路径组织而成。</div>
      <svg viewBox={`0 0 ${W} ${H}`} width="100%" style={{ display: "block" }}>
        {graph.edges.map((e, i) => {
          const a = pos.get(e.a);
          const b = pos.get(e.b);
          if (!a || !b) return null;
          const mx = (a.x + b.x) / 2;
          const my = (a.y + b.y) / 2;
          const w = e.l.length * 8.8 + 8;
          return (
            <g key={`edge${i}`}>
              <line x1={a.x} y1={a.y} x2={b.x} y2={b.y} stroke="#cfd8e2" strokeWidth={1.5} />
              <rect x={mx - e.l.length * 4.4 - 4} y={my - 9} width={w} height={16} rx={4} fill="#fff" stroke="#e6ebf1" />
              <text x={mx} y={my + 3} textAnchor="middle" fontSize={10} fill="#7659c4" className="mono">
                {e.l}
              </text>
            </g>
          );
        })}
        {graph.nodes.map((n, i) => {
          const fill = n.t === "core" ? "#0d8b80" : "#e6f0f9";
          const stroke = n.t === "core" ? "#0a6e65" : "#2f6fb0";
          const tcol = n.t === "core" ? "#fff" : "#2f6fb0";
          const w = n.id.length * 8 + 22;
          return (
            <g key={`node${i}`}>
              <rect x={n.x - w / 2} y={n.y - 13} width={w} height={26} rx={13} fill={fill} stroke={stroke} strokeWidth={1.5} />
              <text x={n.x} y={n.y + 4} textAnchor="middle" fontSize={11.5} fill={tcol} fontWeight={600}>
                {n.id}
              </text>
            </g>
          );
        })}
      </svg>
      <div className="graph-legend">
        <span>
          <i className="lg-dot" style={{ background: "#0d8b80" }} />
          问题核心
        </span>
        <span>
          <i className="lg-dot" style={{ background: "#9fc4ea" }} />
          实体
        </span>
        <span>
          <i className="lg-dot" style={{ background: "#7659c4" }} />
          关系
        </span>
      </div>
    </div>
  );
}

export default function QAEvidence({
  message,
  activeCite,
  focusNonce,
  tab,
  onTab,
}: {
  message: QaMessage | null;
  activeCite: number | null;
  /** 每次点击 [n] / 查看来源时递增，用于在重复点击同一角标时也重新定位。 */
  focusNonce: number;
  tab: "src" | "graph";
  onTab: (t: "src" | "graph") => void;
}) {
  const cardRefs = useRef(new Map<number, HTMLDivElement>());

  // 点 [n] → 定位并 flash 对应来源卡片（focusSource）
  useEffect(() => {
    if (activeCite == null || tab !== "src") return;
    const el = cardRefs.current.get(activeCite);
    if (el) el.scrollIntoView({ behavior: "smooth", block: "start" });
  }, [activeCite, focusNonce, tab]);

  const citations = message?.citations ?? [];
  const graph = message?.graph ?? null;

  return (
    <aside className="evidence">
      <div className="ev-head">
        <div className="ev-title">
          <span className="ic">◳</span> 引用与出处
          <span className="ct">{citations.length} 处来源</span>
        </div>
        <div className="ev-tabs">
          <button className={`ev-tab${tab === "src" ? " active" : ""}`} onClick={() => onTab("src")}>
            引用来源
          </button>
          <button className={`ev-tab${tab === "graph" ? " active" : ""}`} onClick={() => onTab("graph")}>
            检索图谱
          </button>
        </div>
      </div>
      <div className="ev-scroll">
        {tab === "src" ? (
          citations.length > 0 ? (
            citations.map((s) => (
              <SourceCard
                key={s.id}
                s={s}
                active={activeCite === s.id}
                refCb={(el) => {
                  if (el) cardRefs.current.set(s.id, el);
                  else cardRefs.current.delete(s.id);
                }}
              />
            ))
          ) : (
            <div className="ev-empty">
              <span className="ic">◳</span>
              选择一个问题或点击回答中的引用角标，
              <br />
              这里会显示对应的原文片段与出处链接。
            </div>
          )
        ) : graph ? (
          <GraphView graph={graph} />
        ) : (
          <div className="ev-empty">
            <span className="ic">◌</span>
            本次检索未返回知识图谱子图。
          </div>
        )}
      </div>
    </aside>
  );
}
