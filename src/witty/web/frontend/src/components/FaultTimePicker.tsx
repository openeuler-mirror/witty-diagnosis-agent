import { useState } from "react";

/**
 * 故障时间选择器（DC-002：支持具体时间点 / 时间段 / 不确定时间段）。
 * - 时间点 / 时间段：原生 datetime-local 触发日历选择
 * - 不确定：预置「根据日志判断 / 由模型自行判断」等选项，或自定义说明
 * 最终向父组件输出一个自由文本 faultTime（语义由后端/模型判断）。
 */

type Mode = "point" | "range" | "uncertain";

const UNCERTAIN_PRESETS = [
  "不确定时间段，请根据日志自行判断",
  "不确定时间段，由模型自行判断",
  "最近一段时间内偶发，无明确时间点",
];

// "2026-06-10 01:30" <-> datetime-local "2026-06-10T01:30"
const toLocal = (s: string) => (s && /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}/.test(s) ? s.slice(0, 16).replace(" ", "T") : "");
const fromLocal = (s: string) => (s ? s.replace("T", " ") : "");

export default function FaultTimePicker({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  const [mode, setMode] = useState<Mode>("point");
  const [point, setPoint] = useState(toLocal(value) || "2026-06-10T01:30");
  const [start, setStart] = useState(toLocal(value) || "2026-06-10T01:30");
  const [end, setEnd] = useState("2026-06-10T02:00");
  const [uncertain, setUncertain] = useState(UNCERTAIN_PRESETS[0]);
  const [custom, setCustom] = useState("");

  const switchMode = (m: Mode) => {
    setMode(m);
    if (m === "point") onChange(fromLocal(point));
    else if (m === "range") onChange(`${fromLocal(start)} ~ ${fromLocal(end)}`);
    else onChange(custom.trim() || uncertain);
  };

  return (
    <div>
      <div className="seg" style={{ marginBottom: 10 }}>
        <button type="button" className={mode === "point" ? "on" : ""} onClick={() => switchMode("point")}>
          时间点
        </button>
        <button type="button" className={mode === "range" ? "on" : ""} onClick={() => switchMode("range")}>
          时间段
        </button>
        <button type="button" className={mode === "uncertain" ? "on" : ""} onClick={() => switchMode("uncertain")}>
          不确定
        </button>
      </div>

      {mode === "point" && (
        <input
          type="datetime-local"
          className="input"
          value={point}
          onChange={(e) => {
            setPoint(e.target.value);
            onChange(fromLocal(e.target.value));
          }}
        />
      )}

      {mode === "range" && (
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <input
            type="datetime-local"
            className="input"
            value={start}
            onChange={(e) => {
              setStart(e.target.value);
              onChange(`${fromLocal(e.target.value)} ~ ${fromLocal(end)}`);
            }}
          />
          <span style={{ color: "var(--text-3)" }}>至</span>
          <input
            type="datetime-local"
            className="input"
            value={end}
            onChange={(e) => {
              setEnd(e.target.value);
              onChange(`${fromLocal(start)} ~ ${fromLocal(e.target.value)}`);
            }}
          />
        </div>
      )}

      {mode === "uncertain" && (
        <>
          <select
            className="input"
            value={uncertain}
            onChange={(e) => {
              setUncertain(e.target.value);
              if (!custom.trim()) onChange(e.target.value);
            }}
          >
            {UNCERTAIN_PRESETS.map((p) => (
              <option key={p} value={p}>
                {p}
              </option>
            ))}
          </select>
          <input
            className="input"
            style={{ marginTop: 8 }}
            placeholder="或自定义说明（可选），例如：昨晚业务高峰前后"
            value={custom}
            onChange={(e) => {
              setCustom(e.target.value);
              onChange(e.target.value.trim() || uncertain);
            }}
          />
        </>
      )}
    </div>
  );
}
