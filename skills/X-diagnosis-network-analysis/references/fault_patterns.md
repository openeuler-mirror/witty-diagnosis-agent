# 典型故障案例与根因速查表

## 按故障现象速查

| 故障现象 | 优先检查 | 常见根因 | x-diagnosis 工具 |
|------|------|------|------|
| ping 网关不通 | 网卡链路状态、IP 配置 | 网线/光模块故障、IP 配置错误 | — |
| ping 通但端口不通 | iptables、服务监听 | 防火墙拦截、服务绑定 127.0.0.1 | — |
| TCP 连接被 RST | RST 内核调用链 | 端口不可达、半开连接超时、驱动异常 | `xd_tcpresetstack` |
| 连接卡顿/重传频繁 | TCP window、RTT、retrans | 链路丢包、对端缓冲区满、流控异常 | `xd_tcpskinfo` |
| 应用收不到包（抓包可见） | 内核各钩子点丢包 | netfilter 拦截、路由缺失、socket 缓冲区溢出 | `xd_ntrace` |
| 网络带宽耗尽/不可用 | ARP 包速率 | ARP 风暴（交换机环路/虚机异常/VLAN 错误） | `xd_arpstormcheck` |
| virtio 虚机丢包/高延迟 | virtqueue ring 使用率 | 前后端处理速率失衡，宿主机或 Guest 侧瓶颈 | `xd_netvringcheck` |
| 数据包数据错误 | skb 长度一致性 | 驱动 bug、硬件故障 | `xd_skblen_check` |
| 业务抖动（网络中断引起） | CPU 调度延迟、硬中断 | 中断亲和性不当、软中断积压、内核锁竞争 | `xd_schedmonitor` |
| DNS 解析失败 | resolv.conf、DNS 服务器可达性 | DNS 服务器宕机、配置错误、防火墙拦截 53 端口 | — |
| DNS 解析慢 | dig 耗时、search 域配置 | search 域过多导致多次查询、DNS 服务器响应慢 | — |
| TIME_WAIT 堆积 | TCP 连接状态、tw_reuse 配置 | 短连接频繁、tw_reuse/tw_recycle 未开启 | `xd_tcpskinfo` |
| 全连接队列积压 | ss Send-Q、accept 调用 | 应用处理慢、backlog 设置过小 | — |

---

## 分层根因矩阵

### 物理 & 链路层

| 症状 | 诊断命令 | 根因 |
|------|------|------|
| `ip link show` 显示 DOWN | `ethtool <IFACE>` | 网线未插、光模块故障、端口被 shutdown |
| `ethtool -S` 有 rx_errors/tx_errors | `dmesg \| grep NIC` | 网线质量差、硬件故障、驱动 bug |
| ring buffer 频繁满 | `ethtool -g <IFACE>` | ring buffer 设置过小，需调大 |

### IP & 路由层

| 症状 | 诊断命令 | 根因 |
|------|------|------|
| `ip route get <DST>` 无路由 | `ip route show` | 路由未配置或被删除 |
| `ip neigh show` 无法学到网关 MAC | `arping -I <IFACE> <GW>` | ARP 被拦截、VLAN 不通 |
| IP 冲突 | `arping -D -I <IFACE> <IP>` | 同网段有重复 IP |

### 防火墙层

| 症状 | 诊断命令 | 根因 |
|------|------|------|
| `iptables -nvL` 某条规则包数持续增长 | 对比 DROP/REJECT 规则 | 规则误拦截目标流量 |
| SELinux audit 日志有 AVC denied | `audit2allow -i /var/log/audit/audit.log` | SELinux 策略阻断 |

### 服务 & 应用层

| 症状 | 诊断命令 | 根因 |
|------|------|------|
| `ss -tlnp` 无对应端口 | `systemctl status <SVC>` | 服务未启动或崩溃 |
| 服务监听 `127.0.0.1:<PORT>` | 修改配置为 `0.0.0.0` | 服务只绑定本地回环 |
| `ss Send-Q` 持续不为 0 | 检查应用 accept 速率 | 全连接队列积压 |

---

## 难点故障诊断思路

### TCP 连接被 RST — 根因区分

```
RST 来源判断：
├── xd_tcpresetstack 栈帧包含 tcp_send_active_reset
│   ├── 端口不可达 → 服务未监听目标端口
│   └── 半开连接超时 → 调整 tcp_keepalive 参数
├── xd_tcpresetstack 栈帧包含驱动模块函数
│   └── 驱动/硬件层异常 → 升级驱动或更换硬件
└── tcpdump 显示 RST 来自对端
    └── 对端主动关闭 → 检查对端服务日志
```

### 内核静默丢包 — 定位流程

```
xd_ntrace 输出丢包点：
├── NF_HOOK (netfilter)
│   └── 检查 iptables -nvL 哪条规则匹配量在增长
├── ip_route_input / fib_lookup
│   └── 路由缺失，检查 ip route show
└── __sk_receive_skb / sock_queue_rcv_skb
    └── socket 缓冲区溢出，检查 rmem_max / 应用处理速度
```

### ARP 风暴处置

```
1. 先限速：iptables -A INPUT -p arp -m limit --limit 100/s -j ACCEPT
           iptables -A INPUT -p arp -j DROP
2. 定位风暴源：xd_arpstormcheck 告警信息 + tcpdump -i <IFACE> arp
3. 根治：
   ├── 交换机环路 → 启用 STP
   ├── 异常虚机 → 隔离虚机
   └── VLAN 配置错误 → 修正 VLAN 划分
```
