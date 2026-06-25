
/** 过滤 agent 内部思考噪音，仅保留有信息量的诊断日志。 */
function isNoiseLine(line: string): boolean {
  const t = line.trim();
  if (t.length < 5) return true;
  if (/^[\d.:\-\s]+$/.test(t)) return true;
  const lower = t.toLowerCase();
  const noise = [
    "let me", "i need", "i should", "i will", "i can", "i must", "i want",
    "i think", "i have", "actually,", "however,", "but the", "but i",
    "now let", "so let", "ok, let", "the user", "the skill",
    "the system", "the task", "the workflow", "the rule",
    "i'll", "i'm thinking", "let's start", "now i",
    "note:", "wait,", "first,", "second,", "third,",
  ];
  for (const p of noise) {
    if (lower.startsWith(p)) return true;
  }
  return false;
}

/**
 * 故障运维诊断 · opencode 事件 → 任务域事件 合成器（真实路径专用，零外部依赖、可单测）。
 *
 * opencode 无原生「进度%」信号（02 §D-002），只能由宿主把粗粒度的工具调用 / 子代理阶段 /
 * 文本叙述事件映射为阶段与日志。Xuanyuan 在 identity-constraints 中被强制**逐阶段叙述**
 * （“首先调用 Fuxi…”“调用 Dayu 编排…”“Baize 根因分析…”“RCA报告路径：…”），因此本合成器
 * 以「工具事件 + 文本关键词」双途径推断阶段，阶段只增不减（单调推进）。
 *
 * 完成信号不由本合成器给出：opencode 的 session.idle 在每轮子会话边界都会触发、不可靠
 * （02 §D-002）。本合成器只负责在文本里**捕获报告路径关键词**写入 state.reportPath，
 * 由 opencode-driver 在流结束后做「解析路径 + 校验 baize/reports/*.html」的双信号判定与读取。
 */

import { STAGE_ORDER, STAGE_PROGRESS, type Stage, type TaskDriverEvent, type OpencodeEventPayload } from "./types.js";

/** 报告路径关键词（与 xuanyuan/identity-constraints.ts:41 约定一致）。 */
export const REPORT_PATH_MARKERS = ["RCA报告路径：", "报告已写入："] as const;

/** 阶段关键词 → 阶段。命中即把阶段推进到不低于该阶段（forward-only）。 */
const STAGE_KEYWORDS: { stage: Stage; words: string[] }[] = [
  // 文本关键词只保留最基础的「数据采集」阶段，用于 agent 开场白后即推进。
  // 「数据分析」「故障定位」「生成报告」全部依赖工具调用事件推进
  // （SUBAGENT_STAGE / TOOL_STAGE），避免计划文本中包含的 agent 名导致过早跳阶段。
  { stage: "数据采集", words: ["fuxi", "伏羲", "诊断计划", "计划构建", "排查方案"] },
];

/** 工具名 → 触达的阶段（部分工具能直接标定阶段）。 */
const TOOL_STAGE: Record<string, Stage> = {
  report_visualization: "生成报告",
};

/** 子代理类型 → 触达的阶段（比文本关键词更可靠，避免计划文本误匹配）。 */
const SUBAGENT_STAGE: Record<string, Stage> = {
  "fuxi-sub": "数据采集",
  "dayu": "数据分析",
  "baize": "故障定位",
};

export interface TaskSynthState {
  /** 当前阶段在 STAGE_ORDER 中的下标（forward-only）。 */
  stageIndex: number;
  /** 跨 token 累积的文本行缓冲（按行 flush 成日志，并用于关键词探测）。 */
  lineBuf: string;
  /** 捕获到的报告文件路径（供 driver 做完成判定与读取）。 */
  reportPath: string | null;
}

export function initTaskSynthState(): TaskSynthState {
  // 起点为「排队中」，使首个「数据采集」阶段也能作为一次切换被吐出。
  return { stageIndex: STAGE_ORDER.indexOf("排队中"), lineBuf: "", reportPath: null };
}

export interface ReduceResult {
  state: TaskSynthState;
  emits: TaskDriverEvent[];
}

/** 把阶段推进到目标（forward-only），命中则追加一个 stage 事件。 */
function advanceTo(state: TaskSynthState, stage: Stage, emits: TaskDriverEvent[]): void {
  const idx = STAGE_ORDER.indexOf(stage);
  if (idx > state.stageIndex) {
    state.stageIndex = idx;
    emits.push({ type: "stage", stage, progress: STAGE_PROGRESS[stage] });
  }
}

/** 在一段文本里探测阶段关键词与报告路径，必要时推进阶段、记录 reportPath。 */
function scanText(state: TaskSynthState, text: string, emits: TaskDriverEvent[]): void {
  const lower = text.toLowerCase();
  for (const { stage, words } of STAGE_KEYWORDS) {
    if (words.some((w) => lower.includes(w))) advanceTo(state, stage, emits);
  }
  for (const marker of REPORT_PATH_MARKERS) {
    const at = text.indexOf(marker);
    if (at >= 0) {
      const tail = text.slice(at + marker.length).trim();
      const m = tail.match(/^[^\s"'，。；）)]+/);
      if (m && m[0]) state.reportPath = m[0];
    }
  }
}

/** 累积文本增量并按行 flush 成日志；不足一行的暂存 lineBuf。 */
function pushTextDelta(state: TaskSynthState, delta: string, emits: TaskDriverEvent[]): void {
  state.lineBuf += delta;
  // 在「未 flush 的整段缓冲」上探测：阶段关键词与报告路径关键词都可能跨多个 token 增量到达
  scanText(state, state.lineBuf, emits);
  let nl: number;
  while ((nl = state.lineBuf.indexOf("\n")) >= 0) {
    const line = state.lineBuf.slice(0, nl).trim();
    state.lineBuf = state.lineBuf.slice(nl + 1);
    if (line && !isNoiseLine(line)) emits.push({ type: "log", text: line });
  }
}

/**
 * 消费一个 opencode 事件，返回更新后的 state 与若干任务域事件。
 * 仅处理本模块关心的三类：文本增量、工具部件更新、（忽略其余）。
 */
export function reduceTaskEvent(state: TaskSynthState, ev: OpencodeEventPayload): ReduceResult {
  const emits: TaskDriverEvent[] = [];
  const p = ev.properties ?? {};

  // 文本增量（xuanyuan 主会话叙述）：cli/run/types.ts 的 message.part.delta，field:"text"
  if (ev.type === "message.part.delta" && p.field === "text" && typeof p.delta === "string") {
    pushTextDelta(state, p.delta, emits);
    return { state, emits };
  }

  // 工具部件更新：message.part.updated，part.type==="tool"
  if (ev.type === "message.part.updated" && p.part?.type === "tool") {
    const tool = (p.part.tool || p.part.name || "tool").toString();
    const status = p.part.state?.status;
    const toolStage = TOOL_STAGE[tool.toLowerCase()];
    if (toolStage) advanceTo(state, toolStage, emits);

    if (status === "running") {
      // 子代理调用（task 工具）尽量带出 subagent_type 便于观察执行流
      const sub = p.part.state?.input?.subagent_type;
      const label = tool === "task" && typeof sub === "string" ? `子代理 ${sub}` : `工具 ${tool}`;
      emits.push({ type: "log", text: `▶ 调用${label}…` });
      // 子代理类型直接推阶段（比文本关键词更可靠）
      if (typeof sub === "string") {
        const subStage = SUBAGENT_STAGE[sub.toLowerCase()];
        if (subStage) advanceTo(state, subStage, emits);
      }
    } else if (status === "completed") {
      const out = p.part.state?.output;
      if (typeof out === "string" && out) {
        scanText(state, out, emits);
        // 捕获 report_visualization 工具产出的 HTML 路径
        // 其输出格式为: "Successfully converted to HTML: /path/to/file.html"
        if (tool.toLowerCase() === "report_visualization") {
          const htmlMatch = out.match(/Successfully converted to HTML:\s*(\S+\.html)/i);
          if (htmlMatch?.[1]) state.reportPath = htmlMatch[1];
        }
      }
      emits.push({ type: "log", text: `✓ ${tool} 完成` });
    } else if (status === "error") {
      const err = p.part.state?.error || "未知错误";
      emits.push({ type: "log", text: `✗ ${tool} 失败：${err}` });
    }
    return { state, emits };
  }

  return { state, emits };
}

/** 流结束时 flush 残留行缓冲（不足一行的最后一段叙述也要落成日志）。 */
export function flushTaskSynth(state: TaskSynthState): TaskDriverEvent[] {
  const emits: TaskDriverEvent[] = [];
  const rest = state.lineBuf.trim();
  state.lineBuf = "";
  if (rest && !isNoiseLine(rest)) emits.push({ type: "log", text: rest });
  return emits;
}
