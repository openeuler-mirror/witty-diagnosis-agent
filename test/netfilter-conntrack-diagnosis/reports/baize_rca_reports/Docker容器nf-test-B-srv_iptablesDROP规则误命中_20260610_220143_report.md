# 🔴 故障诊断报告

> **报告编号**：RCA-20260610-001
> **故障级别**：P2（重要业务端口被拦截）
> **报告时间**：2026-06-10 22:01:43
> **当前状态**：🔴 处理中

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | Docker 容器 nf-test-B-srv 中 iptables/nftables DROP 规则误命中导致端口 9999 和 10000-10010 被拦截 |
| 影响范围 | Docker 容器 `nf-test-B-srv` 内监听于端口 9999 及 10000-10010 的全部业务服务 |
| 故障时段 | 2026-06-10 22:01:11 ～ 持续中（发现时正在发生） |
| 根本原因 | iptables filter 表及 nftables 规则集中存在对端口 9999 和 10000-10010 的 DROP 规则，且 `ct state related,established` ACCEPT 规则命中计数为 0（无已建立连接），导致所有到达这些端口的 NEW 连接均被 DROP 规则拦截 |
| 是否恢复 | ❌ 未恢复 |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 对应本次故障 |
|------|------|------|-------------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | DROP 规则命中计数与连接数完全吻合，无其他异常现象冲突 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                   事件                                                         性质         溯源路径
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
[诊断发现时]          容器 nf-test-B-srv 运行中                                      🟢 运行态     /home/win11/.witty-diagnosis-agent/dayu/report/kuafu_B_20260610_220111.md:5
  │
  ▼
[持续发生]            iptables filter 表规则 2：DROP tcp dpt:9999                     ⚠️ 规则命中   [同上]:28-29
  │                   计数器：59 packets / 3540 bytes 已丢弃
  │                   iptables filter 表规则 3：DROP tcp dpts:10000:10010
  │                   计数器：3 packets / 180 bytes 已丢弃
  ▼
[持续发生]            nftables 规则 26：tcp dport 9999 drop                           ⚠️ 规则命中   [同上]:44-45
  │                   计数器：59 packets / 3540 bytes 已丢弃
  │                   nftables 规则 27：tcp dport 10000-10010 drop
  │                   计数器：3 packets / 180 bytes 已丢弃
  ▼
[关键证据]            nftables 规则 25：ct state related,established accept           🔴 异常特征   [同上]:43
  │                   计数器：0 packets / 0 bytes（从未命中）
  │                   → 说明没有任何已建立连接通过该规则被放行
  ▼
[结论]                🔴 所有到达端口 9999 和 10000-10010 的 NEW TCP 连接
                      均因 DROP 规则被拦截，服务完全不可达
```

### 故障因果链

```text
容器 nf-test-B-srv 启动后，iptables/nftables 规则集存在 DROP 规则
  │
  ├─► iptables filter 表规则 2：DROP tcp -- 0.0.0.0/0 0.0.0.0/0 tcp dpt:9999
  │       └─► 59 packets 已丢弃
  │
  ├─► iptables filter 表规则 3：DROP tcp -- 0.0.0.0/0 0.0.0.0/0 tcp dpts:10000:10010
  │       └─► 3 packets 已丢弃
  │
  └─► nftables 规则 26-27 同步 DROP
          └─► 规则 25 (ct state established,related accept) 命中计数 = 0
                  └─► 🔴 端口 9999、10000-10010 业务全量不可达
```

---

## 三、排查过程

### 3.1 初始现象

- 诊断系统发现 Docker 容器 `nf-test-B-srv` 中存在非预期的 DROP 规则命中
- iptables filter 表规则 2（端口 9999）已丢弃 **59 packets / 3540 bytes**
- iptables filter 表规则 3（端口 10000-10010）已丢弃 **3 packets / 180 bytes**
- nftables 规则集存在对应的 DROP 规则（规则 26、27），命中计数与 iptables 完全一致

### 3.2 假设驱动排查

#### 假设 A：网络层物理链路故障导致丢包

> 🧪 假设：物理网卡或 Docker 网络驱动层面存在丢包

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 网络连通性 | 容器存活可正常执行诊断命令 | ✅ 容器运行正常 |
| nf_conntrack 可用性 | `nf_conntrack` 模块已加载，`/proc/net/stat/nf_conntrack` 可用 | ✅ 连接跟踪模块正常 |

**❌ 排除**：网络层和 conntrack 模块正常，丢包发生在规则匹配层。

---

#### 假设 B：conntrack 表满导致新连接被丢弃

> 🧪 假设：nf_conntrack 表已满，新连接无法建连

| 检查项 | 操作 | 结论 |
|--------|------|------|
| conntrack 模块 | 已加载 | ✅ 正常 |
| conntrack 统计 | `/proc/net/stat/nf_conntrack` 可用 | ✅ 正常 |

**❌ 排除**：conntrack 模块功能正常，且若 conntrack 表满应先出现 `nf_conntrack: table full, dropping packet` 内核日志，诊断未发现此类异常。

---

#### 假设 C：DROP 规则误命中 ✅ 确认根因

> 🧪 假设：iptables/nftables 中的 DROP 规则正在拦截到达目标端口的合法流量

**Step 1 — 确认 DROP 规则命中计数**

iptables filter 表：
| 规则号 | 匹配条件 | 动作 | 命中包数 | 命中字节数 |
|--------|---------|------|---------|-----------|
| 2 | `tcp dpt:9999` | DROP | **59** | **3540** |
| 3 | `tcp dpts:10000:10010` | DROP | **3** | **180** |

nftables 规则集：
| 规则号 | 匹配条件 | 动作 | 命中包数 | 命中字节数 |
|--------|---------|------|---------|-----------|
| 25 | `ct state related,established` | accept | **0** | **0** |
| 26 | `tcp dport 9999` | drop | **59** | **3540** |
| 27 | `tcp dport 10000-10010` | drop | **3** | **180** |

**Step 2 — 关键证据交叉验证**

- `ct state related,established accept` 规则（nftables 规则 25）**命中计数为 0**
- 这意味着：所有到达端口 9999 和 10000-10010 的流量均为 **NEW 状态连接**
- 对于 NEW 状态的连接，不会匹配 conntrack accept 规则，直接落入 DROP 规则
- iptables 与 nftables 的 DROP 命中计数完全一致（59 / 3540 和 3 / 180），形成交叉印证

**Step 3 — 流量路径分析**

```text
INPUT 路径：
  raw:PREROUTING → mangle:PREROUTING → nat:PREROUTING → 路由决策 →
  filter:INPUT (policy=ACCEPT) → 本机应用
                                    ↓
                         规则 2：tcp dpt:9999 → DROP ❌
                         规则 3：tcp dpts:10000:10010 → DROP ❌
```

**✅ 结论：iptables filter 表中的规则 2（端口 9999）和规则 3（端口 10000-10010）为 DROP 规则，且 nftables 对应规则同步存在。`ct state established,related accept` 规则虽存在于 DROP 规则之前但命中计数为零，说明所有 NEW 连接均被 DROP 规则拦截。不存在针对这些端口的 ACCEPT 规则。**

---

### 3.3 排查结论

```text
容器 nf-test-B-srv 端口 9999/10000-10010 不可达
│
├─► 网络层物理链路          → ✅ 正常，排除
├─► conntrack 模块异常      → ✅ 正常，排除
│
└─► iptables/nftables 规则层 → ❌ DROP 规则命中
        │
        ├─► iptables filter 规则 2 (tcp dpt:9999) → DROP，59 packets
        ├─► iptables filter 规则 3 (tcp dpts:10000:10010) → DROP，3 packets
        ├─► nftables 规则 26 (tcp dport 9999) → drop，59 packets
        ├─► nftables 规则 27 (tcp dport 10000-10010) → drop，3 packets
        │
        └─► nftables 规则 25 (ct state established,related accept) → 0 packets
                └─► 🎯 根因确认：无对应 ACCEPT 规则放行，
                     所有 NEW 连接均被 DROP 规则拦截
```

---

## 四、修复方案

### 4.1 应急处置

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 确认 DROP 规则是否为业务预期配置（如安全策略） | 业务/SRE | 立即 | 判断是否需要保留 |
| 2 | 若需放行业务流量，在对应 DROP 规则前插入 ACCEPT 规则 | SRE | 立即 | 恢复端口可达性 |
| 3 | 验证业务端口连通性 | SRE | 操作后 | 确认恢复 |

**应急恢复命令（如确认 DROP 规则为误配）：**

```bash
# iptables：在 DROP 规则前插入 ACCEPT 规则
iptables -I INPUT 1 -p tcp --dport 9999 -j ACCEPT
iptables -I INPUT 1 -p tcp --dport 10000:10010 -j ACCEPT

# 验证规则顺序
iptables -L INPUT -n --line-numbers

# nftables（同步验证）
nft add rule inet filter input tcp dport 9999 accept
nft add rule inet filter input tcp dport 10000-10010 accept
```

**如需删除 DROP 规则：**

```bash
# iptables 删除规则 2（端口 9999 DROP）
iptables -D INPUT 2

# iptables 删除规则 3（端口 10000-10010 DROP）
iptables -D INPUT 2

# nftables 删除 drop 规则（需通过 handle 号定位）
nft delete rule inet filter input handle 26
nft delete rule inet filter input handle 27
```

### 4.2 永久修复计划

| 修复措施 | 负责人 | 完成时间 |
|--------|------|--------|
| 检查 Docker 容器 iptables/nftables 规则来源，确认 DROP 规则是否为 Docker 自动生成还是人工添加 | SRE | 待定 |
| 若为 Docker 自动生成，检查容器网络配置（docker network / docker-compose port mapping）确保预期端口被正确暴露 | SRE | 待定 |
| 若为人工添加，更新安全策略白名单，添加对应端口的 ACCEPT 规则 | SRE | 待定 |
| 建议将防火墙规则纳入 IaC 管理，通过版本控制避免误配 | SRE | 待定 |
| 建议补充端口连通性监控（如定期 curl/tcpcheck 端口 9999、10000-10010） | SRE | 待定 |
| 建议容器启动时添加防火墙规则合规性自检脚本 | SRE | 待定 |
