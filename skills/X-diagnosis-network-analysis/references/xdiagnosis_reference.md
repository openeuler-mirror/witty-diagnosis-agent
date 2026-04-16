# x-diagnosis 使用规范

## 概述

x-diagnosis 是基于 EulerOS 维护团队多年运维经验形成的系统运维工具集，集成问题定位、系统巡检/监控、ftrace 增强、一键收集日志等功能，是 OS 内核问题定位的核心工具。

## 安装

```bash
# 依赖：python 3.7+
rpm -ivh xdiagnosis-1.x-x.rpm
```

## 全局约束（使用前必读）

| 约束项 | 说明 |
|------|------|
| **不支持并发** | 所有 xd_* 命令**串行执行**，严禁同时启动多个 xd_* 工具 |
| **交付范围** | 当前仅交付存储产品使用，其他产品需联系欧拉团队 |
| **xd_ntrace 专项限制** | 仅支持 IPv4；与 tcpdump 冲突，不可同时运行；与热补丁不可共用同一内核函数 |
| **xd_skblen_check 限制** | 仅校验 IP 层报文；IP 报文头在非线性区时无法校验 |
| **xd_schedmonitor 性能影响** | 在调度/中断频繁场景下有一定性能影响，生产环境需评估 |

---

## 工具速查表

| 工具 | 适用故障场景 | 核心参数 |
|------|------|------|
| `xd_tcpresetstack` | TCP 连接被意外 RST | `-d <depth>` |
| `xd_tcpskinfo` | TCP 连接卡顿/重传/窗口异常 | `-a <IP> -p <PORT>` |
| `xd_arpstormcheck` | ARP 风暴/广播风暴 | `-f <freq> -c <count>` |
| `xd_netvringcheck` | virtio 虚拟网卡队列拥塞 | `<DEVNAME> rx/tx -i <interval>` |
| `xd_ntrace` | 内核协议栈静默丢包定位 | `-p <proto> -S -D -s -d` |
| `xd_skblen_check` | 网络包长度异常检测 | 无参数 |
| `xd_schedmonitor` | 网络 I/O 导致调度/中断延迟 | `-I yes -t <ms> -k yes` |

---

## 详细命令参考

### xd_tcpresetstack — TCP RST 内核栈监控

**功能**：监控 tcp 协议栈（v4/v6）reset 信息，捕获 RST 触发时的内核调用链。

```
xd_tcpresetstack [-d <depth>]
```

| 参数 | 说明 | 默认值 |
|------|------|------|
| `-d / --depth` | 内核调用栈深度 | 5 层 |
| `-h / --help` | 帮助信息 | — |

**典型用法**：
```bash
# 标准监控（默认5层栈）
xd_tcpresetstack

# 加深栈深度，用于复杂调用链分析
xd_tcpresetstack -d 10
```

**分析步骤**：
1. 复现故障期间保持工具运行
2. 捕获 RST 触发时的内核调用链
3. 根据栈帧判断：
   - 协议栈主动发送 RST（端口不可达、半开连接超时）
   - 驱动层/硬件层异常触发

---

### xd_tcpskinfo — TCP Socket 关键信息查看

**功能**：汇总 TCP 连接在 debug 过程中经常需要的信息，比 `ss` 命令更全面，用于辅助协议栈问题定位。

```
xd_tcpskinfo [-a <IP>] [-p <PORT>]
```

| 参数 | 说明 | 默认值 |
|------|------|------|
| `-a / --addr` | IP 地址过滤（不区分源/目的） | 所有 |
| `-p / --port` | 端口过滤（不区分源/目的端口） | 所有 |
| `-h / --help` | 帮助信息 | — |

**典型用法**：
```bash
# 过滤特定连接
xd_tcpskinfo -a 192.168.1.100 -p 8080

# 查看所有 TCP 连接关键信息
xd_tcpskinfo
```

**关键输出字段解读**：

| 字段 | 含义 | 异常判断 |
|------|------|------|
| `rcv_wnd` | 接收窗口大小 | 持续为 0 → 对端缓冲区满 |
| `snd_wnd` | 发送窗口大小 | 持续为 0 → 流控问题 |
| `retrans` | 重传次数 | 持续增长 → 链路丢包 |
| `rtt` | 往返时延 | 值高且抖动 → 链路拥塞 |

---

### xd_arpstormcheck — ARP 风暴监控

**功能**：监控当前网络是否发生 ARP 风暴，超过阈值自动告警。

```
xd_arpstormcheck [-f <freq>] [-c <count>]
```

| 参数 | 说明 | 默认值 |
|------|------|------|
| `-f / --freq` | 告警阈值（每秒包数），超过则告警 | 100/s |
| `-c / --count` | 监控总次数，达到后自动退出 | 持续监控 |
| `-h / --help` | 帮助信息 | — |

**典型用法**：
```bash
# 设置 200/s 阈值，持续监控
xd_arpstormcheck -f 200

# 监控 100 次后退出
xd_arpstormcheck -f 200 -c 100
```

**分析步骤**：
1. 执行命令，观察是否触发告警及告警频率
2. 结合告警信息定位风暴源：
   - 交换机环路 → 检查 STP 配置
   - 异常虚机 → 隔离对应虚机
   - VLAN 配置错误 → 检查 VLAN 规划

---

### xd_netvringcheck — virtio 网卡队列监控

**功能**：监控 virtio 网卡前后端 virtqueue ring 的使用状态，定位虚拟化场景丢包。

```
xd_netvringcheck <DEVNAME> <rx|tx> [-i <interval>] [-q <queueidx>]
```

| 参数 | 说明 | 默认值 |
|------|------|------|
| `DEVNAME` | 网卡名称（**必填**） | — |
| `rx / tx` | 接收/发送队列（**必填**，不可同时） | — |
| `-i / --interval` | 监控时间间隔（秒） | 1s |
| `-q / --queueidx` | 指定队列序号 | 所有队列 |
| `-h / --help` | 帮助信息 | — |

> ⚠️ **注意**：当前仅支持 rx 或 tx 的单独查询，不支持同时查询 rx 和 tx。

**典型用法**：
```bash
# 监控 eth0 接收队列，1s 间隔
xd_netvringcheck eth0 rx -i 1

# 监控 eth0 发送队列，指定队列 0
xd_netvringcheck eth0 tx -q 0 -i 2
```

**分析步骤**：
1. 观察 ring 使用率是否持续接近满载
2. 分析前后端处理速率差异：
   - 宿主机处理瓶颈 → 检查宿主机 CPU/中断负载
   - Guest 侧消费慢 → 检查 Guest 内核驱动/CPU 负载

---

### xd_ntrace — 内核协议栈丢包点检测

**功能**：检测报文在内核各钩子点（netfilter/路由/socket层）的丢包位置，精准定位静默丢包根因。

```
xd_ntrace -p <proto> [-S <saddr>] [-D <daddr>] [-s <sport>] [-d <dport>]
```

| 参数 | 说明 | 备注 |
|------|------|------|
| `-p / --protocol` | 协议类型：tcp / udp / icmp（**必填**） | — |
| `-S / --saddr` | 源 IP 地址（tcp/udp） | — |
| `-D / --daddr` | 目的 IP 地址（tcp/udp） | — |
| `-s / --sport` | 源端口（tcp/udp） | — |
| `-d / --dport` | 目的端口（tcp/udp） | — |
| `-I / --icmpaddr` | ICMP 对端 IP（**icmp 协议专用过滤参数**） | — |
| `-h / --help` | 帮助信息 | — |

> ⚠️ **重要限制**：
> - 仅支持 IPv4 场景
> - **不支持并发执行**
> - **与 tcpdump 冲突，请勿同时使用**
> - 与热补丁不可共用同一内核函数
> - 不支持大包与分片场景；报文头在非线性区时不支持检测
> - 网桥场景检测 ICMP 协议时可能存在误报
> - ICMP 协议过滤只支持指定对端地址（`-I` 参数）

**典型用法**：
```bash
# 精准过滤 TCP 流
xd_ntrace -p tcp -S 192.168.1.10 -D 192.168.1.20 -d 8080

# 检测 UDP
xd_ntrace -p udp -D 10.0.0.1 -d 53

# 检测 ICMP（只能用 -I 参数过滤地址）
xd_ntrace -p icmp -I 192.168.1.1
```

**丢包点输出解读**：

| 丢包位置 | 可能根因 | 处理方向 |
|------|------|------|
| netfilter 钩子 | iptables/nftables 规则拦截 | 检查防火墙规则 |
| 路由层 | 路由缺失或配置错误 | 检查路由表 |
| socket 缓冲区 | 接收缓冲区溢出、应用处理慢 | 调整 rmem 或优化应用 |

---

### xd_skblen_check — 网络包长度异常检测

**功能**：检测网络包记录长度与实际数据长度是否一致，不一致时输出 MAC 地址、协议号和长度差值。

```
xd_skblen_check   # 无参数
```

> ⚠️ **注意**：仅能做 IP 层报文长度校验；IP 报文头在非线性区的报文无法校验。

**典型用法**：
```bash
# 持续监控，有异常时自动输出
xd_skblen_check
```

**分析步骤**：
1. 有输出时记录：MAC 地址、协议号、长度差值
2. 结合 `ethtool -i <IFACE>` 核查驱动版本
3. 判断是驱动 bug 还是硬件故障

---

### xd_schedmonitor — CPU 调度监控

**功能**：监控 CPU 长时间被占用（通常由网络中断引起）导致其他进程无法被调度的事件。

```
xd_schedmonitor [-c <cpus>] [-I <yes|no>] [-k <yes|no>] [-w <yes|no>] [-t <ms>]
```

| 参数 | 说明 | 默认值 |
|------|------|------|
| `-c / --cpus` | 指定追踪的 CPU（多个用","分隔，最大256个） | 所有 CPU |
| `-I / --interrupt` | 是否开启硬中断监控（yes/no） | no |
| `-k / --kstack` | 是否打印内核调用栈（yes/no） | yes |
| `-w / --waitsched` | 是否开启唤醒等待监控（yes/no） | no |
| `-t / --threshold` | 调度事件时间阈值（ms），低于此值不上报 | 500ms |
| `-h / --help` | 帮助信息 | — |

> ⚠️ **注意**：指定 `-c` 后 `-w` 参数失效；本工具影响调度关键路径，调度/中断频繁场景下有性能影响。

**典型用法**：
```bash
# 开启硬中断监控，阈值 100ms，打印内核栈
xd_schedmonitor -I yes -t 100 -k yes

# 只监控 CPU 0,1
xd_schedmonitor -c 0,1 -I yes -t 200
```

**分析步骤**：
1. 捕获超阈值的调度事件及内核调用栈
2. 判断根因：
   - 网卡中断亲和性配置不当 → 调整 `smp_affinity`
   - 软中断积压 → 检查 `ksoftirqd` 负载
   - 内核锁竞争 → 分析调用栈锁路径
