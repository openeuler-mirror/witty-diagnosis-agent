# SMART 磁盘健康诊断指南

> 覆盖场景：华为 iBMC / H3C iBMC / OS infocollect 日志包
> 场景2（浪潮 iBMC）无 SMART 日志导出，已跳过。

---

## 附录：SMART 核心指标速查（行业标准）

在阅读各场景表格前，先了解业界公认的关键指标。这些指标分为多个维度，涵盖了介质错误、机械健康、寿命消耗等。

### 1. 核心物理健康状态（快速红绿判断）
| 指标名 | 含义 | 采集方式 |
|---|---|---|
| smart_health | SMART 整体健康状态 | smartctl PASSED/FAILED |
| smart_health_asc | Informational Exceptions 异常码 | SAS/SATA Error ASC |
| smart_health_ascq | 异常码子码 | Error ASCQ |

### 2. 介质错误指标（最核心预测特征）
Backblaze 对近 7 万块磁盘的长期研究表明：**76.7% 的故障盘**在失效前，以下指标中至少有一个发生异常。这些指标被业界视为磁盘故障预测的"黄金五项"：

| 指标名 / ID# | 适用盘型 | 含义 | 故障相关性 |
|:---|:---|:---|:---|
| **smart_5_raw_value (5)** | SATA HDD/SSD | 重映射扇区数（Reallocated Sectors） | 最强。已发生不可逆物理坏道并完成重映射 |
| **smart_197_raw_value (197)** | SATA HDD/SSD | 待映射扇区数（Current Pending Sectors） | 最强。存在读写困难的"疑似坏道"，正在等待重映射 |
| **smart_198_raw_value (198)** | SATA HDD/SSD | 脱机不可校正扇区（Uncorrectable Sectors） | 最强。彻底无法修复的扇区，大概率伴随数据丢失 |
| **Reported_Uncorrectable (187)** | SATA HDD/SSD | 报告给主机的无法纠正错误数 | 较强。反映已经影响到主机的读取错误 |
| **Command_Timeout (188)** | SATA HDD/SSD | 指令超时计数 | 较强。反映接口或介质响应异常 |
| **elem_in_grown_defect_list** | SAS HDD | G-list 缺陷增长数量 | 最强。SAS 盘的坏块表增长 |
| **read_total_uncorrected_error** | SAS HDD | 读不可校正错误总数 | 最强。SAS 盘读坏块 |
| **verify_total_uncorrected_error** | SAS HDD | 校验不可校正错误总数 | 最强。SAS 盘校验坏块 |
| **write_total_uncorrected_error** | SAS HDD | 写不可校正错误总数 | 最强。SAS 盘写坏块 |

### 3. ECC 校正压力指标（早期劣化信号）
| 指标名 | 含义 | 预测价值 |
|---|---|---|
| read_corrected_ecc_delayed | 读路径 ECC 延迟修正次数 | 高则说明错误多但尚可纠正 |
| verify_corrected_ecc_delayed | 校验路径 ECC 延迟修正 | SAS 盘尤为重要 |
| write_corrected_ecc_delayed | 写路径 ECC 延迟修正 | 写路径劣化早期信号 |
| read_corrected_ecc_fast | 读路径 ECC 快速修正 | 基线噪音较大，结合 delayed 看 |

### 4. 机械健康指标（HDD 专属）
| 指标名 | SMART ID | 含义 |
|---|---|---|
| Spin_Up_Time | 3 | 启动时间，偏长说明电机老化 |
| Spin_Retry_Count | 10 | 启动重试次数，非零即异常 |
| Seek_Error_Rate | 7 | 寻道错误率 |
| Seek_Time_Performance | 8 | 寻道性能，下降说明老化 |
| Calibration_Retry_Count | 11 | 校准重试次数 |

### 5. SSD/NVMe 专属指标
| 指标名 | 含义 | 临界参考 |
|---|---|---|
| Percentage_Used | NVMe 寿命消耗百分比 | ≥ 90% 高风险 |
| Media_and_Data_Integrity_Errors | NVMe 介质/数据完整性错误 | > 0 即需关注 |
| Critical_Warning | NVMe 严重警告位图 | 非 0x00 即异常 |
| Available_Spare | NVMe 可用备用块百分比 | ≤ 10% 风险升高 |
| Wear_Leveling_Count | SSD 擦写均衡计数（SATA 177） | 参考厂商 TBW |
| Reallocated_Event_Count | SSD 重分配事件数（SMART 196） | > 0 需关注 |

### 6. 负载与使用强度指标（评估老化背景风险）
检测目的：评估磁盘使用强度和老化背景，用于风险评分加权，而非直接判故障。
| 指标名 | 含义 | 采集方式 |
|---|---|---|
| power_on_hours | 累计上电时间（小时） | SMART ID 9 |
| accumulated_start_stop_cycles | 累计启停次数 | SMART ID 4 / SAS Log |
| accumulated_load_unload_cycles | 累计加载卸载次数（HDD） | SMART ID 193 |
| cycle_count_over_lifetime | 生命周期内循环次数 | SAS Log Page |
| load_unload_count_over_lifetime | 生命周期加载卸载计数 | SAS Log Page |
| %util（IO利用率） | 块设备 IO 利用率 | iostat -xm 1 |
| await（IO等待时间） | 平均 IO 等待时间（ms） | iostat -xm 1 |
| r/s、w/s | 每秒读/写请求数 | iostat -xm 1 |

> **判读原则**：VALUE（归一化健康分）越高越好，通常出厂值为 100/200；RAW_VALUE 是绝对物理量，才是排查时最需要直接看的字段。

### 7. 关键指标临界值参考表
*重要说明：临界值受盘型/厂商/业务负载影响，建议按 厂商 × 型号 × 容量 × 介质类型 分组建立基线，以下为通用参考值。*

**7.1 介质错误指标临界值**
| 指标 | 正常 | 警告 | 危险 | 说明 |
|---|---|---|---|---|
| smart_5_raw_value（重映射） | 0 | 1~4 | ≥ 5 | 任何非零都需关注；增长速度比绝对值更重要 |
| smart_197_raw_value（待映射） | 0 | 1~9 | ≥ 10 | 最敏感早期信号；一旦出现即启动跟踪 |
| smart_198_raw_value（不可校正） | 0 | 1~2 | ≥ 3 | 一旦非零，高风险；结合197同步看 |
| elem_in_grown_defect_list（G-list）| 0~50 | 51~300 | ≥ 300 | SAS盘核心指标；增长速率关键 |
| read_total_uncorrected_error | 0 | 1~99 | ≥ 100 | SAS盘读路径不可恢复错误 |
| verify_total_uncorrected_error | 0 | 1~99 | ≥ 100 | SAS盘校验路径不可恢复错误 |
| write_total_uncorrected_error | 0 | 1~9 | ≥ 10 | 写路径故障容忍度更低 |

**7.2 健康状态临界值**
| 指标 | 正常 | 异常 |
|---|---|---|
| smart_health | PASSED / OK | FAILED 或其他 |
| smart_health_asc | 0x00 / 0x5D | 其他任何值 |
| smart_health_ascq | 0x00 | 非零，尤其 0x30/0x62/0x64 极高危 |
| NVMe Critical_Warning | 0x00 | 任何非零位 |
| NVMe Percentage_Used | < 80% | ≥ 90% 高危 |
| NVMe Available_Spare | > 20% | ≤ 10% 危险 |
| NVMe Media_and_Data_Integrity_Errors | 0 | > 0 即异常 |

**7.3 链路与环境指标临界值**
| 指标 | 正常 | 警告 | 危险 |
|---|---|---|---|
| smart_199_raw_value（CRC错误） | 0 | 1~50 | ≥ 50 |
| Command_Timeout（SMART 188） | 0 | 1~9 | ≥ 10 |
| SATA_Downshift_Error_Count（SMART 183）| 0 | 1~4 | ≥ 5 |
| cur_temperature（温度℃） | 25~45 | 46~55 | ≥ 55 或 ≤ 0 |
| diff_cur_temperature（14天温度变化）| < 5 | 5~10 | > 10 |

**7.4 寿命与负载临界值**
| 指标 | 低风险 | 中风险 | 高风险 |
|---|---|---|---|
| power_on_hours（上电时间） | < 26,280h（3年） | 26,280~43,800h | > 43,800h（5年） |
| %util（IO利用率） | < 70% | 70~90% | > 90% |

---

## 场景一：华为 iBMC

### 场景一：SMART 日志总览

| 维度 | 全局汇总日志 | 单盘历史日志 |
|:---|:---|:---|
| **文件路径** | `<序列号>/dump_info/LogDump/PD_SMART_INFO_C0`（C0 对应阵列卡编号，多控时可有 C1、C2 等） | `<序列号>/dump_info/LogDump/storage/drivelog/Disk<N>/SMARTAttribute`（含历史轮转文件 `.1`、`.2`、`.5` 等） |
| **文件作用** | 一次性汇总该阵列卡下**所有物理硬盘**的当前 SMART 状态。排查问题时**首选此文件**，快速定位异常盘槽位 | 记录**单块磁盘**在各采集时间点的详细 SMART 属性。轮转文件可还原坏道随时间增长的历史趋势，适合追溯问题根因 |
| **数据格式** | 头部基础信息段 + SMART 属性表格段（两段格式与单盘日志完全一致，多盘按 Slot 顺序拼接） | 头部基础信息段 + SMART 属性表格段 |

### 场景一：数据格式详解

**头部基础信息段示例：**
```
Device Name    : Disk42
Enclosure Id   : 64
Slot Number    : 38
Manufacturer   : SAMSUNG
Serial Number  : S45RNA0MC30570
Model          : SAMSUNG MZ7LH240HAHQ-00005
Interface Type : SATA
Timestamp      : 2024-01-08 04:33:29
```

**SMART 属性表格段示例：**
```
ID# ATTRIBUTE_NAME             FLAG   VALUE WORST THRESHOLD TYPE     UPDATED WHEN_FAILED RAW_VALUE
  5 Reallocated_Sectors_Count  0x0033  100   100    010     Pre-fail Always      -          0
  9 Power_On_Hours             0x0032  093   093    000     Old_age  Always      -       34026
194 Temperature_Celsius        0x0022  072   056    000     Old_age  Always      -          28
197 Current_Pending_Sector     0x0032  100   100    000     Old_age  Always      -          0
```

### 场景一：核心数据指标与健康判定标准

| ID# | 属性名称 | 字段说明 | 🟢 健康 | 🟡 亚健康（需关注） | 🔴 故障（需立即处理） |
|:---:|:---|:---|:---|:---|:---|
| **5** | Reallocated_Sectors_Count | 已被重映射的物理坏块数（RAW = 实际坏块个数） | RAW = 0 | RAW 1~10，且近期无增长 | RAW > 0 且持续增长；或 RAW > 50 |
| **9** | Power_On_Hours | 累计通电时间（RAW = 实际小时数） | < 30,000 h（约 3.4 年） | 30,000–50,000 h，需加强监控 | > 50,000 h（约 5.7 年），进入高故障期 |
| **177** | Wear_Leveling_Count | SSD 专属：损耗均衡计数，反映闪存写入寿命消耗（VALUE = 剩余寿命百分比类评分） | VALUE 远高于 THRESHOLD（剩余寿命 > 20%） | VALUE 逼近 THRESHOLD（剩余寿命 5%–20%） | VALUE ≤ THRESHOLD，剩余寿命耗尽 |
| **187** | Reported_Uncorrectable_Errors | 上报给主机的无法纠正错误数 | RAW = 0 | RAW 1–5 | RAW > 5 或快速增长 |
| **194** | Temperature_Celsius | 磁盘温度（RAW = 当前温度℃，括号内为历史最小/最大值） | HDD ≤ 45℃；SSD ≤ 55℃ | HDD 45–55℃；SSD 55–65℃ | HDD > 60℃；SSD > 70℃（加速老化，需检查散热） |
| **197** | Current_Pending_Sector | 等待重映射的疑似坏道数（RAW = 待处理扇区个数） | RAW = 0 | RAW 1–10，且稳定不增 | RAW > 0 且持续增长；或单次出现数十以上 |
| **198** | Offline_Uncorrectable | 离线扫描中彻底不可修复的扇区数 | RAW = 0 | — | RAW > 0 即为致命级，直接判定为故障盘 |
| **WHEN_FAILED 字段** | 失效状态标记 | 该列为 `-` 正常；出现异常含义如右 | 所有行均为 `-` | 出现 `In_the_past`（曾跌破阈值） | 出现 `FAILING_NOW`（当前 Pre-fail 属性跌破阈值，硬盘即将失效） |

> **综合判定规则**
> - **ID 198 RAW > 0** → 直接判定故障盘，立即换盘
> - **ID 5 或 ID 197 RAW > 0 且持续增长** → 判定故障盘，尽快换盘并迁移数据
> - **WHEN_FAILED = FAILING_NOW** → 直接判定故障盘
> - **ID 5 或 ID 197 RAW 出现非零但静止不增，且其余指标正常** → 亚健康，加强每日巡检频率，提前准备备件
> - **多个指标同时异常（Backblaze 研究：2+ 项触发时故障概率显著提升）** → 无论单项是否超阈，均应升级为故障处理

---

## 场景二：浪潮 iBMC

> ⚠️ **该场景无 SMART 日志导出，跳过。**
> 浪潮（Inspur）iBMC 在当前收集的日志包中未包含 SMART 相关文件，如需磁盘健康数据，建议通过以下方式补充：
> - 登录 iBMC Web 界面 → 存储 → 物理磁盘 → 查看 SMART 信息
> - 在操作系统层面执行 `smartctl -a /dev/sdX` 获取实时数据

---

## 场景三：H3C iBMC

H3C iBMC 日志的文件结构与数据格式与场景一（华为 iBMC）高度一致，均遵循相同的 SMART 规范。以下表格重点突出 H3C 场景的文件路径特征与诊断重点。

### 场景三：SMART 日志总览

| 维度 | 全局汇总日志 | 单盘历史日志 |
|:---|:---|:---|
| **文件路径** | `dump_info/LogDump/PD_SMART_INFO_C*`（`C*` 对应控制器编号） | `dump_info/LogDump/storage/drivelog/Disk<N>/SMARTAttribute`（含 `.1`、`.2` 等历史轮转文件） |
| **文件作用** | 汇总阵列卡下所有物理盘的当前 SMART 状态，**排查硬盘问题首选文件** | 单块磁盘的详细历史 SMART 快照，可回溯坏道随时间增长的趋势 |
| **数据格式** | 与场景一完全相同：头部基础信息段（Slot Number、Serial Number、Timestamp 等）+ SMART 属性表格段（ID# / VALUE / WORST / THRESHOLD / WHEN_FAILED / RAW_VALUE） | 同上 |

### 场景三：核心数据指标与健康判定标准

| ID# | 属性名称 | 关注重点 | 🟢 健康 | 🟡 亚健康 | 🔴 故障 |
|:---:|:---|:---|:---|:---|:---|
| **5** | Reallocated_Sector_Ct | 最关键坏块指标，优先查此项 | RAW = 0 | RAW 1–10，稳定 | RAW > 0 且增长，或 > 50 |
| **177** | Wear_Leveling_Count | SSD 寿命剩余（VALUE 反映剩余比例） | VALUE >> THRESHOLD | VALUE 与 THRESHOLD 差距 < 20 | VALUE ≤ THRESHOLD |
| **197** | Current_Pending_Sector | 疑似坏道等待处理数 | RAW = 0 | RAW 1–10，稳定 | RAW 持续增长或骤增至数十以上 |
| **198** | Offline_Uncorrectable | 彻底无法修复的坏道数 | RAW = 0 | — | RAW > 0，直接判故障 |
| **3** | Spin_Up_Time | HDD 电机启动时间 | VALUE 正常 | — | VALUE ≤ THRESHOLD，电机老化 |
| **4** | Start_Stop_Count | 累计启停次数 | RAW < 10,000 | RAW > 10,000，机械磨损加剧 | RAW 极高，伴随其他故障 |
| **10** | Spin_Retry_Count | 启动重试次数 | RAW = 0 | RAW > 0，关注机械故障风险 | VALUE ≤ THRESHOLD |
| **187** | Reported_Uncorrectable | 报告给主机的无法纠正错误数 | RAW = 0 | RAW 1–5 | RAW > 5 或快速增长 |
| **188** | Command_Timeout | 指令超时计数 | RAW = 0 | RAW 1–100 | RAW > 100（接口/介质异常） |
| **193** | Load_Cycle_Count | HDD 磁头加载/卸载次数 | RAW < 300,000 | RAW > 300,000，机械疲劳 | — |
| **VALUE vs THRESHOLD** | 归一化健康评分与厂商阈值 | Pre-fail 类属性一旦 VALUE ≤ THRESHOLD，代表硬盘即将物理失效 | VALUE > THRESHOLD（所有 Pre-fail 属性） | VALUE 与 THRESHOLD 差距 < 10 | VALUE ≤ THRESHOLD（WHEN_FAILED 列出现 FAILING_NOW） |

> **H3C 场景特别说明**
> - 可通过对比 `SMARTAttribute`（当前）与 `SMARTAttribute.1`、`.2`（历史）中 ID 5 / ID 197 的 RAW_VALUE 变化趋势，判断坏道是否在扩散。
> - 若 **Timestamp 时间戳**之间 RAW_VALUE 有增长（哪怕只增长 1），即视为"活跃坏道"，需要立即提级处理。

---

## 场景四：OS Infocollect 日志包

与 iBMC 日志不同，infocollect 是在操作系统层面采集的，覆盖操作系统可见的所有磁盘（包括非 RAID 直通盘），并额外包含内核日志中的 SMART 守护进程告警。

### 场景四：SMART 日志总览

| 日志文件路径 | 文件作用 | 数据来源层次 |
|:---|:---|:---|
| `disk/disk_smart.txt` | 核心健康报告。包含所有磁盘的 SMART 综合状态（`Health: PASSED/FAILED`）及完整属性表格，由 `smartctl` 工具采集 | OS 用户态，通过 ATA/SCSI 命令直接与磁盘固件通信 |
| `disk/disk_other_info.txt` | 补充报告。包含 SCSI 协议层扩展信息，如 `Informational exceptions`（SCSI SMART 异常扩展）和温度基准值对比 | OS 用户态，SCSI Log Pages |
| `system/var/log/messages-*` | 系统内核日志。包含 `smartd` 守护进程的实时告警，记录操作系统层面感知到的磁盘 I/O 错误与 SMART 警告 | OS 内核态，驱动层上报 |

### 场景四：数据格式说明

**`disk/disk_smart.txt` 关键片段示例：**
```
=== START OF READ SMART DATA SECTION ===
SMART overall-health self-assessment test result: PASSED

ID# ATTRIBUTE_NAME          FLAG  VALUE WORST THRESH TYPE     UPDATED WHEN_FAILED RAW_VALUE
  5 Reallocated_Sector_Ct   0x0033  200   200   140  Pre-fail Always     -              0
  9 Power_On_Hours           0x0032  087   087   000  Old_age  Always     -           9532
187 Reported_Uncorrectable   0x0032  100   100   000  Old_age  Always     -              0
197 Current_Pending_Sector   0x0032  100   100   000  Old_age  Always     -              0
198 Offline_Uncorrectable    0x0030  100   100   000  Old_age  Offline    -              0
```

**`system/var/log/messages` 告警片段示例：**
```
smartd[1234]: Device: /dev/sda, 1 Currently unreadable (pending) sectors
smartd[1234]: Device: /dev/sdb, SMART Failure: 5 Reallocated_Sector_Ct
kernel: blk_update_request: I/O error, dev sda, sector 1234567
```

### 场景四：核心数据指标与健康判定标准

| 日志来源 | 指标 / 字段 | 含义说明 | 🟢 健康 | 🟡 亚健康（需关注） | 🔴 故障（需立即处理） |
|:---|:---:|:---|:---|:---|:---|
| `disk_smart.txt` | **Health（综合自检）** | 磁盘固件自检综合结论 | `PASSED` | `PASSED`（但细分指标有异常，不可只看此项） | `FAILED`（固件自判即将彻底失效） |
| `disk_smart.txt` | **ID 5**：Reallocated_Sector_Ct | 已重映射的物理坏块数 | RAW = 0 | RAW 1–10，稳定不增 | RAW 持续增长，或任意非零值伴随其他异常 |
| `disk_smart.txt` | **ID 9**：Power_On_Hours | 累计通电时间 | < 30,000 h | 30,000–50,000 h | > 50,000 h（高故障概率期） |
| `disk_smart.txt` | **ID 187**：Reported_Uncorrectable_Errors | 上报给主机的无法纠正错误数 | RAW = 0 | RAW 1–5 | RAW > 5 或快速增长 |
| `disk_smart.txt` | **ID 188**：Command_Timeout | 指令超时计数 | RAW = 0 | RAW 低位数（< 100） | RAW 快速增长（接口异常或介质响应迟缓） |
| `disk_smart.txt` | **ID 197**：Current_Pending_Sector | 等待重映射的疑似坏道数 | RAW = 0 | RAW 1–10，稳定 | RAW > 0 且持续增长，或骤增至数十以上 |
| `disk_smart.txt` | **ID 198**：Offline_Uncorrectable | 离线不可修复扇区数 | RAW = 0 | — | RAW > 0，直接判故障 |
| `disk_other_info.txt` | **Informational exceptions** | SCSI 层 SMART 异常扩展报告 | 无异常记录 | 出现低级别异常代码 | 出现明确的故障异常代码 |
| `disk_other_info.txt` | **Temperature** | 磁盘温度（与 SCSI 基准参考值对比） | Current < 45℃，低于 Reference 值 | 45–60℃ | > 65℃，或超过 Reference 值（如 `Reference 70C` 时 Current > 65℃） |
| `var/log/messages-*` | **smartd 告警** | OS 内核层感知到的 SMART 警告与 I/O 错误 | 无相关告警 | 出现 `unreadable sectors` 或间歇性 I/O error | 出现 `SMART Failure`、大量持续 `I/O error`、`blk_update_request: I/O error` |

> **综合判定规则（infocollect 场景）**
> 1. **不能只看 `Health: PASSED`**：部分磁盘固件在坏道初期仍报 PASSED，需同时核查 ID 5 / 197 / 198。
> 2. **三层交叉验证**：`disk_smart.txt`（固件层）+ `disk_other_info.txt`（SCSI 层）+ `messages`（内核层）三层均出现异常时，故障确定性最高。
> 3. **ID 197 或 ID 198 任一 RAW > 0** → 直接判定高危盘，无论 Health 是否 PASSED，均应立即启动数据备份和换盘流程。
> 4. **messages 中出现 `Currently unreadable (pending) sectors`** → 与 ID 197 直接对应，OS 已感知到介质异常，业务 I/O 存在出错风险。

---

## 快速判定决策树

```
磁盘 SMART 告警 → 开始排查
│
├─ ID 198 (Offline_Uncorrectable) RAW > 0?
│   └─ 是 → 🔴 致命故障，立即换盘（数据可能已丢失）
│
├─ ID 197 (Current_Pending_Sector) RAW > 0 且持续增长?
│   └─ 是 → 🔴 故障，紧急换盘并备份数据
│
├─ ID 5 (Reallocated_Sector_Ct) RAW > 0 且持续增长?
│   └─ 是 → 🔴 故障，尽快换盘
│
├─ WHEN_FAILED = FAILING_NOW?
│   └─ 是 → 🔴 故障，Pre-fail 属性跌破厂商阈值
│
├─ ID 5 / ID 197 RAW > 0 但静止不增，其余指标正常?
│   └─ 是 → 🟡 亚健康，每日巡检，提前准备备件
│
├─ Power_On_Hours > 50,000 h，其余指标正常?
│   └─ 是 → 🟡 亚健康，高龄盘，纳入近期更换计划
│
└─ 所有关键指标 RAW = 0，VALUE >> THRESHOLD → 🟢 健康
```

---

*参考来源：Backblaze Drive Stats 研究（2016–2024）、SMART 行业标准（ATA/ATAPI-8）、smartmontools 文档*
