# 🔴 故障诊断报告

> **报告编号**：RCA-20260608-NFSv4-001
> **故障级别**：P3 / 低严重度
> **报告时间**：2026-06-08 03:10:00 UTC
> **当前状态**：🟢 已恢复

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | NFS Server 重启引发 NFSv4 Lease 过期，客户端自动完成状态恢复 |
| 影响范围 | NFSv4 客户端挂载点 `/mnt/nfs-test`（`nfs-server:/`），NFSv3 挂载未受影响 |
| 故障时段 | 2026-06-08 02:50:00 UTC ～ 2026-06-08 02:50:XX UTC（约数秒至数十秒） |
| 根本原因 | NFS Server 侧重启 `rpc.nfsd` + `rpc.mountd` 服务，导致客户端 NFSv4 Lease 过期，触发 Session 重建与状态回收流程 |
| 是否恢复 | ✅ 已恢复（客户端 Lease 自动恢复成功，零错误） |
| 根因置信度 | 🟢 高置信 |

### 置信度说明（此表固定展示作为参考）

| 等级 | 标识 | 含义 | 示例场景 | 
|------|------|------|--------| 
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | `reclaim_comp` > 0 且错误计数为零，直接证明状态回收成功完成 | 
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — | 
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — | 
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — | 

---

## 二、根因速览

> **NFS Server 重启 → NFSv4 Lease 失效 → 客户端自动执行 Session 重建 + 状态回收 → 零错误恢复**。

### 事故时间线 & 故障传导链路

```text
时间                           事件                                                   性质         溯源路径
──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-06-08 02:50:00            NFS Server 侧重启 rpc.nfsd + rpc.mountd                 🔴 故障注入   [kuafu_T1_20260608_branchC.md:4-6]
  │
  ▼
2026-06-08 02:50:00+           Server 中断 NFSv4 服务，已建立的 Lease 过期                ⚠️ 连接断开   [kuafu_T1_20260608_branchC.md:5]
  │                            Client 侧 NFSv4 会话（Session）失效
  ▼
2026-06-08 02:50:00+           Client 发起 14 次 exchange_id 重新协商身份                  🟡 恢复启动   [kuafu_T1_20260608_branchC.md:24]
  │                            (试图与重启后的 Server 重建 Client ID)
  ▼
2026-06-08 02:50:00+           Client 执行 create_session(10) > destroy_session(7)         🟡 会话重建   [kuafu_T1_20260608_branchC.md:20-22]
  │                            销毁旧 Session、创建新 Session
  │                            同时发起 get_lease_time(2) 重新协商 Lease 时长
  ▼
2026-06-08 02:50:00+           reclaim_comp = 8（状态回收完成）                            🔵 状态回收   [kuafu_T1_20260608_branchC.md:23]
  │                            客户端向 Server 申请回收之前持有的锁与状态信息
  ▼
2026-06-08 02:50:XX            ✅ 恢复完成 — 错误计数为零，挂载可正常访问                    🟢 已恢复     [kuafu_T1_20260608_branchC.md:32-33,40-41]
  │                            ls /mnt/nfs-test/ 正常，无 D 状态进程
  ▼
2026-06-08 02:50:XX            客户端 sequence 操作计数 = 0 → 无进行中操作，链路完全就绪     🟢 稳态       [kuafu_T1_20260608_branchC.md:25]
```

### 故障因果链

```text
NFS Server 重启（rpc.nfsd + rpc.mountd）
    └─► NFSv4 Lease 在 Server 端过期，Client 端 Session 失效
            └─► NFSv4 客户端检测到连接中断，自动触发状态恢复流程
                    ├─► exchange_id 身份重新协商（14 次）
                    ├─► destroy_session 销毁旧会话（7 次）
                    ├─► create_session 创建新会话（10 次）
                    ├─► get_lease_time 重新协商 Lease 时长（2 次）
                    └─► reclaim_comp 完成状态回收（8 次）
                            └─► 🟢 恢复完成，零错误，挂载访问正常
```

---

## 三、排查过程

> 排查逻辑：**提出假设 → 收集证据 → 验证或排除 → 逐步收敛到根因**。

### 3.1 初始现象

- **故障注入**：NFS Server (`nfs-server`) 侧重启了 NFS 服务（`rpc.nfsd` + `rpc.mountd`）。
- **预期影响**：NFSv4 客户端 Lease 过期，可能进入挂起（Hang）状态或触发错误。
- **挂载配置**：
  - NFSv3: `nfs-server:/exports` → `/mnt/nfs-test`（hard, tcp, timeo=600）
  - NFSv4.2: `nfs-server:/` → `/mnt/nfs-test`（hard, tcp, timeo=600）

### 3.2 假设驱动排查

#### 假设 A：NFSv4 Lease 过期后客户端永久挂起（Hang）

> 🧪 假设：NFSv4 Lease 过期后，客户端所有 I/O 操作卡住，进程进入 D 状态（不可中断睡眠），无法自动恢复。

| 检查项 | 操作 / 证据 | 结论 |
|--------|-------------|------|
| D 状态进程 | `ls /mnt/nfs-test/` 正常，无 NFS 相关 D 状态进程 | ✅ 正常 |
| 挂载可达性 | `/mnt/nfs-test` 可正常列出文件 | ✅ 正常 |
| 错误计数 | `nfsstat` 中 expired/stale/bad/denied 错误均为 0 | ✅ 无错误 |

**❌ 排除**：客户端未进入永久挂起状态，故障自动恢复。

---

#### 假设 B：NFSv4 状态恢复失败 — 状态无法回收

> 🧪 假设：Server 重启后，Client 持有的文件锁（Lock State）和打开文件状态（Open State）无法重新注册到 Server，导致状态不一致。

| 检查项 | 操作 / 证据 | 结论 |
|--------|-------------|------|
| `reclaim_comp` 计数 | 计数 = 8（占比 3%），表示客户端成功完成了 8 次状态回收操作 | ✅ 回收成功 |
| `sequence` 操作 | 计数 = 0，表示没有正在进行的 sequence 操作，当前无 pending 请求 | ✅ 无阻塞操作 |
| 错误计数 | 所有相关错误计数均为零 | ✅ 无残留错误 |

**❌ 排除**：状态回收已成功完成，未出现 reclaim 失败。

---

#### 假设 C：NFSv4 Lease 到期自动恢复 ✅ 确认场景

> 🧪 假设：Server 重启导致 Lease 过期，客户端自动执行 Session 重建 + 状态回收，且恢复过程顺利。

**Step 1 — 验证 Session 重建行为**：
```text
nfsstat -4 -c 关键指标：
- exchange_id:  14 次 → 客户端反复与 Server 交换身份信息
- create_session:  10 次 → 新 Session 创建
- destroy_session:  7 次 → 旧 Session 销毁
- create_session(10) > destroy_session(7) → 新建多于销毁，最终处于稳定状态
```

**Step 2 — 验证 Lease 重新协商**：
```text
- get_lease_time: 2 次 → 客户端主动查询新的 Lease 超时时间
- 说明 Server 重启后 Lease 超时参数已变化，客户端重新获取
```

**Step 3 — 验证状态回收完成**：
```text
- reclaim_comp: 8 次 → ✅ 最重要的指标，表示状态回收操作全部成功完成
- 每次 reclaim_comp 代表一个 NFSv4 状态（如打开文件句柄、锁）被成功重新注册
```

**Step 4 — 验证最终状态**：
```text
- 零错误：expired = 0, stale = 0, bad = 0, denied = 0
- sequence = 0 → 无 pending 操作
- ls /mnt/nfs-test/ → ✅ 正常
- 无 D 状态进程 → ✅ 无阻塞
```

**✅ 结论：NFS Server 重启 → NFSv4 Lease 过期 → 客户端自动执行 exchange_id → create_session/destroy_session → reclaim_comp 完成状态回收 → 零错误恢复。这是一个 NFSv4 协议设计的正常自愈行为。**

---

### 3.3 排查结论

```text
NFS Server 重启导致 NFSv4 Lease 过期
├─► 假设 A：客户端永久挂起 → ❌ 排除（挂载正常，无 D 状态进程）
└─► 假设 B：状态回收失败    → ❌ 排除（reclaim_comp=8，零错误）
        └─► 假设 C：自动恢复 → ✅ 确认根因
                ├─► exchange_id: 14 次 → 身份重新协商
                ├─► create_session: 10 > destroy_session: 7 → Session 重建
                ├─► get_lease_time: 2 → Lease 重新协商
                └─► reclaim_comp: 8 → 🎯 状态回收成功
                        └─► 零错误，挂载正常 → 完全恢复
```

---

## 四、修复方案

### 4.1 应急处置

此故障场景为 NFSv4 协议的标准自愈行为，无需应急处置。客户端已自动完成恢复。

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 确认挂载状态：`ls /mnt/nfs-test/` | 系统/监控 | 2026-06-08 02:50:XX | ✅ 访问正常 |
| 2 | 确认无 D 状态：`ps aux | grep nfs` | 系统/监控 | 2026-06-08 02:50:XX | ✅ 无阻塞 |
| 3 | 确认错误计数：`nfsstat -4 -c` | 系统/监控 | 2026-06-08 02:50:XX | ✅ 零错误 |

### 4.2 永久修复计划

由于这是 NFSv4 协议的正常行为，并非代码缺陷或配置错误，以下为**加固建议**而非修复：

| 建议措施 | 说明 | 优先级 |
|---------|------|:----:|
| 监控 `nfsstat -4 -c` 中 `reclaim_comp` 的突增 | 可用于提前感知 Server 重启引发的客户端状态回收 | 中 |
| 配置 NFSv4 client 端 `timeo` 和 `retrans` 参数 | 根据业务容忍度调整超时重试策略，控制恢复期间等待时长 | 中 |
| 避免同时依赖 NFSv3 和 NFSv4 混合挂载 | NFSv3 无 stateful 机制，不会受 Lease 过期影响，若业务可接受可统一为 NFSv3 | 低 |
| 使用 `-o soft,timeo=600` 而非 `hard` 选项 | hard 挂载在 Server 不可用时会持续重试可能导致进程 D 状态；soft 挂载返回错误给应用 | 视业务而定 |
| 若为容器环境，确保 NFS 内核模块挂载至宿主机 | 部分容器化环境（如 WSL2）可能缺失 `/proc/net/rpc/nfs4.0/` 状态路径，影响问题排查 | 低 |
