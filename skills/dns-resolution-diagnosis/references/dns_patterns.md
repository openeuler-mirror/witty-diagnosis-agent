# DNS 故障模式与正则匹配

## 通用 DNS 错误模式

| 模式 | 正则 | 对应故障 |
|------|------|---------|
| 解析超时 | `connection timed out; no servers could be reached` | 超时/网络不可达 |
| 域名不存在 | `status: NXDOMAIN` | NXDOMAIN 误报 |
| 服务失败 | `status: SERVFAIL` | 上游 DNS 问题 |
| 查询拒绝 | `status: REFUSED` | 访问控制/防火墙 |
| 格式错误 | `status: FORMERR` | 查询格式/EDNS0 |
| 截断标记 | `flags:.* TC` | UDP 包过大 |
| 无应答 | `;; no servers could be reached` | 全部 nameserver 不可达 |
| 连接被拒 | `connection refused` | TCP 53 被拒 |

## resolv.conf 异常模式

| 模式 | 正则 | 说明 |
|------|------|------|
| 空文件 | `^$` | 0 字节文件 |
| 无 nameserver | `^(?!.*nameserver)` | 缺少 nameserver 行 |
| 环回地址 | `nameserver\s+127\.\d+` | 本地存根 DNS |
| 格式错误 | `^[^#\s\n]` | 无效指令行 |
| 符号链接损坏 | `broken symbolic link` | resolv.conf 链接失效 |
| 权限异常 | `Permission denied` | 文件不可读 |

## nsswitch.conf 异常模式

| 模式 | 正则 | 说明 |
|------|------|------|
| myhostname 优先 | `hosts:.*myhostname.*dns` | 主机名源优先于 DNS |
| mdns 优先 | `hosts:.*mdns[^_]` | mDNS 非最小化配置 |
| 缺少 dns | `^(hosts:)(?!.* dns)` | 完全排除 DNS 源 |
| resolve 接管 | `hosts:.*\bresolve\b` | systemd-resolved 接管 |

## systemd-resolved 异常

| 模式 | 正则 | 说明 |
|------|------|------|
| 缓存命中 | `Cache Miss` / `Cache Hit` | 缓存状态 |
| DNSSEC 失败 | `DNSSEC validation failed` | DNSSEC 验证错误 |
| 服务器不可用 | `DNSSEC server failure` | 上游 DNSSEC 问题 |
| 缓存大小 | `Current Cache Size: \d+` | 缓存条目数 |
| 否定缓存 | `NXDOMAIN` in cache stats | NXDOMAIN 否定缓存 |

## DNS 劫持检测模式

| 模式 | 正则 | 说明 |
|------|------|------|
| 解析 IP 差异 | `对比 @8.8.8.8 与 @local` | 外部与本地不一致 |
| 钓鱼 IP 特征 | `103\.\d+\.\d+\.\d+` | 已知劫持 IP 段 |
| 伪造 DNS 应答 | `No DNS response from upstream` | 上游无响应但本地有 |
| TTL 异常 | `ttl:\d+` in response | 应答 TTL 与实际不符 |
| 响应 ID 不匹配 | `id: \d+` mismatch | DNS ID 劫持 |

## EDNS0 异常模式

| 模式 | 正则 | 说明 |
|------|------|------|
| 不支持 EDNS0 | `EDNS: version: 0,.*MBZ:.*ignored` | EDNS0 标记被忽略 |
| OPT 截断 | `OPT PSEUDOSECTION` empty | OPT 记录被中间盒截断 |
| 大包失败 | `Reply size unexpectedly` | UDP 包大小限制 |
| PMTU 问题 | `frag needed` / `too big` | PMTU 路径问题 |
| 未知 OPT 被弃 | `UNKNOWN OPT CODE` | 未知 OPT 代码 |

## 日志文件匹配模式

### syslog/messages

```regex
# DNS 超时
resolved.*Timeout waiting for DNS response

# 服务器不可用
resolved.*Server .* not reachable

# DNSSEC 失败
resolved.*DNSSEC validation failed for

# 缓存清除
resolved.*Flushing all caches

# 配置变化
resolved.*Using DNS server
```

### dnsmasq 日志

```regex
# 转发失败
dnsmasq.*failed to send packet

# 缓存
dnsmasq.*cached

# 上游超时
dnsmasq.*timeout from upstream

# NXDOMAIN
dnsmasq.*NXDOMAIN
```

## 关键端口速查

| 端口 | 协议 | 用途 |
|------|------|------|
| 53 | UDP/TCP | DNS 查询 |
| 5353 | UDP | mDNS (Multicast DNS) |
| 853 | TCP | DNS over TLS |
| 443 | TCP | DNS over HTTPS |
| 5355 | UDP | LLMNR |
