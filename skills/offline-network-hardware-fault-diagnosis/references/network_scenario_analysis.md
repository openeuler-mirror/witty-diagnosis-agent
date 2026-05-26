# 网络硬件故障场景专项分析指南

## 概述

本指南提供了针对网卡、光模块、物理链路及驱动层的深度故障分析流程。在 Step 1 确定故障场景后，必须遵循以下“从物理到逻辑”的推导逻辑锁定根因。

---

## 1. 总线与核心硬件故障 (NIC_BUS_HARDWARE)

### 1.1 核心日志与指纹识别
- `ibmc_logs/sel.db`：重点查找 `PCIe Error`、`NIC Fault`、`Temp Critical` 以及 `Suprise Removal`。
- `infocollect_logs/system/dmesg.txt`：查找 `PCIe Bus Error: severity=Fatal` 或 `AER: Uncorrected (Fatal) error`。

### 1.2 物理坐标映射规则
在分析 PCIe 错误时，必须将 BDF 地址映射到物理槽位/网卡名：
1. `dmesg` 中的 `0000:03:00.0` -> 通过 `lspci -v` 或 `ethtool -i` 确认对应 `eth0`。
2. 结合 `iBMC` 日志，确认 `NIC 1` 所在的物理槽位是否发生电压波动或过温。

### 1.3 经典传导链：PCIe 复位导致网卡“消失”
*   **时序链条**：`[主板槽位供电不稳] -> [PCIe 控制器检测到致命错误 (T0)] -> [内核记录 AER Uncorrected Error] -> [驱动试图重启 Adapter 失败] -> [网卡从 PCI 树中消失] -> [业务层面 ethX 接口丢失]`。

---

## 2. 物理层光/电接口故障 (PHYSICAL_LAYER_SFP)

### 2.1 关键诊断指纹 (DOM 审计)
查阅 `infocollect_logs/network/optical.txt` 中的 DOM（Digital Optical Monitoring）数据：

| 监控指标 | 健康阈值 (参考) | 异常含义 |
| :--- | :--- | :--- |
| **Rx Power** (接收光功率) | -1dBm ~ -12dBm | **低于 -15dBm**：光衰过载，通常由线缆脏、弯折或对端发光弱引起。 |
| **Tx Power** (发送光功率) | -1dBm ~ -5dBm | **极低或 N/A**：光模块激光器故障，TX Fault。 |
| **Temperature** (模块温度) | 0℃ ~ 70℃ | **超过 75℃**：模块高温报警，可能导致误码率（CRC）激增。 |

### 2.2 证据验证点
- 检查 `iBMC` 是否有 `SFP Abnormal` 或 `I2C Read Error`（读不到模块信息）。

---

## 3. 链路层完整性/信号故障 (LINK_LAYER_INTEGRITY)

### 3.1 核心指纹识别 (ethtool 计数器审计)
查阅 `infocollect_logs/network/ethtool_S.txt`，分析报错计数的潜在指向：

| 计数器名称 | 指向可能根因 (Root Cause Hypothesis) |
| :--- | :--- |
| **rx_crc_errors / rx_fcs_errors** | **物理链路干扰**：网线/光纤由于电磁干扰、接触不良导致的物理层校验失败。 |
| **rx_missed_errors / rx_resource_errors** | **硬件资源耗尽**：网卡内部缓冲区溢出，常见由于 PCIe 带宽不足或系统处理中断过慢。 |
| **rx_length_errors** | **MTU 不一致**：收到的数据包超过网卡配置上限，导致被硬件层丢弃。 |
| **rx_dropped** | **软件栈压力**：内核协议栈处理不过来，或防火墙规则/队列溢出导致。 |

### 3.2 经典传导链：CRC 风暴导致链路震荡
*   **时序链条**：`[网线屏蔽层受损] -> [rx_crc_errors 计数爆发式增长 (T0)] -> [PHY 物理层层触发链路自愈重协商] -> [系统记录 Link is DOWN / Link is UP (震荡)] -> [Bonding 驱动主备反复切换] -> [应用层大量重传及延时]`。

---

## 4. 驱动与固件逻辑故障 (DRIVER_FIRMWARE_LOGIC)

### 4.1 核心指纹
- `dmesg` 报错：`ixgbe/i40e/mlx5_core: TX hang` 或 `NETDEV WATCHDOG: ethX: transmit queue timeout`。
- `ethtool -i`：核对固件 (Firmware) 版本是否在厂家官方兼容列表中。

### 4.2 分析建议
- **固件挂死**：如果 `TX hang` 伴随 `Reset Adapter` 但无法恢复，通常是硬件固件进入逻辑死锁状态，需下电冷重启。

---

## 5. 中断处理与资源调度故障 (RESOURCE_SCHEDULING)

### 5.1 监控特征
- `top` 中的 `%si` (Softirq) 长期处于某一 CPU 核心高位（>80%），而其他核心空闲。
- `infocollect_logs/system/interrupts.txt` 中某一 `ethX-fp-0` 中断计数远高于其他。

### 5.2 根因路径
- 检查 `irq_affinity` 配置。如果单核饱和，根因通常是 **RSS (Receive Side Scaling) 队列数过少** 或 **中断绑定未生效**。

---

## 6. 逻辑 Bond 与物理配置限制 (LOGICAL_BONDING_CONFIG)

### 6.1 典型深度指纹
- **MTU 截断**：
  - **现象**：`ping -s 1472` (小包) 通，`ping -s 9000` (巨型帧) 不通。
  - **证据**：`ethtool -S` 中 `rx_length_errors` 增长，且 OS `messages` 中伴随 `fragmentation needed`。
- **udev 漂移**：
  - **证据**：`/etc/udev/rules.d/70-persistent-net.rules` 中的 MAC 地址与 `ip link` 中实际显示的 MAC 地址不匹配。

---

## 7. 执行策略与交叉校验 (Critical Rules)

1.  **分层互斥**：在判定“网卡损坏”前，必须先通过 `optical.txt` 排除“链路层/对端交换机”干扰。如果光功率极佳但 CRC 错误多，则回溯排查本地网口物理损害。
2.  **孤证不立**：内核层面的 `ethX: link down` 必须找到对应的硬件层报错（如：`iBMC SEL: Cable Disconnected` 或 `NIC temperature abnormal`）才可定性为物理根因。
3.  **时序逻辑闭环**：所有结论必须附带以 T0（故障零点）为起点的传导链分析，严禁直接跳跃至结论。
