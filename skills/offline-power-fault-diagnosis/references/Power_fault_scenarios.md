# Power 故障场景分类

服务器电源诊断过程中，主要涉及以下六大核心故障场景：

| 场景标签 | 中文描述 | 主要特征 |
| :--- | :--- | :--- |
| `POWER_LOSS` | 服务器掉电 | 系统意外关机、AC 丢失、全系统下电；导致内存 dirty page/WAL 数据丢失 |
| `POWER_MODULE_FAILURE` | 电源模块故障 | iBMC SEL 报告 PSU 故障、PSU 缺失、PSU 内部硬件错误 |
| `VOLTAGE_ANOMALY` | 电压异常 | iBMC 报告电压超出范围、电压传感器故障；可能触发处理器自保护降频 |
| `REDUNDANCY_FAILURE` | 电源冗余失效 | PSU 冗余丢失、N+1 状态破坏、多路供电负载极度不均衡 |
| `OVERLOAD` | 电源过载 | 系统功耗超过 PSU 额定容量、电流过载保护触发 |
| `TEMPERATURE_ISSUE` | 电源过热 | PSU 内部温度过高、PSU 风扇转子锁定或转速异常 |
