# GPU 故障场景分类

GPU 诊断过程中，主要涉及以下五大核心故障场景：

| 场景标签 | 中文描述 | 主要特征与案例 |
| :--- | :--- | :--- |
| `GPU_HARDWARE_FATAL` | GPU 硬件致命故障 | ① **GPU 掉卡** (Fallen off the bus / XID 79)；② **物理损坏** (iBMC GPU Fault)；③ **供电/电压异常** (Voltage instability)；④ **硬件引擎掛死** (XID 31/45) |
| `GPU_DRIVER_CRASH` | 驱动与软件层故障 | ① **驱动初始化失败** (Initialization error)；② **内核崩溃** (NVRM Kernel Oops)；③ **CUDA 运行报错** (XID 62)；④ **版本不匹配** (API mismatch) |
| `GPU_MEMORY_ECC` | 显存 ECC 错误 | ① **不可纠正 ECC 错误** (Uncorrectable ECC / XID 31/43)；② **可纠正 ECC 风暴** (Correctable ECC Storm)；③ 显存页退休 (Page Retirement) |
| `GPU_THERMAL_POWER` | 散热与功耗限制 | ① **过温降频** (HW Slowdown / Thermal violation)；② **功耗封顶** (SW Power Cap)；③ iBMC 记录 GPU 温度告警 |
| `GPU_PCIE_LINK` | PCIe 链路与总线异常 | ① **链路减速** (Link width/speed reduction)；② **PCIe 总线错误** (AER Error / XID 61)；③ 接口 CRC 报错 |
