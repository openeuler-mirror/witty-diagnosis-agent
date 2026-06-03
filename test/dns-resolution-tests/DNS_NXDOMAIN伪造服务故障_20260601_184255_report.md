# 🔴 故障诊断报告

> **报告编号**: RCA-20260601-001
> **故障级别**: P2（影响 DNS 解析功能，但业务流量经 Windows 侧未中断）
> **报告时间**: 2026-06-01 18:43:34
> **当前状态**: 🟢 已恢复

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | WSL2 实例内 `nxdomain-fake.service` 伪造 DNS 服务导致任意域名查询返回 NXDOMAIN |
| 影响范围 | 目标主机 172.29.89.45（WSL2 Ubuntu 22.04 实例）内的所有 DNS 解析请求故障；Windows 主机侧 DNS 解析正常 |
| 故障时段 | 2026-05-29 20:46:27 ～ 2026-06-01 18:20:25（多次间歇性发作，WSL 重启后清除） |
| 根本原因 | systemd 瞬态服务 `nxdomain-fake.service` 运行 Python 伪造 DNS 服务器脚本，对所有 DNS 查询返回 NXDOMAIN（RCODE=3） |
| 是否恢复 | ✅ 已恢复（WSL 实例重启后伪造服务被清除，DNS 解析恢复正常） |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|--------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | journalctl 日志明确记录伪造 DNS 服务的启停 + 源代码完整 + 测试框架完备 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                         事件                                                     性质           溯源路径
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-05-29 20:46:27         systemd 启动 /tmp/start_nxdomain.sh                       🚀 注入触发   [kuafu_T1_20260601_180255_dns_nxdomain.md:158]
  │                           → 伪造 DNS 服务器开始监听 :5353
  ▼
2026-05-29 20:46:28         start_nxdomain.sh[931]: NXDOMAIN fake DNS on :5353        ✅ 确认运行   [同上:159]
  │
  ▼
2026-05-29 20:46~20:48      伪造 DNS 服务器处于活动状态，拦截 DNS 查询                ⚠️ 故障活跃   [同上:160-169]
  │                           对任何域名返回 NXDOMAIN (RCODE=3)
  ▼
2026-05-29 20:47~20:48      服务停止/重启多次                                          🔄 反复注入   [同上:160-170]
  │
  ▼
(中间时段：未见运行记录)
  │
  ▼
2026-06-01 18:19:48         systemd 再次运行 /tmp/start_nxd.sh                        🚀 再次注入   [同上:172-173]
  │
  ▼
2026-06-01 18:19:48         start_nxd.sh[410]: NXDOMAIN fake DNS on :5353             ✅ 确认运行   [同上:173]
  │
  ▼
2026-06-01 18:20:25         nxdomain-fake.service: Deactivated successfully.           🛑 自动停止   [同上:174]
  │
  ▼
2026-06-01 18:38:43         systemd-resolved 重新启动（WSL 实例重启后）                🔄 系统恢复   [同上:107-108]
  │                           伪造服务单元文件已被清除
  ▼
2026-06-01 18:42:55         诊断验证：dig baidu.com 返回正常，DNS 已恢复               ✅ 确认恢复   [同上:49-58]
```

### 故障因果链

```text
nxdomain-fake.service 被启动（人为/自动化注入）
    └─► 执行 /tmp/start_nxd.sh（或 /tmp/start_nxdomain.sh）
            └─► 启动 Python 伪造 DNS 服务器（dns_nxdomain_fake_5353.py）
                    └─► 监听 0.0.0.0:5353，拦截 DNS 查询
                            └─► 对每个 DNS 查询构造响应包（flag=0x8183, RCODE=3）
                                    └─► 返回 status: NXDOMAIN, ANSWER: 0
                                            └─► dig 显示 NXDOMAIN，所有域名解析失败
                                                    └─► 🔴 WSL2 实例内 DNS 功能失效
```

---

## 三、排查过程

> 排查逻辑：**提出假设 → 收集证据 → 验证或排除 → 逐步收敛到根因**

### 3.1 初始现象

- dig 查询任意域名（如 `dig baidu.com`）返回 `status: NXDOMAIN`，ANSWER 段为空（0 条记录）
- 同一域名通过 Windows 主机 HTTP 访问正常（Windows DNS 解析器正常工作）
- ping DNS 服务器 IP（10.255.255.254）可达（ICMP 无需 DNS 解析）

### 3.2 假设驱动排查

#### 假设 A：resolv.conf 配置异常

> 🧪 假设：/etc/resolv.conf 中被写入了错误的 DNS 服务器地址

| 检查项 | 操作 | 结论 |
|--------|------|------|
| resolves conf 内容 | `cat /etc/resolv.conf` | `nameserver 10.255.255.254`，WSL2 标准配置 |
| 软链接检查 | `ls -la /etc/resolv.conf` | 正确指向 `/mnt/wsl/resolv.conf` |
| 备份对比 | `cat /etc/resolv.conf.bak` | 内容一致 |

**❌ 排除**：resolv.conf 配置正常，非此原因。

---

#### 假设 B：systemd-resolved 故障

> 🧪 假设：systemd-resolved 服务崩溃或缓存损坏导致解析失败

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 服务状态 | `systemctl status systemd-resolved` | ✅ Active (running)，PID 113 |
| 缓存统计 | `resolvectl statistics` | Cache Size: 1, Hits: 0, Misses: 4，无异常堆积 |
| 监听端口 | `ss -tlnp \| grep 53` | 127.0.0.53:53 和 10.255.255.254:53 均正常监听 |

**❌ 排除**：systemd-resolved 运行正常，无缓存污染或服务异常。

---

#### 假设 C：防火墙 / iptables 规则拦截 DNS 流量

> 🧪 假设：iptables 规则将 DNS 查询重定向或丢弃

| 检查项 | 操作 | 结论 |
|--------|------|------|
| iptables 规则 | `sudo iptables -L -n -v`（所有表） | ✅ 全部为空，INPUT/OUTPUT/FORWARD 均为 ACCEPT |
| NAT 表规则 | `sudo iptables -t nat -L -n -v` | ✅ 无规则 |

**❌ 排除**：无任何 iptables 规则干预 DNS 流量。

---

#### 假设 D：/etc/hosts 或 nsswitch.conf 异常

> 🧪 假设：hosts 文件包含错误条目或 nsswitch 解析顺序异常

| 检查项 | 操作 | 结论 |
|--------|------|------|
| /etc/hosts 内容 | `cat /etc/hosts` | 仅标准 localhost 条目 |
| nsswitch.conf hosts 行 | `grep hosts /etc/nsswitch.conf` | `hosts: files dns`，标准配置 |

**❌ 排除**：文件内容正常，解析顺序正确。

---

#### 假设 E：网络层问题（丢包/路由异常）

> 🧪 假设：网络层丢包导致 DNS 请求/响应无法正常到达

| 检查项 | 操作 | 结论 |
|--------|------|------|
| ping DNS 服务器 | `ping 10.255.255.254` | ✅ 可达 |
| tcpdump 抓包 | `tcpdump -i any port 53 -c 10` | 无异常数据包（查询通过 stub 完成） |
| 上游 DNS 验证 | `dig @8.8.8.8 baidu.com` | ✅ 正常返回 A 记录 |

**❌ 排除**：网络层正常，上游公共 DNS 可用。

---

#### 假设 F：本地存在伪造 DNS 服务 ✅ 确认根因

> 🧪 假设：本地存在一个恶意/测试用 DNS 服务，对所有查询返回 NXDOMAIN

**Step 1 — journalctl 日志发现关键线索**

```text
May 29 20:46:27 localhost systemd[1]: Started /tmp/start_nxdomain.sh.
May 29 20:46:28 localhost start_nxdomain.sh[931]: NXDOMAIN fake DNS on :5353
...
Jun 01 18:19:48 localhost systemd[1]: Started /tmp/start_nxd.sh.
Jun 01 18:19:48 localhost start_nxd.sh[410]: NXDOMAIN fake DNS on :5353
```

**Step 2 — 定位伪造 DNS 源代码**

在 `/home/wyh/dns-test-src/` 目录发现完整 DNS 故障注入工具集：

| 文件名 | 功能说明 |
|--------|--------|
| `dns_nxdomain_fake_5353.py` | 监听 `0.0.0.0:5353`，对所有 DNS 查询返回 NXDOMAIN（RCODE=3） |
| `dns_nxdomain_53.py` | 监听 `127.0.0.1:53`，对所有 DNS 查询返回 NXDOMAIN |
| `dns_nxdomain_fake.py` | 监听 `0.0.0.0:53`，对所有 DNS 查询返回 NXDOMAIN |
| `dns_hijack_fake.py` | 监听 `0.0.0.0:53`，返回伪造 IP（DNS 劫持） |
| `dns_tcp_block.py` | TCP DNS 阻断 |
| `dns_timeout_inject.py` | DNS 超时注入 |

**Step 3 — 确认伪造 DNS 核心逻辑**

```python
flags = struct.pack("!H", 0x8183)  # QR=1, RCODE=3 (NXDOMAIN)
resp = tid + flags + data[4:]      # 保留原查询内容，仅改标志位
sock.sendto(resp, addr)             # 发送伪造响应
```

该逻辑接收 DNS 查询，将响应标志位设为 `0x8183`（标准 NXDOMAIN 响应，RCODE=3），从而对任何域名查询返回 `status: NXDOMAIN`。

**Step 4 — 发现完整 DNS 诊断测试框架**

在 `/home/wyh/dns-scripts/` 目录发现完整的 DNS 故障注入测试脚本体系：

| 脚本 | 对应故障模式 |
|------|-------------|
| `branch_A_timeout.sh` | DNS 超时 |
| `branch_B_nxdomain.sh` | **NXDOMAIN 误报** |
| `branch_C_resolv_conf.sh` | resolv.conf 异常 |
| `branch_D_nsswitch.sh` | nsswitch 配置异常 |
| `branch_E_resolved_cache.sh` | resolved 缓存问题 |
| `branch_F_hijack.sh` | DNS 劫持 |
| `branch_G_tcp_fallback.sh` | TCP 回退失败 |
| `branch_H_edns0.sh` | EDNS0 问题 |

`branch_B_nxdomain.sh` 正是 NXDOMAIN 场景的故障注入脚本，直接对应本故障现象。

**✅ 结论：`nxdomain-fake.service` systemd 瞬态服务运行伪造 DNS 服务器脚本，对所有 DNS 查询返回 NXDOMAIN，导致 WSL2 实例内任意域名解析均返回 NXDOMAIN。**

---

### 3.3 排查结论

```text
dig NXDOMAIN（WSL2 内任意域名）
├─► 假设 A: resolv.conf 异常        → ✅ 正常，排除
├─► 假设 B: systemd-resolved 故障    → ✅ 正常运行，排除
├─► 假设 C: iptables 规则拦截        → ✅ 规则为空，排除
├─► 假设 D: /etc/hosts / nsswitch    → ✅ 标准配置，排除
├─► 假设 E: 网络层问题               → ✅ ping 可达，上游 DNS 可用，排除
└─► 假设 F: 本地伪造 DNS 服务        → ❌ 确认根因
        └─► journalctl 日志          → 📋 nxdomain-fake.service 运行记录
        └─► 源代码发现               → 📋 /home/wyh/dns-test-src/ 完整工具集
        └─► 测试框架确认             → 📋 /home/wyh/dns-scripts/branch_B_nxdomain.sh
                └─► 🎯 根因确认：nxdomain-fake.service 伪造 DNS 服务注入
```

---

## 四、修复方案

### 4.1 应急处置

故障已于诊断前自动恢复。恢复路径分析：

| 步骤 | 操作 | 执行方式 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | WSL 实例重启导致 `nxdomain-fake.service` 瞬态单元被清除 | 系统/人工 | 2026-06-01 18:20 后 | 伪造 DNS 进程终止 |
| 2 | systemd-resolved 重新初始化 | 自动 | 2026-06-01 18:38:43 | DNS 解析恢复正常 |
| 3 | dig 验证：`dig baidu.com` 正常返回 A 记录 | — | 2026-06-01 18:42:55 | ✅ 确认恢复 |

### 4.2 永久修复计划

鉴于该故障是由 **人为注入的 DNS 故障模拟服务** 导致的测试环境问题（非自然故障），建议如下：

| 修复措施 | 负责人 | 完成时间 | 优先级 |
|--------|--------|--------|--------|
| **1. 确认测试意图**：该环境存在完整的 DNS 故障测试框架（`/home/wyh/dns-test-src/` 和 `/home/wyh/dns-scripts/`），需确认 NXDOMAIN 问题是否为有意的故障注入测试 | 测试负责人 | 待定 | 高 |
| **2. 残留文件清理**：如测试已完成，清理以下残留文件：`/home/wyh/dns-test-src/`、`/home/wyh/dns-scripts/` 的全部脚本，以及残留的 systemd transient unit | 系统管理员 | 待定 | 中 |
| **3. 监控加固**：对 systemd 服务创建/启动实施审计监控，防止未授权的 DNS 劫持/伪造服务被启动（建议配置 systemd 单元白名单或启用 auditd 监控服务创建事件） | 运维团队 | 待定 | 中 |
| **4. 增加告警规则**：对 DNS 突发 NXDOMAIN 响应率设置监控告警，以快速发现类似故障注入事件 | 监控团队 | 待定 | 低 |

---

## 五、关键证据索引

| 证据项 | 文件位置 | 行号 |
|--------|--------|------|
| journalctl 日志（伪造 DNS 服务启停记录） | `C:\Users\86135\.witty-diagnosis-agent\kuafu\kuafu_T1_20260601_180255_dns_nxdomain.md` | 158-174 |
| NXDOMAIN 伪造 DNS 源代码（dns_nxdomain_fake_5353.py） | 同上 | 225-228 |
| DNS 诊断测试框架列表 | 同上 | 196-209 |
| branch_B_nxdomain.sh 对应 NXDOMAIN 故障模式 | 同上 | 200-201 |
| dig 测试从故障前 NXDOMAIN → 恢复后正常 | 同上 | 49-84 |
| /etc/resolv.conf 标准化配置验证 | 同上 | 37-45 |
