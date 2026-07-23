import { useEffect, useState } from "react";
import { listTasks } from "../api";
import { useStore } from "../store";
import type { Task } from "../types";
import { Pill, fmtTime } from "../util";
import { IconSearch, IconPlus } from "../icons";

export default function OpsList() {
  const { goWizard, goDetail } = useStore();
  const [tasks, setTasks] = useState<Task[]>([]);
  const [filter, setFilter] = useState<"all" | "online" | "offline">("all");
  const [q, setQ] = useState("");
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let alive = true;
    const load = () =>
      listTasks(filter)
        .then((t) => alive && setTasks(t))
        .catch(() => {})
        .finally(() => alive && setLoading(false));
    load();
    // 列表里有运行中任务时轮询刷新进度
    const iv = setInterval(load, 3000);
    return () => {
      alive = false;
      clearInterval(iv);
    };
  }, [filter]);

  const rows = tasks.filter((t) => !q || t.title.toLowerCase().includes(q.toLowerCase()) || t.id.includes(q));

  return (
    <>
      <div className="page-head">
        <div>
          <h1 className="t">故障运维</h1>
          <p className="d">以任务为单元创建诊断，后台执行、实时查看进度，完成后查看报告并评分。</p>
        </div>
        <button className="btn primary" onClick={goWizard}>
          <IconPlus /> 新建运维任务
        </button>
      </div>

      <div className="toolbar">
        <div className="search">
          <IconSearch />
          <input className="input" placeholder="搜索任务描述 / 任务 ID…" value={q} onChange={(e) => setQ(e.target.value)} />
        </div>
        <div className="seg">
          {(["all", "online", "offline"] as const).map((f) => (
            <button key={f} className={filter === f ? "on" : ""} onClick={() => setFilter(f)}>
              {f === "all" ? "全部" : f === "online" ? "在线" : "离线"}
            </button>
          ))}
        </div>
      </div>

      <div className="card">
        {loading ? (
          <div className="empty">
            <div className="spinner" style={{ margin: "0 auto" }} />
          </div>
        ) : rows.length === 0 ? (
          <div className="empty">
            <div className="ei">🗂️</div>
            还没有诊断任务，点击右上角「新建运维任务」开始。
          </div>
        ) : (
          <div className="tlist">
            {rows.map((t) => (
              <div className="trow" key={t.id} onClick={() => goDetail(t.id)}>
                <div className="col-main">
                  <div className="tt">{t.title}</div>
                  <div className="tm">
                    <span className={`tag ${t.mode}`}>{t.mode === "online" ? "在线" : "离线"}</span>
                    <span className="mono">{t.id.slice(0, 8)}</span>
                    <span>·</span>
                    <span>{t.mode === "online" ? t.target?.hostIp : (t.files || []).map((f) => f.filename).join(", ")}</span>
                    <span>·</span>
                    <span>{fmtTime(t.createdAt)}</span>
                  </div>
                </div>
                {(t.status === "running" || t.status === "queued") && (
                  <div className="mini-prog">
                    <i style={{ width: `${t.progress}%` }} />
                  </div>
                )}
                <Pill status={t.status} />
                <button className="btn sm" onClick={(e) => { e.stopPropagation(); goDetail(t.id); }}>
                  查看 →
                </button>
              </div>
            ))}
          </div>
        )}
      </div>
    </>
  );
}
