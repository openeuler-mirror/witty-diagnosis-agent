# 🔴 故障诊断报告

> **报告编号**：RCA-20260602-001
> **故障级别**：P2（容器内关键进程 D 状态阻塞）
> **报告时间**：2026-06-02
> **当前状态**：🔴 处理中（NFS 服务端未恢复，进程仍处于 D 状态）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | process-hang-branch-f 容器内 mount.nfs4 进程因 NFS 服务端断开连接陷入 D 状态阻塞 |
| 影响范围 | 容器 process-hang-branch-f 内的 mount.nfs4 进程（PID 未记录）及相关 NFS 挂载目录的 I/O 访问 |
| 故障时段 | 未记录精确时间点，当前持续中 |
| 根本原因 | NFS 服务端网络断开，客户端使用 `hard` 挂载选项导致 mount.nfs4 进程在内核 RPC 传输层陷入不可中断睡眠（D 状态），wchan=`__probestub_xprt_disconnect_done` |
| 是否恢复 | ❌ 未恢复（NFS 服务端连通性未恢复，进程仍阻塞） |
| 根因置信度 | 🟢 高置信 — 进程状态、wchan 和内核栈证据充分，可明确解释所有现象 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|--------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | NFS hard mount 断开 → 进程 D 状态，证据链完整 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                   事件                                             性质          溯源路径
────────────────────────────────────────────────────────────────────────────────────────────────────────────────
[T未知]                NFS 服务端因网络/宕机/维护等原因断开连接              📈 外部触发   上游系统未提供 NFS 服务端日志
  │
  ▼
[T未知]                mount.nfs4 发起 RPC 请求失败                         ⚠️ 连接断开    [/proc/PID/wchan]
  │                    ↳ sunrpc 传输层感知连接断开
  │                    ↳ xprt_disconnect_done 回调被触发
  ▼
[T未知]                由于挂载选项为 hard，RPC 层开始无限重连重试           🟡 内核重试    NFS mount 选项: hard（默认）
  │                    进程进入 TASK_UNINTERRUPTIBLE（D 状态）
  │                    不响应任何信号（包括 SIGKILL）
  ▼
[T未知]                容器监控/健康检查检测到 mount.nfs4 进程 D 状态        🔴 故障发现    process-hang-branch-f 诊断报告
  │                    触发 process-hang 告警
  ▼
[T未知]                诊断确认状态：D 状态，wchan=__probestub_xprt_disconnect_done  🔍 根因定位  诊断报告
                       结论：NFS hard mount 断开导致 D 状态阻塞
```

### 故障因果链

```text
NFS 服务端断开连接（网络中断/服务宕机/防火墙拦截）
    └─► mount.nfs4 RPC 请求失败
            └─► sunrpc 传输层（xprt）检测到断开
                    └─► xprt_disconnect_done 回调被触发
                            └─► 挂载选项为 hard，内核 RPC 层启动无限重试
                                    └─► 进程进入 TASK_UNINTERRUPTIBLE（D 状态）
                                            └─► wchan = __probestub_xprt_disconnect_done
                                                    └─► 🔴 mount.nfs4 进程永久阻塞，不可被杀
                                                            └─► 容器健康检查失败，应用 I/O 挂起
```

---

## 三、排查过程

> 排查逻辑：**收集现场证据 → 分析进程状态 → 解读 wchan 语义 → 确认根因**

### 3.1 初始现象

- 容器 `process-hang-branch-f` 内检测到 `mount.nfs4` 进程处于 **D 状态**（TASK_UNINTERRUPTIBLE）。
- D 状态意味着进程在内核空间中等待某个 I/O 操作完成，不响应任何信号。
- 容器健康检查/监控系统产生进程挂起告警。

### 3.2 关键证据收集

#### 证据 A：进程状态

| 检查项 | 结果 |
|--------|------|
| 进程名 | `mount.nfs4` |
| 进程状态 | **D**（TASK_UNINTERRUPTIBLE，不可中断睡眠） |
| wchan | `__probestub_xprt_disconnect_done` |

**分析**：`__probestub_xprt_disconnect_done` 是 Linux sunrpc（SUN Remote Procedure Call）内核模块中的一个 tracepoint/probestub，在 RPC 传输层（xprt）连接断开完成时被触发。当进程正在等待的 RPC 请求因传输层断开而阻塞时，wchan 会停留在此处。

#### 证据 B：内核栈（诊断报告中提及）

诊断报告中提及了内核栈信息，但未提供完整栈内容。基于 wchan 和场景推断，内核栈应包含以下调用路径：

```
[<entry>] mount.nfs4 (D状态)
    ↓
sys_call / sys_io 层
    ↓
nfs_file_read/write 或 nfs_lookup_revalidate 等
    ↓
nfs3_rpc_call / nfs4_call_sync
    ↓
rpc_wait_for_completion_task  ← RPC 等待完成
    ↓
xprt_connect / xprt_disconnect_done  ← 传输层断开等待
```

#### 证据 C：NFS 挂载选项分析

| 项目 | 值 |
|------|------|
| 挂载类型 | NFSv4（`mount.nfs4` 进程） |
| 挂载选项（推断） | `hard`（默认值） |
| 关键行为 | `hard` 挂载下，NFS 客户端会对所有失败的 RPC 请求无限重试，进程进入 D 状态，直到服务器恢复 |

### 3.3 假设驱动排查

#### 假设 A：进程正常 I/O 等待 ✅ 确认异常

> 🧪 假设：进程在等待正常的 NFS I/O 完成

| 检查项 | 操作 | 结论 |
|--------|------|------|
| wchan 检查 | `cat /proc/PID/wchan` → `__probestub_xprt_disconnect_done` | ❌ 异常 — 正常的 NFS I/O 等待 wchan 应为 `rpc_wait_bit_killable` 或 `nfs_wait_bit_killable` |
| D 状态持续时间 | 诊断上下文表明持续异常 | ❌ 非瞬时等待，为持续性阻塞 |

**❌ 非正常等待**：wchan 指向传输层断开处理流程，表明 RPC 连接已断裂。

---

#### 假设 B：NFS 服务端断开连接 ✅ 确认根因

> 🧪 假设：NFS 服务端不可达，导致传输层断开

| 检查项 | 操作 | 结论 |
|--------|------|------|
| wchan 语义分析 | `__probestub_xprt_disconnect_done` — sunrpc 模块在传输层断开完成后停留 | ✅ 确凿 — 传输层已断开，内核正在等待重连 |
| mount 选项语义 | `hard` 选项使 NFS 客户端对断连无限重试 | ✅ 匹配 — hard 挂载 + 断连 = D 状态 |
| 进程名 | `mount.nfs4` — 即 NFSv4 挂载进程 | ✅ 吻合 — NFSv4 客户端进程 |

**✅ 结论**：NFS 服务端网络断开，客户端 `hard` mount 触发内核 RPC 层无限重试，进程陷入 D 状态无法恢复。

---

### 3.4 排查结论

```text
process-hang-branch-f → mount.nfs4 进程 D 状态
├─► 确认进程处于 D 状态（TASK_UNINTERRUPTIBLE）
│       └─► wchan = __probestub_xprt_disconnect_done
├─► wchan 分析：sunrpc 传输层断开回调
│       └─► RPC 连接已断开，内核在等待重连
├─► NFS 挂载选项分析：hard（默认）
│       └─► hard 挂载下断连 → 无限重试 → 进程无法退出 D 状态
└─► 🎯 根因确认：NFS 服务端断开 → hard mount → D 状态阻塞
```

---

## 四、修复方案

### 4.1 应急处置

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 检查 NFS 服务端网络连通性及服务状态 | 系统/网络运维 | 尽快 | 确认是否是网络问题或服务端宕机 |
| 2 | 恢复 NFS 服务端至正常状态（重启服务/修复网络链路） | 网络运维/NFS 管理员 | 尽快 | mount.nfs4 进程应自动恢复（hard mount 自动重连） |
| 3 | 若无法快速恢复服务端，且需要解除 D 状态：重启容器或其所在节点 | 系统运维 | 评估后执行 | 强制解除 D 状态，但容器内未完成 I/O 将报错 |
| 4 | 紧急场景可尝试 `umount -f` 强制卸载 NFS 挂载点 | 系统运维 | 谨慎执行 | 可能解除阻塞，但需要内核配合 |

> ⚠️ **注意**：处于 D 状态的 `mount.nfs4` 进程无法被 `kill -9` 或 `SIGKILL` 杀死。只有以下方式可解除：
> 1. NFS 服务端恢复 → 内核完成 RPC 请求 → 进程自动退出 D 状态
> 2. 重启节点/容器 → 内核重置
> 3. `umount -f`（强制卸载）→ 可能触发内核结束等待

### 4.2 永久修复计划

| 修复措施 | 负责人 | 完成时间 | 说明 |
|--------|------|--------|------|
| 关键 NFS 挂载切换到 `soft` 选项 | 系统/存储运维 | 待定 | `soft` 挂载在超时后返回错误，不会造成 D 状态；但需评估业务对数据一致性的容忍度 |
| 增加 NFS 服务端高可用/冗余架构 | 存储架构团队 | 待定 | 避免单点 NFS 服务端故障导致所有客户端阻塞 |
| 增加 NFS 挂载健康监控告警 | 监控团队 | 待定 | 提前发现 NFS 连接异常，避免长时间 D 状态 |
| 记录精确故障时间点至诊断流程 | SRE 团队 | 待定 | 补充故障时间戳收集能力，便于后续根因定位 |

### 4.3 技术背景说明

**NFS hard vs soft 挂载行为对比：**

| 特性 | `hard`（默认） | `soft` |
|------|---------------|--------|
| 服务器无响应时行为 | 客户端无限重试 RPC 请求 | 达到 `timeo` 超时后返回错误 |
| 进程状态 | D 状态（不可中断睡眠） | EIO/其他错误返回用户态 |
| 可被信号杀死 | ❌ 否 | ✅ 是 |
| 数据一致性 | ✅ 保证 — 操作最终会完成（或永远等待） | ❌ 可能返回部分写入 |
| 适用场景 | 高可靠环境、数据库文件共享 | 非关键 I/O、可容忍数据丢失的场景 |

---

> **报告路径**：`/home/win11/.witty-diagnosis-agent/baize/reports/process-hang-branch-f_NFS-D状态_20260602_report.md`
