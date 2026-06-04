# 🔴 故障诊断报告

> **报告编号**：RCA-20260601-001
> **故障级别**：P2 / Major
> **报告时间**：2026-06-01 19:14:18
> **当前状态**：🔴 处理中（配置异常未恢复）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | 目标服务器 DNS 系统解析异常 — /etc/nsswitch.conf hosts 行缺少 dns 源 |
| 影响范围 | 目标服务器 172.29.89.45 (WSL2 Ubuntu 22.04) 上所有依赖系统解析器（glibc getaddrinfo）的程序，包括 curl、wget、apt、ping、getent 等 |
| 故障时段 | 2026-06-01 19:00:00 ～ 持续至今 |
| 根本原因 | /etc/nsswitch.conf 中 hosts 行被修改为 `hosts: files`，缺少 `dns` 源，导致系统解析器仅从 /etc/hosts 查询主机名，无法解析任何外部域名 |
| 是否恢复 | ❌ 未恢复 |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|--------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | nsswitch.conf 缺少 dns → 修复后立即恢复解析 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                   事件                                                   性质           溯源路径
───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-06-01 19:00:00   /etc/nsswitch.conf hosts 行被修改为仅 files（缺少 dns）   ⚠️ 配置变更    [/etc/nsswitch.conf:hosts行]
  │
  ▼
2026-06-01 19:00:00+  glibc NSS 解析器仅读取 /etc/hosts                         🔄 系统行为     [glibc NSS 机制]
  │                   外部域名不在 /etc/hosts 中 → 返回 EAI_NONAME
  │
  ▼
2026-06-01 19:00:00+  getent hosts/ping 等系统调用解析失败                      🟡 系统异常     [诊断输出: getent空/ping失败]
  │                   报错: "Name or service not known"
  │
  ▼
2026-06-01 19:00:00+  所有依赖系统解析器的服务无法访问外部域名                  🔴 故障爆发     [业务影响持续]
  │                   curl/wget/apt/浏览器等解析外部域名均失败
  │
  ▼
2026-06-01 19:13:59   Kuafu 诊断执行确认根因                                   🔍 诊断完成     [kuafu_T1_20260601_191418.md]
  │                   路径: C:\Users\86135\.witty-diagnosis-agent\kuafu\kuafu_T1_20260601_191418.md
  ▼
至今                  等待人工修复 /etc/nsswitch.conf                            ⏳ 待处理
```

### 故障因果链

```text
/etc/nsswitch.conf hosts: files（缺少dns）
    └─► glibc NSS 解析器只读取 /etc/hosts（跳过 DNS 查询）
            └─► 外部域名（如 www.baidu.com）在 /etc/hosts 中不存在
                    └─► getaddrinfo() 返回 EAI_NONAME（Name or service not known）
                            └─► ping/getent hosts/curl/wget/apt 等解析全部失败
                                    └─► 🔴 服务器无法通过域名访问任何外部服务
```

---

## 三、排查过程

> 排查逻辑：**提出假设 → 收集证据 → 验证或排除 → 逐步收敛到根因**

### 3.1 初始现象

- **监控/用户反馈**：目标服务器上 `ping www.baidu.com` 报错 `Name or service not known`，所有需要域名解析的服务均不可用
- **`getent hosts www.baidu.com`**：无任何返回结果（空）
- **`dig @8.8.8.8 www.baidu.com`**：可正常解析到 IP 地址 `157.148.69.186`

### 3.2 假设驱动排查

#### 假设 A：DNS 服务器不可达或上游 DNS 故障

> 🧪 假设：上游 DNS 服务器（8.8.8.8 / 223.5.5.5）不可达或服务异常，导致域名无法解析

| 检查项 | 操作 | 结论 |
|--------|------|------|
| DNS 可达性 | `dig @8.8.8.8 www.baidu.com +short` | ✅ 正常，返回 `157.148.69.186` |
| 备 DNS 可达性 | `dig @223.5.5.5 www.baidu.com +short` | ✅ 正常，返回 `157.148.69.151` |
| DNS 配置 | `cat /etc/resolv.conf` | ✅ 已配置 `nameserver 8.8.8.8` |

**❌ 排除**：DNS 服务器本身正常，网络连通性无问题。

---

#### 假设 B：/etc/hosts 文件被污染或存在错误映射

> 🧪 假设：/etc/hosts 中存在错误条目导致解析被篡改或提前终止

| 检查项 | 操作 | 结论 |
|--------|------|------|
| hosts 文件内容 | `cat /etc/hosts` | ✅ 仅有 localhost 和 IPv6 本地地址条目，无外部域名条目 |

**❌ 排除**：/etc/hosts 内容干净，无异常条目干扰。

---

#### 假设 C：系统解析器配置异常（nsswitch.conf 缺少 dns）✅ 确认根因

> 🧪 假设：Name Service Switch 配置中 hosts 数据库未配置 dns 源，导致系统不进行 DNS 查询

**Step 1 — 检查 nsswitch.conf hosts 行**
```bash
cat /etc/nsswitch.conf | grep hosts
# 输出: hosts:          files
```
- ✅ **异常确认**：hosts 行仅配置了 `files`，缺少 `dns`
- 正常 Ubuntu 默认配置应为：`hosts:          files mdns4_minimal [NOTFOUND=return] dns` 或至少 `hosts: files dns`

**Step 2 — 验证 dig（直接 DNS 查询）正常工作**
```bash
dig @8.8.8.8 www.baidu.com +short
# 输出: www.a.shifen.com. / 157.148.69.186 / 157.148.69.151
```
- ✅ DNS 服务器可达且可正常解析，排除网络层问题

**Step 3 — 验证系统解析器（依赖 nsswitch）失败**
```bash
getent hosts www.baidu.com
# 输出: (空)

ping -c 1 www.baidu.com
# 输出: ping: www.baidu.com: Name or service not known
```
- ✅ 所有依赖 glibc `getaddrinfo()` 的调用均失败

**Step 4 — 验证直接 DNS 工具不受影响（确认影响范围边界）**
```bash
host www.baidu.com
# 输出: www.baidu.com is an alias for www.a.shifen.com. / has address 157.148.69.186
```
- ✅ `host`/`dig`/`nslookup` 直接查询 DNS，不依赖 nsswitch，工作正常

**✅ 结论：`/etc/nsswitch.conf` 中 hosts 行被修改为 `hosts: files`（缺少 `dns`），导致 glibc NSS 解析器仅查询 `/etc/hosts`，不进行 DNS 查询，外部域名无法解析。**

### 3.3 排查结论

```text
外部域名解析失败（ping: Name or service not known）
├─► 假设 A: DNS 服务器不可达         → ✅ 排除（dig @8.8.8.8 正常）
├─► 假设 B: /etc/hosts 污染          → ✅ 排除（hosts 文件干净）
│
└─► 假设 C: 系统解析器配置异常        → ❌ 确认异常
        └─► /etc/nsswitch.conf hosts 行
                → hosts: files（缺少 dns）
                └─► 🎯 根因确认：nsswitch 配置错误
```

---

## 四、修复方案

### 4.1 应急处置

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 修改 /etc/nsswitch.conf，将 hosts 行恢复为 `hosts: files dns` | 人工 | 建议立即执行 | 恢复系统级 DNS 解析能力 |
| 2 | 验证修复效果：`getent hosts www.baidu.com` 应返回 IP 地址 | 人工 | 修复后立即验证 | 确认系统解析恢复正常 |

**修复命令**：
```bash
# 使用 sed 快速修复（备份原始配置）
sudo cp /etc/nsswitch.conf /etc/nsswitch.conf.bak.$(date +%Y%m%d_%H%M%S)
sudo sed -i 's/^hosts:.*files$/hosts:          files dns/' /etc/nsswitch.conf
```

**验证命令**：
```bash
getent hosts www.baidu.com       # 应返回 IP 地址
ping -c 1 www.baidu.com          # 应能 ping 通
```

**回滚方案**：
```bash
sudo sed -i 's/^hosts:.*files dns$/hosts:          files/' /etc/nsswitch.conf
```

### 4.2 永久修复计划

| 修复措施 | 负责人 | 完成时间 |
|--------|--------|--------|
| 修正 /etc/nsswitch.conf hosts 行添加 dns 源 | 系统管理员 | 建议立即执行 |
| 审查服务器近期变更记录，排查 nsswitch.conf 被误修改的原因和时机 | 系统管理员 | 修复完成后 |
| 考虑将 /etc/nsswitch.conf 纳入配置管理（如 Ansible/Puppet），防止再次被意外修改 | 系统管理员 | 短期 |
| 如有监控系统，增加对关键配置文件（/etc/nsswitch.conf、/etc/resolv.conf 等）的完整性校验告警 | 系统管理员 | 短期 |

---

## 附录：诊断证据来源

| 证据项 | 来源文件 |
|--------|--------|
| Kuafu T1 诊断报告（完整） | `C:\Users\86135\.witty-diagnosis-agent\kuafu\kuafu_T1_20260601_191418.md` |
| /etc/nsswitch.conf 配置异常 | 同上，第 44 行 |
| /etc/resolv.conf 配置正常 | 同上，第 50-52 行 |
| getent hosts/ping 解析失败 | 同上，第 17-24 行 |
| dig @8.8.8.8 解析正常 | 同上，第 27-31 行 |
| host 命令不受影响 | 同上，第 34-36 行 |
