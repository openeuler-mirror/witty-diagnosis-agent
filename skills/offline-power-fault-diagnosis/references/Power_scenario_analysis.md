# Power 故障场景专项分析指南

## 概述

本指南提供了六种电源故障场景的专项分析流程。当 Step 1 确定故障场景后，应根据对应的场景执行专项分析。如果没有匹配的场景，则使用通用分析流程。

## 1. 服务器掉电分析 (POWER_LOSS)

### 1.1 核心日志文件
- `ibmc_logs/sel.db` / `sel.tar` - iBMC 系统事件日志（电源事件）
- `infocollect_logs/system/dmesg.txt` - 内核掉电事件
- `messages/messages` - 系统关机/重启记录

### 1.2 关键错误模式
| 错误类型 | 错误关键字 | 含义 |
| :--- | :--- | :--- |
| iBMC SEL | `Power Supply Unit .* AC Lost` | 电源交流输入丢失 |
| iBMC SEL | `Power Supply Unit .* Power Loss` | 电源输出丢失 |
| 内核日志 | `unexpected shutdown` | 意外关机 |
| 系统日志 | `system reboot` | 系统重启 |

### 1.3 分析命令
```bash
# 检查 iBMC SEL 中的电源丢失错误
python3 scripts/diagnose_ibmc.py <ibmc_logs目录> -k "AC Lost" "Power Loss"

# 检查系统关机日志
python3 scripts/diagnose_messages.py <messages目录> -k "shutdown" "reboot" "unexpected"

# 综合电源分析
python3 scripts/diagnose_power.py <log_dir> --loss
```

### 1.4 根因推理框架与传导链
**经典传导链：外部供电故障导致服务器下电**
*   **时序链条**：`[外部 AC 停止供电] -> [iBMC 记录 AC Lost] -> [PSU 依靠电容维持极短时间后记录 Power Loss] -> [系统断电导致内存 dirty page/WAL 被丢弃] -> [系统强行断开并产生文件系统损坏]`。
*   **诊断验证点**：如果在 T0 时刻所有电源模块同时报告 `AC Lost`，基本可定性为外部供电（PDU/市电）故障。

### 1.5 推荐修复建议

*   **硬件与基础设施 (预防)**：
    1.  **双路 UPS 部署**：确保服务器接入独立循环的双路 UPS 供电。
    2.  **RAID 卡 BBU/超级电容**：针对带缓存的 RAID 卡，强制安装 BBU 电池或超级电容，确保掉电时 Cache 数据强制刷盘。
*   **系统与软件优化 (减灾)**：
    1.  **文件系统挂载**：使用 `data=ordered` 或 `data=journal` 挂载参数，降低掉电导致的文件系统损坏概率。
    2.  **刷盘周期调整**：通过 `/proc/sys/vm/dirty_expire_centisecs` 缩短 OS 脏页刷盘周期。
    3.  **数据库同步建议**：开启数据库 WAL (Write-Ahead Logging) 强同步选项（如 PostgreSQL `synchronous_commit = on`）。
*   **恢复措施**：
    1.  **崩溃自愈**：在系统启动项配置针对非根分区的自动 `fsck -y`。
    2.  **逻辑一致性扫描**：利用业务软件（如数据库）自带的 Crash Recovery 机制执行 redo 操作。

---

## 2. 电源模块故障分析 (POWER_MODULE_FAILURE)

### 2.1 核心日志文件
- `ibmc_logs/psu_status.txt` - PSU 状态数据
- `ibmc_logs/sel.db` - 硬件告警
- `messages/messages` - 操作系统层面的电源管理日志

### 2.2 关键错误模式
| 错误类型 | 错误关键字 | 含义 |
| :--- | :--- | :--- |
| iBMC SEL | `PSU #.* Failure` | PSU 硬件故障 |
| iBMC SEL | `PSU #.* Absent` | PSU 缺失（物理拔出或连接异常） |
| 系统日志 | `power supply.*removed` | 操作系统检测到电源移除 |

### 2.3 分析命令
```bash
# 检查电源故障关键字
python3 scripts/diagnose_ibmc.py <ibmc_logs目录> -k "PSU" "Failure"

# 综合电源硬件分析
python3 scripts/diagnose_power.py <log_dir> --hardware
```

### 2.4 根因推理框架
**经典传导链：PSU 内部电路老化导致故障**
*   **时序链条**：`[PSU 内部元件故障] -> [PSU 硬件控制器上报 Failure 信号] -> [iBMC SEL 记录故障及冗余丢失] -> [（若总功耗高）操作系统检测到功率波动]`。
*   **诊断验证点**：单路 PSU 故障通常伴随着 `Redundancy Lost`，若系统依然运行，说明另一路正常；若双路均报 `Failure` 且 T0 接近，需怀疑电源背板或环境骤变（雷击/涌流）。

---

## 3. 电压异常分析 (VOLTAGE_ANOMALY)

### 3.1 核心日志文件
- `ibmc_logs/sensor_info.txt` - 电压传感器数值
- `infocollect_logs/system/dmesg.txt` - 内核感知

### 3.2 关键错误模式
| 错误类型 | 错误关键字 | 含义 |
| :--- | :--- | :--- |
| iBMC SEL | `Voltage .* Out of range` | 电压超出阈值范围 |
| 内核日志 | `Voltage violation` | 电压违规 |

*   **传导链逻辑**：`[电源 Vout / Vin 异常波动] -> [iBMC 检测到并产生电压传感器告警] -> [主板电路检测到不稳定电压信号] -> [触发处理器电压自保护降频机制 (PROCHOT)] -> [CPU 运行主频大幅下降并可能导致软负载卡顿]`。

### 3.4 推荐修复建议

*   **硬件层面 (治本)**：
    1.  **交叉互换定位**：将报错 PSU 与正常槽位对换。若故障随 PSU 移动，则更换 PSU；若故障留在原槽位，则更换主板/电源背板。
    2.  **电压轨监测**：利用 iBMC 历史数据追踪 Vout/Vin 的纹波表现，判定是否为电路老化。
    3.  **固件升级**：升级 iBMC 和 PSU 固件，修复已知的保护逻辑误触发问题。
*   **配置层面 (对冲)**：
    1.  **电源策略校正**：在 BIOS 中确认 Power Policy 设置为“高性能”，排除低功耗策略导致的异常压降。
    2.  **环境散热优化**：防止过热导致的 VRM 元件参数漂移，清理服务器内部积尘及金手指接触面。

---

## 4. 电源冗余失效分析 (REDUNDANCY_FAILURE)

### 4.1 分析焦点
- 检查 PSU 数量是否满足配置（如 1+1 冗余）。
- 检查 `ibmc_logs/psu_status.txt` 中的负载分布，是否存在单路长期处于零输出状态。

---

## 5. 电源过载分析 (OVERLOAD)

### 5.1 分析焦点
- 检查 `ibmc_logs/power_monitor.txt` 中的历史峰值功耗。
- 对比应用层的高负载业务运行时间，是否存在 T0 与业务突发峰值重叠。

---

## 6. 电源过热分析 (TEMPERATURE_ISSUE)

### 6.1 分析流程
1. **时序追踪**：从 T0 向回追溯 30 分钟。
2. **环境对齐**：检查 `Ambient Temperature` (环境温度) 与 `PSU Inlet Temperature` (PSU 进风温度)。
3. **风扇联动**：确认 PSU 内部风扇转速是否已拉满（100% PWM）。

---

## 8. 执行策略 (Policy)

### 8.1 证据驱动
- 严禁仅根据 `system reboot` 就推断 `PSU 损坏`。
- 物理故障必须找到 iBMC 的底层 `Critical` 警告日志。

### 8.2 时空对齐
- 必须确认 OS 日志与 iBMC 日志的时间偏差量，并在传导链描述中注明（如：T0_OS = T0_iBMC - 2min）。
