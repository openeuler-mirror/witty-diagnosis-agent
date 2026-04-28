#!/bin/bash
# show_location_index.sh — 快速问题定位索引 (仅包含 xd 网络诊断工具)

cat << 'EOF'
## 快速问题定位索引 (网络专项)

---

### 🔴 故障：TCP 连接被意外 RST，无法定位原因
**现象：** 业务报连接中断，tcpdump 抓到 RST 包，但不清楚是哪一端、哪个内核路径触发的。
**推荐命令：** `xd_tcpresetstack`
**定位步骤：**
1. 在出现 RST 的节点上执行 `xd_tcpresetstack`，工具开始挂载内核探针。
2. 复现业务连接断开（或等待问题自然触发）。
3. 查看工具输出，分别找到"发送 RST 调用栈"和"接收 RST 调用栈"。
4. 根据调用栈函数名判断触发原因（如 `tcp_send_active_reset`、`tcp_v4_send_reset` 等），结合内核源码确认具体场景。

---

### 🔴 故障：TCP 连接性能异常（吞吐低 / 时延抖动）
**现象：** 业务传输慢或时延高，用 `ss -nit` 查看信息有限，无法判断是窗口不足还是拥塞控制问题。
**推荐命令：** `xd_tcpskinfo`
**定位步骤：**
1. 通过 `ss -nit` 先确认异常连接的四元组（src IP:port → dst IP:port）。
2. 执行 `xd_tcpskinfo` 获取该连接的完整 socket 状态。
3. 重点查看以下字段：
   - `cwnd`（拥塞窗口）是否过小
   - `snd_wnd` / `rcv_wnd`（收发窗口）是否受限
   - 拥塞状态是否处于 `CA_Loss` 或 `CA_Recovery`
4. 根据字段判断是网络丢包导致拥塞、还是对端接收窗口限制了速率，针对性处理。

---

### 🔴 故障：网络疑似 ARP 风暴，流量异常
**现象：** 服务器网络质量下降，网卡 RX 流量激增，怀疑二层 ARP 广播或 ICMPv6 邻居发现报文泛滥。
**推荐命令：** `xd_arpstormcheck`
**定位步骤：**
1. 执行 `xd_arpstormcheck`，工具按阈值实时统计 ARP / ICMPv6 流量速率。
2. 观察输出是否出现超阈值告警信息。
3. 若确认为风暴，记录告警时刻的来源 MAC/IP，通过交换机日志或 `arp -n` 追溯来源设备。
4. 联系网络团队隔离异常端口或配置 ARP 限速策略。

---

### 🔴 故障：ping 不通 / TCP-UDP 丢包，找不到丢包点
**现象：** 两端网络互通但 ping 丢包，或 TCP/UDP 业务偶发超时，不确定丢包发生在协议栈哪一层。
**推荐命令：** `xd_ntrace`
**定位步骤：**
1. 确认丢包的协议类型和对端 IP。
2. 执行命令，指定协议和目标：
   ```bash
   # ICMP 丢包（ping 不通）
   xd_ntrace -p icmp -H <对端IP>
   # TCP 丢包（指定端口）
   xd_ntrace -p tcp -H <对端IP> -P <端口>
   ```
3. 工具自动遍历协议栈 17 种丢包点，输出触发的具体丢弃位置（如 `nf_hook_slow`、`ip_route_input` 等）。
4. 根据丢包函数名判断原因（防火墙规则、路由缺失、连接跟踪满等），再针对性修复。

---

### 🔴 故障：虚拟机网络中断，Host/Guest 问题定界
**现象：** 虚拟机（Guest）网络不通或丢包，不确定是 Guest 内部协议栈问题还是宿主机（Host）virtio 队列异常。
**推荐命令：** `xd_netvringcheck`
**定位步骤：**
1. 在 **Host** 上确认 Guest 使用的 virtio 网卡名（如 `vnet0`）。
2. 分别检查收发队列状态：
   ```bash
   xd_netvringcheck vnet0 rx -i 1   # 检查接收队列
   xd_netvringcheck vnet0 tx -i 1   # 检查发送队列
   ```
3. 观察 Ring 描述符填充情况：
   - Ring 描述符耗尽（`avail == used`）→ 问题在 Host 侧未及时处理；
   - Ring 描述符充足但 Guest 无数据 → 问题在 Guest 侧协议栈。
4. 根据定界结果，分别在 Host 或 Guest 内进一步排查。

---

### 🔴 故障：网络报文长度异常
**现象：** 怀疑数据包被截断或驱动层处理异常导致长度不一致。
**推荐命令：** `xd_skblen_check`
**定位步骤：**
1. 执行 `xd_skblen_check` 开始监控。
2. 观察输出中的 MAC 地址、协议号和长度差值。
3. 结合网卡驱动版本核查是否存在 Bug。
EOF
