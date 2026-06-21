import { useEffect, useRef } from "react";
import type { HtmlReport } from "../types";

/** HTML 报告内嵌展示（真实路径：Baize + report_visualization 产出，后端已脱敏）。
 *  用沙箱 iframe 隔离报告自带样式/脚本，避免污染平台 UI；高度随内容自适应。 */
export default function HtmlReportView({ report }: { report: HtmlReport }) {
  const frameRef = useRef<HTMLIFrameElement>(null);
  const m = report.meta;

  const fit = () => {
    const f = frameRef.current;
    const doc = f?.contentDocument;
    if (f && doc?.body) f.style.height = `${doc.documentElement.scrollHeight || doc.body.scrollHeight}px`;
  };
  useEffect(() => {
    const t = setTimeout(fit, 60);
    return () => clearTimeout(t);
  }, [report.html]);

  const download = () => {
    const blob = new Blob([report.html], { type: "text/html;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `${m.id || "diagnosis-report"}.html`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <div className="card card-pad" style={{ marginBottom: 16 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 10 }}>
        <div className="hint">
          <b>诊断报告</b> · 编号 <span className="mono">{m.id}</span> · {m.level} · by {m.agent}
        </div>
        <button className="btn sm" onClick={download}>下载 HTML</button>
      </div>
      <iframe
        ref={frameRef}
        title="诊断报告"
        srcDoc={report.html}
        onLoad={fit}
        sandbox="allow-same-origin"
        style={{ width: "100%", border: "1px solid var(--line, #e2e8f0)", borderRadius: 10, background: "#fff" }}
      />
    </div>
  );
}
