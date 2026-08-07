import { useState } from "react";
import { login } from "../api";
import { useStore } from "../store";

export default function Login() {
  const setUser = useStore((s) => s.setUser);
  const toast = useStore((s) => s.toast);
  const [username, setUsername] = useState("ops.zhang@demo.io");
  const [password, setPassword] = useState("demo1234");
  const [busy, setBusy] = useState(false);

  const submit = async () => {
    setBusy(true);
    try {
      const u = await login(username, password);
      setUser(u);
      toast("已登录：" + u.displayName);
    } catch {
      toast("登录失败，请重试");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="login">
      <div className="login-card">
        <div className="brand">
          <div className="logo">eU</div>
          <div className="brand-name">openEuler 智能诊断平台</div>
        </div>
        <h1>登录</h1>
        <p className="sub">使用您的账号进入工作台。任务与报告仅本人可见。</p>
        <div className="field">
          <label>账号 / 邮箱</label>
          <input className="input" value={username} onChange={(e) => setUsername(e.target.value)} />
        </div>
        <div className="field">
          <label>密码</label>
          <input
            className="input"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && submit()}
          />
        </div>
        <button
          className="btn primary"
          style={{ width: "100%", justifyContent: "center", marginTop: 6 }}
          disabled={busy}
          onClick={submit}
        >
          {busy ? "登录中…" : "登录"}
        </button>
        <div className="login-hint">演示账号已预填，直接点「登录」即可体验（dev 占位认证，生产对接统一认证）</div>
      </div>
    </div>
  );
}
