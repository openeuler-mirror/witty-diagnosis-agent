import { useRef, useState } from "react";
import { connectivityTest, createTask, uploadLog } from "../api";
import { useStore } from "../store";
import type { OfflineFile, TaskMode } from "../types";
import { fmtSize } from "../util";
import { IconFile } from "../icons";
import FaultTimePicker from "../components/FaultTimePicker";

export default function NewTaskWizard() {
  const { goList, goDetail, toast } = useStore();
  const [desc, setDesc] = useState("");
  const [faultTime, setFaultTime] = useState("2026-06-10 01:30");
  const [mode, setMode] = useState<TaskMode>("online");

  // online
  const [ip, setIp] = useState("192.168.10.21");
  const [port, setPort] = useState("22");
  const [acc, setAcc] = useState("root");
  const [pwd, setPwd] = useState("");
  const [connState, setConnState] = useState<"none" | "testing" | "ok" | "fail">("none");
  const [connReason, setConnReason] = useState("");

  // offline
  const [offlineSource, setOfflineSource] = useState<"upload" | "path">("upload");
  const [logPath, setLogPath] = useState("");
  const [files, setFiles] = useState<OfflineFile[]>([]);
  const [uploading, setUploading] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);

  const [submitting, setSubmitting] = useState(false);

  const switchMode = (m: TaskMode) => {
    setMode(m);
    setConnState("none");
  };

  const testConn = async () => {
    if (!ip || !acc || !pwd) {
      toast("请填写主机 IP / 账号 / 密码");
      return;
    }
    setConnState("testing");
    try {
      const r = await connectivityTest({ hostIp: ip, sshUser: acc, sshPassword: pwd, sshPort: Number(port) || 22 });
      if (r.ok) {
        setConnState("ok");
        toast("连通成功，可开始诊断");
      } else {
        setConnState("fail");
        setConnReason(r.reason || "连接失败");
      }
    } catch (e) {
      setConnState("fail");
      setConnReason(e instanceof Error ? e.message : "连接失败");
    }
  };

  const onPickFiles = async (list: FileList | null) => {
    if (!list || list.length === 0) return;
    setUploading(true);
    try {
      for (const f of Array.from(list)) {
        const dto = await uploadLog(f);
        setFiles((prev) => [...prev, dto]);
      }
    } catch (e) {
      toast(e instanceof Error ? e.message : "上传失败");
    } finally {
      setUploading(false);
      if (fileRef.current) fileRef.current.value = "";
    }
  };

  const removeFile = (id: string) => setFiles((prev) => prev.filter((f) => f.id !== id));

  const offlineReady = offlineSource === "upload" ? files.length > 0 : logPath.trim().length > 0;

  const start = async () => {
    if (!desc.trim()) {
      toast("请填写故障现象");
      return;
    }
    setSubmitting(true);
    try {
      const body =
        mode === "online"
          ? {
              title: desc.trim(),
              faultTime,
              mode,
              hostIp: ip,
              sshUser: acc,
              sshPassword: pwd,
              sshPort: Number(port) || 22,
              connectivityVerified: connState === "ok",
            }
          : {
              title: desc.trim(),
              faultTime,
              mode,
              uploadIds: offlineSource === "upload" ? files.map((f) => f.id) : [],
              logPath: offlineSource === "path" ? logPath.trim() : undefined,
            };
      const { taskId } = await createTask(body);
      toast("任务已创建，开始后台诊断");
      goDetail(taskId);
    } catch (e) {
      toast(e instanceof Error ? e.message : "创建失败");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <>
      <div className="page-head">
        <div>
          <h1 className="t">新建运维任务</h1>
          <p className="d">填写故障信息，选择在线或离线方式进行诊断。</p>
        </div>
        <button className="btn ghost" onClick={goList}>
          ← 返回列表
        </button>
      </div>

      <div className="card card-pad" style={{ marginBottom: 16 }}>
        <div className="field-row">
          <label className="req">任务描述（故障现象）</label>
          <textarea
            className="input"
            placeholder="例如：02:14 起 Nginx 大量返回 502，前端下单失败…"
            value={desc}
            onChange={(e) => setDesc(e.target.value)}
          />
        </div>
        <div className="grid2">
          <div className="field-row">
            <label className="req">运维类型</label>
            <div className="seg">
              <button className={mode === "online" ? "on" : ""} onClick={() => switchMode("online")}>
                在线诊断
              </button>
              <button className={mode === "offline" ? "on" : ""} onClick={() => switchMode("offline")}>
                离线分析
              </button>
            </div>
            <div className="hint">{mode === "online" ? "连接目标主机自动采集数据" : "上传已有日志进行分析"}</div>
          </div>
          <div className="field-row">
            <label className="req">故障时间</label>
            <FaultTimePicker value={faultTime} onChange={setFaultTime} />
            <div className="hint">点击选择日历时间点 / 时间段，或选「不确定」由日志 / 模型自行判断</div>
          </div>
        </div>
      </div>

      <div className="card card-pad">
        {mode === "online" ? (
          <>
            <h4 style={{ margin: "0 0 14px", fontSize: 14 }}>在线诊断 · 目标主机</h4>
            <div className="grid2">
              <div className="field-row">
                <label className="req">主机 IP</label>
                <input className="input mono" value={ip} onChange={(e) => { setIp(e.target.value); setConnState("none"); }} />
              </div>
              <div className="field-row">
                <label>SSH 端口</label>
                <input className="input mono" value={port} onChange={(e) => setPort(e.target.value)} />
              </div>
              <div className="field-row">
                <label className="req">账号</label>
                <input className="input mono" value={acc} onChange={(e) => { setAcc(e.target.value); setConnState("none"); }} />
              </div>
              <div className="field-row">
                <label className="req">密码</label>
                <input
                  className="input"
                  type="password"
                  placeholder="SSH 登录口令"
                  value={pwd}
                  onChange={(e) => { setPwd(e.target.value); setConnState("none"); }}
                />
              </div>
            </div>
            <div style={{ display: "flex", alignItems: "center", gap: 12, marginTop: 4 }}>
              <button className="btn" onClick={testConn} disabled={connState === "testing"}>
                {connState === "testing" ? "测试中…" : "测试连通性"}
              </button>
              <div className="conn-result">
                {connState === "ok" && (
                  <>
                    <span className="pill ok">连通成功</span>
                    <span style={{ color: "var(--text-2)" }}>已可执行诊断</span>
                  </>
                )}
                {connState === "fail" && (
                  <>
                    <span className="pill fail">连接失败</span>
                    <span style={{ color: "var(--text-2)" }}>{connReason}</span>
                  </>
                )}
              </div>
            </div>
            <div className="hint" style={{ marginTop: 14 }}>
              凭据将加密存储，报告与日志中自动脱敏。仅本次使用，不保存。
            </div>
            <div style={{ marginTop: 18, borderTop: "1px solid var(--border-2)", paddingTop: 16, display: "flex", gap: 10, alignItems: "center" }}>
              <button className="btn primary" onClick={start} disabled={connState !== "ok" || submitting}>
                开始诊断
              </button>
              <span className="hint" style={{ margin: 0 }}>
                {connState === "ok" ? "后台将自动采集数据并分析" : "请先测试连通性，通过后方可开始"}
              </span>
            </div>
          </>
        ) : (
          <>
            <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 14, flexWrap: "wrap", gap: 10 }}>
              <h4 style={{ margin: 0, fontSize: 14 }}>离线分析 · 日志来源</h4>
              <div className="seg">
                <button type="button" className={offlineSource === "upload" ? "on" : ""} onClick={() => setOfflineSource("upload")}>
                  上传文件
                </button>
                <button type="button" className={offlineSource === "path" ? "on" : ""} onClick={() => setOfflineSource("path")}>
                  服务器路径
                </button>
              </div>
            </div>

            {offlineSource === "upload" ? (
              <>
                <input
                  ref={fileRef}
                  type="file"
                  multiple
                  accept=".log,.tar.gz,.zip"
                  style={{ display: "none" }}
                  onChange={(e) => onPickFiles(e.target.files)}
                />
                <div className="dropzone" onClick={() => fileRef.current?.click()}>
                  <div style={{ fontSize: 22 }}>📄</div>
                  <div style={{ marginTop: 8, fontWeight: 600 }}>{uploading ? "上传中…" : "点击此处添加日志文件"}</div>
                  <div className="hint">支持 .log / .tar.gz / .zip，可多选</div>
                </div>
                {files.length > 0 && (
                  <div className="filelist">
                    {files.map((f) => (
                      <div className="fileitem" key={f.id}>
                        <IconFile />
                        <span className="mono">{f.filename}</span>
                        <span className="hint" style={{ margin: 0 }}>{fmtSize(f.size)}</span>
                        <span className="x" onClick={() => removeFile(f.id)}>✕</span>
                      </div>
                    ))}
                  </div>
                )}
              </>
            ) : (
              <div className="field-row" style={{ marginBottom: 0 }}>
                <label>服务器日志路径</label>
                <input
                  className="input mono"
                  placeholder="例如：/var/log/diagnose/case-01/ 或 /var/log/messages"
                  value={logPath}
                  onChange={(e) => setLogPath(e.target.value)}
                />
                <div className="hint">
                  将日志放到后端服务器可访问的路径下（文件或目录均可），由后端就地读取，无需上传。后端会校验路径是否存在。
                </div>
              </div>
            )}

            <div style={{ marginTop: 18, borderTop: "1px solid var(--border-2)", paddingTop: 16, display: "flex", gap: 10, alignItems: "center" }}>
              <button className="btn primary" onClick={start} disabled={!offlineReady || submitting}>
                开始分析
              </button>
              <span className="hint" style={{ margin: 0 }}>
                {offlineReady
                  ? "后台将解析日志并定位故障"
                  : offlineSource === "upload"
                    ? "请先添加至少一个日志文件"
                    : "请填写服务器日志路径"}
              </span>
            </div>
          </>
        )}
      </div>
    </>
  );
}
