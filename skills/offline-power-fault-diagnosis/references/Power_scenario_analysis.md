# Power 故障场景专项分析指南

## 概述

本指南提供了六种电源故障场景的专项分析流程。在 Step 1 确定故障场景后，应根据对应的场景执行专项分析。如果没有匹配的场景，则使用通用分析流程。

---

## 1. 服务器掉电分析 (POWER_LOSS)

### 1.1 核心日志文件

- `ibmc_logs/sel.db` / `sel.tar` - iBMC 系统事件日志（电源事件）
- `infocollect_logs/system/dmesg.txt` - 内核感知掉电事件
- `messages/messages` - 操作系统层面的系统日志

### 1.2 关键错误模式 (指纹识别)

| 错误类型 | 错误关键字 | 含义 |
| :--- | :--- | :--- |
| iBMC SEL | `Power Supply Unit .* AC Lost` | **AC 丢失**：外部交流输入中断 |
| iBMC SEL | `Power Supply Unit .* Power Loss` | **输出丢失**：PSU 内部直流输出失效 |
| 内核日志 | `unexpected shutdown` | **意外关机**：系统在未接收到合法指令前断电 |
| 内核日志 | `Last reboot was not clean` | **非正常重启**：检查文件系统是否需要 fsck |

### 1.3 分析命令

```bash
# 检查 iBMC 中的 AC 丢失和掉电事件
python3 scripts/diagnose_ibmc.py <ibmc_logs目录> -k "AC Lost" "Power Loss"

# 检查系统日志中的异常停机
python3 scripts/diagnose_messages.py <messages目录> -k "unexpected" "reboot" "shutdown"

# 使用电源专项脚本分析掉电原因
python3 scripts/diagnose_power.py <log_dir> --loss
```

### 1.4 根因推理框架

- **外部掉电**：所有 PSU 同时报告 `AC Lost` -> 根因为机房 PDU 或市电供电中断。
- **内部掉电**：PSU 记录 `Power Loss` 但无 `AC Lost` 且仅有单个 PSU 报错 -> 根因为 PSU 硬件损坏。

---

## 2. 电源模块故障分析 (POWER_MODULE_FAILURE)

### 2.1 核心日志文件

- `ibmc_logs/psu_status.txt` - PSU 实时健康状态
- `ibmc_logs/sel.db` - 物理硬件告警

### 2.2 关键错误模式 (指纹识别)

| 错误类型 | 错误关键字 | 含义 |
| :--- | :--- | :--- |
| iBMC SEL | `PSU #.* Failure` | **硬件故障**：电源模块内部电路失效 |
| iBMC SEL | `PSU #.* Absent` | **模块缺失**：物理拔出或连接器接触不良 |
| 传感器 | `Presence: NO` | 电源不在位 |

### 2.3 分析命令

```bash
# 检查 PSU 硬件报错
python3 scripts/diagnose_ibmc.py <ibmc_logs目录> -k "PSU" "Failure" "Absent"

# 专项电源硬件健康度分析
python3 scripts/diagnose_power.py <log_dir> --hardware
```

---

## 3. 电压异常分析 (VOLTAGE_ANOMALY)

### 3.1 核心日志文件

- `ibmc_logs/sensor_info.txt` - 电压传感器历史记录
- `infocollect_logs/system/dmesg.txt` - 内核对电压波动的感知

### 3.2 关键错误模式 (指纹识别)

| 错误类型 | 错误关键字 | 含义 |
| :--- | :--- | :--- |
| iBMC SEL | `Voltage .* Out of range` | **电压超限**：实测电压超过预设容忍阈值 |
| 内核日志 | `Voltage violation` | **电压违规**：内核检测到背板供电不稳 |
| iBMC SEL | `VRM .* Error` | **主板 VRM 故障**：主板调压模块失效 |

### 3.3 分析命令

```bash
# 过滤电压超限和违规信号
python3 scripts/diagnose_ibmc.py <ibmc_logs目录> -k "Voltage" "range"
python3 scripts/diagnose_messages.py <messages目录> -k "Voltage" "violation"
```

---

## 4. 电源冗余失效分析 (REDUNDANCY_FAILURE)

### 4.1 核心逻辑

冗余失效（Redundancy Lost）通常是 PSU 故障或配置不匹配的级联表现。

### 4.2 关键错误模式 (指纹识别)

| 错误类型 | 错误关键字 | 含义 |
| :--- | :--- | :--- |
| iBMC SEL | `Redundancy Lost` | **冗余丢失**：活动 PSU 数量低于配置要求 |
| PSU Stats | `Current distribution anomaly` | **负载失衡**：两路 PSU 输出电流差异超过 30% |

### 4.3 诊断方案

1. **数量核对**：检查物理安装的 PSU 总数。
2. **负载校验**：使用 `diagnose_power.py` 检查单路是否长期处于极低输出状态（可能存在金手指污染）。

---

## 5. 电源过载分析 (OVERLOAD)

### 5.1 核心日志文件

- `ibmc_logs/power_monitor.txt` - 功耗实时监控数据
- `infocollect_logs/system/top.txt` - 系统负载历史快照

### 5.2 关键错误模式 (指纹识别)

| 错误类型 | 错误关键字 | 含义 |
| :--- | :--- | :--- |
| iBMC SEL | `Power Overload` | **电源过载**：系统总功耗超过 PSU 额定容量 (Wattage) |
| iBMC SEL | `Power Capping activated` | **限功率激活**：由于供电不足，iBMC 强行压制 CPU 功率 |

### 5.3 根因推理

- **T0 对齐**：业务峰值时间点是否与 `Power Overload` 告警重合。
- **环境验证**：检查是否由于单路 PSU 离线导致剩余 PSU 无法承载全负载。

---

## 6. 电源过热分析 (TEMPERATURE_ISSUE)

### 6.1 核心日志文件

- `ibmc_logs/sensor_info.txt` - PSU 入口及内部温度传感器
- `ibmc_logs/sel.db` - 风扇硬件状态

### 6.2 关键错误模式 (指纹识别)

| 错误类型 | 错误关键字 | 含义 |
| :--- | :--- | :--- |
| iBMC SEL | `Over-temp Trip` | **热保护下电**：温度突破临界值，为保护硬件强制断电 |
| iBMC SEL | `Fan Rotor Locked` | **风扇转子锁定**：PSU 内部风扇无法旋转，热量积聚 |
| 传感器 | `PSU Inlet Temp > 45C` | 环境进风过热 |

### 6.3 诊断策略

1. **环境温度校验**：检查环境温度是否符合机房标准。
2. **气流路径检查**：检查背板风道是否被遮挡或 PSU 防尘网是否积尘。

---

## 7. 执行策略 (Policy)

### 7.1 证据驱动原则
- **物理故障定性**：严禁仅凭 OS 重启就判断 PSU 故障，必须满足 iBMC/SEL 层的硬件告警证据。
- **孤证不立**：单一点的电压波动需配合传导链上的受灾表现（如 CPU 降频或重新上电）。

### 7.2 时空对齐
- **跨日志轴校准**：分析时必须校准 OS 与 iBMC 的 NTP 偏差，确保传导链顺序逻辑自洽。

### 7.3 结论防发散 (Anti-Hallucination)
- **拦截假想**：若传导链中出现证据断裂（如 PSU 无告警但 OS 提示电压低），结论必须降级为“疑似 (Suspected)”并标注取证盲区。
