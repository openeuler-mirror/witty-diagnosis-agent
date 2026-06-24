/**
 * mock 驱动用的诊断报告 HTML 生成（自包含样式，可独立打开/下载）。
 *
 * 真实路径下报告由 Baize + report_visualization 生成 .html，由 opencode-driver 直接采集；
 * 本模板仅供 mock 驱动产出形态一致的占位报告，让前端「HTML 内嵌展示」主链路可联调。
 */

import type { TaskDriverInput } from "./types.js";

function esc(s: string): string {
  return s.replace(/[&<>]/g, (m) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" })[m] as string);
}

export interface MockReportContent {
  reportNo: string;
  faultLevel: string;
  rootcause: string;
  impact: string;
  timeline: { time: string; text: string }[];
  remediation: string[];
}

/** 按在线/离线给出两套有代表性的占位结论。 */
function contentFor(input: TaskDriverInput, reportNo: string): MockReportContent {
  if (input.mode === "online") {
    return {
      reportNo,
      faultLevel: "P1 · 严重",
      rootcause:
        "上游应用进程句柄耗尽导致 Nginx 与后端建链失败，反向代理大量返回 <code>502 Bad Gateway</code>。",
      impact: "前端下单链路不可用，错误率峰值约 73%，持续约 11 分钟。",
      timeline: [
        { time: "02:14", text: "Nginx error.log 出现 connect() failed (111: Connection refused)" },
        { time: "02:15", text: "后端 app 进程 RSS 稳定但 fd 使用率冲高至 98%" },
        { time: "02:21", text: "重启 app 进程后 502 恢复，错误率回落至 0.2%" },
      ],
      remediation: [
        "【立即】对受影响后端实例滚动重启，释放泄漏句柄，恢复服务。",
        "【根治】定位未关闭的连接/文件句柄（核对连接池 maxIdle 与 close 逻辑）。",
        "【预防】为 fd 使用率加监控告警（阈值 80%），并提高 systemd LimitNOFILE。",
      ],
    };
  }
  return {
    reportNo,
    faultLevel: "P2 · 重要",
    rootcause: "节点内存压力触发 OOM Killer，关键服务进程被终止，引发级联超时。",
    impact: "目标服务在故障窗口内不可用，相关请求超时；节点其余进程一度抖动。",
    timeline: [
      { time: "—", text: "dmesg 出现 Out of memory: Killed process (oom_score_adj 命中)" },
      { time: "—", text: "服务进程被 SIGKILL 终止，监控探活失败" },
      { time: "—", text: "进程被 supervisor 拉起后恢复，但根因仍在" },
    ],
    remediation: [
      "【立即】确认服务已恢复，检查是否存在残留半启动状态。",
      "【根治】排查内存泄漏/突发大对象；为容器设置合理 requests/limits。",
      "【预防】配置内存水位告警与 OOM 事件采集，避免静默被杀。",
    ],
  };
}

export function buildMockReportHtml(input: TaskDriverInput, reportNo: string): { html: string; faultLevel: string } {
  const c = contentFor(input, reportNo);
  const reportTime = new Date(input.faultTime || Date.now()).toString() === "Invalid Date" ? input.faultTime : input.faultTime;
  const target = input.mode === "online" ? esc(input.online?.hostIp ?? "—") : esc((input.offline?.logPaths ?? []).join(", ") || "离线日志");

  const html = `<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8">
<title>故障诊断报告 ${esc(c.reportNo)}</title>
<style>
body{font-family:Georgia,"Noto Serif SC",serif;max-width:880px;margin:36px auto;padding:0 24px;color:#1b2430;line-height:1.7}
h1{font-size:24px;border-bottom:2.5px solid #1b2430;padding-bottom:12px}
h2{font-size:19px;margin-top:30px}
.meta{background:#eef4fb;border-radius:10px;padding:14px 18px;margin:18px 0;font-family:sans-serif;font-size:13px}
.meta div{margin:3px 0}
.tone{border-radius:9px;padding:12px 15px;margin:12px 0;font-family:sans-serif;font-size:14px;background:#fbe9e9}
.ok{background:#e6f5ec}
ul,ol{padding-left:22px}
li{margin:6px 0}
code{background:#fbe9e9;color:#c0392b;padding:1px 6px;border-radius:4px;font-family:monospace;font-size:12px}
table{width:100%;border-collapse:collapse;margin:10px 0;font-family:sans-serif;font-size:13px}
th,td{border:1px solid #e2e8f0;padding:8px 11px;text-align:left}
.by{color:#5b6b7b;font-family:sans-serif;font-size:13px}
</style></head><body>
<h1>故障诊断报告</h1>
<div class="meta">
<div><b>报告编号：</b>${esc(c.reportNo)}</div>
<div><b>故障级别：</b>${esc(c.faultLevel)}</div>
<div><b>故障现象：</b>${esc(input.title)}</div>
<div><b>故障时间：</b>${esc(reportTime)}</div>
<div><b>诊断对象：</b>${target}（${input.mode === "online" ? "在线诊断" : "离线分析"}）</div>
<div class="by"><b>by</b> Xuanyuan · 全链路智能运维（mock 驱动）</div>
</div>

<h2>一、根因结论</h2>
<div class="tone">${c.rootcause}</div>

<h2>二、影响范围</h2>
<p>${esc(c.impact)}</p>

<h2>三、故障时间线</h2>
<table><thead><tr><th style="width:90px">时间</th><th>事件</th></tr></thead><tbody>
${c.timeline.map((t) => `<tr><td><code>${esc(t.time)}</code></td><td>${esc(t.text)}</td></tr>`).join("")}
</tbody></table>

<h2>四、处置建议</h2>
<ol>${c.remediation.map((r) => `<li>${esc(r)}</li>`).join("")}</ol>

<div class="tone ok">本报告由 mock 驱动生成，用于联调「执行流程 + 报告内嵌展示」主链路。配置真实模型并设 <code>TASK_DRIVER=opencode</code> 后，将由 Xuanyuan→Fuxi→Dayu→Kuafu→Baize 全链路产出真实 RCA 报告。</div>
</body></html>`;

  return { html, faultLevel: c.faultLevel };
}
