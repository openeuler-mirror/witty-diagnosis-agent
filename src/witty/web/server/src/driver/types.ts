/**
 * 故障运维诊断（Xuanyuan）模块 · 驱动层契约。
 *
 * 「驱动」负责把一次诊断任务（在线/离线）跑成一条 **任务域事件流**（阶段 / 日志 / 报告），
 * 供 web/server 的 runner 消费：落库执行记录、脱敏、SSE 推送、保存报告。两种实现：
 *  - mock-driver：本期默认。不起 opencode/LLM，用确定性的阶段时序模拟整条流水线，
 *    跑通「新建→执行→实时进度/日志→看报告」主链路，便于未配置模型时联调。
 *  - opencode-driver（真实路径，对应设计 02 §D-001/D-002）：每任务 createOpencode + 重定向
 *    HOME/XDG 隔离 + session.promptAsync({ agent:"xuanyuan", tools:{question:false} }) +
 *    event.subscribe；把 opencode 事件流经 ./event-synthesizer 合成为本契约的任务域事件，
 *    双信号判定完成（解析报告路径关键词 + 校验 baize/reports/*.html）。
 *    依赖 @opencode-ai/sdk，**不被 web/server 编译路径静态 import**（见 ./index.ts）。
 *
 * 本文件零外部依赖，供 web/server 直接 import（仅类型 + 工厂入口在 ./index.ts）。
 */

/** 进度阶段标签（与前端 stepper / server STAGES 一致）。 */
export const STAGE_ORDER = ["排队中", "计划构建", "数据采集", "根因分析", "报告生成", "完成"] as const;
export type Stage = (typeof STAGE_ORDER)[number];

/** 每个阶段对应的进度百分比（单调递增，与 stepper 节点对齐）。 */
export const STAGE_PROGRESS: Record<Stage, number> = {
  排队中: 5,
  计划构建: 25,
  数据采集: 45,
  根因分析: 65,
  报告生成: 85,
  完成: 100,
};

/**
 * 任务域事件（驱动 → runner）。runner 只认这三类，与驱动是 mock 还是真实 opencode 无关。
 *  - stage：阶段切换（含进度百分比）。
 *  - log：一行实时日志（runner 落库前会脱敏）。
 *  - report：最终诊断报告 HTML（runner 落库前会脱敏；前端内嵌展示）。
 */
export type TaskDriverEvent =
  | { type: "stage"; stage: Stage; progress: number }
  | { type: "log"; text: string }
  | { type: "report"; html: string; reportNo?: string; faultLevel?: string };

/** 在线诊断目标主机（含密码：真实驱动需注入首条 prompt 供 Kuafu SSH；runner 侧负责脱敏）。 */
export interface TaskOnlineTarget {
  hostIp: string;
  sshUser: string;
  sshPort: number;
  sshPassword: string;
}

export interface TaskDriverInput {
  taskId: string;
  /** 故障现象（任务描述）。 */
  title: string;
  /** 故障时间（自由文本）。 */
  faultTime: string;
  mode: "online" | "offline";
  /** 在线诊断目标主机（mode==="online" 时存在）。 */
  online?: TaskOnlineTarget;
  /** 离线分析日志来源绝对路径（上传文件落盘路径或服务器路径，mode==="offline" 时存在）。 */
  offline?: { logPaths: string[] };
  /** 每任务专属 HOME（真实驱动重定向 HOME/XDG_* 至此实现进程级隔离，BC-011/D-001）。 */
  taskHome: string;
  /** 停止生成 / 超时中止。 */
  signal: AbortSignal;
  /**
   * opencode 服务就绪回调：驱动创建 opencode server 后触发，
   * 将 server.close() 暴露给调用方（runner），
   * 用于取消时定点关闭该任务进程，而非全局 pkill。
   */
  onServerReady?: (close: () => void) => void;
}

export interface TaskDriver {
  /** 执行一次诊断，产出任务域事件流。Generator 结束即进入终态（成功/失败由是否产出 report 判定）。 */
  run(input: TaskDriverInput): AsyncGenerator<TaskDriverEvent, void, unknown>;
}

// ---------- 真实 opencode 路径专用：事件最小载荷形状 ----------

/**
 * opencode 事件流的最小载荷形状（仅取本模块所需字段；与 cli/run/types.ts 同源）。
 * 仅 opencode-driver / event-synthesizer 使用；mock-driver 不涉及。
 */
export interface OpencodeEventPayload {
  type: string;
  properties?: {
    field?: string;
    delta?: string;
    part?: {
      type?: string;
      tool?: string;
      name?: string;
      text?: string;
      state?: {
        status?: string;
        output?: string;
        error?: string;
        title?: string;
        input?: Record<string, unknown>;
      };
    };
    info?: Record<string, unknown>;
    [k: string]: unknown;
  };
}
