# 🔴 故障诊断报告

> **报告编号**：RCA-20260608-001
> **故障级别**：P2（Major）
> **报告时间**：2026-06-08 02:52:00 UTC
> **当前状态**：🔴 处理中

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | NFS 客户端 rpc.statd 进程被 kill 导致锁服务 NLM 不可用 |
| 影响范围 | NFS 客户端节点（主机），所有依赖 NFS 文件锁的应用程序 |
| 故障时段 | 2026-06-08 02:52:00 UTC ～ 至今（持续中） |
| 根本原因 | rpc.statd 进程被 `pkill -9` 强制终止，导致 NFS 锁服务（NLM）完全不可用，rpcbind 随同一同终止 |
| 是否恢复 | ❌ 未恢复 |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|--------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | 诊断数据明确显示 rpc.statd 被 kill → rpcbind 终止 → lockd 模块未加载 → 所有现象可被唯一解释 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                         事件                                                        性质           溯源路径
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-06-08 02:52:00          rpc.statd 进程被 pkill -9 强制终止                              🔴 人为/恶意触发  [kuafu_T1_20260608_branchD.md:4-6]
  │
  ▼
2026-06-08 02:52:00 (瞬时)    rpcbind 进程随 statd 一同终止                                    🔴 连带效应      [kuafu_T1_20260608_branchD.md:14-15]
  │                           （systemd socket 激活机制未触发重启）
  ▼
2026-06-08 02:52:00 (瞬时)    statd / nlockmgr 从 rpcinfo 注册表中消失                          ⚠️ 服务注销      [kuafu_T1_20260608_branchD.md:19-21]
  │
  ▼
2026-06-08 02:52:00 (瞬时)    内核 lockd 模块未加载（依赖用户态 statd 注册回调）                  ⚠️ 功能降级      [kuafu_T1_20260608_branchD.md:15-16]
  │                            lockd 无法处理 NLM 请求
  ▼
2026-06-08 02:52:00 (持续)    文件锁状态: /proc/locks 无 NFS 条目，nfsstat 锁统计为空            🟡 证据确认      [kuafu_T1_20260608_branchD.md:23-25]
  │
  ▼
2026-06-08 02:52:00 (持续)    NFS 挂载仍正常（v3 123 calls, v4 209 calls）                     ✅ 部分正常     [kuafu_T1_20260608_branchD.md:31-33]
  │                            数据路径无影响，但锁操作将全面失败
  ▼
2026-06-08 02:52:00 (持续)    任何应用尝试获取 NFS 文件锁（fcntl/flock）将返回失败（EACCES/EAGAIN） 🔴 业务受影响   [kuafu_T1_20260608_branchD.md:39-40]
```

### 故障因果链

```text
rpc.statd 进程被 pkill -9 强制终止
    └─► rpcbind 进程随 statd 一同终止（rpcbind 与 statd 共享进程组或套接字关联）
            └─► statd 不再向 rpcinfo 注册（statd 服务从 RPC 注册表中消失）
            └─► nlockmgr 服务从 rpcinfo 注册表中消失
                    └─► 内核 lockd 模块未加载（依赖用户态 statd 完成 NLM 心跳注册）
                            └─► /proc/locks 无 NFS 锁条目，锁统计为零
                                    └─► NFS 客户端无法协商或获取文件锁（fcntl/flock 调用失败）
                                            └─► 依赖 NFS 文件锁的应用（如数据库、集群软件）将出现锁定失败
```

---

## 三、排查过程

> 排查逻辑：**提出假设 → 收集证据 → 验证或排除 → 逐步收敛到根因**

### 3.1 初始现象

- 故障注入信息：客户端 rpc.statd 进程被 kill，锁服务（NLM）不可用
- 故障模式：rpc.statd/lockd 异常
- 测试时间：2026-06-08 02:52:00 UTC
- 表征现象：系统 NFS 锁功能完全失效，rpc.statd 和 rpcbind 均不可用

---

### 3.2 假设驱动排查

#### 假设 A：rpc.statd 进程崩溃（段错误/SIGSEGV）

> 🧪 假设：rpc.statd 因自身 Bug 或内存异常而崩溃退出

| 检查项 | 操作 | 结论 |
|--------|------|------|
| rpc.statd 进程状态 | 检查进程存活 | ❌ 进程不存在 |
| 核心转储文件 | 检查 /var/lib/nfs/ 或系统 core 路径 | 无 core 文件生成 |
| syslog/journal 异常 | rpc.statd 相关日志 | 未发现崩溃日志 |

**❌ 排除**：故障注入明确为 `pkill -9` 而非进程崩溃，且无 core dump 或异常退出日志。

---

#### 假设 B：rpcbind 独立故障

> 🧪 假设：rpcbind 自身出现问题，导致 statd 注册丢失

| 检查项 | 操作 | 结论 |
|--------|------|------|
| rpcbind 状态 | 检查进程存活 | ❌ 进程不存在 |
| rpcinfo 注册表 | 查询已注册服务 | ❌ statd、nlockmgr 均未注册 |
| rpcbind 独立启动 | 尝试 systemctl 状态 | ❌ 未运行 |

**❌ 排除**：诊断结论明确 rpcbind "随 statd 一起被 kill"，属于连带效应而非独立故障。

---

#### 假设 C：内核 lockd 模块加载失败

> 🧪 假设：lockd 内核模块本身损坏或加载失败

| 检查项 | 操作 | 结论 |
|--------|------|------|
| lockd 模块状态 | lsmod \| grep lockd | ❌ 未加载 |
| 内核模块目录 | /lib/modules/$(uname -r)/ 中 lockd.ko | 模块文件存在（可正常加载） |
| dmesg 错误 | 模块加载相关错误 | 无加载失败记录 |

**⚠️ 间接原因**：lockd 未加载是由用户态 statd/rpcbind 未运行导致的，非内核模块自身问题。lockd 通常由 statd 通过 `nlm_register` 回调触发加载，statd 不运行则 lockd 无法自动加载。

---

#### 假设 D：rpc.statd 被 `pkill -9` 强制终止 ✅ 确认根因

> 🧪 假设：rpc.statd 进程被 `pkill -9` 信号强制终止

**Step 1 — 确认进程是否存在**
```bash
ps aux | grep rpc.statd
# 结果：进程不存在
```

**Step 2 — 确认 rpcbind 状态**
```bash
ps aux | grep rpcbind
# 结果：进程不存在
ps aux | grep rpc.statd
# 结果：进程不存在
```

**Step 3 — 确认 rpcinfo 注册**
```bash
rpcinfo -p localhost
# 结果：statd、nlockmgr 均未注册（rpcbind 未运行）
```

**Step 4 — 确认锁状态**
```bash
cat /proc/locks
# 结果：无 NFS 相关锁条目
nfsstat -l
# 结果：无 NFS 锁统计
```

**✅ 结论：确认 rpc.statd 被 pkill -9 终止，rpcbind 随之终止，导致 NFS 锁服务（NLM）全面不可用。**

---

### 3.3 排查结论

```text
NFS 锁服务不可用
├─► 假设 A：rpc.statd 进程崩溃（SIGSEGV/Bug）
│       └─► ❌ 排除：诊断为 pkill -9，无崩溃证据
├─► 假设 B：rpcbind 独立故障
│       └─► ❌ 排除：rpcbind 是随 statd 连带终止
├─► 假设 C：内核 lockd 模块加载失败
│       └─► ⚠️ 间接关联：lockd 未加载是因 statd 未运行，模块自身正常
└─► 假设 D：rpc.statd 被 pkill -9 强制终止
        └─► 🎯 根因确认：pkill -9 终止 rpc.statd
                ├─► rpcbind 连带终止
                ├─► statd/nlockmgr 从 rpcinfo 注册表消失
                ├─► 内核 lockd 模块未加载
                └─► NFS 文件锁操作全面失败
```

---

## 四、修复方案

### 4.1 应急处置（推荐执行顺序）

| 步骤 | 操作 | 执行人 | 说明 |
|------|------|--------|------|
| 1 | 启动 rpcbind 服务：`systemctl start rpcbind` | 系统管理员 | 恢复 RPC 端口映射服务 |
| 2 | 启动 rpc.statd 服务：`systemctl start rpc-statd`（或 `rpc.statd`） | 系统管理员 | 恢复 NFS 锁守护进程 |
| 3 | 验证 rpcinfo 注册：`rpcinfo -p localhost` | 系统管理员 | 确认 statd（端口 100021, 100024）和 nlockmgr（100021）已注册 |
| 4 | 验证 lockd 模块：`lsmod \| grep lockd` | 系统管理员 | 确认 lockd 内核模块已自动加载 |
| 5 | 验证锁操作：在 NFS 挂载点上测试 `flock` 或 `fcntl` 锁定 | 系统管理员 | 确认锁功能恢复 |

```bash
# 一键恢复脚本（建议以 root 执行）
systemctl restart rpcbind && systemctl restart rpc-statd
sleep 2
rpcinfo -p localhost | grep -E "statd|nlockmgr" && echo "✅ NFS 锁服务已恢复" || echo "❌ 恢复失败，请检查日志"
```

### 4.2 永久修复计划

| 修复措施 | 负责人 | 完成时间 |
|--------|------|--------|
| 配置 systemd 自动重启：为 rpc-statd 添加 `Restart=always` 策略，确保进程被意外终止后自动拉起 | 系统管理员 | 待定 |
| 配置 rpcbind 自动重启：确保 rpcbind 也启用 `Restart=always` | 系统管理员 | 待定 |
| 实施进程监控告警：对 rpc.statd、rpcbind 等关键 NFS 组件进程实施监控（如 Prometheus Node Exporter + Alertmanager），进程消失时即时告警 | 运维团队 | 待定 |
| 评估 lockd 模块预加载：在 `/etc/modules-load.d/` 中配置 lockd 模块开机预加载，降低对 statd 依赖 | 系统管理员 | 待定 |
| 排查进程被 kill 的原因：调查是否存在 OOM Killer、人为操作或自动化脚本误杀，补充白名单保护机制 | 安全/运维团队 | 待定 |

### 4.3 预防建议

- 为 `rpc.statd`、`rpcbind` 等关键系统服务配置 systemd 的 `Restart=on-failure` 或 `Restart=always`
- 在自动化运维脚本中增加关键进程白名单，避免误杀
- 对 NFS 锁服务建立周期性健康检查脚本，检测 `rpcinfo -p` 中 statd/nlockmgr 的注册状态
- 建议使用 NFSv4.2（不再依赖 statd 进行锁管理），从根本上减少该故障面

---

**RCA 报告路径**：`/home/win11/.witty-diagnosis-agent/baize/reports/NFS锁服务故障_rpc.statd被kill_20260608_025200_report.md`
