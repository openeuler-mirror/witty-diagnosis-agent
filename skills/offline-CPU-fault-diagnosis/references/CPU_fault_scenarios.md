# CPU 故障场景分类

CPU 诊断过程中，主要涉及以下七大核心故障场景：

| 场景标签 | 中文描述 | 主要特征 |
| :--- | :--- | :--- |
| `CPU_HARDWARE_FAILURE` | CPU 硬件故障 | iBMC SEL 报告 CPU 硬件错误、致命硬件告警、包含 UCE (不可纠正错误) 引发 MCE #18 导致系统 Panic |
| `CPU_OVERHEATING` | CPU 过热 | CPU 温度持续超过安全阈值、风扇故障、散热不良、触发 Thermal Trip |
| `CPU_MICROCODE_ERROR` | CPU 微码错误 | 微码更新失败、微码版本不匹配、原生微码逻辑缺陷 |
| `CPU_CACHE_ERROR` | CPU 缓存错误 | L1/L2/L3 缓存 ECC 校验错误、包含高频 CE (可纠正错误) 诱发 CE 风暴进而导致 CPU 降频保护 |
| `CPU_FREQUENCY_THROTTLING` | CPU 频率调节 | CPU 频率被限制、电源管理策略异常、高温自保护降频 |
| `CPU_INTERCONNECT_ERROR` | CPU 互连错误 | QPI/UPI 总线通信错误、多路 CPU 间数据同步异常 |
| `CPU_VOLTAGE_REGULATION` | CPU 电压调节 | VRM（电压调节模块）故障、CPU 供电波动或欠压/过压 |