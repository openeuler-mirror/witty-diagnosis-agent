# NPU 故障场景分类

NPU（神经网络处理器）诊断过程中，主要涉及以下五大核心故障场景。这些场景涵盖了从物理链路到底层驱动的主要失效模式：

| 场景标签 | 中文描述 | 主要特征与案例 |
| :--- | :--- | :--- |
| `NPU_HARDWARE_FAILURE` | NPU 核心硬件故障 | ① **核心器件故障** (Die 或封装损坏)；② **内部逻辑错误** (严重且无法自我恢复的内部死锁)；③ **设备离线** (由于内部严重硬件故障导致的硬性 Offline) |
| `NPU_PCIE_LINK_ISSUE` | PCIe 链路与拓扑故障 | ① **AER 报错** (Advanced Error Reporting, 如 Uncorrectable Error)；② **设备丢失** (PCIe 枚举阶段或运行中突然 Missing)；③ **链路反复训练/重置** (Link reset, link down)；④ 虚接或 Riser 故障导致的心跳丢失 |
| `NPU_DRIVER_SW_STACK` | 驱动与软件栈报错 | ① **驱动加载失败** (依赖缺失或版本不匹配)；② **CANN 与 Firmware 不匹配** (导致功能异常或初始化失败)；③ **内核崩溃** (NPU 驱动抛出 Panic/Oops)；④ **通信层 Acl Error** (HCCP/集合通信等接口超时或错误) |
| `NPU_HBM_PERFORMANCE` | HBM 与显存故障 | ① **Uncorrectable ECC** (致命的双比特/多比特显存损坏)；② **Correctable ECC风暴** (达到阈值，反映颗粒老化)；③ **显存访问死锁或超时**； |
| `NPU_THERMAL_POWER` | 热电与功耗异常 | ① **过温保护** (Thermal Throttling 或达到致死温度触发自动断电)；② **供电波动** (背板/电源模块异常导致瞬时供电不足掉卡)；③ **功耗受限** (Policy限制导致频率和性能无法达标) |
