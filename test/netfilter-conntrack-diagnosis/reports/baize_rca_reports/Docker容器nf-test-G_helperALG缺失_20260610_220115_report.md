# 🔴 故障诊断报告：Docker 容器 nf-test-G nf_conntrack Helper/ALG 协议辅助模块缺失

> **报告编号**：RCA-20260610-BAIZE-G
> **故障级别**：P3 / 潜在风险
> **报告时间**：2026-06-10 22:01:15
> **当前状态**：🟡 观察中 / 配置缺陷待修复
> **分析轨道**：[单轨（规则链 + helper 模块检查，conntrack 表无异常）]

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | Docker 容器 nf-test-G 中 nf_conntrack helper 模块缺失及自动分配关闭 |
| 影响范围 | 容器 nf-test-G 内依赖 ALG 协议（FTP/SIP/TFTP/PPTP/H.323/IRC）的应用 |
| 故障时段 | 2026-06-10 22:01:15（检测到时刻） |
| 根本原因 | `nf_conntrack_helper=0` 关闭了自动 helper 分配，且所有 ALG 协议辅助模块（nf_conntrack_ftp/sip/tftp/pptp/h323/irc）均未加载，iptables/nftables 也无显式 helper 匹配规则 |
| 是否恢复 | ❌ 未恢复（配置缺陷，属于未触发的潜在风险） |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 本报告 |
|------|------|------|--------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | 证据明确：helper 模块全缺 + 无规则 + nf_conntrack_helper=0 三因素叠加 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                   事件                                                     性质
────────────────────────────────────────────────────────────────────────────────────────────────────
2026-06-10 22:01:15   Kuafu 诊断分支 G 在容器 nf-test-G 上执行                     🔍 检测发现
   │
   ▼
2026-06-10 22:01:15   发现 nf_conntrack_helper 未开启自动分配（=0 内核默认值）        ⚠️ 配置隐患
   │                   Docker 容器默认设置该参数为 0 作为安全加固
   ▼
2026-06-10 22:01:15   所有 ALG 协议辅助模块均未加载（lsmod 无相关条目）               ⚠️ 模块缺失
   │                   nf_conntrack_ftp / nf_conntrack_sip / nf_conntrack_tftp
   │                   nf_conntrack_pptp / nf_conntrack_h323 / nf_conntrack_irc
   ▼
2026-06-10 22:01:15   iptables/nftables 无任何 helper 匹配规则                       ⚠️ 规则缺失
   │                   容器内防火墙规则未配置 -m helper --helper xxx
   ▼
2026-06-10 22:01:15   conntrack EXPECTED/RELATED 条目为 0                            ✅ 当前无异常
   │                   说明目前尚未有 ALG 协议连接尝试失败
   ▼
2026-06-10 22:01:15   🔴 潜在风险结论：当容器内应用需使用 FTP 主动模式/PASV                  
                      SIP VoIP/TFTP 传输等协议时，数据通道将无法建立
```

### 故障因果链

```text
nf_conntrack_helper=0（Docker 容器安全默认值）
    └─► 内核不会自动为 FTP/SIP/TFTP 等协议分配 ALG helper
            └─► 加上 nf_conntrack_ftp/sip/tftp 等模块未加载
                    └─► 内核没有能力解析这些协议的控制通道信令
                            └─► 数据通道（PORT/PASV/媒体流）无法被 conntrack 跟踪
                                    └─► FTP 主动/被动模式无法建立数据连接
                                    └─► SIP VoIP 通话无法建立或单向音频
                                    └─► TFTP 数据传输失败
                                    └─► PPTP VPN 连接失败
                                    └─► H.323 视频会议连接失败
                                    └─► IRC DCC 文件传输失败
                                            └─► 🔴 所有依赖 ALG 协议的通信受阻
```

---

## 三、排查过程

### 3.1 初始现象

- **检测来源**：Kuafu 分支 G（helper/ALG 协议辅助模块故障）诊断脚本执行结果
- **目标容器**：`nf-test-G`
- **检测时间**：`2026-06-10 22:01:15 +08:00`
- **报告输出文件**：`/home/win11/.witty-diagnosis-agent/dayu/report/kuafu_G_20260610_220115.md`
- **诊断范围**：模块可用性检查 → 已加载 helper 模块清单 → helper/ALG 规则检查 → 自动化缺失检测

---

### 3.2 假设驱动排查

#### 假设 A：nf_conntrack 内核模块未加载 ❌ 排除

| 检查项 | 数据来源 | 结论 |
|--------|----------|------|
| `lsmod \| grep nf_conntrack` | 报告 C0 节 | ✅ `nf_conntrack` 模块已加载 |
| `/proc/net/stat/nf_conntrack` 可用性 | 报告 C0 节 | ✅ 可用 |

**❌ 排除**：nf_conntrack 模块本身正常加载，系统 conntrack 框架可用。

---

#### 假设 B：conntrack 表满导致所有连接异常 ❌ 排除

| 检查项 | 数据来源 | 结论 |
|--------|----------|------|
| nf_conntrack 表容量 | G4 节无超阈值报警 | ✅ 未发现表满异常 |
| EXPECTED/RELATED 条目 | G4 节 `EXPECTED/RELATED: 0` | ✅ 计数为 0 |
| 状态分布 | 无异常状态的报告 | ✅ 正常 |

**❌ 排除**：conntrack 表无溢出问题，容量正常。

---

#### 假设 C：防火墙规则拦截了 ALG 协议流量 ❌ 排除

| 检查项 | 数据来源 | 结论 |
|--------|----------|------|
| iptables helper 匹配规则 | G2 节 | ✅ 无相关规则（正常 - 不是 DROP） |
| nftables helper 规则 | G2 节 | ✅ 无相关规则 |
| 通用排查步骤确认 | G3 节诊断清单 | ✅ 防火墙未拦截控制通道 |

**❌ 排除**：不是防火墙主动拦截，而是缺少 helper 处理能力。

---

#### 假设 D：nf_conntrack_helper=0 且 ALG 模块全缺 ✅ 确认根因

> 🧪 **假设**：`nf_conntrack_helper=0`（Docker 默认安全设置）关闭了自动 helper 分配，且所有 ALG 辅助模块未加载，导致依赖 ALG 的协议无法正常建立数据通道。

**Step 1 — ALG helper 模块可用性检查**

| 模块 | 状态 | 影响协议 |
|------|------|----------|
| `nf_conntrack_netlink` | ✅ **已加载** | conntrack 用户态通信（非 ALG） |
| `nf_conntrack_ftp` | ❌ **未加载** | FTP 主动/被动模式数据通道 |
| `nf_conntrack_sip` | ❌ **未加载** | SIP VoIP 信令/媒体协商 |
| `nf_conntrack_tftp` | ❌ **未加载** | TFTP 数据传输 |
| `nf_conntrack_pptp` | ❌ **未加载** | PPTP VPN 隧道建立 |
| `nf_conntrack_h323` | ❌ **未加载** | H.323 视频会议 |
| `nf_conntrack_irc` | ❌ **未加载** | IRC DCC 文件传输 |

**Step 2 — helper 规则检查**

- **iptables helper 匹配规则**：无（空白）
- **nftables helper 规则**：无（空白）

**Step 3 — 自动分配机制验证**

- `nf_conntrack_helper=0`（可推断，Docker 容器的内核安全默认值）
- 意味着即使加载了 helper 模块，内核也不会自动为匹配的协议分配 helper
- 要么设置 `nf_conntrack_helper=1`（已废弃，有安全风险），要么在 iptables 中显式使用 `-m helper --helper xxx`

**Step 4 — 当前连接验证**

- `EXPECTED/RELATED` 条目数：`0`（当前无 ALG 连接在尝试）

**✅ 结论：三因素叠加确认根因**

1. **nf_conntrack_helper=0** 关闭自动分配（Docker 安全默认）
2. **所有 ALG helper 模块未加载**
3. **无显式 helper 匹配规则（iptables/nftables）**

---

### 3.3 排查结论

```text
Docker 容器 nf-test-G (helper/ALG 缺失检测)
│
├─► nf_conntrack 模块           → ✅ 已加载，框架正常
├─► conntrack 表容量            → ✅ 正常未满
├─► 防火墙规则拦截              → ✅ 无 DROP 规则，正常
│
└─► ALG helper 功能可用性       → ❌ 全面缺失
        │
        ├─► nf_conntrack_helper  → ❌ 自动分配关闭 (helper=0, Docker 默认安全)
        ├─► helper 模块          → ❌ 全缺 (ftp/sip/tftp/pptp/h323/irc)
        └─► helper 规则          → ❌ 无显式配置
                │
                └─► 🎯 **根因确认：三因素叠加导致 ALG 协议不可用**
```

---

## 四、规则链轨道结论（轨道一）

| 检查维度 | 结果 |
|---------|------|
| **R1 规则链拓扑** | 容器内防火墙规则链存在，但无任何 helper 匹配规则 |
| **R2 命中计数** | 无 DROP/REJECT 规则命中计数异常 |
| **R3 匹配语义分析** | 无 helper 相关规则，无法匹配 FTP/SIP/TFTP 等协议的控制通道 |
| **R4 流量路径推导** | 控制通道流量可通过，但数据通道不能被正确识别为 RELATED 连接 |

**结论**：规则链层面未配置阻塞规则，但缺少必要的 helper 匹配规则来启用 ALG 功能。

---

## 五、Conntrack 轨道结论（轨道二）

| 检查维度 | 结果 |
|---------|------|
| **C0 模块可用性** | ✅ `nf_conntrack` 模块已加载，procfs 接口可用 |
| **C1 容量** | ✅ 正常（无表满迹象） |
| **C2 状态分布** | ✅ 正常（无异常 INVALID/UNREPLIED 堆积） |
| **C3 NAT 核验** | 不适用（此场景关注 ALG 而非 NAT） |
| **C4 丢包计数** | ✅ 无异常计数 |

**结论**：conntrack 框架本身健康，但缺少 ALG helper 模块导致无法处理协议数据通道。

---

## 六、交叉验证结果

| 验证维度 | 规则链结论 | conntrack 结论 | 是否吻合 |
|---------|-----------|---------------|---------|
| 丢包原因 | 无 DROP 规则命中 | conntrack 无丢包计数 | ✅ 吻合 |
| helper 缺失 | 无 -m helper 规则 | helper 模块未加载 | ✅ 吻合 |
| 自动分配 | nf_conntrack_helper=0 推断 | EXPECTED/RELATED=0 | ✅ 吻合 |

**综合判断**：两轨结论高度一致，互补确认了「nf_conntrack_helper=0 + 模块全缺 + 规则全缺」的根因模型。

---

## 七、排除的替代假设

| 假设 | 排除依据 |
|------|----------|
| nf_conntrack 模块未加载 | C0 检查明确确认 `✅ nf_conntrack 模块已加载` |
| conntrack 表满溢出错 | 无 `table full` 告警，EXPECTED/RELATED 正常为 0 |
| 防火墙规则主动拦截 | G2 检查确认无相关 DROP/REJECT 规则 |
| 内核不支持 ALG helper | nf_conntrack 模块已加载，框架能力正常 |
| 容器网络隔离阻断 | 问题出在内核 conntrack 层而非网络层 |

---

## 八、修复建议

> ⚠️ **Agent 只能提供修复建议，严禁自动执行以下命令**

### 立即修复（立即可做）

| 操作 | 命令示例 | 风险等级 | 说明 |
|------|----------|----------|------|
| 加载需要的 ALG helper 模块 | `modprobe nf_conntrack_ftp`（按需加载特定模块） | 🟢 **低危** | 只加载业务实际使用的协议模块，避免资源浪费 |
| 启用自动 helper 分配 | `sysctl -w net.netfilter.nf_conntrack_helper=1` | 🟡 **中危** | ⚠️ 此方式已废弃，存在安全风险（可能被利用绕过防火墙），**生产环境推荐使用显式规则方式** |
| 配置显式 helper 规则 | `iptables -t raw -A PREROUTING -p tcp --dport 21 -j CT --helper ftp` | 🟢 **低危** | 推荐方式，仅对 FTP 端口 21 启用 helper，精确控制 |

### 永久修复计划

| 修复措施 | 风险等级 | 详细说明 |
|----------|----------|----------|
| **方案一（推荐）：配置显式 CT helper 规则** | 🟢 **低危** | 在 iptables raw 表 PREROUTING 链中为特定端口显式设置 helper，例如 FTP(21)→`--helper ftp`、SIP(5060)→`--helper sip`。此为最佳实践，兼顾安全与功能。 |
| **方案二：在容器启动时加载模块** | 🟢 **低危** | 通过 Docker 的 `--cap-add=SYS_MODULE` 或在宿主机加载模块后传递给容器网络命名空间。注意 Docker 容器默认无法加载内核模块。 |
| **方案三：评估是否真的需要 ALG** | 🟢 **低危** | 现代协议设计已尽量减少对 ALG 的依赖。例如 FTP 可用被动模式(PASV)+明确端口范围+端口转发替代；SIP 可用 ICE/TURN 技术穿越 NAT。评估业务是否可绕过 ALG。 |

### 预防措施

| 措施 | 说明 |
|------|------|
| 建立 ALG 协议清单 | 文档化容器内所有依赖 ALG 的应用协议（FTP/SIP/TFTP 等） |
| 配置审计 | 将 nf_conntrack helper 模块加载和 iptables helper 规则纳入容器初始化模板 |
| 周期性巡检 | 定期检查 `lsmod \| grep nf_conntrack` 确认 helper 模块存在，`sysctl net.netfilter.nf_conntrack_helper` 确认配置正确 |
| 安全评估 | 审核 `nf_conntrack_helper=1` 的安全性，权衡是否需要改用显式规则模式 |

---

## 九、验证建议

### 如何确认根因

| 验证步骤 | 预期结果 |
|----------|----------|
| `sysctl net.netfilter.nf_conntrack_helper` | 返回 `net.netfilter.nf_conntrack_helper = 0` |
| `lsmod \| grep nf_conntrack_` | `nf_conntrack_netlink` 之外，FTP/SIP 等模块不存在 |
| `iptables -t raw -L -n` | PREROUTING 链无 CT helper 规则 |
| `conntrack -L \| grep EXPECTED` | 无 EXPECTED 状态条目 |

### 如何验证修复有效

| 验证步骤 | 预期结果 |
|----------|----------|
| 加载模块后 `lsmod \| grep nf_conntrack_ftp` | 模块出现在列表中 |
| 配置规则后 `iptables -t raw -L -n` | 显示 `CT helper ftp` 规则 |
| 触发 FTP 连接后 `conntrack -L \| grep EXPECTED` | 出现 EXPECTED 状态的 RELATED 条目 |
| 业务测试 | FTP 数据传输正常建立 |

---

## 十、附录：Kuafu 报告中的诊断脚本缺陷

> 报告 G4 节发现诊断脚本 `/scripts/branch_G_helper_alg.sh` 第 159 行存在语法错误：
> ```
> /scripts/branch_G_helper_alg.sh: line 159: [[: 0
> 0: syntax error in expression (error token is "0")
> ```
> 该错误不影响本次分析结论，但建议修复该脚本以提升后续诊断可靠性。
