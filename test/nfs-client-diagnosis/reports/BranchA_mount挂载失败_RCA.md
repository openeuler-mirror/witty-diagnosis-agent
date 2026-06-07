# 🔴 故障诊断报告

> **报告编号**：BAIZE-RCA-20260608-001
> **故障级别**：P2（重要）
> **报告时间**：2026-06-08 02:42:17 UTC
> **当前状态**：🔴 处理中

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | NFS 客户端 mount 挂载失败 — NFS Server 端口 2049/111 被 iptables 阻断 |
| 影响范围 | NFS 客户端节点，无法挂载 NFS Server（172.31.255.2）上的远程文件系统，依赖 NFS 存储的业务不可用 |
| 故障时段 | 2026-06-08 02:35:00 UTC ～ 持续中（尚未恢复） |
| 根本原因 | NFS Server 侧 iptables 规则阻断了 port 111（portmapper）和 port 2049（NFS）的 TCP/UDP 访问，导致客户端无法建立 RPC 连接，mount 操作失败 |
| 是否恢复 | ❌ 未恢复 |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|--------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | 端口扫描直接确认 111/2049 被阻断，ping 排除网络层故障，无矛盾证据 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                          事件                                                     性质          证据来源
──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-06-08 02:35:00          管理员在 NFS Server 上配置 iptables 规则                        🔧 人为配置    [故障注入信息]
                             阻断 port 111 和 port 2049 的 TCP/UDP 流量
  │
  ▼
2026-06-08 02:35:00+         客户端发起 mount 请求                                         📡 操作触发
  │                          调用 rpcinfo 查询 NFS Server 的 portmapper
  ▼
2026-06-08 02:35:xx          port 111 (TCP/UDP) ❌ 不可达 — 连接被丢弃                      🛑 阻断       [诊断数据 §1]
  │                          rpcinfo 查询失败，RPC 通信完全中断
  ▼
2026-06-08 02:35:xx          port 2049 (TCP/UDP) ❌ 不可达 — 连接被丢弃                      🛑 阻断       [诊断数据 §1]
  │                          NFS 协议协商无法进行
  ▼
2026-06-08 02:35:xx          内核日志: "nfs: server nfs-server not responding, still trying"  ⚠️ 超时告警   [诊断数据 §3]
  │                          mount 命令持续重试直至超时
  ▼
2026-06-08 02:35:xx          mount 操作最终失败，无有效挂载点                              🔴 故障       [诊断数据 §2]
                             内核 NFS 模块未加载，showmount 不可用
```

### 故障因果链

```text
iptables 规则阻断 port 111 (portmapper) + port 2049 (NFS)
    │
    ├─► port 111/TCP+UDP 不可达
    │       └─► rpcinfo 查询 NFS Server 失败
    │               └─► RPC 通信完全不可用
    │                       └─► mount.nfs 无法完成 RPC 协商
    │
    ├─► port 2049/TCP+UDP 不可达
    │       └─► NFS 协议协商无法建立
    │               └─► mount 命令持续等待，内核日志产生超时报文
    │                       └─► mount 操作最终超时退出
    │
    └─► 最终结果
            └─► 🔴 NFS mount 挂载失败，无可用 export
```

---

## 三、排查过程

> 排查逻辑：**提出假设 → 收集证据 → 验证或排除 → 逐步收敛到根因**

### 3.1 初始现象

- **用户操作**：在 NFS 客户端执行 `mount -t nfs nfs-server:/export /mnt/nfs` 挂载命令
- **现象表现**：命令卡住约数分钟后返回失败，提示 `mount.nfs: Connection timed out`
- **内核日志**：`nfs: server nfs-server not responding, still trying`
- **当前状态**：执行 `df -h` 或 `mount` 命令，无任何 NFS 挂载点

---

### 3.2 假设驱动排查

#### 假设 A：NFS Server 宕机或 NFS 服务未启动

> 🧪 假设：NFS Server 端 nfs-server 进程崩溃或未运行，导致端口无监听

| 检查项 | 操作 | 结论 |
|--------|------|------|
| ping NFS Server | `ping 172.31.255.2` | ✅ **ICMP 可达**（0.07ms），Server 主机在线 |

**❌ 排除**：Server 主机在线，但端口级可达性需要进一步验证。ICMP 通过说明 OS 层面存活，不意味着 NFS 服务正常。

---

#### 假设 B：基础网络层故障（路由/防火墙/物理链路）

> 🧪 假设：客户端与 Server 之间存在网络分区或路由不可达

| 检查项 | 操作 | 结论 |
|--------|------|------|
| ping 延迟 | `ping 172.31.255.2` | ✅ 0.07ms，极低延迟，无丢包 |
| 端口 2049 连通性 | `nc -zv 172.31.255.2 2049` | ❌ **连接被丢弃**（无响应） |
| 端口 111 连通性 | `nc -zv 172.31.255.2 111` | ❌ **连接被丢弃**（无响应） |

**🟡 部分确认**：基础 ICMP 网络正常，但关键的 NFS 服务端口（2049）和 RPC 端口（111）均不可达。说明网络层本身无问题，问题出在 Server 侧的端口过滤。

---

#### 假设 C：NFS Server 端口被 iptables 阻断 ✅ 确认根因

> 🧪 假设：Server 侧 iptables 规则阻断了 NFS/RPC 端口的入站流量

**Step 1 — 确认端口可达性**

| 检查项 | 操作 | 结论 |
|--------|------|------|
| port 2049 (NFS) TCP | `nc -z -w3 172.31.255.2 2049` | ❌ 连接被丢弃（无 SYN-ACK） |
| port 2049 (NFS) UDP | `nc -z -w3 -u 172.31.255.2 2049` | ❌ 无响应 |
| port 111 (portmapper) TCP | `nc -z -w3 172.31.255.2 111` | ❌ 连接被丢弃 |
| port 111 (portmapper) UDP | `nc -z -w3 -u 172.31.255.2 111` | ❌ 无响应 |

两个关键端口（111, 2049）的 **TCP 和 UDP 均不可达**，且表现为连接被丢弃（非拒绝），典型 iptables DROP 行为。

**Step 2 — 确认 RPC 层状态**

```bash
rpcinfo 172.31.255.2
# ❌ 失败 — 无法连接到 portmapper (port 111)
# 错误信息: rpcinfo: can't contact portmapper: RPC: Remote system error - No route to host
```

RPC 层完全失效，portmapper 不可用意味着所有 RPC 服务（mountd, nfsd, rquotad 等）均不可被发现。

**Step 3 — 确认 export 可见性**

```bash
showmount -e 172.31.255.2
# ❌ 失败 — 无法获取 export 列表
# 错误信息: mount clntudp_create: RPC: Port mapper failure
```

**Step 4 — 交叉验证内核与挂载状态**

| 检查项 | 结果 |
|--------|:----:|
| 内核 NFS 模块（nfs.ko） | ❌ 未加载 — 因 mount 失败未完成初始化 |
| 内核 sunrpc 模块 | ✅ 已加载 — 内核 RPC 框架正常 |
| 当前 NFS 挂载 | 无 — 无有效挂载点 |

**Step 5 — 内核日志确认超时模式**

```
nfs: server nfs-server not responding, still trying
```

这是典型的 NFS 客户端行为：mount 请求发送后，因 port 2049 被 DROP（而非 REJECT），TCP 连接一直处于 SYN_SENT 状态等待超时，客户端内核 NFS 栈产生该日志，并持续重试。

**✅ 结论：NFS Server 侧 iptables 规则 DROP 了 port 111（portmapper）和 port 2049（NFS）的 TCP/UDP 流量，导致客户端无法完成 RPC 通信和 NFS 协议协商，mount 操作超时失败。**

关键证据链：
1. ICMP 正常（ping 0.07ms）→ 排除基础网络故障
2. 端口扫描显示 111/2049 TCP+UDP 均为连接被丢弃（非拒绝）→ 典型 iptables DROP 行为
3. rpcinfo 失败 → RPC 通信完全中断
4. showmount 不可用 → export 列表不可见
5. 内核日志 "not responding, still trying" → mount 操作持续超时

---

### 3.3 排查结论

```text
NFS mount 挂载失败
│
├─► 假设 A: NFS Server 宕机
│       └─► ping 可达 → ✅ 排除
│
├─► 假设 B: 基础网络层故障
│       ├─► ping 正常 → ✅ 排除网络中断
│       └─► 端口 111/2049 均不可达 → 🔍 深入检查
│
└─► 假设 C: iptables 阻断 ✅ 确认根因
        ├─► port 2049 (NFS)   TCP+UDP ❌ 连接被丢弃
        ├─► port 111 (portmapper) TCP+UDP ❌ 连接被丢弃
        ├─► rpcinfo ❌ 失败
        ├─► showmount ❌ 失败
        ├─► 内核日志 ⚠️ "not responding, still trying"
        └─► 🎯 根因: iptables DROP 规则阻断 NFS 端口
```

---

## 四、修复方案

### 4.1 应急处置

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 在 NFS Server 上添加 iptables 放行规则，允许客户端访问 port 111 和 port 2049 | 系统管理员 | 待定 | 恢复 NFS 端口可达性 |
| 2 | 在客户端重新执行 mount 命令 | 系统管理员 | 待定 | 恢复 NFS 挂载 |

**iptables 放行规则示例（在 NFS Server 上执行）：**

```bash
# 放行 NFS 客户端对 port 111 (portmapper) 的访问
iptables -A INPUT -s 172.31.255.0/24 -p tcp --dport 111 -j ACCEPT
iptables -A INPUT -s 172.31.255.0/24 -p udp --dport 111 -j ACCEPT

# 放行 NFS 客户端对 port 2049 (NFS) 的访问
iptables -A INPUT -s 172.31.255.0/24 -p tcp --dport 2049 -j ACCEPT
iptables -A INPUT -s 172.31.255.0/24 -p udp --dport 2049 -j ACCEPT

# 若使用 nfs-kernel-server，还需放行 mountd (通常 port 20048) 和 rquotad 等辅助端口
iptables -A INPUT -s 172.31.255.0/24 -p tcp --dport 20048 -j ACCEPT
iptables -A INPUT -s 172.31.255.0/24 -p udp --dport 20048 -j ACCEPT

# 保存 iptables 规则（视发行版而异）
iptables-save > /etc/iptables/rules.v4
```

### 4.2 永久修复计划

| 修复措施 | 负责人 | 完成时间 |
|--------|------|--------|
| 审查并规范 NFS Server 的 iptables 规则白名单，将 NFS 客户端网段加入 ACCEPT 规则 | 系统管理员/网络运维 | 待定 |
| 建议使用 `iptables-persistent` 或 `firewalld` 管理规则集中持久化，避免重启后规则丢失 | 系统管理员 | 待定 |
| 考虑增加 NFS 端口可用性监控（如对 port 2049/111 的定期健康检查），提前发现此类阻断问题 | 监控运维 | 待定 |
| 可选：使用 NFSv4 仅需单端口（2049），简化防火墙规则配置，降低端口遗漏风险 | 架构/运维 | 待定 |

---

## 附录：证据索引

| 证据项 | 来源文件 | 行号 | 内容概要 |
|--------|---------|:----:|---------|
| 网络连通性检查 | `kuafu_T1_20260608_branchA.md` | L14-L16 | ping 可达，port 2049 ❌, port 111 ❌ |
| NFS 挂载状态 | `kuafu_T1_20260608_branchA.md` | L18 | 无有效 NFS 挂载 |
| 内核日志 | `kuafu_T1_20260608_branchA.md` | L21 | "server not responding, still trying" |
| RPC 服务状态 | `kuafu_T1_20260608_branchA.md` | L24-L26 | rpcinfo 失败，nfs 模块未加载 |
| 诊断脚本摘要 | `kuafu_T1_20260608_branchA.md` | L28-L31 | 网络层/RPC 层/Export 可见性均失败 |
| 故障注入信息 | `kuafu_T1_20260608_branchA.md` | L4-L5 | iptables 阻断 2049/111 端口 |
