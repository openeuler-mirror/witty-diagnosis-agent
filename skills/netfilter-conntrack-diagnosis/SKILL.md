---
name: netfilter-conntrack-diagnosis
description: >
  Netfilter / iptables / conntrack 防火墙与连接跟踪深度诊断技能（双轨：规则链 + conntrack）。
  当用户提到 nf_conntrack 表满、防火墙丢包、iptables DROP、NAT 映射异常、conntrack INVALID 丢包、
  nftables 规则误命中、SNAT/DNAT 失败、连接跟踪超时、ipset 匹配异常、ct helper/ALG 问题等关键词时，
  必须使用本技能。覆盖场景：nf_conntrack_max 溢出丢包、iptables/nftables 规则误命中导致 DROP/REJECT、
  NAT/SNAT/DNAT 映射异常、conntrack 状态(INVALID/UNREPLIED/UNESTABLISHED)丢包、TCP window tracking 异常、
  ct timeout 超时、helper/ALG 协议辅助模块异常、ipset 匹配失效。诊断定位路径：规则链遍历 → conntrack 表状态
  → NAT 映射验证 → 内核丢包计数点定界。与 network-diagnosis（通用 IP/路由/ARP/接口诊断）区隔。
  本技能聚焦 Linux 内核 Netfilter 框架本身的问题，而非通用网络连通性。
---

# Netfilter / iptables / conntrack 防火墙与连接跟踪诊断（双轨：规则链 + conntrack）

## 第一节：故障目录结构

```text
netfilter_case/              # 故障诊断案例目录
├── baseline/                # 基线采集数据（由 01_collect_baseline.sh 生成）
│   ├── ruleset/             # 规则链快照（iptables/nftables 规则及命中计数）
│   ├── conntrack/           # conntrack 快照（条目状态分布、容量、NAT 映射）
│   └── counters/            # 内核计数器（/proc/net/stat/nf_conntrack 丢包计数）
├── logs/                    # 【可选】故障时间窗口内的系统日志/dmesg
├── tcpdump/                 # 【可选】故障时间窗口内的抓包文件
└── reports/                 # 诊断报告输出
```

```bash
# Step 1：在故障主机上执行基线采集
cd netfilter_case && bash /path/to/scripts/01_collect_baseline.sh --out ./baseline

# Step 2：根据基线结果选择分支脚本深入分析
bash /path/to/scripts/branch_A_conntrack_full.sh ./baseline
```

> ⚠️ **【绝对禁止】安全红线声明** ⚠️
>
> 1. **【严禁自动执行修复命令】**：禁止自动执行任何修复类命令（包括但不限于：修改/清空 iptables/nftables 规则、修改 conntrack 内核参数、刷新 conntrack 表、重启防火墙服务等）。
>
> 2. **【只提供诊断证据和建议】**：Agent 只能提供诊断结论和修复建议，由用户自行决定是否执行。
>
> 3. **【必须标注风险等级】**：所有修复建议必须标注风险等级：
>    - 🔴 **高危**：可能导致服务中断、连接断开、安全策略失效的操作
>    - 🟡 **中危**：可能影响部分服务或需谨慎评估的操作
>    - 🟢 **低危**：风险较低，通常可安全执行的操作
>
> 4. **【高危操作必须包含回滚方案】**：高危操作建议必须同时提供回滚方案。

---

## 第二节：分析策略（并行双轨，交叉验证）

**规则链分析和 conntrack 分析应同时进行，而非先后顺序。** 两条轨道相互独立推进，最终交叉比对以确认根因。

```
┌────────────────────────────────────────────────────────────────────┐
│                    并行双轨分析模型                                  │
│                                                                     │
│  轨道一：规则链分析（正向）        轨道二：conntrack 分析（逆向）     │
│  ────────────────────────        ───────────────────────────       │
│  从规则链遍历出发，正向追踪         从连接跟踪表出发，逆向溯源         │
│                                                                     │
│  回答：什么规则命中了？              回答：conntrack 表状态是否       │
│        流量匹配了哪条链？                  导致丢包或映射错误？      │
│                                                                     │
│            ↓                                   ↓                    │
│            └────────────── 交叉验证 ────────────┘                   │
│                                                                     │
│  见：第三节（统一分析流程：分支决策→双轨并行→交叉验证→输出）         │
└────────────────────────────────────────────────────────────────────┘
```

**两条轨道的分工与互补**：

| | 规则链轨道 | conntrack 轨道 |
|--|-----------|---------------|
| **优势** | 精确的规则命中计数、完整规则链拓扑、明确的 DROP/REJECT 动作 | 真实的连接跟踪状态、NAT 映射快照、超时和溢出计数 |
| **局限** | 不感知连接状态（stateless）、无法判断 conntrack 内部状态机 | 不感知规则匹配顺序、无法判断规则逻辑错误 |
| **典型盲区** | stateful 规则依赖 conntrack 状态，但无法独立验证 | NAT 映射正确但规则链未放行导致丢包 |

**何时两条轨道都必须做**：有 conntrack 相关故障怀疑时，两条轨道必须同时进行。

**何时只能走规则链轨道**：纯 stateless 防火墙规则问题（无 NAT/无状态连接跟踪），可仅走规则链分析，但需在结论中标注。

---

## 第三节：统一分析流程（分支决策 → 双轨并行 → 交叉验证 → 输出）

本节将"基线采集 + 规则链轨道 + conntrack 轨道 + 交叉验证"融合为一条可直接照做的统一流程。

> 执行约束：所有分析脚本的默认超时时间为 **3 分钟（180s）**。

### Step 1：启动（基线信息收集 + 分支推荐）

运行：

```bash
bash scripts/01_collect_baseline.sh
```

记录输出中的四类关键信息（后续所有步骤都围绕它们推进）：

- 规则链状态（iptables/nftables 各表链结构和命中计数）
- conntrack 容量（当前条目数、`nf_conntrack_max`、使用率）
- conntrack 丢包计数（`/proc/net/stat/nf_conntrack` 中的 drop、early_drop、insert_failed）
- 关键告警（dmesg 中的 "table full"、"dropping packet" 等关键词）

### Step 2：故障类型定界（选择分支脚本一键跑）

按 Step 1 输出推荐，执行对应分支脚本：

```bash
bash scripts/branch_X_xxx.sh [基线采集目录]
```

说明：每个 `branch_X_xxx.sh` 已内置规则链和 conntrack 双轨的分析命令序列。

若 Step 1 输出推荐多个分支脚本，必须按以下优先级顺序全部执行，不可只选其一：

```
优先级 1: nf_conntrack 表满（drop 最多，影响面最广）
优先级 2: 规则误命中 DROP/REJECT（明确丢包）
优先级 3: NAT 映射异常（影响连接建立）
优先级 4: ct 状态丢包 / timeout / window / helper / ipset
```

脚本对应执行参考如下：

```
基线信息中的关键信号
  ├─ dmesg 含 "nf_conntrack: table full, dropping packet"            → 分支A: nf_conntrack 表满
  ├─ iptables/nftables 含 DROP/REJECT 规则且 pkts > 0                → 分支B: 规则误命中
  ├─ conntrack 含 NAT 映射异常/SNAT 未生效/回包 DNAT 不匹配          → 分支C: NAT 映射异常
  ├─ conntrack 含 大量 INVALID/UNREPLIED 状态的 entry                → 分支D: ct 状态丢包
  ├─ /proc/net/stat/nf_conntrack 含 tcp_window 计数异常增长          → 分支E: TCP window tracking
  ├─ sysctl 含 conntrack timeout 与业务预期不匹配                    → 分支F: ct timeout 超时
  ├─ lsmod 含 FTP/SIP/TFTP 等协议 ALG 模块未加载或连接异常           → 分支G: helper/ALG 故障
  └─ ipset/iptables 含 ipset 匹配计数不为零但预期不应匹配/应匹配但计数为零 → 分支H: ipset 匹配异常
```

### Step 3：规则链分析（轨道一：回答"什么规则命中了流量？"）

从 iptables/nftables 规则链出发，完成四步证据链：

- **R1 规则链拓扑还原**：确认 iptables 表链结构（raw→mangle→nat→filter→security），nftables 链 hook 点和优先级
- **R2 规则命中计数核查**：逐条检查 DROP/REJECT 规则的 `pkts` 计数，确认哪些规则实际生效
- **R3 规则匹配语义分析**：结合协议/端口/接口/in 参数判断规则是否与故障流量匹配
- **R4 规则链流量路径推导**：根据 `policy`（ACCEPT/DROP）、链跳转（`-j`）、RETURN 规则，推导整条流量路径的最终动作

输出（供交叉验证使用）：

```
R1 规则链拓扑：table > chain > rule 层次结构
R2 命中计数：<chain>:<rule#> pkts=<N> target=<DROP/REJECT/ACCEPT>
R3 匹配语义：[匹配条件] 是否符合故障流量特征？ □ 吻合 □ 不吻合
R4 路径推导：从 <input_chain> 到 <最终动作> 的全路径
```

### Step 4：conntrack 分析（轨道二：回答"连接跟踪表状态是否导致丢包？"）

从 conntrack 表状态出发，完成五步证据链：

#### C0：模块可用性检查（防止误判）

```bash
# 确认 nf_conntrack 模块已加载
lsmod | grep nf_conntrack

# 确认 procfs 接口可用
cat /proc/net/stat/nf_conntrack

# 若模块未加载，后续所有 conntrack 分析不可行
# 结论标注："conntrack 模块未加载，轨道二不可用"
```

模块未加载的典型原因：
- 内核未编译 `CONFIG_NF_CONNTRACK`（少见）
- 系统未加载 `nf_conntrack` 模块（`modprobe nf_conntrack` 可解决）
- 容器环境未加载内核模块

模块不可用时降级：仅走规则链轨道，在结论中标注"conntrack 轨道不可用"。

#### C1：conntrack 表容量检查

当前条目数 vs `nf_conntrack_max`，使用率是否超过 90% 阈值。

#### C2：conntrack 状态分布

聚合统计各协议各状态的 entry 数（ESTABLISHED / TIME_WAIT / CLOSE / INVALID / UNREPLIED）。

#### C3：NAT 映射核验

检查 SNAT/DNAT 映射表，确认源/目的 IP+端口转换是否正确。

#### C4：丢包计数点定位

读取 `/proc/net/stat/nf_conntrack` 中的 `drop` / `early_drop` / `insert_failed` 计数。

输出（供交叉验证使用）：

```
C1 容量：<current>/<max> = <usage%>（阈值 90%）
C2 状态分布：ESTABLISHED=<N> INVALID=<M> UNREPLIED=<K> ...
C3 NAT 核验：预期转换 <X.X.X.X:port → Y.Y.Y.Y:port> □ 正确 □ 异常
C4 丢包计数：drop=<V1> early_drop=<V2> insert_failed=<V3>
```

### Step 5：交叉验证（双轨汇合，冲突仲裁，置信度收敛）

对每条证据做对齐检查：

| 验证维度 | 规则链结论 | conntrack 结论 | 是否吻合？ |
|---------|-----------|---------------|-----------|
| 丢包原因 | 规则 R<#> DROP 计数增长 | conntrack 丢包计数正常 | □ 吻合 □ 不符 |
| 流量方向 | 规则匹配方向为 IN/OUT/FORWARD | conntrack 方向确认 | □ 吻合 □ 不符 |
| NAT 映射 | 规则链存在 NAT 规则 | conntrack NAT entry 确认转换 | □ 吻合 □ 不符 |
| stateful 规则 | 规则依赖 ct state 匹配 | conntrack 状态符合/不符合条件 | □ 吻合 □ 不符 |

不一致时的仲裁原则：

```
丢包原因仲裁：
  - 规则 pkts > 0 且 target=DROP → 规则丢包为主因（规则链结论优先）
  - 规则无 DROP 命中但 nf_conntrack drop 计数增长 → conntrack 丢包（conntrack 结论优先）
  - 两者都增长 → 复合原因，需叠加分析
NAT 映射仲裁：以 conntrack 实际 entry 中的 NAT 转换记录为准（conntrack 优先）
```

置信度收敛：

- **高**：两轨完全吻合 + 内核计数器和规则计数双向验证通过
- **中**：两轨基本吻合，但有 1 个维度依赖推断
- **低**：两轨存在矛盾且无法解释；或关键计数无法获取
- **无法定界**：既无规则命中也无 conntrack 丢包计数，需回退到 network-diagnosis 检查路由/接口

常见误判陷阱（用于复核结论质量）：

- 规则计数增长 ≠ 故障原因：DROP 规则的 pkts 增长可能源于正常的安全策略（如防扫描），需确认匹配条件是否与故障流量重叠
- conntrack INVALID 不一定是根因：INVALID 可能是校验和错误（offload 问题）或 tcp_be_liberal=0 的 window violation，需区分来源
- conntrack 表未满但仍有丢包：insert_failed 增长但使用率不高说明可能是内存分配失败，而非容量问题
- NAT 映射正确但业务不通：需检查 FORWARD 链是否放行了转换后的流量，DNAT 后流量走 FORWARD 链

### Step 6：最终输出（按第九节模板落盘）

将 Step 3/4/5 的输出填入第九节报告结构，并显式写清：结论、证据链、排除项、修复建议、验证建议。

---

## 第四节：轨道一 —— 规则链分析（正向追踪）

本节已合并进第三节的统一流程（Step 3）。

详细内容见第三节 Step 3（R1-R4 证据链）。

---

## 第五节：轨道二 —— conntrack 分析（逆向溯源）

本节已合并进第三节的统一流程（Step 4）。

详细内容见第三节 Step 4（C0-C4 证据链，C0 为模块可用性预检）。

---

## 第六节：交叉验证与结论收敛（双轨汇合）

本节已合并进第三节的统一流程（Step 5）。

详细内容见第三节 Step 5（验证维度、仲裁原则、置信度收敛）。

---

## 第七节：故障类型决策树（两条轨道共用）

本节内容已合并进第三节的统一流程（Step 2）。

---

## 第八节：注意事项与置信度评级

本节内容已合并进第三节的统一流程（Step 5）。

置信度评级标准已在 Step 5 中定义。注意事项包括：

- 规则链分析优先于 conntrack 分析：当规则已有明确的 DROP/REJECT 命中计数时，先回答"规则是否按预期工作"再深入 conntrack
- conntrack 分析依赖 nf_conntrack 模块加载：如果模块未加载（`lsmod | grep nf_conntrack` 为空），conntrack 轨道不可用，参见 Step 4 C0 预检
- 无计数器数据时需降级：如果 `/proc/net/stat/nf_conntrack` 不可用（内核未编译 CONFIG_NF_CONNTRACK_PROCFS），需使用 `conntrack -S` 替代
- C0 模块预检不可跳过：在进入 C1-C4 分析前必须确认模块可用，否则结论无效
- 时间窗口一致性验证：故障时间窗口内的计数增量才有效，需排除历史计数干扰

---

## 第九节：最终报告结构

```
## 崩溃概要
   故障模式：<nf_conntrack 表满 / 规则误命中 / NAT 映射异常 / ct 状态丢包 / ...>
   置信度：<高/中/低/无法定界>
   分析轨道：[双轨（规则链 + conntrack）| 单轨（仅规则链）]
   内核版本：<版本号>
   故障时间窗口：<开始时间 - 结束时间>

## 规则链轨道结论（轨道一）
   R1 规则链拓扑：<table:chain:rule 结构总览>
   R2 命中计数：
     - <chain>:#<rule> pkts=<N> target=<DROP/REJECT/ACCEPT> → <匹配条件>
     - <chain>:#<rule> pkts=<N> target=<DROP/REJECT/ACCEPT> → <匹配条件>
   R3 匹配语义分析：<规则是否匹配故障流量特征>
   R4 流量路径推导：<从 ingress 到 egress 的完整规则链路径>

## conntrack 轨道结论（轨道二）
   C1 容量：<current>/<max> = <usage%>
   C2 状态分布：
     - ESTABLISHED: <N>
     - INVALID: <N>
     - UNREPLIED: <N>
     - TIME_WAIT: <N>
     - 其他: <N>
   C3 NAT 映射核验：<预期转换 vs 实际转换>
   C4 丢包计数：drop=<V1> early_drop=<V2> insert_failed=<V3>

## 交叉验证结果（有 conntrack 数据时填写）
   丢包原因吻合：     □ 是  □ 否（差异说明：<...>）
   流量方向吻合：     □ 是  □ 否（差异说明：<...>）
   NAT 映射吻合：     □ 是  □ 否（差异说明：<...>）
   stateful 规则吻合： □ 是  □ 否（差异说明：<...>）
   综合判断：<两轨结论是否一致，若有矛盾如何解释>

## 完整因果链（双轨收敛后）
   [触发条件] → [<规则/配置/容量> 问题] → [丢包/映射异常]
   → [影响流量路径] → [业务感知表现]

## 排除的替代假设
   - <假设X>：排除原因 <...>

## 修复建议
   > ⚠️ **Agent 只能提供修复建议，严禁自动执行**

   立即修复（立即可做）：
     <具体修复命令，标注风险等级>
   根本修复（设计层面）：
     <更深层的配置/架构/容量优化>

## 验证建议
   <如何确认根因 + 如何验证修复有效>
```

---

## 第十节：参考文件

- `references/conntrack_reference.md`：conntrack 内核机制、参数调优、状态机详细说明
- `references/iptables_nftables_reference.md`：iptables/nftables 命令速查、规则解读方法
- `references/nat_reference.md`：NAT/SNAT/DNAT/MASQUERADE 映射分析与故障排查
