# X-diagnosis 网络诊断工具参考手册

本手册涵盖了用于网络系统在线故障诊断的核心工具及其详细使用说明。

---

## 1. xd_tcpresetstack

**功能**
监控 TCP 协议栈 (v4/v6) reset 信息，捕获触发 RST 时的内核调用链。

**用法**
```bash
xd_tcpresetstack [ OPTIONS ]
```

**参数**
- `-d, --depth`: 内核调用栈深度（默认 5 层）。
- `-h, --help`: 显示帮助信息。

---

## 2. xd_tcpskinfo

**功能**
查看 TCP 连接 Socket 的关键信息。该工具汇总了 TCP 连接在定位过程中经常需要的信息（如窗口大小、重传次数、RTT 等），辅助协议栈问题定位。

**用法**
```bash
xd_tcpskinfo [ OPTIONS ]
```

**参数**
- `-a, --addr`: IP 地址过滤（不区分源地址或目的地址）。
- `-p, --port`: 端口过滤（不区分源端口或目的端口）。
- `-h, --help`: 显示帮助信息。

---

## 3. xd_arpstormcheck

**功能**
监控当前网络是否发生网络风暴（ARP/ICMPv6）。

**用法**
```bash
xd_arpstormcheck [ OPTIONS ]
```

**参数**
- `-c, --count`: 总监控次数（默认持续监控）。
- `-f, --freq`: 告警阈值（默认 100/s）。
- `-h, --help`: 显示帮助信息。

---

## 4. xd_netvringcheck

**功能**
监控 virtio_net 网卡前后端 virtqueue ring 的使用状态，用于定界虚拟化场景下的丢包问题。

**用法**
```bash
xd_netvringcheck DEVNAME [rx/tx] [ OPTIONS ]
```

**参数**
- `DEVNAME`: 网卡名称（强制指定）。
- `[rx/tx]`: 指定收发队列（发送：tx，接收：rx）。
- `-i, --interval`: 监控时间间隔（默认 1s）。
- `-q, --queueidx`: 过滤指定的队列序号（默认所有）。

**注意事项**
- 当前仅支持 rx 或 tx 的单独查询，不支持同时查询。

---

## 5. xd_ntrace

**功能**
OS 内核协议栈丢包点检测，支持 TCP/UDP/ICMP 协议。

**用法**
```bash
xd_ntrace [ OPTIONS ]
```

**参数**
- `-p, --protocol`: 指定协议 [tcp|udp|icmp]。
- `-I, --icmpaddr`: 指定 ICMP 过滤的对端 IP。
- `-S, --saddr`: 指定源 IP。
- `-D, --daddr`: 指定目的 IP。
- `-s, --sport`: 指定源端口。
- `-d, --dport`: 指定目的端口。

**注意事项**
- 仅支持 IPv4。
- 与 `tcpdump` 冲突，不可同时使用。
- 与热补丁不可共用于同一个内核函数。
- 大包与分片场景不支持检测。

---

## 6. xd_skblen_check

**功能**
用于检测网络包记录长度与实际数据长度是否相等。如果不相等，则输出 MAC 地址、协议号和报文长度。

**用法**
```bash
xd_skblen_check [ OPTIONS ]
```

**参数**
- `-h, --help`: 显示帮助信息。

**注意事项**
- 仅能做 IP 层报文长度校验。
- IP 报文头在非线性区的报文无法校验。
