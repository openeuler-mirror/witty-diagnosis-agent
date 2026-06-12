# NAT/SNAT/DNAT 映射分析手册

## 一、NAT 类型概览

### 1.1 SNAT (Source NAT)

```
[内网客户端] ──► SNAT ──► [外网]
 192.168.1.100        1.2.3.4:10000
  └── 原始源地址          └── 转换后源地址
```

**用途**：将内网私有 IP 转换为公网 IP 访问外网
**iptables**: `-t nat -A POSTROUTING -s 192.168.1.0/24 -j SNAT --to-source 1.2.3.4`
**nftables**: `snat to 1.2.3.4`

### 1.2 DNAT (Destination NAT)

```
[外网客户端] ──► DNAT ──► [内网服务]
 1.2.3.4:8080        192.168.1.100:80
  └── 原始目的地址        └── 转换后目的地址
```

**用途**：将公网 IP 端口映射到内网服务
**iptables**: `-t nat -A PREROUTING -d 1.2.3.4 -p tcp --dport 8080 -j DNAT --to-destination 192.168.1.100:80`
**nftables**: `dnat to 192.168.1.100:80`

### 1.3 MASQUERADE（动态 SNAT）

```
MASQUERADE = SNAT + 自动取接口IP
```

**用途**：接口 IP 动态变化时使用（PPPoE、DHCP 等）
**iptables**: `-t nat -A POSTROUTING -o ppp0 -j MASQUERADE`
**nftables**: `masquerade`

**和 SNAT 的区别**：
- SNAT 需要显式指定 `--to-source IP`
- MASQUERADE 自动获取出接口 IP
- MASQUERADE 比 SNAT 有额外的性能开销（每次检查接口 IP）

### 1.4 REDIRECT（本机重定向，特殊的 DNAT）

```
[本机客户端] ──► REDIRECT ──► [本机代理]
 10.0.0.1:80         127.0.0.1:3128
```

**用途**：透明代理、端口转发
**iptables**: `-t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-port 3128`
**nftables**: `redirect to :3128`

---

## 二、NAT 流量路径详解

### 2.1 入站 DNAT 路径

```
外网客户端 (1.2.3.4:5000)
    │
    ▼
[1] NF_INET_PRE_ROUTING
    │  raw:PREROUTING (可能 NOTRACK)
    │  mangle:PREROUTING
    ▼  nat:PREROUTING → DNAT 1.2.3.4:8080 → 192.168.1.100:80
[2] 路由决策（目的地址已被改为 192.168.1.100）
    │  ┌────────────────────────────────┐
    │  │ 关键：DNAT 发生在路由决策之前  │
    │  │ 路由看到的是 DNAT 后的地址    │
    │  └────────────────────────────────┘
    ▼
[3] NF_INET_LOCAL_IN（本机入站）
    │  mangle:INPUT
    │  filter:INPUT → 需放行到 192.168.1.100:80 的流量
    ▼  security:INPUT
    本机应用（192.168.1.100:80）
```

### 2.2 出站 SNAT 路径

```
本机应用/客户端
    │
    ▼
[1] NF_INET_LOCAL_OUT（本机出站）
    │  raw:OUTPUT
    │  mangle:OUTPUT
    │  nat:OUTPUT (内网→外网的 DNAT 发在这里)
    │  filter:OUTPUT
    │  security:OUTPUT
    ▼
[2] 路由决策（确定出接口）
    │  ┌────────────────────────────────┐
    │  │ SNAT 发生在路由决策之后！      │
    │  │ 路由决定了出接口后，SNAT 才能  │
    │  │ 决定源地址                     │
    │  └────────────────────────────────┘
    ▼
[3] NF_INET_POST_ROUTING
    │  mangle:POSTROUTING
    ▼  nat:POSTROUTING → SNAT/MASQUERADE
    出站到外网
```

### 2.3 FORWARD 转发的 SNAT+DNAT 完整路径

```
[外网]──[入站包]──► NF_INET_PRE_ROUTING (DNAT)
                        │
                        ▼
                    路由决策 → 目标为本机? → 否 → FORWARD
                        │
                        ▼
                    NF_INET_FORWARD (filter:FORWARD)
                        │
                        ▼
                    NF_INET_POST_ROUTING (SNAT/MASQUERADE)
                        │
                        ▼
                    [出站到内网目标]
```

---

## 三、NAT 映射的 conntrack 表示

### 3.1 NAT entry 结构

```
原始方向 (Original):      回复方向 (Reply):
  src=192.168.1.100:1234    src=8.8.8.8:80
  dst=8.8.8.8:80            dst=1.2.3.4:10000  ← SNAT 后的源地址
                            ^^^^^^^^^^^^^^^^^
                            回复方向的目的 = SNAT 前的源
```

`conntrack -L -n` 输出示例：

```
tcp 6 431999 ESTABLISHED src=192.168.1.100 dst=8.8.8.8 sport=1234 dport=80
  src=8.8.8.8 dst=1.2.3.4 sport=80 dport=10000 [ASSURED] mark=0 use=1
  ^^^^^^^^^ ^^^^^^^^                              ^^^^^^^^
  回包源IP   回包目的IP(=SNAT后的源)                SNAT 映射后的端口
```

### 3.2 NAT 映射核验方法

```bash
# 1. 查看所有 NAT 映射
conntrack -L -n

# 2. 按 SNAT 过滤（回复方向的目的地址 != 原始方向的目的地址）
conntrack -L -n | grep -E "dst=.*dst="

# 3. 按 DNAT 过滤（原始方向的目的地址与一般不同）
conntrack -L -n | grep -v "src=.*src="

# 4. 查看特定 IP 的 NAT 映射
conntrack -L -n | grep "10.0.0.1\|1.2.3.4"

# 5. 查看特定端口的 NAT 映射
conntrack -L -n | grep "dport=80\|sport=80"

# 6. 验证 NAT 转换是否对称
# 期望: 原始方向的 src=dst(回复方向)
#      原始方向的 dst=src(回复方向)
```

### 3.3 NAT 映射异常检测

| 现象 | 可能的根因 |
|------|-----------|
| conntrack 中无对应 NAT entry | NAT 规则未生效或未匹配 |
| NAT entry 的方向与预期相反 | NAT 规则表/链错误 |
| 原始方向正确但回复方向错误 | SNAT 地址配置错误或 MASQUERADE 取错接口 |
| DNAT 后目标不可达 | FORWARD 策略未放行、路由问题 |
| NAT 转换后的地址在外网不可路由 | SNAT 取了错误的 IP |
| conntrack 有 entry 但连接仍失败 | stateful 规则未放行 ESTABLISHED/RELATED |

---

## 四、常见 NAT 故障模式

### 4.1 SNAT 未生效

**症状**：出站包源 IP 未转换，导致回包无法正确路由

**排查步骤**：
```bash
# 1. 确认 SNAT/MASQUERADE 规则存在
iptables -t nat -L POSTROUTING -n -v

# 2. 确认规则 pkts > 0
iptables -t nat -L POSTROUTING -n -v --line-numbers

# 3. 检查 conntrack 中的 NAT 映射
conntrack -L -n | head -5

# 4. 如果是 MASQUERADE，确认出接口 IP 正确
ip addr show dev eth0

# 5. 检查 FORWARD 链是否放行
iptables -L FORWARD -n -v
```

### 4.2 DNAT 未到达内网目标

**症状**：外部访问公网 IP:端口但无法连接

**排查步骤**：
```bash
# 1. 确认 DNAT 规则存在
iptables -t nat -L PREROUTING -n -v

# 2. 确认规则 pkts > 0
iptables -t nat -L PREROUTING -n -v --line-numbers

# 3. 确认内网目标可达
ping 192.168.1.100

# 4. 确认 FORWARD 链放行了到内网目标的流量
#    DNAT 后流量走 FORWARD 链（除非目标为本机）
iptables -L FORWARD -n -v

# 5. 确认 conntrack 正确记录了 DNAT
conntrack -L -n | grep DNAT
```

### 4.3 MASQUERADE 接口 IP 改变后旧的 conntrack entry 失效

**症状**：PPPoE 重拨后现有连接中断

**根因**：重拨后接口 IP 改变了，但旧的 conntrack entry 中的源 IP 还是旧 IP

**诊断**：
```bash
# 检查 conntrack 中 NAT 映射的源 IP 是否与当前接口 IP 一致
conntrack -L -n | grep "$(ip -4 addr show dev ppp0 | grep -oP 'inet \K[\d.]+')"
```

### 4.4 NAT 环回问题 (Hairpin NAT)

**场景**：内网客户端通过公网 IP 访问内网服务，需要在 PREROUTING DNAT 之后，也在 POSTROUTING 做 SNAT

**症状**：内网访问公网 IP 映射的服务失败，但外网访问正常

**排查**：
```bash
# 检查是否有 Hairpin NAT 的 SNAT 规则
iptables -t nat -L POSTROUTING -n -v | grep -E "SNAT|MASQUERADE"
```

---

## 五、NAT 与 netfilter hook 的关系

### 5.1 NAT 与 conntrack 的依赖关系

```
NAT 依赖 conntrack:
  1. NAT 规则匹配时需要 conntrack 来跟踪连接状态
  2. NAT 转换信息存储在 conntrack entry 的 nat 字段
  3. 回包通过 conntrack 的回复方向 tuple 来逆转换

conntrack 不依赖 NAT:
  1. 无 NAT 规则时 conntrack 也能正常工作
  2. conntrack 仅跟踪连接状态，NAT 是附加信息
```

### 5.2 NOTRACK 对 NAT 的影响

```bash
# NOTRACK 使数据包绕过 conntrack
iptables -t raw -A PREROUTING -p tcp --dport 80 -j NOTRACK

# 后果：NOTRACK 的流量无法进行 NAT
# 因为 NAT 依赖 conntrack 来存储映射信息
# DNAT 在 nat:PREROUTING，在 raw:PREROUTING 之后
# 但 conntrack 不跟踪，导致 NAT entry 无法创建
```

### 5.3 CT target（nftables 的 NOTRACK 等效）

```bash
# nftables 跳过 conntrack
nft add rule inet raw prerouting tcp dport 80 notrack

# 这同样会使 NAT 不可用于该流量
```

---

## 六、调试与排障命令速查

### 6.1 NAT 配置调试

```bash
# 查看完整 NAT 规则
iptables -t nat -L -n -v --line-numbers

# 查看特定表
iptables -t nat -L PREROUTING -n -v
iptables -t nat -L POSTROUTING -n -v
iptables -t nat -L OUTPUT -n -v

# nftables NAT 规则
nft list table ip nat
nft list table ip6 nat
```

### 6.2 NAT 流量确认

```bash
# 查看 conntrack 确认 NAT 映射已建立
conntrack -L -n | head -20

# 查看 MASQUERADE 对应的接口 IP
ip addr show dev <iface>

# iptables 规则命中计数监控（每 1 秒刷新）
watch -n 1 'iptables -t nat -L -n -v'
```

### 6.3 NAT 相关内核参数

```bash
# 查看 NAT 相关参数
sysctl -a | grep -E "nf_conntrack.*nat|nf_nat"

# NAT 表大小
sysctl net.netfilter.nf_nat_max  # N/A in newer kernels
```
