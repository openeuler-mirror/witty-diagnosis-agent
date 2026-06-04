---
name: dns-resolution-diagnosis
description: >
  DNS 解析故障诊断技能。当用户提到解析超时、域名无法解析、NXDOMAIN、
  /etc/resolv.conf 配置错误、nsswitch.conf 顺序异常、systemd-resolved 缓存问题、
  DNS 劫持、dig/nslookup 失败、TCP fallback 失败、EDNS0 兼容性问题、
  间歇性解析失败、特定域名解析异常、DNS 服务器无响应等关键词时，
  必须使用本技能。覆盖场景：解析超时/查询失败、NXDOMAIN 误报、
  resolv.conf 配置异常、nsswitch.conf 顺序错误、systemd-resolved 缓存污染、
  DNS 劫持检测、TCP fallback 失败、EDNS0 兼容性问题。
  即使只收到"上不了网"、"网页打不开"、"域名解析慢"但怀疑 DNS 相关时
  也应触发本技能。
---

# DNS 解析故障诊断（三层下钻：系统层 → 类型层 → 代码根因层）

## 第一节：故障目录结构

```text
dns_case/                   # 故障案例目录
├── scripts/                # 【内置】本技能的诊断脚本
│   ├── 01_baseline_info.sh
│   ├── branch_A_timeout.sh
│   ├── branch_B_nxdomain.sh
│   ├── branch_C_resolv_conf.sh
│   ├── branch_D_nsswitch.sh
│   ├── branch_E_resolved_cache.sh
│   ├── branch_F_hijack.sh
│   ├── branch_G_tcp_fallback.sh
│   └── branch_H_edns0.sh
├── logs/                   # 【可选】应用日志
│   ├── application.log
│   └── dmesg_output.txt
├── packet_capture/         # 【可选】故障时刻的抓包文件
│   ├── dns_query.pcap
│   └── dns_response.pcap
└── report/                 # 【输出】诊断报告目录
```

```bash
# 检查 DNS 解析状态基线
dig +short example.com
```

---

## 第二节：分析策略（三层下钻，逐层收敛）

DNS 解析故障诊断采用**三层下钻模型**，从最外层逐层深入，层间存在依赖关系：

```
┌─────────────────────────────────────────────────────────────────┐
│                   三层下钻分析模型                                 │
│                                                                 │
│   L1: 系统层         /etc/resolv.conf / nsswitch.conf            │
│       │               systemd-resolved --status                  │
│       └─ 判断：系统 DNS 配置与基础连通性是否正常？                │
│                                                                 │
│   L2: 类型层         dig +trace / nslookup / host                │
│       │               tcpdump -i any port 53                     │
│       └─ 判断：是超时？NXDOMAIN？劫持？EDNS 兼容？               │
│                                                                 │
│   L3: 代码/协议层    strace -e trace=network                    │
│                      tcpdump -vv -X port 53                      │
│                      DNS 应答码分析 / EDNS0 OPT 记录             │
│                      └─ 根因定位：配置错误 / 缓存污染 / 劫持     │
│                                                                 │
│   每层输出：证据 + 结论。L3 输出最终根因。                       │
└─────────────────────────────────────────────────────────────────┘
```

### 故障分类树

```
L1 ─ 系统 DNS 配置检查
│
├─ L2 ─ 解析结果正常？──── 是 ──→ 非 DNS 问题，转其他技能
│                         否
│                         ↓
├─ L2 ─ 超时/无响应？──── 是 ──→ Branch A (Timeout)
│                         否
│                         ↓
├─ L2 ─ NXDOMAIN？─────── 是 ──→ Branch B (NXDOMAIN)
│                         否
│                         ↓
├─ L2 ─ 返回 IP 异常？─── 是 ──→ Branch F (Hijack)
│                         否
│                         ↓
├─ L2 ─ 间歇性/特定域名？─ 是 ──→ Branch E (Cache) / Branch H (EDNS0)
│                         否
│                         ↓
├─ L2 ─ TCP 问题？─────── 是 ──→ Branch G (TCP Fallback)
│                         否
│                         ↓
└─ L2 ─ 配置问题？─────── 是 ──→ Branch C (resolv.conf) / Branch D (nsswitch)
```

---

## 第三节：诊断流程

### L1: 系统层 — 基线采集与配置检查

检查系统 DNS 基础配置，判断是否为系统级配置问题。

```bash
# 1. 检查 /etc/resolv.conf
cat /etc/resolv.conf

# 2. 检查 /etc/nsswitch.conf 中 hosts 配置
grep ^hosts /etc/nsswitch.conf

# 3. 检查 systemd-resolved 状态
resolvectl status 2>/dev/null || systemd-resolve --status 2>/dev/null

# 4. 基本连通性测试
dig +short example.com @8.8.8.8
```

**L1 结论判定**：

| 现象 | 可能原因 | 下一层 |
|------|---------|--------|
| resolv.conf 为空/格式错误 | 配置损坏 | Branch C |
| nameserver 指向 127.0.0.53 | systemd-resolved 存根 | → resolvectl 检查 |
| nsswitch 中 hosts 顺序异常 | 解析顺序错误 | Branch D |
| 基础 dig 超时 | 网络/防火墙 | Branch A |
| 返回 IP 与预期不符 | 劫持/缓存 | Branch F / Branch E |

### L2 → L3: 类型层与代码根因层

#### Branch A — 解析超时/查询失败

**触发条件**：L1 中 `dig @server domain` 超时或返回无响应。

```
L2 诊断：
├── 1. ping DNS 服务器 IP（检查网络连通性）
├── 2. telnet DNS_IP 53（检查端口可达性）
├── 3. dig +tcp @server domain（检查 TCP 协议）
├── 4. dig @server domain +timeout=2（缩短超时重试）
├── 5. tcpdump -i any port 53 -c 10（抓包确认请求是否发出）
│
└── L3 根因判定：
    ├── ping 不通 → 网络层故障（路由/防火墙/链路）
    ├── telnet 不通但 ping 通 → 防火墙拦截 UDP 53
    ├── tcp 通但 udp 不通 → UDP 53 被 QoS 限流或丢弃
    ├── 请求已发出但无响应 → DNS 服务器端问题
    └── 本地防火墙拦截 → iptables -L -n 检查规则
```

**典型输出**：
```
结论: DNS 服务器 8.8.8.8 ping 响应正常，但 UDP 53 端口无响应。
      tcpdump 显示请求已发出但未收到应答。
根因: 上游防火墙或 QoS 策略丢弃了 UDP 53 出站流量。
```

#### Branch B — NXDOMAIN 误报

**触发条件**：已知应存在的域名返回 NXDOMAIN。

```
L2 诊断：
├── 1. dig +trace @root-servers domain（从根开始追踪）
├── 2. dig @不同上游 NS 查询（对比多个权威）
├── 3. curl -v http://domain（HTTP 层面验证）
├── 4. nslookup domain 127.0.0.53（本地存根校验）
├── 5. delv +multiline domain（DNSSEC 验证）
│
└── L3 根因判定：
    ├── 权威返回正确，本地返回 NXDOMAIN → 本地缓存污染
    ├── 所有上游都返回 NXDOMAIN → 域名已过期/被暂停
    ├── DNSSEC 验证失败 → 签名过期/算法不兼容
    ├── CDN 智能 DNS 返回不一致 → 区域分裂/GeoDNS 策略
    └── 仅特定客户端失败 → 中间设备篡改（透明代理/防火墙）
```

**典型输出**：
```
结论: 权威根服务器返回正确 A 记录，本地 stub 返回 NXDOMAIN。
      resolvectl 显示缓存中存在 NXDOMAIN 条目。
根因: systemd-resolved 缓存污染，NXDOMAIN 否定缓存未过期。
```

#### Branch C — /etc/resolv.conf 配置异常

**触发条件**：resolv.conf 被篡改、格式错误、nameserver 不可达。

```
L2 诊断：
├── 1. stat /etc/resolv.conf（检查是否为符号链接）
├── 2. cat /etc/resolv.conf（完整内容检查）
├── 3. ls -la /etc/resolv.conf（权限和链接检查）
├── 4. cat /etc/resolvconf/resolv.conf.d/*（resolvconf 后端）
├── 5. networkctl status（NetworkManager 托管状态）
│
└── L3 根因判定：
    ├── 文件为空 → resolvconf 未正确生成
    ├── nameserver 指向 127.0.0.53 → resolved 存根，需查 resolved 状态
    ├── 权限 000 → 其他程序/管理员操作误修改
    ├── 符号链接指向不存在的文件 → resolvconf 软件包损坏
    ├── 包含 option rotate → 多 nameserver 轮询异常
    └── 被 NetworkManager 覆盖 → nmcli 配置冲突
```

**典型输出**：
```
结论: /etc/resolv.conf 为空文件（0 字节），
      且非符号链接。stat 显示文件大小为 0。
根因: resolvconf 服务未运行或未正确生成配置文件。
```

#### Branch D — nsswitch.conf 顺序错误

**触发条件**：hosts 查找顺序异常导致解析绕过 DNS。

```
L2 诊断：
├── 1. grep ^hosts /etc/nsswitch.conf
├── 2. getent hosts domain（检查实际查找结果）
├── 3. strace -e openat getent hosts domain 2>&1（追踪查找顺序）
├── 4. cat /etc/hosts（检查本地 hosts 覆盖）
├── 5. sssd/LDAP 状态检查（sssd 服务影响）
│
└── L3 根因判定：
    ├── myhostname 排在 dns 前 → 主机名可能被 myhostname 解析
    ├── mdns 排在 dns 前 → .local 域名被 mDNS 抢答
    ├── files 排在 dns 前 → /etc/hosts 优先于 DNS
    ├── sss 排在 dns 前 → SSSD 域认证影响 DNS
    └── resolve 排在第一位 → systemd-resolved 完全接管
```

**典型输出**：
```
结论: nsswitch.conf hosts 配置为 "files mdns dns"，
      mdns 优先于 dns。dig 返回正确 IP，但 getent 返回 169.254.x.x。
根因: mDNS 模块抢答了非 .local 域名的解析请求。
```

#### Branch E — systemd-resolved 缓存污染

**触发条件**：缓存中存在过期/错误的 DNS 记录。

```
L2 诊断：
├── 1. resolvectl statistics（缓存统计）
├── 2. resolvectl query domain（查看缓存内容）
├── 3. resolvectl cache（查看缓存条目）
├── 4. resolvectl flush-caches（清空后对比解析结果）
├── 5. resolvectl dns（查看各接口 DNS 配置）
├── 6. resolvectl domain（查看搜索域配置）
│
└── L3 根因判定：
    ├── 清空缓存后解析恢复正常 → 缓存污染
    ├── 缓存条目 TTL 异常大 → 上游 DNS 返回异常 TTL
    ├── 特定域名解析 IP 是旧的 → A 记录更新后缓存未刷新
    ├── DNSSEC 缓存导致 SERVFAIL → 验证失败缓存
    └── 多个接口 DNS 配置冲突 → link-local 多路 DNS
```

**典型输出**：
```
结论: resolvectl 显示 example.com 缓存 TTL 剩余 86400 秒
      （已缓存 24 小时）。清空后解析 IP 从旧 IP 变为新 IP。
根因: 上游 DNS TTL 返回异常大值，导致 resolved 长时间缓存错误记录。
```

#### Branch F — DNS 劫持检测

**触发条件**：域名解析返回的 IP 不是预期的真实 IP。

```
L2 诊断：
├── 1. dig +short @8.8.8.8 domain（外部权威对比）
├── 2. dig +short @本地网关 domain（本地 DNS 对比）
├── 3. curl -v -H 'Host: domain' http://真实IP（直接 IP 验证）
├── 4. openssl s_client -connect domain:443（TLS 证书验证）
├── 5. tcpdump -vv -s 0 port 53（抓包确认应答来源）
├── 6. wireshark 对比 TTL 和 ID 字段（判断中间人注入）
│
└── L3 根因判定：
    ├── 本地 DNS 与 8.8.8.8 返回不一致 → 本地 DNS 被篡改
    ├── 网关 DNS 返回钓鱼 IP → 路由器 DNS 劫持
    ├── HTTP 直接访问真实 IP 正常 → 仅 DNS 层被劫持
    ├── TLS 证书与域名不匹配 → HTTPS 劫持
    ├── 响应包 TTL 异常/ID 重复 → 中间人注入伪造应答
    └── HTTP 响应被插入广告 → 运营商 DNS 劫持
```

**典型输出**：
```
结论: dig @8.8.8.8 返回真实 IP，但本地解析返回 103.235.46.96（钓鱼 IP）。
      curl 直接访问真实 IP 返回正确页面。
根因: 本地网关路由器 DNS 配置被篡改，指向恶意 DNS 服务器。
```

#### Branch G — TCP Fallback 失败

**触发条件**：DNS 响应被截断（TC 标志），TCP 回退查询失败。

```
L2 诊断：
├── 1. dig +short @server domain（检查 TC 标志）
├── 2. dig +tcp @server domain（强制 TCP 查询）
├── 3. dig +bufsize=512 @server domain（限制 UDP 大小触发 TC）
├── 4. dnstcpbench @server domain（TCP 压力测试）
├── 5. tcpdump -i any port 53 and tcp（TCP DNS 抓包）
│
└── L3 根因判定：
    ├── UDP 返回 TC=1，TCP 超时 → 防火墙拦截 TCP 53
    ├── TCP 连接被 RST → 中间设备主动阻断 TCP DNS
    ├── TCP 响应极慢 → DNS 服务器 TCP 性能瓶颈
    ├── EDNS0 不支持大响应 → 上游 DNS 不支持 EDNS0
    └── 特定记录类型（RRSIG/NSEC）过大 → DNSSEC 导致超 MTU
```

**典型输出**：
```
结论: dig +dnssec 返回 TC=1 标志位，强制 TCP 后连接超时。
      tcpdump 显示 TCP SYN 发出后无 SYN-ACK 响应。
根因: 中间防火墙丢弃了 TCP 53 端口的 SYN 包。
```

#### Branch H — EDNS0 兼容性问题

**触发条件**：EDNS0 OPT 记录导致 DNS 服务器无响应或返回异常。

```
L2 诊断：
├── 1. dig +edns0 @server domain（含 EDNS0 查询）
├── 2. dig +noedns @server domain（禁用 EDNS0 对比）
├── 3. dig +bufsize=4096 @server（大 UDP 包测试）
├── 4. dig +dnssec @server domain（DNSSEC 依赖 EDNS0）
├── 5. dig +unknownformat @server（检查未知 OPT 处理）
│
└── L3 根因判定：
    ├── +edns0 失败，+noedns 成功 → 上游 DNS 不支持/损坏 EDNS0
    ├── 大 bufsize（4096）失败，512 成功 → PMTU 问题
    ├── +dnssec 返回 SERVFAIL → DNSSEC 验证链断裂
    ├── 中间盒修改 OPT 记录 → 透明代理改写 EDNS0
    ├── IPv6 EDNS0 客户端子网异常 → ECS 导致 GeoDNS 返回错误
    └── NSID/DAU 等未知 OPT 导致超时 → 防火墙丢弃未知 OPT
```

**典型输出**：
```
结论: dig +edns0 请求超时，dig +noedns 正常返回。
      tcpdump 显示 OPT 记录长度为 0，被中间设备截断。
根因: 中间防火墙截断了 EDNS0 OPT 伪记录，导致 DNS 服务器静默丢弃。
```

---

## 第四节：故障模式速查表

| 故障模式 | 核心命令 | 特征日志/现象 |
|---------|---------|-------------|
| 解析超时 | `dig +timeout=2` | `connection timed out; no servers could be reached` |
| NXDOMAIN 误报 | `dig +trace` | `status: NXDOMAIN`（对已知域名） |
| resolv.conf 异常 | `stat /etc/resolv.conf` | 空文件、权限异常、坏链接 |
| nsswitch 顺序 | `grep ^hosts /etc/nsswitch.conf` | myhostname/mdns 排在 dns 前 |
| resolved 缓存 | `resolvectl statistics` | `Current Cache Size` 异常大 |
| DNS 劫持 | `dig @8.8.8.8` vs `dig @local` | 两个结果 IP 不一致 |
| TCP fallback | `dig +tcp` vs `dig +notcp` | `TC` 标志 + TCP 超时 |
| EDNS0 异常 | `dig +edns0` vs `dig +noedns` | 含 EDNS0 超时，不含正常 |

## 第五节：参考文档

- `references/dns_commands.md` — DNS 诊断命令速查
- `references/dns_params.md` — 内核/DNS 相关参数说明
- `references/dns_patterns.md` — DNS 故障模式与正则匹配
