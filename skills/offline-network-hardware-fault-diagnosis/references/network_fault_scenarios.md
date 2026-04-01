# 网络硬件故障场景分类

网络硬件诊断过程中，主要涉及以下六大核心故障场景：

| 场景标签 | 中文描述 | 主要特征 |
| :--- | :--- | :--- |
| `NIC_HARDWARE_FAILURE` | 网卡硬件故障 | iBMC SEL 报告硬件错误、PCIe 致命错误、网卡热插拔事件、温度临界保护、UCE 引发网卡重置 |
| `DRIVER_ISSUE` | 驱动/固件问题 | 内核日志出现网卡驱动 Panic、固件加载失败、版本/型号不匹配、驱动逻辑 BUG 导致 TX Hang |
| `LINK_DOWN` | 物理链路故障 | 网口 Link Down、载波丢失、物理层(PHY)检测异常、Bond 网卡因链路故障发生主备切换 |
| `PERFORMANCE_DEGRADATION` | 性能下降/丢包 | 网络丢包/错包(CRC)/乱序、时延大/RTT 抖动、网络环路/拥塞引发的广播风暴 |
| `INTERRUPT_ERROR` | 中断/调度错误 | 网卡中断负载极化 (单核过载)、MSI/MSI-X 配置失败、中断风暴挤占 CPU 周期 |
| `CONFIG_ERROR` | 配置/协议错误 | IP 冲突、路由配置错误、MTU 不一致导致大包丢弃、网卡名枚举乱序 (eth0/eth1 漂移) |
