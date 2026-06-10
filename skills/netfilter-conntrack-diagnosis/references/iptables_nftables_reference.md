# iptables / nftables 命令速查与规则解读

## 一、iptables 表链结构与遍历顺序

### 表优先级

IPv4 数据包经过的 hook 点（按优先级排序）：

```
hook                        表遍历顺序
─────────────────────────────────────────────────────────
NF_INET_PRE_ROUTING         raw → mangle → nat (DNAT)
NF_INET_LOCAL_IN            mangle → filter → security
NF_INET_FORWARD             mangle → filter → security
NF_INET_LOCAL_OUT           raw → mangle → nat (DNAT) → filter → security
NF_INET_POST_ROUTING        mangle → nat (SNAT/MASQUERADE)
```

### 链默认策略(policy)影响

| 链 | 默认 policy | 含义 |
|----|------------|------|
| `filter:INPUT` | ACCEPT | 入站默认允许（大部分系统） |
| `filter:FORWARD` | ACCEPT/DROP | 默认取决于系统角色（转发通常 DROP） |
| `filter:OUTPUT` | ACCEPT | 出站默认允许 |
| `nat:PREROUTING` | ACCEPT | NAT 预处理 |
| `nat:POSTROUTING` | ACCEPT | NAT 后处理 |

**重要**：当链 `policy=DROP` 时，未匹配任何显式 ACCEPT 规则的流量都会被丢弃。这是常见的配置错误源。

---

## 二、iptables 规则解读

### 2.1 规则字段详解

```
iptables -L INPUT -n -v --line-numbers

Chain INPUT (policy ACCEPT 4862K packets, 1587M bytes)
num  pkts bytes target     prot opt in     out     source               destination
1   4779 1570K DROP       0    --  enp4s0 *       0.0.0.0/0            0.0.0.0/0
2      0     0 ACCEPT     tcp  --  *      *       0.0.0.0/0            0.0.0.0/0    tcp dpt:22
```

| 字段 | 含义 | 诊断意义 |
|------|------|---------|
| `num` | 规则序号（1-indexed） | 调整顺序时使用 |
| `pkts` | 命中该规则的数据包数 | **0=未命中，>0=已生效** |
| `bytes` | 命中该规则的数据字节数 | 大包场景留意 |
| `target` | 动作 (ACCEPT/DROP/REJECT/RETURN/LOG) | 决定流量命运 |
| `prot` | 协议 (tcp/udp/icmp/all) | 确认协议匹配 |
| `opt` | 选项 (通常 `--`) | 很少用 |
| `in` | 入站接口 | 入站流量关键匹配条件 |
| `out` | 出站接口 | 出站流量关键匹配条件 |
| `source` | 源 IP/网段 | 确认是否匹配故障源 |
| `destination` | 目的 IP/网段 | 确认是否匹配故障目的 |

### 2.2 关键匹配模块

#### state/conntrack 模块
```bash
# state 模块（旧，依赖 conntrack）
-m state --state NEW,ESTABLISHED,RELATED,INVALID

# conntrack 模块（新，更细粒度）
-m conntrack --ctstate NEW,ESTABLISHED,RELATED,INVALID,SNAT,DNAT,UNTRACKED
-m conntrack --ctproto tcp
-m conntrack --ctorigsrc 10.0.0.0/8
-m conntrack --ctorigdstport 80
-m conntrack --ctstatus CONFIRMED,EXPECTED
```

#### helper 模块
```bash
-m helper --helper ftp
-m helper --helper sip
```

#### ipset 匹配
```bash
# 匹配源 IP 在 ipset 中
-m set --match-set my_set src
# 匹配目的 IP 在 ipset 中
-m set --match-set my_set dst
# 匹配源 IP+port 在 ipset 中
-m set --match-set my_set src,dst
```

#### addrtype 模块
```bash
-m addrtype --dst-type LOCAL
-m addrtype --src-type LOCAL
```

### 2.3 常用 NAT 规则解读

```bash
# SNAT：将内网流量伪装成公网 IP
# 场景：内网 192.168.1.0/24 通过 1.2.3.4 访问外网
iptables -t nat -A POSTROUTING -s 192.168.1.0/24 -j SNAT --to-source 1.2.3.4

# MASQUERADE：SNAT 的动态版本，自动取接口 IP
# 场景：PPPoE 拨号，接口 IP 动态分配
iptables -t nat -A POSTROUTING -o ppp0 -j MASQUERADE

# DNAT：将公网端口映射到内网服务
# 场景：1.2.3.4:8080 → 192.168.1.100:80
iptables -t nat -A PREROUTING -d 1.2.3.4 -p tcp --dport 8080 -j DNAT --to-destination 192.168.1.100:80

# REDIRECT：本机端口重定向
# 场景：80 端口重定向到透明代理 3128
iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 3128
```

---

## 三、nftables 规则解读

### 3.1 nftables 架构

```
nftables 框架
├── table (地址族: ip/ip6/inet/arp/bridge)
│   ├── chain (类型: filter/nat/route, hook: input/forward/output/prerouting/postrouting)
│   │   ├── rule 1 (匹配条件 + 语句)
│   │   ├── rule 2
│   │   └── rule N
│   └── set (命名集合: ipv4_addr, ipv6_addr, 等)
├── table ...
└── ...
```

### 3.2 nftables 规则解读示例

```bash
# 查看全量规则
nft list ruleset

# 输出示例解读：
table inet firewalld {      # inet 地址族（同时适用于 IPv4 和 IPv6）
    chain filter_INPUT {     # 链定义
        type filter hook input priority filter + 10; policy accept;
                              # ^ type: 链类型
                              # ^ hook: hook 点
                              # ^ priority: 优先级（数字越小越先执行）
                              # ^ policy: 默认策略

        ct state established,related accept
        # 匹配：conntrack 状态为 established 或 related 的包
        # 动作：accept（放行）

        tcp dport { 22, 80, 443 } accept
        # 匹配：TCP 目的端口 22、80、443
        # 动作：accept

        ip saddr @trusted_src accept
        # 匹配：源 IP 在 trusted_src 集合中
        # 动作：accept

        counter drop
        # 动作：计数器 + drop
        # 这是常见的审计方式，counter 可查命中数
    }

    set trusted_src {        # 命名集合（类似 ipset）
        type ipv4_addr
        flags interval       # 支持网段（如 10.0.0.0/8）
        elements = {
            10.0.0.0/8,
            172.16.0.0/12
        }
    }
}
```

### 3.3 nftables 核心匹配语法

| 匹配 | 示例 | 含义 |
|------|------|------|
| `ct state` | `ct state established accept` | 按 conntrack 状态匹配 |
| `ct helper` | `ct helper "ftp" accept` | 按 helper 匹配 |
| `iifname` | `iifname "eth0"` | 入站接口名 |
| `oifname` | `oifname "eth0"` | 出站接口名 |
| `ip saddr` | `ip saddr 10.0.0.0/8` | IPv4 源地址 |
| `ip daddr` | `ip daddr 192.168.1.0/24` | IPv4 目的地址 |
| `tcp dport` | `tcp dport 80` | TCP 目的端口 |
| `tcp sport` | `tcp sport 1024-65535` | TCP 源端口范围 |
| `udp dport` | `udp dport 53` | UDP 目的端口 |
| `@set_name` | `ip saddr @blacklist` | 引用命名集合 |
| `meter` | `meter web-meter tcp dport 80` | 动态计量（类似 recent） |
| `vmap` | `vmap { 80 : accept, 443 : accept }` | 值映射 |

### 3.4 nftables vs iptables 对应

| iptables | nftables 对应 |
|----------|---------------|
| `-t filter -A INPUT` | `add rule inet filter input` |
| `-t nat -A PREROUTING` | `add rule ip nat prerouting` |
| `-m conntrack --ctstate` | `ct state` |
| `-m helper --helper ftp` | `ct helper "ftp"` |
| `-m set --match-set` | 命名集合 + `@set` |
| `-j LOG --log-prefix "X:"` | `log prefix "X:"` |
| `-j DROP` | `drop` |
| `-j REJECT` | `reject` |

---

## 四、规则计数解读（常见误判预防）

### 4.1 pkts 计数增长模式

| 模式 | 解读 |
|------|------|
| pkts=0 | 规则从未被命中（可能是顺序问题或匹配条件不生效） |
| pkts 稳定缓慢增长 | 正常匹配，无异常 |
| pkts 在故障窗口内激增 | 与故障强相关，重点审查 |
| pkts 在故障后不再增长 | 故障已恢复或流量路径已变 |
| pkts 持续高速增长 | 正在发生大量匹配，可能导致性能问题 |

### 4.2 常见误判场景

**场景 1：DROP 计数增长但业务正常**
- 可能的 DROP 目标不是故障流量（如针对攻击源的 DROP 规则）
- 需确认 DROP 规则的匹配条件是否与故障流量匹配

**场景 2：多条 DROP 规则命中**
- 哪条规则先匹配到故障流量？
- 规则顺序决定实际生效的规则

**场景 3：无 DROP 命中但网络不通**
- 可能在更早的 hook 点被 DROP（如 raw 表的 NOTRACK 影响了 conntrack）
- 可能不是防火墙问题（检查路由、ARP、接口）

**场景 4：pkts=0 的规则**
- 不是故障原因（规则未生效）
- 但可能是潜在风险（应该生效的规则未生效）

### 4.3 规则生效路径判断

```bash
# 方法 1：使用 iptables 计数器逐链查看
watch -n 1 'iptables -L INPUT -v -n | grep -E "Chain|DROP|REJECT"'

# 方法 2：使用 TRACE 跟踪特定包（raw 表）
iptables -t raw -A PREROUTING -p tcp --dport 80 -j TRACE
iptables -t raw -A OUTPUT -p tcp --sport 80 -j TRACE
# 然后查看 trace 日志
xtables-monitor --trace

# 方法 3：nftables 等价
nft add rule inet filter prerouting tcp dport 80 trace accept
nft monitor trace
```

---

## 五、ipset 命令速查

| 命令 | 用途 |
|------|------|
| `ipset list` | 列出所有 ipset 及条目 |
| `ipset list <name>` | 查看指定 ipset |
| `ipset create <name> hash:ip` | 创建 hash:ip 类型的 ipset |
| `ipset add <name> X.X.X.X` | 添加条目 |
| `ipset del <name> X.X.X.X` | 删除条目 |
| `ipset test <name> X.X.X.X` | 测试条目是否存在 |
| `ipset save` | 保存所有 ipset |
| `ipset restore` | 恢复 ipset |
| `ipset flush <name>` | 清空指定 ipset |
| `ipset destroy <name>` | 删除指定 ipset |

### ipset 类型对照

| 类型 | 存储内容 | 匹配方式 | 典型用途 |
|------|---------|---------|---------|
| `bitmap:ip` | IP 范围 | `--match-set set src` | 小范围连续 IP |
| `hash:ip` | 独立 IP | `--match-set set src` | IP 黑白名单 |
| `hash:net` | 网段 | `--match-set set src` | 网段黑白名单 |
| `hash:ip,port` | IP+端口 | `--match-set set src,dst` | 精细访问控制 |
| `hash:mac` | MAC 地址 | `--match-set set src` | MAC 过滤 |
| `list:set` | 嵌套集合 | 自动 | 集合组合 |
