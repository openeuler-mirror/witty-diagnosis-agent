# DNS 相关参数与配置说明

## 系统 DNS 配置文件

### /etc/resolv.conf

```bash
# 配置格式
search example.com sub.example.com   # 搜索域（最多 6 个，256 字符）
nameserver 8.8.8.8                   # DNS 服务器（最多 3 个）
nameserver 114.114.114.114
option rotate                        # 轮询 nameserver
option timeout:2                     # 超时时间（秒）
option attempts:3                    # 重试次数
option edns0                         # 启用 EDNS0
option trust-ad                      # 信任 AD 标志
option ndots:1                       # 域名含多少点才直接查询
sortlist 10.0.0.0/255.0.0.0         # 地址排序
```

**关键规则**：
- `search` 和 `domain` 互斥，不能同时使用
- nameserver 最多配置 3 个
- `option rotate` 让多个 nameserver 轮询使用（默认顺序优先）
- `option timeout:1` 每个 nameserver 超时（默认 5 秒）
- `option attempts:2` 总重试次数（默认 2）

### /etc/nsswitch.conf

```bash
# hosts 数据库配置项
hosts:          files dns myhostname
# 可选源（按优先级排序）：
#   files      - /etc/hosts
#   dns        - DNS
#   mdns       - Multicast DNS（.local）
#   mdns_minimal - 仅 .local 用 mDNS
#   myhostname - 本机主机名
#   resolve    - systemd-resolved
#   sss        - SSSD
#   wins       - WINS（Windows）
```

**常见错误配置**：
- `mdns` 排在 `dns` 前 → mDNS 抢答非 .local 域名
- `myhostname` 影响正常域名解析
- `resolve` 导致绕过 `/etc/hosts`

## systemd-resolved 配置

### /etc/systemd/resolved.conf

```ini
[Resolve]
DNS=8.8.8.8 114.114.114.114    # 全局 DNS 服务器
FallbackDNS=1.1.1.1             # 后备 DNS
Domains=~.                      # 搜索域（~. 表示所有域名）
LLMNR=no                        # 多链路本地名称解析
MulticastDNS=no                 # mDNS
DNSSEC=allow-downgrade          # DNSSEC 模式
DNSOverTLS=opportunistic        # DNS over TLS
Cache=yes                       # 是否启用缓存
CacheFromLocalhost=no           # 是否缓存本地查询
DNSStubListener=yes             # 监听 127.0.0.53
```

### resolvectl 接口级配置

```bash
# 查看所有接口
resolvectl status

# 配置特定接口 DNS
resolvectl dns eth0 8.8.8.8

# 配置接口搜索域
resolvectl domain eth0 example.com

# 配置接口 DNS 优先级
resolvectl default-route eth0 true

# 查看 DNS 服务器统计
resolvectl statistics
```

## 内核网络参数

```bash
# UDP 协议相关（影响 DNS 大包）
sysctl net.core.rmem_default        # UDP 接收缓冲区（默认 212992）
sysctl net.core.rmem_max            # UDP 接收缓冲区最大
sysctl net.core.wmem_default        # UDP 发送缓冲区
sysctl net.core.wmem_max

# conntrack 相关（DNS 查询跟踪）
sysctl net.netfilter.nf_conntrack_udp_timeout
sysctl net.netfilter.nf_conntrack_udp_timeout_stream

# PMTU 相关（影响 EDNS0 大包）
sysctl net.ipv4.ip_no_pmtu_disc     # 是否禁用 PMTU 发现
sysctl net.ipv4.route.min_pmtu      # 最小 PMTU
```

## DNS 响应码速查

| 响应码 | 名称 | 含义 |
|--------|------|------|
| 0 | NOERROR | 查询成功 |
| 1 | FORMERR | 查询格式错误 |
| 2 | SERVFAIL | 服务器内部失败 |
| 3 | NXDOMAIN | 域名不存在 |
| 4 | NOTIMP | 服务器不支持该查询类型 |
| 5 | REFUSED | 服务器拒绝查询 |
| 6 | YXDOMAIN | 域名本应存在但不存在 |
| 7 | YXRRSET | 资源记录集本应存在但不存在 |
| 8 | NXRRSET | 资源记录集不存在 |
| 9 | NOTAUTH | 服务器对该区域无权威 |
| 10 | NOTZONE | 域名不在该区域 |

## EDNS0 Option Codes

| 代码 | 名称 | 说明 |
|------|------|------|
| 1 | LLQ | 长寿命查询 |
| 2 | UL | 租约更新时间 |
| 3 | NSID | 名称服务器标识 |
| 4 | DAU | DNSSEC 算法理解 |
| 5 | DHU | DS 哈希理解 |
| 6 | N3U | NSEC3 哈希理解 |
| 7 | ECS (EDNS Client Subnet) | 客户端子网 |
| 8 | EXPIRES | 区域过期时间 |
| 9 | COOKIE | DNS Cookies |
| 10 | TCP_KEEPALIVE | TCP 保活 |
| 11 | PADDING | 填充 |
| 12 | CHAIN | 链查询 |
| 13 | KEY_TAG | 密钥标签 |
