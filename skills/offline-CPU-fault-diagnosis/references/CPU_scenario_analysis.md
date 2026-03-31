# CPU故障场景专项分析指南

## 概述

本指南提供了七种CPU故障场景的专项分析流程。当Step 1确定故障场景后，应根据对应的场景执行专项分析。如果没有匹配的场景，则使用通用分析流程。

## 1. CPU硬件故障分析 (CPU_HARDWARE_FAILURE)

### 1.1 核心日志文件

- `ibmc_logs/sel.db` / `sel.tar` - iBMC系统事件日志（CPU硬件错误）
- `infocollect_logs/system/dmesg.txt` - 内核MCE（机器检查异常）日志
- `messages/messages` - 系统级CPU错误日志

### 1.2 关键错误模式

| 错误类型 | 错误关键字 | 含义 |
|---------|-----------|------|
| iBMC SEL | `CPU #.* Correctable Error` | CPU可纠正错误 |
| iBMC SEL | `CPU #.* Uncorrectable Error` | CPU不可纠正错误 |
| iBMC SEL | `CPU #.* Machine Check` | 机器检查异常 |
| 内核日志 | `MCE:.*CPU` | 机器检查异常（CPU相关） |
| 内核日志 | `CPU.*fatal error` | CPU致命错误 |
| 内核日志 | `CPU.*hardware error` | CPU硬件错误 |

### 1.3 分析命令

```bash
# 检查iBMC SEL中的CPU错误
python3 scripts/diagnose_ibmc.py <ibmc_logs目录> -k "CPU.*Error" "Machine Check"

# 检查内核MCE日志
python3 scripts/diagnose_messages.py <messages目录> -k "MCE" "machine check"

# 综合CPU分析
python3 scripts/diagnose_cpu.py <log_dir> --hardware
```

### 1.4 根因推理框架与经典传导链

**经典故障传导链示范：UCE (不可纠正错误) 导致 Panic 宕机**
*   **时序链条**：`[底层物理损坏/供电不稳] -> [硅片出现多比特UCE] -> [硬件立即触发 Machine Check #18 中断] -> [内核判定不可恢复触发 Kernel Panic] -> [系统直接复位重启]`。
*   **诊断验证点**：在遇到不明原因重复宕机时，需重点检索 `dmesg` 中的 `Uncorrected hardware memory error` 或 `MCE #18` 及 MCE Bank 寄存器日志块。

**通用推理步骤**：
1. **因果链条**：整理从"最早的异常日志时间戳"到"故障发生结果"的完整事件序列。
2. **鉴别排除**：对照根因假设矩阵进行双向检验并排异（例：先有 `CPU temperature high` 再出现 `CPU error` → 属过热传导；仅有 `CPU error` 且周围环境/散热日志干净 → 属纯硬件故障）。
3. **根因锁定**：必须有至少 2 条独立的跨层证据支持，且验证无矛盾证据后，方可锁定最终根因。
4. **不确定标注**：若因日志缺失导致无法锁定，必须降级为"疑似"或"多种可能"，并说明传导链在哪里出现断层。

> 🔍 **重点确认**：报错是 UCE 还是 CE？MCE 报错的具体 Bank 寄存器编号是多少？是否有环境温度异常的先兆干扰？

## 2. CPU过热分析 (CPU_OVERHEATING)

### 2.1 核心日志文件

- `ibmc_logs/cpu_sensor.txt` - CPU温度传感器数据
- `ibmc_logs/fan_sensor.txt` - 风扇转速传感器数据
- `infocollect_logs/system/thermal.txt` - 系统温度监控数据
- `messages/messages` - 系统热管理日志

### 2.2 关键错误模式

| 错误类型 | 错误关键字 | 含义 |
|---------|-----------|------|
| iBMC SEL | `CPU #.* Thermal Trip` | CPU温度触发保护 |
| iBMC SEL | `CPU #.* Temperature` | CPU温度异常 |
| 内核日志 | `CPU.*over temperature` | CPU过热 |
| 内核日志 | `thermal.*throttling` | 热管理降频 |
| 内核日志 | `CPU.*throttling` | CPU降频 |

### 2.3 分析命令

```bash
# 检查CPU温度数据
python3 scripts/diagnose_ibmc.py <ibmc_logs目录> -k "Temperature" "Thermal"

# 检查热管理日志
python3 scripts/diagnose_messages.py <messages目录> -k "thermal" "throttling" "over temperature"

# 综合CPU温度分析
python3 scripts/diagnose_cpu.py <log_dir> --temperature
```

### 2.4 根因推理框架

1. **因果链条**：整理从"温度升高"到"触发保护"的完整事件序列
2. **鉴别排除**：从根因假设矩阵中逐一标注 ✅/❌/❓
3. **根因锁定**：至少有 2 条独立证据支持，且无矛盾证据时，方可锁定根因
4. **不确定标注**：若证据不足以锁定，明确标注"待验证假设"并说明缺失的证据类型

> 🔍 **重点确认**：是环境温度过高？散热器问题？风扇故障？还是负载异常导致发热？

## 3. CPU微码错误分析 (CPU_MICROCODE_ERROR)

### 3.1 核心日志文件

- `infocollect_logs/system/dmesg.txt` - 内核微码相关日志
- `infocollect_logs/system/cpuinfo.txt` - CPU信息（含微码版本）
- `messages/messages` - 系统微码更新日志

### 3.2 关键错误模式

| 错误类型 | 错误关键字 | 含义 |
|---------|-----------|------|
| 内核日志 | `microcode` | 微码相关 |
| 内核日志 | `CPU.*microcode` | CPU微码 |
| 内核日志 | `microcode.*error` | 微码错误 |
| 内核日志 | `microcode.*update` | 微码更新 |

### 3.3 分析命令

```bash
# 检查微码相关日志
python3 scripts/diagnose_messages.py <messages目录> -k "microcode"

# 检查CPU信息
python3 scripts/diagnose_infocollect.py <infocollect目录> -k "microcode" "CPU"

# 综合微码分析
python3 scripts/diagnose_cpu.py <log_dir> --microcode
```

### 3.4 根因推理框架

1. **因果链条**：整理微码相关事件的完整序列
2. **鉴别排除**：从根因假设矩阵中逐一标注 ✅/❌/❓
3. **根因锁定**：至少有 2 条独立证据支持，且无矛盾证据时，方可锁定根因
4. **不确定标注**：若证据不足以锁定，明确标注"待验证假设"并说明缺失的证据类型

> 🔍 **重点确认**：微码版本是否匹配CPU型号？微码更新是否成功？是否有已知的微码bug？

## 4. CPU缓存错误分析 (CPU_CACHE_ERROR)

### 4.1 核心日志文件

- `infocollect_logs/system/dmesg.txt` - 内核缓存错误日志
- `messages/messages` - 系统缓存错误日志
- `ibmc_logs/sel.db` - iBMC缓存相关事件

### 4.2 关键错误模式

| 错误类型 | 错误关键字 | 含义 |
|---------|-----------|------|
| 内核日志 | `cache error` | 缓存错误 |
| 内核日志 | `CPU.*cache` | CPU缓存 |
| 内核日志 | `ECC error` | ECC错误 |
| 内核日志 | `L1.*error` | L1缓存错误 |
| 内核日志 | `L2.*error` | L2缓存错误 |
| 内核日志 | `L3.*error` | L3缓存错误 |

### 4.3 分析命令

```bash
# 检查缓存错误
python3 scripts/diagnose_messages.py <messages目录> -k "cache error" "ECC" "L1" "L2" "L3"

# 综合缓存分析
python3 scripts/diagnose_cpu.py <log_dir> --cache
```

### 4.4 根因推理框架与经典传导链

**经典故障传导链示范：CE (可纠正错误) 风暴导致降频保护**
*   **时序链条**：`[缓存出现单比特底层错误] -> [ECC硬件介入自动纠错(CE)] -> [错误频次过高达到触发阈值(CE风暴)] -> [海量 MCE 轮询风暴挤占CPU核心周期并触发内核降频自保] -> [业务端表现为进程严重卡顿或节点假死]`。
*   **诊断验证点**：当发现服务器监控并未极度高温，系统却频繁触发 `throttling` (降频) 或 `Soft Lockup` 时，必须反查 OS messages 或硬件 SEL 中是否存在呈现指数激增的 ECC Corrected Error count。

**通用推理步骤**：
1. **因果链条**：整理完整的事件序列，特别注意从偶发 CE 到 CE 风暴爆发的频次变化的时间拐点。
2. **鉴别排除**：对照根因假设矩阵，证实或排除外部环境干扰（如内存控制器故障还是总线干扰）。
3. **根因锁定**：建立完整的闭环（包含底层的高频的 ECC 记录器自增证据 + 顶层的系统降频卡顿表象）。
4. **不确定标注**：若缺少其中一环日志证据，降级确信度说明。

> 🔍 **重点确认**：是可纠正(CE)还是不可纠正(UCE)？每秒发生的错误频次(Error Rate)是多少？是否已引发了系统级的次生灾害（如软锁死或降频）？

## 5. CPU频率调节分析 (CPU_FREQUENCY_THROTTLING)

### 5.1 核心日志文件

- `infocollect_logs/system/cpufreq.txt` - CPU频率调节信息
- `infocollect_logs/system/turbostat.txt` - CPU频率统计
- `messages/messages` - 系统电源管理日志

### 5.2 关键错误模式

| 错误类型 | 错误关键字 | 含义 |
|---------|-----------|------|
| 系统日志 | `throttling` | 降频 |
| 系统日志 | `frequency` | 频率 |
| 系统日志 | `CPU.*frequency` | CPU频率 |
| 系统日志 | `power management` | 电源管理 |

### 5.3 分析命令

```bash
# 检查频率调节日志
python3 scripts/diagnose_messages.py <messages目录> -k "throttling" "frequency" "power management"

# 检查CPU频率信息
python3 scripts/diagnose_infocollect.py <infocollect目录> -k "cpufreq" "turbostat"

# 综合频率分析
python3 scripts/diagnose_cpu.py <log_dir> --frequency
```

### 5.4 根因推理框架

1. **因果链条**：整理频率调节事件的完整序列
2. **鉴别排除**：从根因假设矩阵中逐一标注 ✅/❌/❓
3. **根因锁定**：至少有 2 条独立证据支持，且无矛盾证据时，方可锁定根因
4. **不确定标注**：若证据不足以锁定，明确标注"待验证假设"并说明缺失的证据类型

> 🔍 **重点确认**：降频是由于温度过高？电源策略？还是硬件限制？

## 6. CPU互连错误分析 (CPU_INTERCONNECT_ERROR)

### 6.1 核心日志文件

- `infocollect_logs/system/dmesg.txt` - 内核总线错误日志
- `messages/messages` - 系统总线错误日志
- `ibmc_logs/sel.db` - iBMC总线相关事件

### 6.2 关键错误模式

| 错误类型 | 错误关键字 | 含义 |
|---------|-----------|------|
| 内核日志 | `QPI error` | QPI总线错误 |
| 内核日志 | `UPI error` | UPI总线错误 |
| 内核日志 | `interconnect` | 互连 |
| 内核日志 | `bus error` | 总线错误 |
| 内核日志 | `CPU.*bus` | CPU总线 |

### 6.3 分析命令

```bash
# 检查互连错误
python3 scripts/diagnose_messages.py <messages目录> -k "QPI" "UPI" "interconnect" "bus error"

# 综合互连分析
python3 scripts/diagnose_cpu.py <log_dir> --interconnect
```

### 6.4 根因推理框架

1. **因果链条**：整理互连错误事件的完整序列
2. **鉴别排除**：从根因假设矩阵中逐一标注 ✅/❌/❓
3. **根因锁定**：至少有 2 条独立证据支持，且无矛盾证据时，方可锁定根因
4. **不确定标注**：若证据不足以锁定，明确标注"待验证假设"并说明缺失的证据类型

> 🔍 **重点确认**：是物理连接问题？信号完整性问题？还是协议错误？

## 7. CPU电压调节分析 (CPU_VOLTAGE_REGULATION)

### 7.1 核心日志文件

- `ibmc_logs/cpu_sensor.txt` - CPU电压传感器数据
- `ibmc_logs/sel.db` - iBMC电压相关事件
- `messages/messages` - 系统电源相关日志

### 7.2 关键错误模式

| 错误类型 | 错误关键字 | 含义 |
|---------|-----------|------|
| iBMC SEL | `CPU #.* Voltage` | CPU电压异常 |
| iBMC SEL | `VRM` | 电压调节模块 |
| 系统日志 | `voltage` | 电压 |
| 系统日志 | `power supply` | 电源供应 |

### 7.3 分析命令

```bash
# 检查电压相关日志
python3 scripts/diagnose_ibmc.py <ibmc_logs目录> -k "Voltage" "VRM"

# 检查电源相关日志
python3 scripts/diagnose_messages.py <messages目录> -k "voltage" "power supply"

# 综合电压分析
python3 scripts/diagnose_cpu.py <log_dir> --voltage
```

### 7.4 根因推理框架

1. **因果链条**：整理电压异常事件的完整序列
2. **鉴别排除**：从根因假设矩阵中逐一标注 ✅/❌/❓
3. **根因锁定**：至少有 2 条独立证据支持，且无矛盾证据时，方可锁定根因
4. **不确定标注**：若证据不足以锁定，明确标注"待验证假设"并说明缺失的证据类型

> 🔍 **重点确认**：是VRM模块故障？主板电容问题？还是电源供应不稳定？

## 8. 执行策略

### 8.1 场景匹配优先

1. **优先使用专项分析**：当Step 1确定故障场景后，优先使用对应的专项分析流程
2. **参考专项分析指南**：按照本指南中对应场景的分析步骤执行
3. **使用专用参数**：使用场景专用的分析命令和参数

### 8.2 通用分析备用

1. **无匹配场景时使用**：当故障现象不符合任何专项场景时，使用通用分析流程
2. **组合使用**：可以同时使用多个通用分析脚本，覆盖不同的日志来源
3. **逐步深入**：从概览分析开始，逐步深入具体问题

### 8.3 结果验证

1. **交叉验证**：使用不同来源的日志相互验证
2. **时间关联**：验证不同日志中的时间关联性
3. **根因确认**：确保至少有2条独立证据支持根因结论