# DNS 诊断命令速查

## 基础检测

| 命令 | 用途 | 示例 |
|------|------|------|
| `dig` | 全能 DNS 查询工具 | `dig +short example.com` |
| `nslookup` | 传统 DNS 查询 | `nslookup example.com` |
| `host` | 简洁 DNS 查询 | `host example.com` |
| `getent` | 系统库级名称解析 | `getent hosts example.com` |
| `resolvectl` | systemd-resolved 管理 | `resolvectl status` |

## /etc/resolv.conf 相关

```bash
cat /etc/resolv.conf
stat /etc/resolv.conf
ls -la /etc/resolv.conf
cat /etc/resolvconf/resolv.conf.d/head
cat /etc/resolvconf/resolv.conf.d/base
nmcli dev show | grep DNS
```

## nsswitch.conf 检查

```bash
grep ^hosts /etc/nsswitch.conf
grep -v '^#' /etc/nsswitch.conf | grep -v '^$'
```

## systemd-resolved 管理

```bash
resolvectl status              # 全局状态
resolvectl statistics          # 缓存统计
resolvectl query example.com   # 查询指定域名
resolvectl cache               # 查看缓存（旧版）
resolvectl flush-caches        # 清空缓存
resolvectl dns                 # 各接口 DNS 配置
resolvectl domain              # 各接口搜索域
resolvectl log level           # 日志级别
```

## 协议级诊断

```bash
# EDNS0 测试
dig +edns0 example.com
dig +noedns example.com
dig +bufsize=4096 example.com

# TCP fallback 测试
dig +tcp example.com
dig +notcp example.com

# 追踪解析链路
dig +trace example.com

# DNSSEC 验证
dig +dnssec example.com
delv +multiline example.com

# 指定 DNS 服务器
dig @8.8.8.8 example.com
dig @127.0.0.53 example.com
```

## 抓包分析

```bash
# DNS 查询/应答抓包
tcpdump -i any port 53 -c 10 -n
tcpdump -i any port 53 -vv -X

# 过滤特定域名
tcpdump -i any -n 'port 53 and (udp[10] & 0x80 != 0)'

# 跟踪 TCP DNS
tcpdump -i any 'port 53 and tcp'
tcpdump -i any 'tcp port 53 and tcp[tcpflags] & tcp-syn != 0'

# 保存抓包文件
tcpdump -i any port 53 -w dns_capture.pcap
```

## 系统和网络检测

```bash
# 检查防火墙
iptables -L -n -v | grep 53
nft list ruleset | grep 53

# 端口连通性
nc -zv 8.8.8.8 53
nc -zvu 8.8.8.8 53

# traceroute 到 DNS 服务器
traceroute -n -p 53 8.8.8.8

# MTU 检测（影响 EDNS0）
ping -M do -s 1472 8.8.8.8

# DNS 性能测试
dnstcpbench 8.8.8.8 example.com
dnsperf -s 8.8.8.8 -d querylist.txt
```
