import { useEffect, useRef, useState, useCallback } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import type { Citation, GraphSubview, QaMessage } from "../types";

/**
 * 证据面板（右栏，FR-003/FR-004）：引用来源卡片 + 检索图谱（内联 SVG）双 tab。
 * 点正文 [n] → activeCite 变化 → 对应来源卡片滚动定位 + flash 高亮；缺字段优雅降级（S-009）。
 * 复刻 openEuler-ops-qa.html 的 renderSources / renderGraph / focusSource。
 */

const BADGE_CLASS: Record<Citation["type"], string> = { doc: "b-doc", kb: "b-kb", inc: "b-inc", skill: "b-skill" };

/** 判断是否为可点击的 HTTP URL */
function isHttpUrl(url: string): boolean {
  return /^https?:\/\//i.test(url);
}

/** 根据 URL 扩展名判断摘录用 Markdown 还是纯文本渲染。仅 .md 系列走 Markdown，其余一律纯文本。 */
function getSourceFormat(s: Citation): "markdown" | "plain" {
  const url = (s.url || "").split("?")[0].split("#")[0].toLowerCase();
  const lastDot = url.lastIndexOf(".");
  if (lastDot !== -1) {
    const ext = url.slice(lastDot);
    if ([".md", ".markdown", ".mdown"].includes(ext)) return "markdown";
  }
  return "plain";
}


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
      {s.url && isHttpUrl(s.url) ? (
        <div className="src-origin">
          <span className="ic">⌖ 出处</span>
          <a href={s.url} target="_blank" rel="noopener noreferrer">
            {s.url}
          </a>
        </div>
      ) : s.url ? (
        <div className="src-origin">
          <span className="ic">⌖ 出处</span>
          <span>{s.url}</span>
        </div>
      ) : null}
      {s.excerpt && (
        <div className="src-excerpt">
          {getSourceFormat(s) === "markdown" ? (
            <ReactMarkdown remarkPlugins={[remarkGfm]}
              components={{
                img: ({ alt }) => <span className="src-img-alt">[图片: {alt || "未命名"}]</span>,
              }}
            >{s.excerpt.replace(/<[^>]+>/g, "")}</ReactMarkdown>
          ) : (
            <span>{s.excerpt}</span>
          )}
        </div>
      )}
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
        {s.url && isHttpUrl(s.url) ? (
          <a href={s.url} target="_blank" rel="noopener noreferrer">
            ↗ 打开原文
          </a>
        ) : (
          <span />
        )}
      </div>
    </div>
  );
}

function GraphView({ graph }: { graph: GraphSubview }) {
  const W = 400;
  const H = 360;
  const [scale, setScale] = useState(1);
  const [translate, setTranslate] = useState({ x: 0, y: 0 });
  const [tooltip, setTooltip] = useState<{ x: number; y: number; content: string } | null>(null);
  const [nodePositions, setNodePositions] = useState<Map<string, { x: number; y: number }>>(
    new Map(graph.nodes.map((n) => [n.id, { x: n.x, y: n.y }]))
  );
  const [isDragging, setIsDragging] = useState(false);
  const [dragType, setDragType] = useState<"node" | "canvas" | null>(null);
  const [dragState, setDragState] = useState<{
    nodeId?: string;
    startClientX: number;
    startClientY: number;
    startX: number;
    startY: number;
    offsetX: number;
    offsetY: number;
    startTranslateX: number;
    startTranslateY: number;
  } | null>(null);
  const svgRef = useRef<SVGSVGElement>(null);


  const handleWheel = useCallback((e: React.WheelEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.stopPropagation();
    const rect = (e.currentTarget as HTMLElement).getBoundingClientRect();
    const cursorX = e.clientX - rect.left;
    const cursorY = e.clientY - rect.top;
    setScale((prev) => {
      const delta = e.deltaY > 0 ? -0.15 : 0.15;
      const newS = Math.max(0.3, Math.min(3.0, prev + delta));
      if (newS !== prev) {
        // 缩放到鼠标位置：保持光标下的图形位置不变
        const graphX = (cursorX - translate.x) / prev;
        const graphY = (cursorY - translate.y) / prev;
        setTranslate({
          x: cursorX - graphX * newS,
          y: cursorY - graphY * newS,
        });
      }
      return newS;
    });
  }, [translate]);

  const toSvgCoords = useCallback((clientX: number, clientY: number) => {
    if (!svgRef.current) return { x: 0, y: 0 };
    const point = svgRef.current.createSVGPoint();
    point.x = clientX;
    point.y = clientY;
    const matrix = svgRef.current.getScreenCTM()?.inverse();
    if (!matrix) return { x: 0, y: 0 };
    const svgPoint = point.matrixTransform(matrix);
    return { x: svgPoint.x, y: svgPoint.y };
  }, []);

  const handleMouseMove = useCallback((e: MouseEvent) => {
    if (isDragging && dragState) {
      const cur = toSvgCoords(e.clientX, e.clientY);
      const s = scale;
      if (dragType === "node" && dragState.nodeId) {
        setNodePositions((prev) => {
          const newPositions = new Map(prev);
          newPositions.set(dragState.nodeId!, {
            x: (cur.x - (dragState.offsetX ?? 0)) / s,
            y: (cur.y - (dragState.offsetY ?? 0)) / s,
          });
          return newPositions;
        });
      } else if (dragType === "canvas") {
        // translate 在 scale 之后应用，视觉位移 = translate 增量（不受 scale 影响）
        setTranslate({
          x: dragState.startTranslateX + (e.clientX - dragState.startClientX),
          y: dragState.startTranslateY + (e.clientY - dragState.startClientY),
        });
      }
      return;
    }
    if (tooltip && svgRef.current) {
      const { x, y } = toSvgCoords(e.clientX, e.clientY);
      setTooltip((prev) => prev ? { x, y, content: prev.content } : null);
    }
  }, [isDragging, dragState, dragType, tooltip, toSvgCoords, scale]);

  const handleMouseUp = useCallback(() => {
    setIsDragging(false);
    setDragType(null);
    setDragState(null);
  }, []);

  const handleNodeMouseDown = useCallback((e: React.MouseEvent, nodeId: string) => {
    e.preventDefault();
    e.stopPropagation();
    const svgPos = toSvgCoords(e.clientX, e.clientY);
    const nodePos = nodePositions.get(nodeId) ?? { x: 0, y: 0 };
    setIsDragging(true);
    setDragType("node");
    setDragState({
      nodeId,
      startClientX: e.clientX,
      startClientY: e.clientY,
      startX: nodePos.x,
      startY: nodePos.y,
      offsetX: svgPos.x - nodePos.x * scale,
      offsetY: svgPos.y - nodePos.y * scale,
      startTranslateX: translate.x,
      startTranslateY: translate.y,
    });
    setTooltip(null);
  }, [nodePositions, toSvgCoords, translate.x, translate.y, scale]);

  const handleCanvasMouseDown = useCallback((e: React.MouseEvent) => {
    const target = e.target as Element;
    if (e.target === svgRef.current || target.tagName === "svg" || (target.tagName === "rect" && !target.classList.contains("graph-node"))) {
      e.preventDefault();
      setIsDragging(true);
      setDragType("canvas");
      setDragState({
        startClientX: e.clientX,
        startClientY: e.clientY,
        startX: translate.x,
        startY: translate.y,
        offsetX: 0,
        offsetY: 0,
        startTranslateX: translate.x,
        startTranslateY: translate.y,
      });
      setTooltip(null);
    }
  }, [toSvgCoords, translate.x, translate.y]);

  const handleNodeHover = useCallback((e: React.MouseEvent, content: string) => {
    if (isDragging) return;
    const { x, y } = toSvgCoords(e.clientX, e.clientY);
    setTooltip({ x, y, content });
  }, [isDragging, toSvgCoords]);

  const handleNodeLeave = useCallback(() => {
    if (!isDragging) {
      setTooltip(null);
    }
  }, [isDragging]);

  const handleReset = useCallback(() => {
    setScale(1);
    setTranslate({ x: 0, y: 0 });
    setNodePositions(new Map(graph.nodes.map((n) => [n.id, { x: n.x, y: n.y }])));
  }, [graph.nodes]);

  useEffect(() => {
    if (isDragging) {
      document.addEventListener("mousemove", handleMouseMove);
      document.addEventListener("mouseup", handleMouseUp);
      return () => {
        document.removeEventListener("mousemove", handleMouseMove);
        document.removeEventListener("mouseup", handleMouseUp);
      };
    }
  }, [isDragging, handleMouseMove, handleMouseUp]);

  const MAX_NODE_WIDTH = 120;
  const NODE_LINE_HEIGHT = 14;
  const REL_MAX_WIDTH = 100;
  const REL_LINE_HEIGHT = 12;

  const getNodeLayout = (text: string) => {
    const maxChars = Math.floor(MAX_NODE_WIDTH / 7);
    const lines: string[] = [];
    let currentLine = "";
    const chars = text.split("");
    for (const char of chars) {
      if ((currentLine + char).length > maxChars) {
        lines.push(currentLine);
        currentLine = char;
      } else {
        currentLine += char;
      }
    }
    if (currentLine) lines.push(currentLine);
    const height = Math.max(26, lines.length * NODE_LINE_HEIGHT + 8);
    return { lines, height };
  };

  const getRelationLayout = (text: string) => {
    const maxChars = Math.floor(REL_MAX_WIDTH / 6);
    const lines: string[] = [];
    let currentLine = "";
    const chars = text.split("");
    for (const char of chars) {
      if ((currentLine + char).length > maxChars) {
        lines.push(currentLine);
        currentLine = char;
      } else {
        currentLine += char;
      }
    }
    if (currentLine) lines.push(currentLine);
    return { lines, height: lines.length * REL_LINE_HEIGHT + 8, width: Math.min(text.length * 6 + 12, REL_MAX_WIDTH) };
  };

  const getOffsetPoint = (a: { x: number; y: number }, b: { x: number; y: number }, offset: number) => {
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const len = Math.sqrt(dx * dx + dy * dy);
    if (len === 0) return { x: a.x, y: a.y };
    const nx = dx / len;
    const ny = dy / len;
    return { x: a.x + nx * offset, y: a.y + ny * offset };
  };

  return (
    <div className="graph-wrap">
      <div className="graph-cap">本次回答检索到的子图：实体（节点）经由关系（边）连接，回答正是沿这些路径组织而成。</div>
      <div className="graph-controls">
        <button onClick={() => setScale((s) => Math.max(0.3, s - 0.2))} title="缩小">−</button>
        <span>{Math.round(scale * 100)}%</span>
        <button onClick={() => setScale((s) => Math.min(3.0, s + 0.2))} title="放大">+</button>
        <button onClick={handleReset} title="重置视图">⟲</button>
      </div>
      <div className="graph-scroll" onWheel={handleWheel}>
        <svg ref={svgRef} viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="xMidYMid meet"
          style={{ display: "block", width: "100%", height: "100%", cursor: dragType === "canvas" ? "grabbing" : "grab" }}
          onMouseDown={handleCanvasMouseDown}>
          <g style={{ transform: `translate(${translate.x}px, ${translate.y}px) scale(${scale})`, transformOrigin: "center center", transition: dragType ? "none" : "transform 0.15s ease-out" }}>
            {graph.edges.map((e, i) => {
              const aPos = nodePositions.get(e.a);
              const bPos = nodePositions.get(e.b);
              if (!aPos || !bPos) return null;
              const a = { ...aPos, id: e.a };
              const b = { ...bPos, id: e.b };
              const aLayout = getNodeLayout(a.id);
              const bLayout = getNodeLayout(b.id);
              const aOffset = getOffsetPoint(a, b, aLayout.height / 2 + 8);
              const bOffset = getOffsetPoint(b, a, bLayout.height / 2 + 8);
              const mx = (aOffset.x + bOffset.x) / 2;
              const my = (aOffset.y + bOffset.y) / 2;
              const { lines: relLines, height: relHeight, width: relWidth } = getRelationLayout(e.l);
              return (
                <g key={`edge${i}`}>
                  <line x1={aOffset.x} y1={aOffset.y} x2={bOffset.x} y2={bOffset.y} stroke="#cfd8e2" strokeWidth={1.5} />
                  <rect x={mx - relWidth / 2} y={my - relHeight / 2} width={relWidth} height={relHeight} rx={4} fill="#fff" stroke="#e6ebf1" />
                  {relLines.map((line, j) => (
                    <text key={`rel${j}`} x={mx} y={my - relHeight / 2 + 9 + j * REL_LINE_HEIGHT} textAnchor="middle" fontSize={9} fill="#7659c4" className="mono">
                      {line}
                    </text>
                  ))}
                </g>
              );
            })}
            {graph.nodes.map((n, i) => {
              const fill = n.t === "core" ? "#0d8b80" : "#e6f0f9";
              const stroke = n.t === "core" ? "#0a6e65" : "#2f6fb0";
              const tcol = n.t === "core" ? "#fff" : "#2f6fb0";
              const pos = nodePositions.get(n.id) || { x: n.x, y: n.y };
              const { lines, height } = getNodeLayout(n.id);
              const width = Math.min(n.id.length * 7 + 20, MAX_NODE_WIDTH);
              return (
                <g key={`node${i}`} className="graph-node"
                  onMouseDown={(e) => handleNodeMouseDown(e, n.id)}
                  onMouseEnter={(e) => handleNodeHover(e, n.id)}
                  onMouseLeave={handleNodeLeave}
                  style={{ cursor: isDragging && dragType === "node" ? "grabbing" : "pointer" }}>
                  <rect x={pos.x - width / 2} y={pos.y - height / 2} width={width} height={height} rx={13} fill={fill} stroke={stroke} strokeWidth={isDragging && dragType === "node" ? 2.5 : 1.5} />
                  {lines.map((line, j) => (
                    <text key={`line${j}`} x={pos.x} y={pos.y - height / 2 + 11 + j * NODE_LINE_HEIGHT} textAnchor="middle" fontSize={10} fill={tcol} fontWeight={500}>
                      {line}
                    </text>
                  ))}
                </g>
              );
            })}
          </g>
          {tooltip && (
            <g style={{ transform: `translate(${translate.x}px, ${translate.y}px) scale(${scale})`, transformOrigin: "center center" }}>
              <rect x={tooltip.x + 12} y={tooltip.y - 18} width={Math.max(tooltip.content.length * 7 + 24, 90)} height={34} rx={6} fill="rgba(0,0,0,0.85)" />
              <text x={tooltip.x + 22} y={tooltip.y + 2} fontSize={12} fill="#fff" className="mono">
                {tooltip.content}
              </text>
            </g>
          )}
        </svg>
      </div>
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
        <span className="graph-hint">拖动节点/画布 · 滚轮缩放</span>
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
  // 只显示正文中实际引用的来源（安全校验：仅匹配 citations 范围内的 ID）
  const maxCiteId = (message?.citations ?? []).reduce((max, c) => Math.max(max, c.id), 0);
  const citedIds = new Set<number>();
  if (message?.text && maxCiteId > 0) {
    for (const m of message.text.matchAll(/\[(\d+)\]/g)) {
      const id = Number(m[1]);
      if (id >= 1 && id <= maxCiteId) citedIds.add(id);
    }
  }
  const citations = (message?.citations ?? []).filter((c) => (citedIds.size === 0 && message?.status === "generating") || citedIds.has(c.id));
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
