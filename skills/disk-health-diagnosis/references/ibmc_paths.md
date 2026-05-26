# 三厂商 iBMC 日志路径对照表

## 华为 iBMC（dump_info/ 解压后）

| 优先级 | 路径 | 用途 |
|---|---|---|
| ⭐⭐⭐ | `LogDump/fdm_output` | FDM 故障诊断，最权威 |
| ⭐⭐⭐ | `AppDump/StorageMgnt/RAID_Controller_Info.txt` | RAID VD/PD 状态 |
| ⭐⭐⭐ | `AppDump/SensorAlarm/current_event.txt` | 当前未清除告警 |
| ⭐⭐⭐ | `AppDump/SensorAlarm/sel.db` / `sel.tar` | 硬件事件时间线 |
| ⭐⭐ | `AppDump/SensorAlarm/sensor_info.txt` | 硬盘温度传感器 |
| ⭐⭐ | `AppDump/StorageMgnt/StorageMgnt_dfl.log` | 存储通信异常 |
| ⭐⭐ | `AppDump/Cooling/fan_info.txt` | 风扇转速（影响散热）|
| ⭐ | `LogDump/maintenance_log` | 人为操作审计（排除误判）|

## 浪潮 Inspur iBMC（onekeylog/ 解压后）

| 优先级 | 路径 | 用途 |
|---|---|---|
| ⭐⭐⭐ | `log/ErrorAnalyReport.json` | AI 故障解析报告（Inspur 独有）|
| ⭐⭐⭐ | `log/selelist.csv` | SEL 事件（CSV 格式）|
| ⭐⭐⭐ | `log/emerg.log` / `alert.log` / `crit.log` | 分级系统日志（按优先级查）|
| ⭐⭐⭐ | `log/RegRawData.json` | MCA 硬件错误寄存器（Inspur 独有）|
| ⭐⭐ | `runningdata/rundatainfo.log` | 实时温度/电压/转速 |
| ⭐⭐ | `runningdata/faninfo.log` | 风扇状态 |
| ⭐⭐ | `log/psuFaultHistory.log` | 电源黑匣子 |
| ⭐ | `log/IERR_Capture.jpeg` | 宕机截图 |

**浪潮 SEL 格式（CSV）：**
```
EventID,EventTime,EventType,SensorName,Status,Description
1234,2024-01-15 10:23:45,Critical,Drive 0,Assert,Drive Failure
```
筛选命令：`grep -iE "drive|disk|storage" log/selelist.csv | grep "Assert"`

## H3C iBMC（解压后根目录）

| 优先级 | 路径 | 用途 |
|---|---|---|
| ⭐⭐⭐ | `LogDump/arm_fdm_log` | FDM 故障诊断 |
| ⭐⭐⭐ | `LogDump/fdm_pfae_log` | FDM 预告警（H3C 独有）|
| ⭐⭐⭐ | `LogDump/PD_SMART_INFO_C*` | 硬盘 SMART（iBMC 层，H3C 独有）|
| ⭐⭐⭐ | `AppDump/RAID_Controller_Info.txt` | RAID 状态 |
| ⭐⭐⭐ | `AppDump/current_event.txt` | 当前未清除告警 |
| ⭐⭐ | `LogDump/phy/` | PHY 误码日志（H3C 独有）|
| ⭐⭐ | `LogDump/LSI_RAID_Controller_Log` | LSI RAID 原始日志（H3C 独有）|
| ⭐⭐ | `LogDump/drivelog/` | SAS/SATA 硬盘日志（H3C 独有）|
| ⭐⭐ | `RTOSDump/kbox_info` | 内核黑匣子（H3C 独有）|
| ⭐ | `AppDump/fan_info.txt` | 风扇状态 |

## OS infocollect 包（infocollect_logs/ 解压后）

| 优先级 | 路径 | 用途 |
|---|---|---|
| ⭐⭐⭐ | `disk/disk_smart.txt` | SMART 完整属性（核心）|
| ⭐⭐⭐ | `raid/sasraidlog.txt` | RAID VD/PD 状态（OS 视角）|
| ⭐⭐⭐ | `disk/hwdiag_hdd.txt` | iBMA 健康评分报告 |
| ⭐⭐⭐ | `system/iostat.txt` | I/O 性能指标 |
| ⭐⭐ | `disk/blktrace_log.txt` | 块设备 I/O 延迟（d2c/q2c）|
| ⭐⭐ | `raid/diskmap.txt` | 逻辑盘 → 物理槽位映射 |
| ⭐⭐ | `system/dmesg.txt` | 内核存储报错 |
| ⭐⭐ | `disk/scheduler.txt` | I/O 调度器类型 |
| ⭐ | `scsi/scsi_info.txt` | SCSI 设备识别状态 |
| ⭐ | `disk/phy_info.txt` | 物理路径与槽位映射 |

## 厂商差异速查

| 功能 | 华为 | 浪潮 | H3C |
|---|---|---|---|
| 故障诊断报告 | `fdm_output` | `ErrorAnalyReport.json` ★ | `arm_fdm_log` |
| 预告警 | 无 | 无 | `fdm_pfae_log` ★ |
| SEL 格式 | 数据库/解码文本 | CSV ★ | 数据库/解码文本 |
| iBMC 层 SMART | 无 | 无 | `PD_SMART_INFO_C*` ★ |
| PHY 误码 | 无 | 无 | `LogDump/phy/` ★ |
| MCA 寄存器 | 无 | `RegRawData.json` ★ | 无 |
| LSI RAID 原始日志 | 无 | 无 | `LSI_RAID_Controller_Log` ★ |

★ = 该厂商独有，分析时需额外关注
