# CPU 故障场景分类

CPU 诊断过程中，主要涉及以下七大核心故障场景，旨在通过底层日志指纹锁定物理级根因。

| 场景标签 | 中文描述 | 核心证据与指纹 (Fingerprints) |
| :--- | :--- | :--- |
| `CPU_HARDWARE_FAILURE` | CPU 硬件故障 | ① **CATERR/IERR** (致命错误)；② **MCE #18** (不可纠正硬件错误)；③ **Internal Error** (内核/iBMC 报告物理损坏)；④ 插槽 (Socket) 针脚电气异常 |
| `CPU_OVERHEATING` | CPU 过热 | ① **Thermal Trip** (温度过高自动断电)；② **PROCHOT#** 信号触发；③ CPU 温度持续攀升且风扇转速异常；④ 散热器硅脂失效 |
| `CPU_MICROCODE_ERROR` | CPU 微码/内核 Bug | ① `microcode update failed`；② 触发特定指令集导致的 **Soft Lockup**；③ BIOS/UEFI 版本与 CPU 步进 (Stepping) 不兼容 |
| `CPU_CACHE_ERROR` | CPU 缓存错误 | ① **L1/L2/L3 ECC UCE** (不可纠正错误)；② **CE 风暴** (高频可纠正错误) 诱发系统卡顿；③ 缓存控制器死锁 |
| `CPU_FREQUENCY_THROTTLING` | CPU 频率调节 | ① **C-State/P-State 切换异常**；② 电源管理策略 (Performance/PowerSave) 冲突；③ **HWP** (硬件控制频率) 逻辑失效 |
| `CPU_INTERCONNECT_ERROR` | CPU 互连错误 | ① **UPI/QPI Link Error** (CRC/同步错误)；② 多路服务器节点间的物理链路物理层 (Layer 1) 告警 |
| `CPU_VOLTAGE_REGULATION` | CPU 电压调节 | ① **VRM Fault** (电压调节模块失效)；② CPU 供电电压波动 (Under/Over Voltage)；③ 主板滤波电容老化 |

---

### 辅助诊断红线

- **交叉验证要求**：物理故障判定必须同时具备 iBMC (带外) 和 OS (带内) 的双向证据支持。
- **环境隔离原则**：在判定 CPU 硬件损坏前，务必排除风扇、电源及机房环境等外部诱发因素。
- **场景互斥性**：过热导致的降频属于 `CPU_OVERHEATING`，而非单纯的 `CPU_FREQUENCY_THROTTLING`。