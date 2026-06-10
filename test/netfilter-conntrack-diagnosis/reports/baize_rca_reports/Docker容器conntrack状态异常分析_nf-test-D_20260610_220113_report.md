# Docker 容器 nf-test-D conntrack 状态异常故障诊断报告

> **报告编号**：RCA-20260610-NF001
> **故障级别**：P2（潜在风险类）
> **报告时间**：2026-06-10 22:05:56
> **当前状态**：🟡 已恢复（待验证）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | Docker 容器 nf-test-D conntrack 出现大量 UNREPLIED 条目(约200个)，配置了 ctstate INVALID DROP 规则可能导致丢包 |
| 影响范围 | Docker 容器 nf-test-D 的入站连接 |
| 故障时段 | 2026-06-10 13:50:00 ～ 2026-06-10 22:01:13（诊断时间，实际已自愈） |
| 根本原因 | **直接原因**：瞬时的并发连接突发导致 conntrack 表出现大量 UNREPLIED 条目（约200个），但在诊断收据时已被 conntrack GC 自动清理；**根本风险**：conntrack timeout 配置过于激进（tcp_timeout_established=10s, udp_timeout=5s），以及 ctstate INVALID DROP 规则存在的潜在丢包隐患 |
| 是否恢复 | ✅ 已恢复（UNREPLIED 条目在诊断时已归零，规则未实际触发） |
| 根因置信度 | 🟡 中置信度（现象已消失，基于间接证据推断） |

### 置信度说明

| 等级 | 标识 | 含义 | 适用场景 |
|------|------|------|--------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | — |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | ✅ 当前场景：200 个 UNREPLIED 条目已消失，依赖日志交叉验证 |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                   事件                                                      性质         溯源路径
───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-06-10 13:50:00   业务突发流量→容器 nf-test-D 产生约200个 conntrack UNREPLIED  📈 外部触发   [故障报告描述]
                       条目（疑似 DNS/UDP 短连接或 TCP SYN 突发）
  │
  ▼
2026-06-10 13:52:00   kuafu_A 报告 nf-test-A 出现 "nf_conntrack: table full,       ⚠️  系统告警   [kuafu_A_conntrack_full.md:66-71]
                       dropping packet"(90+条 dmesg 告警)，conntrack 表满溢出
  │                   同集群其他容器出现 conntrack 过载，印证流量突发背景
  ▼
2026-06-10 ~13:55     并发连接逐渐完成/超时。由于 conntrack timeout 配置极度激进      🔄 自愈过程   [kuafu_F_20260610_220115.md:127-137]
                      (tcp_timeout_established=10s, udp_timeout=5s,               (超时配置)
                       tcp_timeout_time_wait=5s)，UNREPLIED 条目被快速 GC 清理
  │
  ▼
2026-06-10 22:01:13   Kuafu 分支 D 诊断采集时，conntrack 状态全部清零                🟢 已自愈      [kuafu_D_20260610_220113.md:20-26]
                      (INVALID=0, UNREPLIED=0, TCP=0, UDP=0)                     (诊断结果)
  │                   DROP 规则命中计数为 0（从未触发）
  │
  ═══════════════════════════════════════════════════════════════════════════════
  ⚠️  潜在风险（未完全消除）：                                    🟡 风险持续
      1. ctstate INVALID DROP 规则已配置 → 若因超时过短导致 conntrack
         提前回收合法连接，后续报文将被标记为 INVALID 并 DROP
      2. conntrack timeout 配置畸低（established=10s）→ 长连接会被
         频繁提前切断，产生大量 INVALID 状态并触发 DROP
```

### 故障因果链

```text
流量突发（并发连接数飙升）
    │
    ├─► conntrack 表产生约 200 个 UNREPLIED 条目
    │       └─► 正常现象：短连接在收到回包前处于 UNREPLIED 状态
    │
    ├─► conntrack timeout 配置过于激进（tcp_timeout_established=10s）
    │       └─► 连接很快被 GC 回收，UNREPLIED 条目自动消失
    │
    └─► ctstate INVALID DROP 规则已配置但未触发
            └─► 风险：若 conntrack 在连接仍有流量时提前回收，
                   后续报文 → INVALID → 被 DROP → 业务中断
                   
    └─► 🎯 诊断结论：当前系统已恢复，但存在潜在的丢包风险
```

---

## 三、双轨分析

> 依据 `netfilter-conntrack-diagnosis` 方法论，执行"规则链轨道 + conntrack 轨道"并行双轨分析。

### 3.1 轨道一：规则链分析（正向追踪）

#### R1 规则链拓扑

容器 nf-test-D 的 iptables 规则链中出现以下 stateful 规则：

| 表 | 链 | 规则 | 动作 | 命中计数 |
|----|----|------|------|---------|
| filter | INPUT | `-m conntrack --ctstate INVALID -j DROP` | DROP | pkts=0 / bytes=0 |
| nftables | — | `ct state invalid counter packets 0 bytes 0 drop` | drop | pkts=0 / bytes=0 |

#### R2 命中计数核查

- **iptables DROP 规则命中计数**：pkts=0（从未匹配任何报文）
- **nftables drop 规则命中计数**：pkts=0 / bytes=0（从未匹配任何报文）
- 两条规则的命中计数均为零，说明 **截至目前，该 DROP 规则从未产生实际丢包**

#### R3 匹配语义分析

- 规则条件：`ctstate INVALID` 匹配 conntrack 状态机判定为无效的连接报文
- 规则动作：`DROP` 丢弃匹配的报文
- 潜在触发场景：
  - TCP 窗口违规（tcp_be_liberal=0 时 window violation）
  - 校验和错误（网卡 offload 问题）
  - conntrack 表满后新连接被拒绝、但仍有后续报文到达
  - conntrack 超时回收后，同一五元组的后续报文
- **当前未触发**：说明上述场景尚未发生

#### R4 流量路径推导

```
入站报文 → raw:PREROUTING → mangle:PREROUTING → nat:PREROUTING
    → 路由决策（本机目的地）
    → filter:INPUT
        → ✂️ [rule: ctstate INVALID → DROP] (pkts=0, 未触发)
        → 【ACCEPT 默认策略】→ 本机应用
```

**结论**：规则链配置无误，当前未产生任何 DROP 动作。但规则的存在意味着一旦条件满足（产生 INVALID entry），流量将被静默丢弃。

---

### 3.2 轨道二：conntrack 分析（逆向溯源）

#### C0 模块可用性检查

| 检查项 | 结果 |
|--------|------|
| nf_conntrack 模块加载 | ✅ 已加载 |
| /proc/net/stat/nf_conntrack 可用 | ✅ 可用 |
| **分析可行性** | **✅ conntrack 双轨完全可行** |

#### C1 容量分析

| 指标 | 值 | 分析 |
|------|----|------|
| 当前条目数 (count) | 0 | 诊断时 conntrack 表完全为空 |
| 最大条目数 (max) | 4096（来自 kuafu_A 同环境） | 容量阈值为 4096 |
| 使用率 | 0.0% | 完全空闲 |

#### C2 状态分布（诊断时刻）

| 协议/状态 | 数量 | 说明 |
|-----------|------|------|
| TCP | 0 | 无 TCP 连接跟踪条目 |
| UDP | 0 | 无 UDP 连接跟踪条目 |
| ICMP | 0 | 无 ICMP 条目 |
| INVALID | 0 | ✅ 无无效条目 |
| UNREPLIED | 0 | ✅ 无未回复条目（故障现象已消失） |

#### C3 NAT 映射核验

诊断未报告 NAT 条目，容器 nf-test-D 无活跃的 NAT 映射。本分支非 NAT 相关问题。

#### C4 丢包计数定位

| CPU | found | drop | early_drop | insert_failed | 分析 |
|-----|-------|------|------------|---------------|------|
| cpu=0~14 | 0 | 0 | 0 | 0 | 无 conntrack 活动 |
| cpu=15 | **400** | 0 | 0 | 0 | ⚠️ 所有 conntrack 处理集中在单一 CPU |

**关键发现**：
- 全部 conntrack 处理集中在 **cpu=15**（found=400），其他 CPU 均为 0
- 所有丢包计数器（drop, early_drop, insert_failed）均为 0
- 说明 nf_conntrack 子系统的哈希分配策略将所有连接映射到了单个 CPU

#### 交叉关联：kuafu_F 超时配置分析

从 kuafu_F（同一轮诊断、同环境的另一容器）获取的超时参数：

| 参数 | 当前值 | 推荐值 | 偏差程度 | 风险等级 |
|------|--------|--------|---------|---------|
| tcp_timeout_established | **10s** | 432000s (5天) | **仅 0.002%** | 🔴 严重偏离 |
| tcp_timeout_time_wait | **5s** | 120s | **仅 4%** | 🟡 过于激进 |
| udp_timeout | **5s** | 30s | **仅 17%** | 🟡 过于激进 |
| udp_timeout_stream | 120s | 180s | 67% | 🟡 偏低 |
| tcp_timeout_fin_wait | 120s | 120s | 100% ✅ | — |
| tcp_timeout_syn_recv | 60s | 60s | 100% ✅ | — |
| tcp_timeout_syn_sent | 120s | 120s | 100% ✅ | — |
| icmp_timeout | 30s | 30s | 100% ✅ | — |

---

### 3.3 交叉验证结果

| 验证维度 | 规则链结论 | conntrack 结论 | 是否吻合 |
|---------|-----------|---------------|---------|
| 丢包原因 | DROP 规则 pkts=0，未产生丢包 | 所有丢包计数为 0 | ✅ 吻合 |
| 流量方向 | 规则作用于 INPUT 链（入站） | 无活跃入口 | ✅ 吻合 |
| NAT 映射 | 无 NAT 规则 | 无 NAT 条目 | ✅ 吻合 |
| stateful 规则 | ctstate INVALID DROP 已配置但未触发 | INVALID=0，无触发条件 | ✅ 吻合 |

**综合判断**：
- 双轨结论完全一致，无矛盾
- **当前系统状态**：conntrack 子系统健康，无丢包、无异常条目
- **根本风险**：ctstate INVALID DROP 规则存在 + 超时配置畸短 = 潜在丢包风险
- **置信度**：🟡 中置信度（故障现象已消失，依赖间接证据与交叉推理）

---

## 四、排查过程

### 4.1 初始现象

- **上游报告**：Docker 容器 nf-test-D 出现 conntrack UNREPLIED 条目约 200 个
- **规则配置**：该容器 iptables INPUT 链配置了 `-m conntrack --ctstate INVALID -j DROP`
- **怀疑方向**：conntrack 状态异常导致丢包

### 4.2 假设驱动排查

#### 假设 A：200 个 UNREPLIED 条目导致 conntrack 表满丢包

| 检查项 | 操作 | 结论 |
|--------|------|------|
| conntrack 条目计数 | 诊断时 count=0 | ✅ 表已空，未过载 |
| drop/insert_failed | 全部为 0 | ✅ 无丢包计数 |
| **结论** |—| **❌ 排除**：UNREPLIED 条目已被自动清理 |

#### 假设 B：ctstate INVALID DROP 规则实际产生了丢包

| 检查项 | 操作 | 结论 |
|--------|------|------|
| iptables 规则 pkts 计数 | pkts=0 | ✅ 规则从未命中 |
| nftables 规则计数器 | packets=0 bytes=0 | ✅ 规则从未触发 |
| conntrack INVALID 条目数 | 0 | ✅ 无 INVALID 状态 |
| **结论** |—| **❌ 排除**：DROP 规则未产生实际丢包 |

#### 假设 C：conntrack 超时过短导致连接被提前回收 → 产生 INVALID → 触发 DROP ✅ 确认根本风险

| 检查项 | 操作 | 结论 |
|--------|------|------|
| tcp_timeout_established | **10s**（kuafu_F 数据） | ✅ **异常**：推荐 432000s |
| udp_timeout | **5s**（kuafu_F 数据） | ✅ **异常**：推荐 30s |
| tcp_timeout_time_wait | **5s**（kuafu_F 数据） | ✅ **异常**：推荐 120s |
| 是否已触发 DROP | pkts=0 尚未触发 | ✅ **当前未触发，但风险持续存在** |
| **结论** |—| **✅ 确认：超时配置极端异常，是潜在根因** |

### 4.3 排查结论

```text
nf-test-D conntrack 状态异常（200 UNREPLIED）
│
├─► 假设 A：conntrack 表满丢包
│       └─→ count=0, drop=0 → ❌ 排除
│
├─► 假设 B：ctstate INVALID DROP 实际丢包
│       └─→ pkts=0 → ❌ 排除
│
└─► 假设 C：超时配置极端异常 + DROP 规则构成潜在风险 ✅ 确认
        │
        ├─► tcp_timeout_established=10s（推荐 432000s） → 🔴 严重异常
        ├─► udp_timeout=5s（推荐 30s）                 → 🟡 异常
        ├─► tcp_timeout_time_wait=5s（推荐 120s）      → 🟡 异常
        │
        └─► ctstate INVALID DROP 规则已配置且就绪
                └─► 一旦连接在仍有流量时被 conntrack 回收
                     → 后续报文被判 INVALID → DROP
                     → 🎯 根本风险确认
```

---

## 五、修复方案

### 5.1 应急处置（如再次出现 UNREPLIED 大量增长）

| 步骤 | 操作 | 执行人 | 风险等级 | 效果 |
|------|------|--------|---------|------|
| 1 | 确认突发的流量来源：`docker logs nf-test-D` 或 `conntrack -L -n` 查看条目明细 | 运维/SRE | 🟢 低危 | 定位流量源 |
| 2 | 如连接数持续增长，临时调整超时：`sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=432000` | 运维/SRE | 🟡 中危 | 防止合法连接被提前回收 |
| 3 | 如需扩大 conntrack 容量：`sysctl -w net.netfilter.nf_conntrack_max=1048576` | 运维/SRE | 🟡 中危 | 防止表满丢包 |

### 5.2 永久修复计划

| 修复措施 | 风险等级 | 详细操作 | 回滚方案 |
|---------|---------|---------|---------|
| **1. 调整 conntrack 超时参数至合理值** | 🟡 中危 | 编辑 `/etc/sysctl.conf` 或容器 sysctl 配置：<br>`net.netfilter.nf_conntrack_tcp_timeout_established = 432000`（5天）<br>`net.netfilter.nf_conntrack_tcp_timeout_time_wait = 120`<br>`net.netfilter.nf_conntrack_udp_timeout = 30` | 恢复为原值后 `sysctl -p` |
| **2. 评估 ctstate INVALID DROP 规则的必要性** | 🟡 中危 | 确认该规则是否为安全基线的一部分。如果是防御性配置，建议保留；但需确保超时参数合理，避免合法流量被误杀。如果非必要，可删除该规则：<br>`iptables -D INPUT -m conntrack --ctstate INVALID -j DROP` | 重新添加规则 |
| **3. 优化 conntrack 哈希分布** | 🟢 低危 | 检查 `nf_conntrack_buckets` 配置，增大哈希桶数以改善多 CPU 分布：<br>`sysctl -w net.netfilter.nf_conntrack_buckets=262144` | 恢复原值 |
| **4. 监控告警完善** | 🟢 低危 | 为 conntrack 使用率添加监控告警，阈值设为 80%：<br>`current/max > 80% → 告警` | — |

### 5.3 风险等级说明

> ⚠️ **Agent 只提供修复建议，严禁自动执行**

| 风险等级 | 说明 |
|---------|------|
| 🔴 **高危** | 可能导致服务中断、连接断开、安全策略失效的操作 |
| 🟡 **中危** | 可能影响部分服务或需谨慎评估的操作 |
| 🟢 **低危** | 风险较低，通常可安全执行的操作 |

---

## 六、验证建议

### 6.1 根因确认

1. **复现验证**：在低峰期，向容器 nf-test-D 发送大量短连接（如 HTTP GET / DNS 查询），观察：
   - conntrack 是否出现 UNREPLIED 条目：`conntrack -L -n | grep UNREPLIED | wc -l`
   - iptables DROP 计数是否增长：`iptables -L INPUT -n -v | grep INVALID`
2. **超时验证**：确认当前超时值：`sysctl net.netfilter.nf_conntrack_tcp_timeout_established`

### 6.2 修复验证

| 验证项 | 验证方法 | 预期结果 |
|--------|---------|---------|
| 超时参数生效 | `sysctl net.netfilter.nf_conntrack_tcp_timeout_established` | 应为 432000 |
| DROP 规则状态 | `iptables -L INPUT -n -v` | 确认规则存在或已被移除 |
| conntrack 容量 | `sysctl net.netfilter.nf_conntrack_max` | 建议 ≥ 1048576 |
| conntrack 使用率 | 监控 conntrack 当前条目数/max | 应在 80% 以下 |

---

## 七、附录

### 7.1 分析数据源

| 数据源 | 路径 | 用途 |
|--------|------|------|
| Kuafu 分支 D 报告 | `/home/win11/.witty-diagnosis-agent/dayu/report/kuafu_D_20260610_220113.md` | 容器 nf-test-D conntrack 诊断数据 |
| Kuafu 分支 F 报告 | `/home/win11/.witty-diagnosis-agent/dayu/report/kuafu_F_20260610_220115.md` | conntrack timeout 配置对照 |
| Kuafu 分支 A 报告 | `/home/win11/.witty-diagnosis-agent/dayu/report/kuafu_A_conntrack_full.md` | 同环境 conntrack 表满溢出证据 |

### 7.2 使用的分析技能

- `fault-rca-report-generation`：故障诊断根因分析与报告生成方法论
- `netfilter-conntrack-diagnosis`：Netfilter/conntrack 双轨分析模型

---

*本报告由 Baize（白泽）Phase 1.4 分析与报告 Agent 自动生成*
