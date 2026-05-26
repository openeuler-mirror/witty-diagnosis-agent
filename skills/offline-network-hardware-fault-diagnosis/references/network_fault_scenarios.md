# 网络硬件故障场景分类

网络硬件诊断过程中，主要涉及以下六大核心故障场景，按从物理底层到逻辑层级的顺序排列：

| 场景标签 | 中文描述 | 主要特征与案例 |
| :--- | :--- | :--- |
| `NIC_BUS_HARDWARE` | 总线与核心硬件故障 | ① **PCIe 致命错误** (Fatal Error/AER)；② **iBMC 硬件告警** (NIC Fault/Board Error)；③ **温度临界保护** (Thermal Shutdown)；④ **主板/槽位供电异常**导致网卡掉线 |
| `PHYSICAL_LAYER_SFP` | 物理层光/电接口故障 | ① **光功率异常** (Rx Power Low/High)；② **光模块故障** (TX/RX Fault)；③ **模块不兼容** (Vendor Mismatch)；④ **环境温度过高**导致光模块性能劣化 |
| `LINK_LAYER_INTEGRITY` | 链路层完整性/信号故障 | ① **CRC 错包风暴** (rx_crc_errors)；② **链路频繁震荡** (Link Flapping)；③ **物理载波丢失** (Carrier Lost)；④ **线缆质量/磁干扰**导致 PHY 握手反复失败 |
| `DRIVER_FIRMWARE_LOGIC` | 驱动与固件逻辑故障 | ① **TX 队列挂死** (TX Hang / NETDEV WATCHDOG)；② **固件加载失败** (Firmware Load Failed)；③ **版本不匹配**导致的初始化异常；④ 驱动 Bug 触发的内核 Panic |
| `RESOURCE_SCHEDULING` | 中断处理与资源调度故障 | ① **中断亲和性极化** (跨核心不均导致单核 si 满)；② **MSI-X 资源耗尽**；③ **软中断(si)风暴**导致系统卡顿；④ **RSS 接收队列**分配不合理 |
| `LOGICAL_BONDING_CONFIG` | 逻辑 Bond 与物理配置限制 | ① **Bond 主备异常切换**；② **MTU 设置不当**导致大包被静默丢弃 (DF check)；③ **udev 规则冲突**导致网卡名漂移；④ **ARP 冲突**引发的网络离线 |

---
