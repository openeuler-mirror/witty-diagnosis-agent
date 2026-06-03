# 🔴 故障诊断报告

> **报告编号**：RCA-20260602-001
> **故障级别**：P3（低优先 - 单用户本地环境，已自行恢复）
> **报告时间**：2026-06-02 20:34:26
> **当前状态**：🟢 已恢复

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | WSL2 Ubuntu 22.04 实例 DNS TCP 查询因 iptables DROP 规则超时 |
| 影响范围 | 目标主机 172.29.89.45（WSL2 Ubuntu 22.04 实例），本地 DNS TCP 解析功能 |
| 故障时段 | 用户发现时持续存在 ～ 2026-06-02 20:31:25（WSL2 实例重启后自动恢复） |
| 根本原因 | iptables OUTPUT 链中存在 DROP tcp dpt:53 规则，阻塞了所有出站 TCP DNS 查询；WSL2 实例停止/重启后规则被清空 |
| 是否恢复 | ✅ 已恢复（WSL2 重启后 iptables 规则集清空，问题不复现） |
| 根因置信度 | 🟡 中置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|--------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | SQL 无索引 → 复现后加索引立即恢复 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | 定位到慢查询，但流量突增原因待查 |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | 多个组件同时异常，无法判断触发顺序 |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | 服务偶发崩溃，日志无异常，无法复现 |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                        事件                                               性质         溯源路径
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
故障发生前                  iptables OUTPUT 链被添加了一条 DROP tcp dpt:53 规则    📥 未知植入   （规则来源不可追溯）
                            （可能来源：Docker 网络配置 / 手动执行 / 启动脚本）
                              │
                              ▼
用户操作时                  dig +tcp @8.8.8.8 baidu.com → 超时无响应                🔴 故障激活   [用户描述]
                              │  出站 SYN → iptables DROP → 无响应
                              │
                              ▼
用户检查时                  sudo iptables -L OUTPUT → DROP tcp dpt:53 可见          🔍 用户确认   [用户描述]
                              │  UDP DNS 正常（不受 DROP 规则影响）
                              │
                              ▼
诊断接入前                  WSL2 实例处于 Stopped 状态（原因未知）                   🔄 状态变更   [Kuafu 诊断报告]
                              │  可能是 Windows 关机/休眠/WSL 自动超时/手动停止
                              │
                              ▼
诊断启动 WSL2 实例后        iptables 规则集被完全清空                               🧹 证据丢失   [C:\Users\86135\.witty-diagnosis-agent\dayu\report\kuafu_T1_20260602_203211.md]
                              │  WSL2 特性：每次启动为"干净"内核状态
                              │  iptables-persistent 未安装
                              ▼
诊断验证时                  dig +tcp @8.8.8.8 baidu.com → NOERROR, 172ms  ✅         🟢 已恢复     [同上]
                              /dev/tcp/8.8.8.8/53 → OK
```

### 故障因果链

```text
iptables OUTPUT 链被植入 DROP tcp dpt:53 规则（来源不明）
    └─► DNS TCP 查询的出站 SYN 包被内核丢弃
            └─► dig +tcp @8.8.8.8 baidu.com 等待响应直到超时（默认 5~10s）
                    └─► 依赖 TCP DNS 的应用/工具受影响
                            │
                            ├─► UDP DNS（dig @8.8.8.8 baidu.com）→ ✅ 正常
                            │       规则仅匹配 TCP，不匹配 UDP
                            │
                            └─► 🔴 故障表现：TCP DNS 超时

WSL2 实例停止（原因未明确）→ 重启
    └─► iptables 规则集随内核状态一起丢失（WSL2 设计特性）
            └─► 现场证据不可追溯，历史规则无法复原
                    └─► 问题自动消失，但根因未根治
```

---

## 三、排查过程

> 排查逻辑：**提出假设 → 收集证据 → 验证或排除 → 逐步收敛到根因**

### 3.1 初始现象

- **用户描述**：`dig +tcp @8.8.8.8 baidu.com` 持续超时无响应；`dig @8.8.8.8 baidu.com`（UDP）正常返回解析结果。
- **用户检查**：`sudo iptables -L OUTPUT` 中可观察到 `DROP tcp dpt:53` 规则。
- **影响**：WSL2 Ubuntu 22.04 实例（172.29.89.45）上所有依赖 TCP 协议的 DNS 查询（如 DNS over TCP、部分 stub resolver 回退逻辑）均不可用。

---

### 3.2 假设驱动排查

#### 假设 A：iptables DROP tcp/53 规则导致 DNS TCP 查询超时 ✅ 确认（历史状态）

> 🧪 假设：iptables OUTPUT 链中的 DROP tcp dpt:53 规则阻止了出站 TCP/53 报文，造成 DNS TCP 查询超时。

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 用户观察到的 iptables 规则 | 用户执行 `iptables -L OUTPUT` | ✅ 存在 DROP tcp dpt:53 |
| UDP DNS 是否受影响 | `dig @8.8.8.8 baidu.com`（UDP） | ✅ 正常，UDP 不受规则影响 |
| TCP DNS 是否受影响 | `dig +tcp @8.8.8.8 baidu.com` | ✅ 超时，与规则完全吻合 |
| 规则匹配行为 | DROP 在 OUTPUT 链拦截出站 SYN | ✅ 出站 TCP/53 SYN 被丢弃 → 无响应 |

**分析**：该规则精确匹配 TCP 协议 + 目标端口 53，这是 DNS TCP 查询使用的协议/端口组合。UDP DNS 查询不受影响的事实进一步佐证了该规则的存在和作用。

**✅ 结论：该假设可完美解释所有现象。但由于 WSL2 实例重启导致规则丢失，属于"历史已确认、当前无法复现"的状态。**

---

#### 假设 B：WSL2 网络栈或 Windows 防火墙导致 TCP DNS 异常

> 🧪 假设：WSL2 的虚拟化网络栈或 Windows 宿主机防火墙拦截了 TCP/53 流量

| 检查项 | 操作 | 结论 |
|--------|------|------|
| WSL2 网络状态 | `wsl --list --verbose` → Running 后测试 | ✅ TCP DNS 正常 |
| TCP/53 端口可达性 | `/dev/tcp/8.8.8.8/53` | ✅ OK（3 个 DNS 服务器均正常） |
| nftables 规则 | `sudo nft list ruleset` | ✅ 无规则 |
| ufw 状态 | `sudo ufw status verbose` | ✅ inactive |

**❌ 排除**：当前 WSL2 网络栈中不存在任何阻碍 TCP/53 的机制。

---

#### 假设 C：iptables 规则因 WSL2 重启丢失，导致证据不可追溯

> 🧪 假设：WSL2 实例在诊断前被停止，重启后 iptables 规则集被清空

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 诊断启动前 WSL 状态 | `wsl --list --verbose` → **Stopped** | ✅ 确认经历过停止周期 |
| iptables 全表扫描 | `iptables-save` + 5 张表逐一检查 | ✅ 全部为空，无任何规则 |
| iptables-persistent 安装 | `dpkg -l iptables-persistent` | ✅ 未安装，规则不持久化 |
| /etc/iptables/ 目录 | `ls /etc/iptables/` | ✅ 目录不存在 |
| 内核/iptables 日志 | `dmesg` / `journalctl -k` | ✅ 无相关条目 |
| 历史启动记录 | 系统已记录 30 次启动（boot -29 至 boot 0） | ✅ 多次启动周期 |

**✅ 结论：WSL2 实例重启后 iptables 规则集完全丢失，且没有任何持久化机制或日志可以恢复历史状态。这是证据不可追溯的根本原因。**

---

### 3.3 排查结论

```text
DNS TCP 查询超时
├─► 假设 A：iptables DROP tcp/53 规则导致超时
│       ├─► 用户观察到规则 ✅
│       ├─► UDP DNS 正常 ✅
│       ├─► TCP DNS 超时 ✅
│       └─► 🎯 根因确认（历史状态）
│
├─► 假设 B：WSL2/Windows 网络栈问题
│       ├─► WSL2 重启后 TCP DNS 正常 ❌ 排除
│       ├─► nftables 为空 ❌ 排除
│       └─► ufw inactive ❌ 排除
│
└─► 假设 C：重启导致证据丢失
        ├─► WSL2 初始为 Stopped ✅
        ├─► iptables 全空 ✅
        ├─► 无持久化机制 ✅
        └─► 🎯 确认证据丢失路径
```

**最终根因判定**：iptables OUTPUT 链中的 `DROP tcp dpt:53` 规则是 DNS TCP 查询超时的直接原因。该规则的植入来源无法追溯（可能为 Docker 网络配置、startup script、或手动误操作），但 WSL2 在实例停止后不持久化 iptables 规则的设计特性导致证据在重启后完全丢失。

---

## 四、修复方案

### 4.1 应急处置

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | WSL2 实例重启（已发生） | 系统/诊断过程 | 2026-06-02 20:31:25 | iptables 规则集被清空，DNS TCP 查询恢复正常 |
| 2 | 验证 DNS TCP 连通性 | Kuafu 诊断 | 2026-06-02 20:31:25 | dig +tcp @8.8.8.8 baidu.com → NOERROR, 172ms |
| 3 | 验证多 DNS 服务器 TCP 可达性 | Kuafu 诊断 | 2026-06-02 20:31:25 | 8.8.8.8/114.114.114.114/223.5.5.5 均正常 |

当前故障已自然恢复，无需额外应急处置。

### 4.2 永久修复计划

| 修复措施 | 负责人 | 完成时间 |
|--------|------|--------|
| 排查 DROP tcp/53 规则的来源（检查 Docker 网络配置、systemd 服务、cron 脚本、用户历史命令等） | 用户/待定 | 待定 |
| 如本机需持久化 iptables 规则，安装 `iptables-persistent` 并在确认规则集正确后执行 `sudo netfilter-persistent save` | 用户/待定 | 待定 |
| 在添加任何 iptables 规则前先保存备份：`sudo iptables-save > ~/iptables_backup_$(date +%Y%m%d_%H%M%S).txt` | 用户/自持 | 持续执行 |
| 建立 WSL2 启动后 iptables 规则校验机制（如检查关键规则是否存在，避免规则意外丢失或混入） | 用户/待定 | 待定 |

### 4.3 预防措施

1. **WSL2 特性认知**：WSL2 实例每次启动都是"干净"内核状态，iptables 规则不持久化。如需持久化，必须通过 `iptables-persistent` 或 `wsl.conf` 启动脚本实现。

2. **规则来源溯源**：若再次出现异常 iptables 规则，建议立即执行以下命令在规则被清空前保存证据：
   ```bash
   sudo iptables-save > ~/iptables_evidence_$(date +%Y%m%d_%H%M%S).txt
   sudo iptables -L -n -v --line-numbers > ~/iptables_detail_$(date +%Y%m%d_%H%M%S).txt
   ```

3. **Docker 联动排查**：如果在 WSL2 中运行 Docker，注意 Docker 可能通过 iptables 管理网络规则。检查 Docker daemon 配置中是否有 DNS 相关的策略。

4. **规则变更审计**：可在 `.bashrc` 或 `.bash_logout` 中添加 iptables 快照钩子，记录每次 shell 会话开始/结束时的 iptables 状态。

---

## 五、附录

### 5.1 诊断执行信息

| 项目 | 内容 |
|------|------|
| 诊断报告源 | `C:\Users\86135\.witty-diagnosis-agent\dayu\report\kuafu_T1_20260602_203211.md` |
| 诊断执行器 | Kuafu T1 |
| 目标主机 | 172.29.89.45（WSL2 Ubuntu 22.04） |
| 诊断执行时间 | 2026-06-02 20:31:25 CST |

### 5.2 关键诊断命令输出摘要

| 命令 | 输出摘要 |
|------|---------|
| `sudo iptables-save` | 无输出（规则集为空） |
| `dig @8.8.8.8 baidu.com` (UDP) | NOERROR, 4 条 A 记录, 4ms |
| `dig +tcp @8.8.8.8 baidu.com` (TCP) | NOERROR, 4 条 A 记录, 172ms |
| `/dev/tcp/8.8.8.8/53` | OK |
| `sudo nft list ruleset` | 无输出 |
| `sudo ufw status verbose` | Status: inactive |

### 5.3 系统指纹

| 属性 | 值 |
|------|-----|
| 操作系统 | WSL2 Ubuntu 22.04 |
| 内核 | WSL2 内核（每次启动干净状态） |
| iptables 持久化 | 未安装 iptables-persistent |
| 历史启动次数 | 30 次 |
| 宿主机 | Windows（WSL2 管理） |
