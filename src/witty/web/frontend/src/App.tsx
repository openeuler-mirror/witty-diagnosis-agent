import { useEffect, useState } from "react";
import { useStore } from "./store";
import { me, logout, listTasks, qaCapabilities } from "./api";
import Login from "./pages/Login";
import OpsList from "./pages/OpsList";
import NewTaskWizard from "./pages/NewTaskWizard";
import TaskDetail from "./pages/TaskDetail";
import QAView from "./pages/QAView";
import Toast from "./components/Toast";
import { IconGrid, IconLogout, IconChat } from "./icons";

export default function App() {
  const { user, authChecked, view, qaEnabled, setUser, setAuthChecked, setQaEnabled, goList, goDetail, goQA } = useStore();
  const toast = useStore((s) => s.toast);
  const [runningCount, setRunningCount] = useState(0);

  // 启动时校验会话
  useEffect(() => {
    me()
      .then(setUser)
      .catch(() => setUser(null))
      .finally(() => setAuthChecked(true));
  }, [setUser, setAuthChecked]);

  // 能力探测：决定是否显示「已知问题查询」导航（FR-011 / DQ-003）
  useEffect(() => {
    if (!user) return;
    qaCapabilities()
      .then((c) => setQaEnabled(c.qa))
      .catch(() => setQaEnabled(false));
  }, [user, setQaEnabled]);

  // 轮询运行中任务数（用于顶栏徽标）
  useEffect(() => {
    if (!user) return;
    let alive = true;
    const refresh = () =>
      listTasks("all")
        .then((ts) => alive && setRunningCount(ts.filter((t) => t.status === "running" || t.status === "queued").length))
        .catch(() => {});
    refresh();
    const iv = setInterval(refresh, 4000);
    return () => {
      alive = false;
      clearInterval(iv);
    };
  }, [user, view]);

  if (!authChecked) {
    return (
      <div style={{ height: "100%", display: "grid", placeItems: "center" }}>
        <div className="spinner" />
      </div>
    );
  }

  if (!user) return <Login />;

  const doLogout = async () => {
    await logout().catch(() => {});
    setUser(null);
    toast("已退出登录");
  };

  const isQa = view.name === "qa";
  const title = isQa ? "已知问题查询" : "故障运维";
  const crumb = view.name === "wizard" ? "新建任务" : view.name === "detail" ? view.taskId : "";

  return (
    <div className="app">
      <aside className="sidebar">
        <div className="brand">
          <div className="logo">eU</div>
          <div className="brand-name">智能诊断平台</div>
        </div>
        <nav className="nav">
          <div className="nav-group">工作台</div>
          <button className={`nav-item${!isQa ? " active" : ""}`} onClick={goList}>
            <IconGrid />
            故障运维
            {runningCount > 0 && <span className="count">{runningCount}</span>}
          </button>
          {qaEnabled && (
            <button className={`nav-item${isQa ? " active" : ""}`} onClick={() => goQA()}>
              <IconChat />
              已知问题查询
            </button>
          )}
        </nav>
        <div className="side-foot">
          <div className="user-chip">
            <div className="avatar">{user.displayName[0]?.toUpperCase()}</div>
            <div className="meta">
              <b>{user.displayName}</b>
              <br />
              <span>已登录 · 数据隔离</span>
            </div>
          </div>
          <button className="nav-item" style={{ marginTop: 4 }} onClick={doLogout}>
            <IconLogout />
            退出登录
          </button>
        </div>
      </aside>

      <div className="main">
        <header className="topbar">
          <h2>{title}</h2>
          <span className="crumb">{crumb ? "/ " + crumb : isQa ? "/ 基于知识图谱的检索增强问答" : ""}</span>
          <div className="right">
            {!isQa && (
              <div className="run-badge">
                <span className={`dot${runningCount ? " run" : ""}`} />
                <span>{runningCount ? `${runningCount} 个任务进行中` : "无运行中任务"}</span>
              </div>
            )}
          </div>
        </header>
        {isQa ? (
          <div className="content qa-content">
            <QAView key={view.sessionId ?? "new"} />
          </div>
        ) : (
          <div className="content">
            <div className="wrap">
              {view.name === "list" && <OpsList />}
              {view.name === "wizard" && <NewTaskWizard />}
              {view.name === "detail" && <TaskDetail key={view.taskId} taskId={view.taskId} onBack={goList} onOpen={goDetail} />}
            </div>
          </div>
        )}
      </div>
      <Toast />
    </div>
  );
}
