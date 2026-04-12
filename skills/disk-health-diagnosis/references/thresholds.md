# 磁盘诊断：字段阈值与评分细则

## §1. SMART 字段完整阈值

### §1.1 SAS/SATA HDD 不可纠正错误类（最高权重）

| 字段名 | 正常 | 预警 | 高危 |
|---|---|---|---|
| `read_total_uncorrected_error` | 0 | >500 且14天差分>50 | >1000 |
| `verify_total_uncorrected_error` | 0 | >500 且差分>50 | >1000 |
| `write_total_uncorrected_error` | 0 | ≥20 且差分>5 | >50 |
| `elem_in_grown_defect_list` | 0 | ≥200 且差分>50 | >1000 |
| `verify_corrected_ecc_delayed` | 0 | >5000 | >10000 |

> **双超一票否决**：`read_total_uncorrected_error > 1000` 且 `verify_total_uncorrected_error > 1000` → 直接高危

### §1.2 SMART ID 关键字段（HDD 机械盘）

| ID | 字段名 | 预警条件 | 高危条件 |
|---|---|---|---|
| 001 | Raw_Read_Error_Rate | worst 趋近 thresh | worst ≤ thresh × 1.05 |
| 003 | Spin_Up_Time | value 波动 | value ≤ 0.3×(100−thresh)+thresh |
| 005 | Reallocated_Sector_Ct | raw≥500 且差分>50 | raw≥1000 |
| 007 | Seek_Error_Rate | worst 持续下降 | worst ≤ thresh × 1.05 |
| 187 | Reported_Uncorrect | value<80 且差分<−10 | value<40 |
| 197 | Current_Pending_Sector | raw≥300 且差分>50 | raw≥1000 |
| 198 | Offline_Uncorrectable | raw≥300 且差分>50 | raw≥1000 |
| 199 | UDMA_CRC_Error_Count | raw>0 短期增长 | raw>100 |

### §1.3 ASC/ASCQ 健康码（SAS 专用）

| ASC | ASCQ | 名称 | 故障率 | 处置 |
|---|---|---|---|---|
| 5D | 00 | Failure Prediction Threshold Exceeded | ~65% | 🟠 预警 |
| 5D | 10 | Spindle Motor Impending Failure | 高 | 🔴 高危 |
| 5D | 30 | Impending Failure General Hard Drive | 100% | 🚨 极高危 |
| 5D | 62 | Predicted Logical Unit Failure | ~100% | 🚨 极高危 |
| 5D | 64 | Failure Prediction Exceeded | 100% | 🚨 极高危 |
| 0B | 01 | Warning - Temperature Exceeded | — | ⚠️ 温度 |

> `ascq=30` 或 `ascq=64` → 一票否决高危；`ascq=62` → 一票否决高危

### §1.4 NVMe SSD 字段阈值

| 字段名 | 预警 | 高危 | 极高危 |
|---|---|---|---|
| `critical_warning` | — | 任何非0值 | bit3=1（介质只读）|
| `percentage_used` | 80~94% | 95~99% | 100% |
| `available_spare` | 10~30% | <10% | ≤ 阈值 |
| `media_errors` | >0 持续增长 | 骤增 | — |
| 温度 | 65~75°C | >75°C | >85°C |

**critical_warning 比特位：**
```
bit0: Available spare below threshold
bit1: Temperature above threshold
bit2: NVM reliability degraded（媒体错误）
bit3: Media in read-only mode       ← 极高危
bit4: Volatile memory backup failed
```

### §1.5 SATA SSD 品牌寿命字段对照

| 品牌 | 字段 | SMART ID | 高危阈值 |
|---|---|---|---|
| Intel | Media_Wearout_Indicator | 233 | value < 5 |
| Samsung | SSD_Life_Left / Wear_Leveling_Count | 231/177 | value < 5 |
| WD/SanDisk | Lifetime_Remaining | 233 | value < 5 |
| Crucial/Micron | Percent_Lifetime_Remain | 202 | value < 5 |

### §1.6 温度阈值

| 盘类型 | 最优区间 | 预警 | 高危 |
|---|---|---|---|
| SAS/SATA HDD | 25~28°C | <15°C 或 >45°C | >55°C |
| SATA SSD | 0~40°C | >55°C | >65°C |
| NVMe SSD | 0~55°C | >65°C | >75°C |

---

## §2. OS 层阈值

### §2.1 iostat 字段

| 字段 | SSD 阈值 | HDD 阈值 |
|---|---|---|
| `%util` | >90% 预警 | >90% 预警 |
| `await` | >10ms 关注; >50ms 高危 | >50ms 关注; >500ms 高危 |
| `svctm` | 正常<1ms | 正常<10ms |

### §2.2 blktrace 延迟阶段

```
Q→G→I→D→C
         └ d2c = D→C 硬件处理延迟
└──────── q2c = Q→C 总延迟

d2c 高 + q2c 高  → 硬盘硬件响应慢
d2c 低 + q2c 高  → 系统调度层积压（软件/配置问题）

HDD d2c 正常: <20ms; 异常: >100ms
SSD d2c 正常: <1ms;  异常: >10ms
```

### §2.3 /var/log/messages 存储关键字严重程度

| 关键字 | 严重程度 |
|---|---|
| `xfs_force_shutdown` / `rejecting I/O to dead queue` | 🚨 极高危 |
| `Buffer I/O error on dev` / `EXT4-fs error` / `XFS.*error` | 🔴 高危 |
| `SCSI error` / `I/O error, dev sd` / `blk_update_request: I/O error` | 🔴 高危 |
| `ata.*: SATA link down` / `RAID.*fail` | 🔴 高危 |
| `end_request: I/O error` | 🟠 中危 |

---

## §3. 综合评分细则

### §3.1 iBMC 硬件层（上限 35 分）

| 条件 | 加分 |
|---|---|
| `fdm_output`/`arm_fdm_log` 检出 `Fault` | +25 |
| `ErrorAnalyReport.json` 检出 `fault` | +25 |
| `current_event.txt` 含存储 `Critical` | +20 |
| RAID VD `Degraded`/`Failed` | +20 |
| RAID PD `Offline`/`Failed` | +20 |
| `current_event.txt` 含存储 `Major` | +12 |
| H3C `fdm_pfae_log` 含预告警 | +10 |
| SEL 含存储 `Asserted` 且未 `Deasserted` | +10 |
| RAID PD `Rebuild` | +8 |
| `StorageMgnt_dfl.log` 含 `comm lost` | +5 |

### §3.2 SMART 错误指标（上限 35 分）

| 条件 | 加分 |
|---|---|
| `smart_health ≠ OK` | +20 |
| NVMe `critical_warning ≠ 0` | +20 |
| `smart_health_ascq` ∈ {30, 64} | +20 |
| `smart_health_ascq` = 62 | +18 |
| NVMe `percentage_used > 95%` | +18 |
| SSD 寿命字段 < 5 | +18 |
| `smart_health_asc ≠ 0` | +12 |
| `read_total_uncorrected_error > 1000` | +15 |
| `verify_total_uncorrected_error > 1000` | +15 |
| `write_total_uncorrected_error > 50` | +15 |
| `elem_in_grown_defect_list > 1000` | +12 |
| ID 197 ≥ 1000 或 ID 198 ≥ 1000 | +12 |
| ID 5 ≥ 1000 | +10 |
| `verify_corrected_ecc_delayed > 10000` | +6 |

### §3.3 SMART 趋势差分（上限 15 分）

| 条件 | 加分 |
|---|---|
| `diff_elem_in_grown_defect_list > 100` | +10 |
| `diff_elem_in_grown_defect_list > 50` | +6 |
| `diff_read_total_uncorrected_error > 50` | +5 |
| `diff_verify_total_uncorrected_error > 50` | +5 |
| `diff_smart_5_raw_value > 50` 且绝对值≥500 | +5 |
| 各差分指标持续 7 天正增长 | +5 |
| `diff_cur_temperature` 单日 >15°C | +3 |

### §3.4 OS I/O 性能（上限 10 分）

| 条件 | 加分 |
|---|---|
| `xfs_force_shutdown` / `rejecting I/O` 出现 | +8 |
| messages I/O error > 10次/天 | +7 |
| EXT4/XFS 文件系统报错 | +6 |
| dmesg I/O error（<10次）| +4 |
| `iostat %util` 持续 >98% | +5 |
| `iostat await` 超阈（HDD>500ms/SSD>50ms）| +4 |
| `blktrace d2c` 持续异常高 | +4 |

### §3.5 环境与寿命（上限 5 分）

| 条件 | 加分 |
|---|---|
| 温度 >50°C | +3 |
| 温度 <15°C | +2 |
| 通电时间 >35000h | +2 |
| 槽位 ∈ {20, 25, 26}（高故障率槽位）| +1 |
| 温度在 25~28°C 最优区间 | −1 |
| load_unload_cycles >2000 且错误全为 0 | −1 |
