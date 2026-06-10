# 🔴 故障诊断报告

> **报告编号**：RCA-20260608-001
> **故障级别**：P1 / Critical
> **报告时间**：2026-06-08 03:00:00 UTC
> **当前状态**：🔴 处理中

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | NFS hard mount 因 iptables OUTPUT 阻断导致访问进程卡死（D 状态） |
| 影响范围 | NFS 客户端上所有需要访问 `/mnt/nfs-test` 挂载点的进程及应用 |
| 故障时段 | 2026-06-08 18:58:27（首次 dmesg 日志） ～ 至今 |
| 根本原因 | iptables OUTPUT 链 DROP 规则阻断了对 NFS Server 2049 端口的出站流量，结合 NFS hard mount 无限重试机制，导致进程进入不可杀的 D 状态 |
| 是否恢复 | ❌ 未恢复 |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|--------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | iptables 阻断规则 + hard mount 机制可完整解释全部现象 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                              事件                                                  性质          证据来源
──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
[故障注入前]                       NFS 客户端执行 mount 操作                                      📋 预备动作
  │                               mount -t nfs4 -o hard,timeo=70,retrans=1 nfs-server:/ /mnt/nfs-test
  │                               挂载成功，没有任何异常
  ▼
[≈ 2026-06-08 18:58:27]           iptables OUTPUT 链插入 DROP 规则，阻断 2049 端口                 🔴 故障注入   [kuafu_T1_20260608_branchF.md : 20-24]
  │                               (TCP+UDP 均被 DROP)
  ▼
[≈ 18:58:27]                      应用进程发起 NFS 文件操作（如读写访问 /mnt/nfs-test）              💥 第一次触发
  │                               
  ▼
[≈ 18:58:27 起]                   NFS RPC 请求发送至 nfs-server:2049，被本地 iptables OUTPUT 链丢弃   ⚠️  请求丢失
  │                               
  ▼
[≈ 18:58:27 + 7s]                 timeo=70（7 秒）RPC 超时到期，未收到 Server 响应                   🟡 首次超时
  │                               触发 NFS 客户端重试（retrans=1 → 剩余 0 次重试）
  ▼
[≈ 18:58:34+]                     NFS 内核日志记录：                                             🔴 故障确认   [kuafu_T1_20260608_branchF.md : 29]
  │                               "nfs: server nfs-server not responding, still trying"
  │                               由于是 hard mount，内核进入无限重试循环
  ▼
[持续]                             任何访问该挂载点的进程                                       🔴 故障恶化
                                   ↓ 内核 NFS 层无法完成 RPC 请求
                                   ↓ 进程被置为 TASK_UNINTERRUPTIBLE（D 状态）
                                   ↓ kill -9 无法杀死
                                   ↓ umount -f 也可能无法卸载
```

### 故障因果链

```text
iptables OUTPUT 链 DROP 2049 端口（TCP+UDP）
    │
    ▼
NFS RPC 请求（从客户端到 Server:2049）被本地防火墙丢弃，始终无法到达 Server
    │
    ▼
Server 永远不会返回响应，客户端的 RPC 请求持续等待
    │
    ▼
timeo=70（7 秒超时）→ RPC 超时 → 触发重试（retrans 计数归零后仍继续重试）
    │
    ▼
hard mount 语义：内核 NFS 客户端无限重试直到 Server 恢复响应
    │
    ▼
内核日志输出 "server nfs-server not responding, still trying"（持续重复）
    │
    ▼
访问该挂载点的进程被置为 TASK_UNINTERRUPTIBLE（D 状态）
    │
    ▼
进程不可杀（SIGKILL 无效），且 umount -f 也可能无法强制卸载
    │
    ▼
🔴 故障表现：D 状态进程堆积，服务不可用
```

---

## 三、排查过程

> 排查逻辑：**提出假设 → 收集证据 → 验证或排除 → 逐步收敛到根因**

### 3.1 初始现象

- 内核 dmesg 日志持续输出：`nfs: server nfs-server not responding, still trying`
- 任何对 `/mnt/nfs-test` 挂载点执行文件操作的进程均进入 D 状态（TASK_UNINTERRUPTIBLE）
- D 状态进程无法被杀掉（即使是 `kill -9`）
- RPC 统计显示 retrans=0（所有请求仍在初始超时窗口内循环，未进入正式重传机制）
- 系统调用数：217 个 NFS RPC calls，全部处于等待状态

### 3.2 假设驱动排查

#### 假设 A：NFS Server 端故障或宕机

> 🧪 假设：NFS Server 本身不可用、端口未监听或网络路由不可达

| 检查项 | 操作/数据 | 结论 |
|--------|----------|------|
| Server 连通性 | 测试 ping NFS Server | 🟡 无法确定（可能网络已被阻断） |
| 本地 iptables 规则 | `iptables -L OUTPUT -n -v` 检查 | ✅ 确认存在 DROP 2049 规则 |

**关键发现**：排查发现客户端 iptables OUTPUT 链存在明确的 DROP 规则，目标端口为 2049，协议覆盖 TCP 和 UDP。这表明阻断发生在**本地发包前**，而非 Server 端问题。

**❌ 排除**：Server 端即使正常，请求也无法离开本机，故障根源在本地防火墙配置。

---

#### 假设 B：NFS 网络路径故障（非防火墙）

> 🧪 假设：物理链路、路由器 ACL 或中间网络设备丢弃了 NFS 流量

| 检查项 | 操作/数据 | 结论 |
|--------|----------|------|
| iptables 规则显式 DROP | 规则表明确显示 OUTPUT 链 DROP ✅ | ❌ 已确认是本机 iptables 丢弃 |

**关键发现**：IPTables 规则为目标端口 2049 配置了明确的 DROP 动作，包在 `NF_INET_LOCAL_OUT` 钩子点直接被丢弃，根本不会进入物理网卡。

**❌ 排除**：非网络链路问题，是本机 netfilter 策略拦截。

---

#### 假设 C：NFS 挂载参数配置不当

> 🧪 假设：挂载参数（如 soft/hard、timeo、retrans）配置导致异常行为

| 检查项 | 操作/数据 | 结论 |
|--------|----------|------|
| 挂载类型 | hard | ✅ hard 模式下操作将无限重试，属于预期行为 |
| timeo 值 | 70（7 秒） | ✅ 每次超时约 7 秒后重试，配置正常 |
| retrans | 1 | ✅ 重传计数 1，超出后日志告警但 hard 模式继续重试 |

**结论**：挂载参数本身配置正确，但 **hard mount 加上网络阻断**的组合才是问题本质。若使用 `soft` 挂载，应用程序会在超时后收到 `EIO` 错误，不会进入 D 状态。

**⚠️ 非根因**：参数配置是故障链路中的一环，但不是根本触发因素。

---

#### 假设 D：iptables OUTPUT 阻断 2049 → 确认根因

> 🧪 假设：iptables OUTPUT 链的 DROP 规则直接导致 NFS 请求无法发出，hard mount 语义造成进程 D 状态

**Step 1 — 确认 iptables 阻断规则生效**

```text
Chain   目标  端口  协议  动作
─────── ──── ───── ──── ────
OUTPUT  2049  TCP   DROP  ✅  → 所有发往 nfs-server:2049 的 TCP 包被丢弃
OUTPUT  2049  UDP   DROP  ✅  → 所有发往 nfs-server:2049 的 UDP 包被丢弃
```

**Step 2 — 确认内核 NFS 超时行为**

```text
dmesg: "nfs: server nfs-server not responding, still trying"
RPC calls: 217, retrans: 0
→ 所有请求均未收到响应，客户端持续重试中
```

**Step 3 — 确认 hard mount 导致的 D 状态**

- hard 挂载模式下，RPC 操作在超时后会无限重试，不会返回错误给用户态
- 访问挂载点的进程挂起在 `nfs_file_read/write` 内核路径上，状态为 D（TASK_UNINTERRUPTIBLE）
- D 状态进程无法响应任何信号（包括 SIGKILL）

**✅ 结论：iptables OUTPUT 链 DROP 2049 端口 → NFS RPC 请求无法发出 → hard mount 无限重试 → 进程 D 状态不可杀。根因确认。**

---

### 3.3 排查结论

```text
"server not responding, still trying" + D 状态进程
│
├─► 假设 A：NFS Server 宕机/不可达 → ❌ 排除（本地防火墙拦截，Server 大概率正常）
│
├─► 假设 B：网络链路路径故障 → ❌ 排除（iptables 本地拦截，未出网卡）
│
├─► 假设 C：挂载参数配置不当 → ⚠️ 非根因（hard 参数是必要条件但非触发因素）
│
└─► 假设 D：iptables OUTPUT 阻塞 2049 → 🎯 根因确认
        │
        ▼
    iptables -A OUTPUT -p tcp --dport 2049 -j DROP
    iptables -A OUTPUT -p udp --dport 2049 -j DROP
        │
        ▼
    NFS hard mount 模式下 RPC 无法发出 → 内核无限重试
        │
        ▼
    🎯 根因：iptables 出站防火墙规则阻断 + hard mount 语义
```

---

## 四、修复方案

### 4.1 应急处置

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 移除 iptables OUTPUT 链阻断规则：`iptables -D OUTPUT -p tcp --dport 2049 -j DROP` 和 `iptables -D OUTPUT -p udp --dport 2049 -j DROP` | 系统运维 | 立即 | 恢复 NFS RPC 通信，D 状态进程逐步恢复 |
| 2 | 如果已存在 D 状态进程无法自动恢复，检查是否需要重启 NFS 服务或重启系统 | 系统运维 | 视情况 | 清理残留 D 状态进程 |
| 3 | 若 umount -f 失败，尝试 `umount -l`（lazy unmount）后重新挂载 | 系统运维 | 恢复后 | 确保挂载点正常 |

```bash
# 恢复脚本示例
# 步骤 1：移除 iptables 阻断规则
iptables -D OUTPUT -p tcp --dport 2049 -j DROP
iptables -D OUTPUT -p udp --dport 2049 -j DROP

# 步骤 2：验证 NFS 连通性
mount | grep nfs-test
ls /mnt/nfs-test

# 步骤 3：如果 D 状态进程未自动恢复，尝试
umount -l /mnt/nfs-test
mount -t nfs4 -o hard,timeo=70,retrans=1 nfs-server:/ /mnt/nfs-test
```

### 4.2 永久修复计划

| 修复措施 | 负责人 | 优先级 | 完成时间 |
|--------|--------|--------|--------|
| 评审防火墙策略，确保 NFS 相关端口（2049、portmap、mountd 等）不在阻断白名单之外被意外拦截 | 安全运维团队 | P0 | 立即 |
| 对关键 NFS 挂载点评估使用 `soft` 或 `intr` 挂载选项的可行性，防止永久 D 状态阻塞 | 系统架构团队 | P1 | 近期 |
| 增加 iptables 规则变更审批与审计流程，防止生产环境意外阻断 | 安全运维团队 | P1 | 近期 |
| 配置监控告警：监控 dmesg 中 "not responding" 关键字及 D 状态进程数 | 监控团队 | P1 | 立即 |
| 建立 NFS 连接健康检查脚本（定期探测 NFS Server 2049 端口连通性） | 系统运维团队 | P2 | 近期 |
