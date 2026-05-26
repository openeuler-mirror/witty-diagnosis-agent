# CPU 故障场景专项分析指南

## 概述

本指南提供了针对七种核心 CPU 故障场景的深度专项分析流程。在 Step 1 确定场景标签后，必须遵循对应的“根因推理框架”和“错误指纹”模型完成最终诊断。

---

## 1. CPU 硬件故障分析 (CPU_HARDWARE_FAILURE)

### 1.1 核心日志文件
- `ibmc_logs/sel.db` / `sel.tar` - iBMC 系统事件日志（致命硬件报错）
- `infocollect_logs/system/dmesg.txt` - 内核 MCE (Machine Check Exception) 详细堆栈
- `messages/messages` - 操作系统层面的硬件诊断事件

### 1.2 关键错误模式 (指纹识别)
| 错误类型 | 错误关键字 | 含义 |
| :--- | :--- | :--- |
| iBMC SEL | `CATERR` / `IERR` | **致命错误**：CPU 内部或总线触发了无法恢复的逻辑/物理故障 |
| 内核日志 | `MCE: [18/00/00]` | **MCE #18**：明确指向 CPU 内部执行单元或寄存器发生 UCE 损坏 |
| iBMC SEL | `MSMI` / `NMI` | **不可屏蔽中断**：硬件检测到严重错误，强制 CPU 停止运行并复位 |
| 内核日志 | `Internal Error [05/20/xx]` | CPU 内部微架构逻辑报错，通常指示硅片缺陷或插槽接触故障 |

### 1.3 分析命令
```bash
# 检查 iBMC 中的致命 CPU 硬件报错
python3 scripts/diagnose_ibmc.py <log_dir> -k "CATERR" "IERR" "Machine Check"

# 提取内核详细 MCE 报错
python3 scripts/diagnose_messages.py <log_dir> -k "MCE" "machine check" "panic"
```

### 1.4 根因推理框架
- **致命路径**：`CATERR` + `MCE #18` -> 确认为物理 CPU (Socket X) 内部逻辑损坏，建议更换备件。
- **接触路径**：频繁出现 `IERR` 且伴随 `Socket Busy` 或 `UPI Link Error` -> 检查主板 Socket 针脚是否弯曲或电气接触不良。

---

## 2. CPU 过热分析 (CPU_OVERHEATING)

### 2.1 核心日志文件
- `ibmc_logs/sensor.txt` - CPU 温度、风扇转速实时数据
- `infocollect_logs/system/thermal.txt` - 系统热管理策略及阈值
- `messages/messages` - 内核热限制 (Thermal Throttling) 记录

### 2.2 关键错误模式 (指纹识别)
| 错误类型 | 错误关键字 | 含义 |
| :--- | :--- | :--- |
| iBMC SEL | **`Thermal Trip`** | **极致高温保护**：温度超过硅片物理临界点，硬件强行断序断电以防损 |
| 内核日志 | `Core temperature above threshold` | CPU 触发内部 PROCHOT# 信号，开始通过降低工作电压/频率自保 |
| iBMC SEL | `Fan .* RPM failed` | 散热风扇转速异常，导致机箱内部积热 |
| 内核日志 | `CPU clock throttled` | 内核检测到硬件热保护信号，执行强制降频 |

### 2.3 根因推理框架
**经典传导链演示**：
`[风扇转子锁定 / 负载瞬间爆发] -> [CPU 温度升高至阈值 (95°C+)] -> [频率持续 Throttled 并伴随 I/O 延迟] -> [触发 Thermal Trip 硬件断电保护 (T0)]`。
- **验证点**：必须对比 T0 发生前 15 分钟的 `sensor` 数据，确认是否存在温度线性增长与风扇转速低下的耦合关系。

---

## 3. CPU 微码/内核 Bug 分析 (CPU_MICROCODE_ERROR)

### 3.1 关键指纹
- **微码报错**：`microcode: updated to revision 0x...` 后发生 `Unexpected Machine Check`，指示新版本微码与旧硬件或 OS 指令集存在逻辑互斥。
- **Soft Lockup**：内核报告 `watchdog: BUG: soft lockup - CPU#X stuck for 22s!`，且堆栈中无 I/O 等待，仅有纯计算指令，高度疑似 CPU 指令集逻辑陷阱或微码死锁。

---

## 4. CPU 缓存错误分析 (CPU_CACHE_ERROR)

### 4.1 核心日志文件
- `infocollect_logs/system/dmesg.txt` - 重点查看 MCE Bank 0-3 (通常负责缓存)
- `messages/messages` - 系统频繁的记录频率统计

### 4.2 关键指纹
| 故障类别 | 典型指纹 | 根因逻辑 |
| :--- | :--- | :--- |
| **UCE (不可纠正)** | `L1/L2 Cache Uncorrected Error` | 缓存物理块损坏，导致数据逻辑链路中断，触发 Panic |
| **CE 风暴** | **海量 `Corrected Error`** | 单个核心缓存区域老化严重，硬件频繁纠错挤占总线带宽，引发业务卡滞 |

---

## 5. CPU 频率调节分析 (CPU_FREQUENCY_THROTTLING)

### 5.1 场景推理
- **电源管理策略**：若 `cpufreq` 始终维持在 `PowerSave` 模式而在高峰期不伸缩，则根因为 OS 层面的调频器 (Governor) 配置不当。
- **硬件频率回退**：若温度正常但 `turbostat` 显示始终无法进入最高 `Turbo Boost` 频率，检查 iBMC 侧是否开启了“功耗配额（Power Capping）”限制。

---

## 6. CPU 互连错误分析 (CPU_INTERCONNECT_ERROR)

### 6.1 核心特征
- **UPI 链路重置**：`mpt3sas` 或 `PCIe` 日志中出现 `Link Training Error`。
- **多路同步失败**：在多核心 (Multi-Socket) 拓补下，若 CPU 0 与 CPU 1 通信延迟激增，主板上的 UPI/QPI 串行链路可能存在电气干扰或插槽引脚受潮。

---

## 7. CPU 电压调节分析 (CPU_VOLTAGE_REGULATION)

### 7.1 典型报警
- **VRM Fault**：iBMC 报告 `Voltage Regulator Module failed`，随后 CPU 报告 `Power Fault`。
- **欠压逻辑**：电压低于临界值 (Under Voltage) 导致逻辑计算逻辑 0/1 判断错误，进而引发海量的假性 MCE 或频繁重启。

---

## 诊断执行红线 (Checklist)
1. **证据闭环**：物理故障判定必须附带 MCE 寄存器行或 iBMC SEL 精确文本。
2. **时序回溯**：报告中的 T0 前必须包含一段“故障孕育期”的日志对比。
3. **互斥排查**：判定 CPU 主体损坏前，已确认确认风扇、环境温度、电源模块（PSU）三项处于 `Healthy` 状态。