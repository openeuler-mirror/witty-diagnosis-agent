# Power 故障场景分类

服务器电源诊断过程中，主要涉及以下六大核心故障场景：

| 场景标签 | 中文描述 | 主要特征与案例 |
| :--- | :--- | :--- |
| `POWER_LOSS` | 服务器掉电 | ① **AC 丢失** (AC Lost)；② **全系统下电** (Power Loss)；③ 意外关机 (Unexpected Shutdown) |
| `POWER_MODULE_FAILURE` | 电源模块故障 | ① **PSU 硬件故障** (PSU Failure)；② **PSU 缺失** (PSU Absent)；③ 固件不兼容；④ 金手指连接异常 |
| `VOLTAGE_ANOMALY` | 电压异常 | ① **电压超限** (Voltage Out of Range)；② **电压违规** (Voltage Violation)；③ 主板 VRM 模块失效 |
| `REDUNDANCY_FAILURE` | 电源冗余失效 | ① **冗余丢失** (Redundancy Lost)；② PSU 数量不匹配；③ 多路负载不均衡 |
| `OVERLOAD` | 电源过载 | ① **系统功耗过载** (Power Overload)；② 瞬间峰值功耗超过额定；③ 限功率策略激活 |
| `TEMPERATURE_ISSUE` | 电源过热 | ① **PSU 过热保护** (Over-temp Trip)；② **风扇转子锁定** (Fan Rotor Locked)；③ 环境散热恶化 |
