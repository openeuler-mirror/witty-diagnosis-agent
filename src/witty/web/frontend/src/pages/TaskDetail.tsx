import { useEffect, useRef, useState } from "react";
import { cancelTask, deleteTask, getReport, getTask, rateTask, retryTask, streamTask } from "../api";
import { useStore } from "../store";
import { STAGES, type ReportPayload, type TaskDetail as TaskDetailT } from "../types";
import { Pill, fmtTime } from "../util";
import ReportView from "../report/ReportView";
import HtmlReportView from "../report/HtmlReportView";
import { downloadReportHtml } from "../report/downloadHtml";

export default function TaskDetail({
  taskId,
  onBack,
  onOpen,
}: {
  taskId: string;
  onBack: () => void;
  onOpen: (id: string) => void;
}) {
  void onOpen;
  const toast = useStore((s) => s.toast);
  const [task, setTask] = useState<TaskDetailT | null>(null);
  const [logs, setLogs] = useState<{ time: string; text: string }[]>([]);
  const [report, setReport] = useState<ReportPayload | null>(null);
  const [logOpen, setLogOpen] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const logBoxRef = useRef<HTMLDivElement>(null);

  // 初次加载
  useEffect(() => {
    let alive = true;
    getTask(taskId)
      .then((t) => {
        if (!alive) return;
        setTask(t);
        setLogs(t.logs);
      })
      .catch(() => alive && setNotFound(true));
    return () => {
      alive = false;
    };
  }, [taskId]);

  // SSE 订阅进度/日志
  useEffect(() => {
    const stop = streamTask(taskId, (e) => {
      if (e.type === "snapshot") {
        setLogs(e.logs);
        setTask((t) => (t ? { ...t, status: e.status, progress: e.progress, currentStage: e.stage } : t));
      } else if (e.type === "progress") {
        setTask((t) => (t ? { ...t, status: e.status, progress: e.progress, currentStage: e.stage } : t));
      } else if (e.type === "log") {
        setLogs((prev) => [...prev, { time: e.time, text: e.text }]);
      } else if (e.type === "done") {
        setTask((t) => (t ? { ...t, status: e.status } : t));
        if (e.status === "succeeded") getReport(taskId).then(setReport).catch(() => {});
        else getTask(taskId).then((t) => { setTask(t); setLogs(t.logs); }).catch(() => {});
      }
    });
    return stop;
  }, [taskId]);

  // 已完成任务首次进入时拉报告
  useEffect(() => {
    if (task?.status === "succeeded" && task.hasReport && !report) {
      getReport(taskId).then(setReport).catch(() => {});
    }
  }, [task?.status, task?.hasReport, report, taskId]);

  // 日志自动滚到底
  useEffect(() => {
    if (logBoxRef.current) logBoxRef.current.scrollTop = logBoxRef.current.scrollHeight;
  }, [logs, logOpen]);

  if (notFound) {
    return (
      <>
        <div className="page-head">
          <h1 className="t">任务不存在或无权访问</h1>
          <button className="btn ghost" onClick={onBack}>← 返回列表</button>
        </div>
        <div className="card card-pad">
          <div className="callout" style={{ background: "var(--danger-soft)", borderColor: "#f0cccc", color: "#7a2020" }}>
            该任务不存在，或不属于当前用户（任务按用户隔离）。
          </div>
        </div>
      </>
    );
  }

  if (!task) {
    return (
      <div className="empty">
        <div className="spinner" style={{ margin: "0 auto" }} />
      </div>
    );
  }

  const onCancel = async () => {
    await cancelTask(taskId).catch(() => {});
    toast("已请求取消任务");
  };
  const onRetry = async () => {
    await retryTask(taskId).catch((e) => toast(e?.message || "重试失败"));
    setReport(null);
    toast("已重新入队");
  };
  const onDelete = async () => {
    try {
      await deleteTask(taskId);
      toast("任务已删除");
      onBack();
    } catch (e) {
      toast(e instanceof Error ? e.message : "删除失败");
    }
  };

  const curIdx = task.status === "succeeded" ? 5 : STAGES.indexOf((task.currentStage as (typeof STAGES)[number]) || "排队中");

  return (
    <>
      <div className="page-head">
        <div>
          <h1 className="t">{task.title}</h1>
          <p className="d">
            <span className={`tag ${task.mode}`}>{task.mode === "online" ? "在线" : "离线"}</span>{" "}
            <span className="mono">{task.id.slice(0, 8)}</span> ·{" "}
            {task.mode === "online" ? task.target?.hostIp : (task.files || []).map((f) => f.filename).join(", ")} ·{" "}
            {fmtTime(task.createdAt)} &nbsp; <Pill status={task.status} />
          </p>
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          {task.status !== "running" && (
            <button className="btn danger sm" onClick={onDelete}>删除</button>
          )}
          <button className="btn ghost" onClick={onBack}>← 返回列表</button>
        </div>
      </div>

      {task.status === "failed" ? (
        <div className="card card-pad">
          <div className="callout" style={{ background: "var(--danger-soft)", borderColor: "#f0cccc", color: "#7a2020" }}>
            <b>诊断失败</b>
            <br />
            {task.failReason || "执行过程中发生错误。"}
          </div>
          <div style={{ marginTop: 14, display: "flex", gap: 10 }}>
            <button className="btn" onClick={onRetry}>重试</button>
            <button className="btn primary" onClick={() => useStore.getState().goWizard()}>改为离线分析</button>
          </div>
        </div>
      ) : task.status === "canceled" ? (
        <div className="card card-pad">
          <div className="callout">任务已取消。{task.failReason}</div>
          <div style={{ marginTop: 14 }}>
            <button className="btn" onClick={onRetry}>重试</button>
          </div>
        </div>
      ) : (
        <>
          {/* 进度块 */}
          <div className="card card-pad" style={{ marginBottom: 16 }}>
            <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", marginBottom: 6 }}>
              <h4 style={{ margin: 0, fontSize: 14 }}>执行进度</h4>
              {task.status === "running" && (
                <button className="btn sm danger" onClick={onCancel}>取消任务</button>
              )}
            </div>
            <div className="stepper">
              {STAGES.map((s, i) => {
                let cls = "";
                if (i < curIdx) cls = "done";
                else if (i === curIdx && task.status === "running") cls = "active";
                else if (task.status === "succeeded") cls = "done";
                const check = i < curIdx || task.status === "succeeded";
                return (
                  <div className={`step ${cls}`} key={s}>
                    <div className="line" />
                    <div className="bub">{check ? "✓" : i + 1}</div>
                    <div className="lbl">{s}</div>
                  </div>
                );
              })}
            </div>
            <div className="prog-bar">
              <i style={{ width: `${task.progress}%` }} />
            </div>
            {logs.length > 0 && (
              <>
                <button className="collapser" onClick={() => setLogOpen((v) => !v)}>
                  {logOpen ? "▾" : "▸"} 实时日志（{logs.length}）
                </button>
                {logOpen && (
                  <div className="logbox" ref={logBoxRef}>
                    {logs.map((l, i) => (
                      <div key={i}>
                        <span className="t-time">{l.time}</span> {l.text}
                      </div>
                    ))}
                  </div>
                )}
              </>
            )}
          </div>

          {/* 报告 + 评分（完成态） */}
          {task.status === "succeeded" && report && (
            <>
              {"html" in report ? (
                <HtmlReportView report={report} />
              ) : (
                <ReportView report={report} onDownload={() => downloadReportHtml(report)} />
              )}
              <RatingBlock taskId={taskId} initial={task.rating || 0} />
            </>
          )}
        </>
      )}
    </>
  );
}

function RatingBlock({ taskId, initial }: { taskId: string; initial: number }) {
  const toast = useStore((s) => s.toast);
  const [stars, setStars] = useState(initial);
  const [hover, setHover] = useState(0);
  const [note, setNote] = useState("");
  const [tags, setTags] = useState<Set<string>>(new Set());
  const tagOptions = ["定位准确", "建议可执行", "已解决问题", "需进一步分析"];

  const submit = async () => {
    if (stars < 1) {
      toast("请先选择星级");
      return;
    }
    try {
      const fullNote = [Array.from(tags).join("、"), note].filter(Boolean).join(" | ");
      await rateTask(taskId, stars, fullNote);
      toast("评分已提交，感谢反馈");
    } catch (e) {
      toast(e instanceof Error ? e.message : "提交失败");
    }
  };

  return (
    <div className="card card-pad" style={{ marginBottom: 16 }}>
      <h4 style={{ margin: "0 0 4px", fontSize: 14 }}>结果评分</h4>
      <p className="hint" style={{ margin: "0 0 12px" }}>结果是否符合预期、是否解决了您的问题？</p>
      <div className="stars" onMouseLeave={() => setHover(0)}>
        {[1, 2, 3, 4, 5].map((i) => (
          <span
            key={i}
            className={`star${i <= (hover || stars) ? " on" : ""}`}
            onMouseEnter={() => setHover(i)}
            onClick={() => setStars(i)}
          >
            ★
          </span>
        ))}
      </div>
      <div className="rate-tags">
        {tagOptions.map((t) => (
          <span
            key={t}
            className={`chip${tags.has(t) ? " sel" : ""}`}
            onClick={() =>
              setTags((prev) => {
                const next = new Set(prev);
                next.has(t) ? next.delete(t) : next.add(t);
                return next;
              })
            }
          >
            {t}
          </span>
        ))}
      </div>
      <textarea
        className="input"
        placeholder="补充说明（可选）"
        style={{ minHeight: 54 }}
        value={note}
        onChange={(e) => setNote(e.target.value)}
      />
      <div style={{ marginTop: 10 }}>
        <button className="btn primary sm" onClick={submit}>提交评分</button>
        {initial > 0 && <span className="hint" style={{ marginLeft: 10 }}>当前评分：{initial} 星</span>}
      </div>
    </div>
  );
}
