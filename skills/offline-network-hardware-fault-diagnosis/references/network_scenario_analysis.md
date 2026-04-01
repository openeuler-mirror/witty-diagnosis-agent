# 网络硬件故障场景专项分析指南

## 概述

本指南提供了六种网络硬件故障场景的专项分析流程。当 Step 1 确定故障场景后，应根据对应的场景执行专项分析。如果没有匹配的场景，则使用通用分析流程。

## 1. 网卡硬件故障分析 (NIC_HARDWARE_FAILURE)

### 1.1 核心日志文件

- `ibmc_logs/sel.db` / `sel.tar` - iBMC 系统事件日志（网卡/PCIe 错误）
- `infocollect_logs/system/dmesg.txt` - 内核 PCIe/网卡底层报错
- `messages/messages` - 系统级驱动/总线错误日志

### 1.2 关键错误模式

| 错误类型 | 错误关键字 | 含义 |
|---------|-----------|------|
| iBMC SEL | `Hardware failure` | 显式硬件故障 | 可能性：1. 网卡芯片烧毁 2. 内部逻辑单元损坏 |
| iBMC SEL | `Hotplug` / `Surprise Removal` | 网卡热插拔事件 | 可能性：1. 人为插拔 2. PCIe 槽位松动触发重枚举 |
| iBMC SEL | `PCIe error` | PCIe 总线错误 |
| iBMC SEL | `NIC temperature` | 网卡温度异常 |
| 内核日志 | `PCIe Bus Error: severity=Fatal` | 致命 PCIe 总线错误 |
| 内核日志 | `AER: Uncorrected (Fatal) error` | 不可纠正 PCIe AER 错误 |
| 内核日志 | `Hardware Error` | 硬件错误（驱动感知） |

### 1.3 分析命令

```bash
# 检查 iBMC 硬件状态
python3 scripts/diagnose_ibmc.py <ibmc_dir> -k "NIC" "PCIe" "Temperature" "Hotplug"
# 检查内核层面 PCIe/网卡错误
python3 scripts/diagnose_messages.py <messages_dir> -k "PCIe error" "NIC failure" "Surprise Removal"

# 综合网络分析
python3 scripts/diagnose_network.py <log_dir> --hardware
```

### 1.4 根因推理框架与经典传导链

**经典故障传导链示范：PCIe AER 错误导致网卡重置及业务中断**
*   **时序链条**：`[物理链路信号不稳/插槽接触不良] -> [PCIe 控制器检测到不可纠正错误(Fatal Error)] -> [内核立即记录 AER 汇报] -> [驱动探测到硬件状态不可用触发 Reset Adapter] -> [链路重初始化失败或反复重置] -> [业务层面表现为网络连接永久中断]`。
*   **诊断验证点**：检查 `dmesg` 中是否有 `AER: Uncorrected` 且 BDF 号指向网卡。

**通用推理步骤**：
1. **因果链条**：梳理从 T0（最早硬件报错）到网卡重置、链路 Down 的时间线。
2. **鉴别排除**：对照根因假设矩阵。先有温度告警则锁定散热；无先兆直接报错则锁定物理损坏。
3. **根因锁定**：需有跨层证据（iBMC + dmesg）支持。
4. **不确定标注**：若日志缺失导致传导链断裂，标注传导深度。

---

## 2. 驱动/固件问题分析 (DRIVER_ISSUE)

### 2.1 核心日志文件

- `infocollect_logs/system/dmesg.txt` - 内核驱动加载/崩溃日志
- `infocollect_logs/network/ethtool_i.txt` - 驱动及固件(FW)版本信息
- `messages/messages` - 系统模块操作日志

### 2.2 关键错误模式

| 错误类型 | 错误关键字 | 含义 |
|---------|-----------|------|
| 内核日志 | `failed to load firmware` | 固件加载失败 |
| 内核日志 | `driver error` | 驱动内部错误 |
| 内核日志 | `ixgbe/i40e/mlx5.*reset` | 驱动触发网卡重置 |
| 内核日志 | `firmware version mismatch` | 固件版本不匹配 |

### 2.3 分析命令

```bash
# 检查驱动加载错误
python3 scripts/diagnose_messages.py <messages目录> -k "driver" "firmware" "failed"

# 检查网卡详细驱动版本
python3 scripts/diagnose_infocollect.py <infocollect目录> -k "ethtool -i" "version"
```

### 2.4 根因推理框架

1. **核对兼容性**：比对 OS 内核、驱动和网卡固件是否在官方兼容列表。
2. **定位崩溃点**：若是驱动导致 Panic，分析堆栈中的函数调用，查找是否有已知的 Bug 补丁。
3. **证据锁定**：锁定“版本冲突”或“逻辑空指针”证据。

---

## 3. 物理链路故障分析 (LINK_DOWN)

### 3.1 核心日志文件

- `messages/messages` - 链路 Up/Down 切换日志
- `infocollect_logs/network/ethtool.txt` - 物理层协商参数
- `infocollect_logs/network/optical.txt` - 光模块功率/温度数据

### 3.2 关键错误模式

| 错误类型 | 错误关键字 | 含义 |
|---------|-----------|------|
| 系统日志 | `NIC Link is UP` (频繁出现) | 链路震荡 | 可能性：1. 屏蔽层干扰 2. 接口频繁复位 |
| 系统日志 | `bonding: Active-Backup` | Bond 网卡切换 | 场景：主从网卡链路 Down 触发流量迁移至备用网卡 |
| 系统日志 | `Link is Down` | 链路断开 |
| 系统日志 | `lost carrier` | 载波丢失 |
| 系统日志 | `autonegotiation failed` | 自动协商失败 |
| 内核日志 | `SFP: vendor mismatch` | 光模块厂商不匹配 |

**经典故障传导链示范：Bond 网卡主备切换过程**
*   **时序链条**：`[Slave 0 网线松动] -> [PHY 检测到载波丢失] -> [Bonding 驱动 MII 轮询发现故障] -> [内核记录 Link Down] -> [驱动执行 failover 将流量切至 Slave 1] -> [网络短暂颤抖后恢复]`。

### 3.3 分析命令

```bash
# 检查链路状态日志
python3 scripts/diagnose_messages.py <messages目录> -k "link down" "carrier" "eth"

# 检查光模块状态
python3 scripts/diagnose_infocollect.py <infocollect目录> -k "SFP" "DOM" "optical"

# 综合链路分析
python3 scripts/diagnose_network.py <log_dir> --link
```

### 3.4 根因推理框架与经典传导链

**经典故障传导链示范：光功率过低导致频繁链路震荡**
*   **时序链条**：`[光口积尘/光纤弯折] -> [网卡 Rx 接收功率持续走低至临界值] -> [PHY 芯片出现误码风暴] -> [链路感知层判定信号丢失触发 Link Down] -> [重协商成功后 Link Up 再次掉线] -> [由于震荡导致业务中断]`。

---

## 4. 性能下降/丢包分析 (PERFORMANCE_DEGRADATION)

### 4.1 核心日志文件

- `infocollect_logs/network/ethtool_S.txt` - 网卡底层统计计数 (Critical)
- `infocollect_logs/network/ifconfig.txt` - 接口收发及报错计数
- `infocollect_logs/system/sar_n_DEV.txt` - 历史流量统计数据

### 4.2 关键错误模式 (底层计数审计)

| 计数名称 | 含义 | 指向可能根因 |
|---------|------|------------|
| `rx_crc_errors` | CRC 冗余校验错误 | 物理链路磁干扰、网线质量差、光模块损坏 |
| `rx_missed_errors` | 网卡内部缓冲区溢出 | PCIe 带宽不足、系统负载过高 |
| `rx_dropped` / `overruns` | `ifconfig` | 核心根因多为 CPU 中断负载不均或处理能力到达瓶颈 |
| `tx_errors` | 发送错误 | 半双工冲突或物理参数不匹配 |

**网络环路/拥塞分析 (Case 3)**：
- **特征**：`/proc/net/dev` 中的广播包 (broadcast) 计数呈指数级增长，伴随全核心 CPU `si` 占比爆表。
- **根因推断**：STP 配置失效触发广播风暴，占满网卡缓冲区。

### 4.3 分析命令

```bash
# 检查网卡详细计数
python3 scripts/diagnose_infocollect.py <infocollect目录> -k "ethtool -S" "errors" "dropped"

# 综合性能分析
python3 scripts/diagnose_network.py <log_dir> --performance
```

---

## 5. 中断/调度错误分析 (INTERRUPT_ERROR)

### 5.1 核心日志文件

- `infocollect_logs/system/interrupts.txt` - `/proc/interrupts` 计数值
- `infocollect_logs/system/top.txt` - CPU 软中断 (si) 占比
- `infocollect_logs/network/irq_affinity.txt` - 中断亲和性配置

### 5.2 关键异常特征

- **单核极化**：某一 CPU 核心处理的中断数远大于其他核心
- **si 占比过大**：`top` 输出中 `%si` 长期处于高位（>50%）
- **MSI-X 失败**：`dmesg` 汇报无法分配 MSI-X 中断，回退到 legacy

### 5.3 分析命令

```bash
# 检查中断分布
python3 scripts/diagnose_infocollect.py <infocollect目录> -k "interrupts" "si" "affinity"
```

---

## 6. 配置/协议错误分析 (CONFIG_ERROR)

### 6.1 核心日志文件

- `infocollect_logs/network/ip_addr.txt` - IP 配置
- `infocollect_logs/network/route.txt` - 路由表
- `infocollect_logs/network/vlan.txt` - VLAN 子接口配置

### 6.2 关键特征

- **IP 冲突**：在 `messages` 中搜索 `duplicate address` 或 `arp reply`。
- **MTU 不一致 (Case 5)**：
  - **现象**：小包正常，大包（如 `ping -s 1472`）不通。
  - **证据**：`dmesg` 中可能出现 `ICMP fragmentation needed` 且 DF 置位。
- **网卡名乱序 (Case 6)**：
  - **现象**：重启后 `eth0` 变为 `eth1`，导致 IP 配置失效。
  - **检查**：审计 `/etc/udev/rules.d/70-persistent-net.rules` 是否与物理 MAC 地址一致。

---

## 7. 执行策略

### 7.1 场景匹配优先

1. **优先使用专项分析**：当 Step 1 确定故障场景后，优先使用对应的专项分析流程。
2. **参考专项分析指南**：按照本指南中对应场景的分析步骤执行。
3. **使用专用参数**：使用场景专用的分析命令和参数。

### 7.2 通用分析备用

1. **无匹配场景时使用**：当故障现象不符合任何专项场景时，使用通用分析流程。
2. **结果验证**：通过跨层交叉（iBMC/内核/工具）确认证据的一致性，确保 2 条独立证据锁定根因。
