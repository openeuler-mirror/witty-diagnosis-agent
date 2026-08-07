import type { Report, ReportBlock } from "../types";

/** RCA 报告渲染（文档风格 + 目录），结构与原型 reportBlock/renderRcaBlock 一致。
 *  html 字段为后端生成且已脱敏的可信内容，这里以 dangerouslySetInnerHTML 渲染富文本片段。 */

function dot(color: Report["meta"]["dot"]): string {
  return color === "red" ? "var(--danger)" : color === "green" ? "var(--ok)" : "var(--warn)";
}

function Block({ b }: { b: ReportBlock }) {
  switch (b.t) {
    case "kv":
      return (
        <table className="rca-tab">
          <tbody>
            {b.rows.map((r, i) => (
              <tr key={i}>
                <td className="k">{r[0]}</td>
                <td dangerouslySetInnerHTML={{ __html: r[1] }} />
              </tr>
            ))}
          </tbody>
        </table>
      );
    case "table":
      return (
        <table className="rca-tab">
          <thead>
            <tr>{b.head.map((h, i) => <th key={i}>{h}</th>)}</tr>
          </thead>
          <tbody>
            {b.rows.map((r, i) => (
              <tr key={i}>{r.map((c, j) => <td key={j} dangerouslySetInnerHTML={{ __html: c }} />)}</tr>
            ))}
          </tbody>
        </table>
      );
    case "p":
      return <p dangerouslySetInnerHTML={{ __html: b.html }} />;
    case "ul":
      return <ul>{b.items.map((i, k) => <li key={k} dangerouslySetInnerHTML={{ __html: i }} />)}</ul>;
    case "ol":
      return <ol>{b.items.map((i, k) => <li key={k} dangerouslySetInnerHTML={{ __html: i }} />)}</ol>;
    case "code":
      return <pre className="snippet">{b.text}</pre>;
    case "tone":
      return <div className={`tone ${b.tone}`} dangerouslySetInnerHTML={{ __html: b.html }} />;
    case "chain":
      return (
        <div className="chain">
          {b.nodes.map((n, i) => (
            <span key={i} style={{ display: "contents" }}>
              {i > 0 && <span className="arr">→</span>}
              <span className={`node${n.bad ? " bad" : ""}`}>{n.text}</span>
            </span>
          ))}
        </div>
      );
    case "timeline":
      return (
        <div className="tl">
          {b.items.map((i, k) => (
            <div className="ti" key={k}>
              <div className="tt">{i.time}</div>
              <div className="td">{i.text}</div>
            </div>
          ))}
        </div>
      );
    case "sub":
      return (
        <div className="rca-sub" id={b.id}>
          <div className="subh">{b.title}</div>
          {b.blocks.map((bb, k) => <Block key={k} b={bb} />)}
        </div>
      );
    default:
      return null;
  }
}

export default function ReportView({ report, onDownload }: { report: Report; onDownload: () => void }) {
  const m = report.meta;
  const color = dot(m.dot);
  const scrollTo = (id: string) => document.getElementById(id)?.scrollIntoView({ behavior: "smooth", block: "start" });

  return (
    <div className="card card-pad" style={{ marginBottom: 16 }}>
      <div style={{ display: "flex", justifyContent: "flex-end", gap: 8, marginBottom: 10 }}>
        <button className="btn sm" onClick={onDownload}>下载 HTML</button>
      </div>
      <div className="rca">
        <nav className="rca-toc">
          <div className="toc-h">目录</div>
          <a className="lv1 first" onClick={() => scrollTo("rca-top")}>
            <span className="tdot" style={{ background: color }} />
            故障诊断报告
          </a>
          {report.sections.map((s) => (
            <span key={s.id} style={{ display: "contents" }}>
              <a className="lv1" onClick={() => scrollTo(s.id)}>{s.label}</a>
              {s.subs.map((su) => (
                <a key={su.id} className="lv2" onClick={() => scrollTo(su.id)}>{su.label}</a>
              ))}
            </span>
          ))}
        </nav>

        <div className="rca-body" id="rca-top">
          <div className="rca-title">
            <h2>
              <span className="bigdot" style={{ background: color }} />
              故障诊断报告
            </h2>
            <div className="by">
              by <b>{m.agent}</b>
            </div>
          </div>
          <div className="rca-meta">
            <div className="row">
              <span className="mk">报告编号：</span>
              <span className="mono">{m.id}</span>
            </div>
            <div className="row">
              <span className="mk">故障级别：</span>
              {m.level}
            </div>
            <div className="row">
              <span className="mk">报告时间：</span>
              {m.time}
            </div>
            <div className="row">
              <span className="mk">当前状态：</span>
              <span
                className="bigdot"
                style={{ display: "inline-block", width: 11, height: 11, verticalAlign: "middle", marginRight: 6, background: color }}
              />
              {m.status}
            </div>
          </div>

          {report.sections.map((s) => (
            <div className="rca-sec" id={s.id} key={s.id}>
              <div className="sh">
                <span className="ey">{s.ey}</span>
                <h3>{s.label}</h3>
              </div>
              {s.blocks.map((b, k) => <Block key={k} b={b} />)}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
