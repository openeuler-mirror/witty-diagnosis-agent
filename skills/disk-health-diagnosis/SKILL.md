---
name: disk-health-diagnosis
description: >
  服务器磁盘健康全栈诊断与故障预测。当用户上传或提到服务器日志包、询问磁盘健康状态、
  磁盘故障排查、I/O 性能异常、RAID 降级、硬盘预测性维护时，必须使用本技能。
  支持三类日志来源：①iBMC 带外日志（华为/浪潮/H3C）②OS infocollect 包（SMART/iostat/RAID）
  ③/var/log/messages 系统日志。输出综合评分（0~100）与五级风险等级及处置建议。
  即使用户只说"帮我看看磁盘""服务器磁盘有没有问题""分析一下这个日志包"也要触发本技能。
---

# 磁盘健康诊断技能

## 概述

本技能覆盖服务器磁盘全栈诊断，目标是在物理故障前 3~7 天识别预警信号，避免非计划停机。

**三层数据来源（权重）：**
- **iBMC 带外层**（35%）— 硬件真实状态，华为/浪潮/H3C 三厂商
- **OS infocollect 层**（45%）— SMART 指标、I/O 性能、RAID 状态
- **OS messages 层**（20%）— 内核事件、文件系统报错时间线

详细字段阈值、厂商路径对照、诊断脚本见：
- `references/thresholds.md` — SMART 字段完整阈值表、ASC/ASCQ 释义、NVMe/SSD 专项
- `references/ibmc_paths.md` — 三厂商 iBMC 日志路径对照表
- `scripts/disk_score.sh` — 全自动综合评分脚本

---

## 诊断执行流程（SOP）

按以下 5 步顺序执行。**禁止使用一票否决制中断流程，必须完成全部步骤的全面诊断后，再基于所有证据给出综合结论。**

### Step 0：识别日志包类型与厂商

```bash
# 华为 iBMC：典型特征是 dump_info 目录 + LogDump/fdm_output
test -f dump_info/LogDump/fdm_output && echo "→ 华为 iBMC"

# H3C iBMC：典型特征是 dump_info 目录 + LogDump/arm_fdm_log
# 也常伴随 H3C 特有目录/文件：3rdDump、SpLogDump、Register、fdm_pfae_log、PD_SMART_INFO_C*
test -f dump_info/LogDump/arm_fdm_log && echo "→ H3C iBMC"

# 浪潮 Inspur iBMC：典型特征是 onekeylog 扁平化目录 + ErrorAnalyReport.json / RegRawData.json / selelist.csv
test -f onekeylog/log/ErrorAnalyReport.json && echo "→ 浪潮 Inspur iBMC"
test -f onekeylog/log/RegRawData.json && echo "→ 浪潮 Inspur iBMC"
test -f onekeylog/log/selelist.csv && echo "→ 浪潮 Inspur iBMC"

# OS infocollect 包：仅表示 OS 侧日志已就绪，不等价于 iBMC 厂商
test -f infocollect_logs/disk/disk_smart.txt && echo "→ OS infocollect 包就绪"
```

快速判断原则：
- 出现 `dump_info/LogDump/fdm_output`，优先判定为华为 iBMC
- 出现 `dump_info/LogDump/arm_fdm_log`，优先判定为 H3C iBMC
- 出现 `onekeylog/log/ErrorAnalyReport.json`、`RegRawData.json`、`selelist.csv` 这类扁平化日志，优先判定为浪潮 Inspur iBMC
- 若同时命中多个特征，继续核对目录形态：`dump_info` 体系通常为华为/H3C，`onekeylog` 体系通常为浪潮 Inspur

---

### Step 1：iBMC 快速定性（< 5 分钟）

#### 华为 iBMC
```bash
DUMP="./dump_info"
# 1. FDM 故障诊断（触发 → 一票否决高危）
grep -i "Fault" ${DUMP}/LogDump/fdm_output 2>/dev/null

# 2. 当前未清除告警
grep -iE "Critical|Major" ${DUMP}/AppDump/SensorAlarm/current_event.txt 2>/dev/null | head -20

# 3. RAID 状态（Degraded/Offline/Failed → 一票否决）
grep -iE "Degraded|Offline|Failed|Rebuild" \
    ${DUMP}/AppDump/StorageMgnt/RAID_Controller_Info.txt 2>/dev/null

# 4. SEL 存储事件时间线
tar -xf ${DUMP}/AppDump/SensorAlarm/sel.tar -C /tmp/sel/ 2>/dev/null
grep -iE "drive|disk|RAID" /tmp/sel/sel_decoded.txt 2>/dev/null | grep "Asserted" | sort
```

#### 浪潮 Inspur iBMC
```bash
# 1. AI 故障解析报告（Inspur 独有）
grep -iE "fault|error|recommend" onekeylog/log/ErrorAnalyReport.json 2>/dev/null

# 2. 分级日志（按优先级）
cat onekeylog/log/emerg.log onekeylog/log/alert.log 2>/dev/null
grep -iE "disk|storage|RAID" onekeylog/log/crit.log 2>/dev/null

# 3. SEL（CSV 格式）
grep -iE "drive|disk|RAID" onekeylog/log/selelist.csv 2>/dev/null | grep "Assert"
```

#### H3C iBMC
```bash
# 1. FDM 故障诊断
grep -iE "Fault|fault detected" LogDump/arm_fdm_log 2>/dev/null

# 2. FDM 预告警（H3C 独有）
grep -iE "warn|predict" LogDump/fdm_pfae_log 2>/dev/null

# 3. 硬盘 SMART（H3C 在 iBMC 层直接有）
grep -iE "Reallocated|Uncorrectable|Pending|FAILED" LogDump/PD_SMART_INFO_C* 2>/dev/null

# 4. PHY 误码（H3C 独有）
grep -iE "error count|invalid dword" LogDump/phy/* 2>/dev/null
```

---

### Step 2：SMART 指标扫描（< 10 分钟）

```bash
SMART="./infocollect_logs/disk/disk_smart.txt"

# ── 一票否决项 ──────────────────────────────────────
# 整体健康状态
grep "SMART overall-health" $SMART | grep -v "PASSED\|OK"
# → 非 PASSED/OK 时直接高危

# SAS ASC/ASCQ 高危码
grep -iE "ascq.*(30|64|62)" $SMART
# → ascq=30/64(故障率100%) ascq=62(接近100%) 直接高危

# ── 核心错误计数 ────────────────────────────────────
grep -E "read_total_uncorrected_error|\
verify_total_uncorrected_error|\
write_total_uncorrected_error|\
elem_in_grown_defect_list" $SMART
# 阈值见 references/thresholds.md §1.1

# ── SMART ID 关键字段 ────────────────────────────────
grep -E "^\s*(5|197|198|187|7|1)\s" $SMART
# ID 5(Reallocated) ID 197(Pending) ID 198(Uncorrectable)
# 阈值见 references/thresholds.md §1.2

# ── NVMe SSD ────────────────────────────────────────
grep -iE "critical_warning|percentage_used|available_spare|media_errors" $SMART
# critical_warning ≠ 0 → 一票否决; percentage_used > 95 → 高危

# ── SATA SSD 寿命 ───────────────────────────────────
grep -iE "Media_Wearout|Wear_Leveling|SSD_Life|Lifetime_Remaining|231|233|177" $SMART
# value < 5 → 高危; < 10 → 预警

# ── 温度 ────────────────────────────────────────────
grep -iE "Temperature_Celsius|cur_temperature|190|194" $SMART
# 最优 25~28°C; >45°C 预警; >55°C 高危

# ── iBMA 健康评分 ────────────────────────────────────
grep -iE "score|predicted|warning|fail" \
    ./infocollect_logs/disk/hwdiag_hdd.txt 2>/dev/null
```

---

### Step 3：OS I/O 性能核查

```bash
IC="./infocollect_logs"

# iostat — %util 和 await
awk 'NR>3 && /sd/ {
    if ($NF+0 > 90) print "HIGH UTIL:", $0
}' ${IC}/system/iostat.txt 2>/dev/null | head -10

# blktrace — d2c/q2c 延迟（d2c高→硬件慢; q2c高d2c低→调度问题）
grep -iE "d2c|q2c" ${IC}/disk/blktrace_log.txt 2>/dev/null | head -10

# I/O 调度器（SSD 不推荐 cfq）
cat ${IC}/disk/scheduler.txt 2>/dev/null

# RAID OS 侧状态
grep -iE "Degraded|Offline|Failed|Rebuild" ${IC}/raid/sasraidlog.txt 2>/dev/null
```

---

### Step 4：/var/log/messages 系统日志

```bash
MSGS="/var/log/messages"

# 宏观量级
echo "I/O error:    $(grep -ci 'I/O error' $MSGS 2>/dev/null)"
echo "SCSI error:   $(grep -ci 'SCSI error' $MSGS 2>/dev/null)"
echo "XFS/EXT4:     $(grep -ciE 'XFS.*error|EXT4-fs error' $MSGS 2>/dev/null)"

# 存储错误详情
grep -iE "I/O error|blk_update_request|Buffer I/O|EXT4-fs error|\
XFS.*error|xfs_force_shutdown|rejecting I/O|SATA link down|\
SCSI error" $MSGS 2>/dev/null | tail -30

# 受影响设备
grep -iE "I/O error|blk_update_request" $MSGS 2>/dev/null \
    | grep -oP "sd[a-z]+[0-9]?" | sort | uniq -c | sort -rn
```

---

### Step 5：综合评分与出具结论

按以下评分规则计算后，对照评级表输出结论。

#### 评分维度

| 维度 | 权重上限 | 核心触发条件（节选）|
|---|---|---|
| iBMC 硬件层 | 35 分 | FDM Fault +25, Critical告警 +20, RAID Degraded +20 |
| SMART 错误指标 | 35 分 | smart_health≠OK +20, read_uncorrected>1000 +15, NVMe critical_warning≠0 +20 |
| SMART 趋势差分 | 15 分 | diff_elem_in_grown>100 +10, 7天持续正增长 +5 |
| OS I/O 性能 | 10 分 | xfs_force_shutdown +8, I/O error>10次/天 +7, %util>98% +5 |
| 环境与寿命 | 5 分 | 温度>50°C +3, 通电>35000h +2 |

完整评分细则见 `references/thresholds.md` §3。

#### 一票否决规则（直接判高危，忽略总分）

```
1. fdm_output / arm_fdm_log 检出 Fault
2. SMART overall-health ≠ OK/PASSED
3. RAID VD 状态 Degraded / Failed
4. smart_health_ascq ∈ {30, 64}（故障率 100%）
5. read_uncorrected_error > 1000 且 verify_uncorrected_error > 1000（双超）
6. NVMe critical_warning ≠ 0 且 percentage_used > 95
7. Inspur ErrorAnalyReport 检出 fault 且 SEL Assert 同时存在
```

#### 风险评级表

| 综合得分 | 等级 | 处置建议 |
|---|---|---|
| 0~15 | ✅ 正常 | 按周期巡检，无需特殊处理 |
| 16~35 | ⚠️ 低风险 | 加强监控频率（每日），关注趋势 |
| 36~55 | 🟠 中风险 | 7日内评估换盘，安排数据迁移 |
| 56~75 | 🔴 高危 | 立即开维修工单，3日内数据迁移 |
| 76+ | 🚨 极高危 | 立即隔离停止写入，紧急换盘 |

---

## 快速场景诊断路径

| 现象 | 优先查看 | 关键字/阈值 |
|---|---|---|
| 硬盘亮黄灯/掉盘 | `fdm_output` → `RAID_Controller_Info.txt` → `sel` | `Fault`, `Offline`, `Failed` |
| IO wait 持续高 | `iostat.txt` → `blktrace_log.txt` → `dmesg.txt` | `%util>98%`, `await>100ms` |
| 文件读写报错 | `dmesg.txt` → `disk_smart.txt` → `messages` | `buffer I/O error`, `Reallocated>0` |
| SSD 寿命告警 | `disk_smart.txt` → `current_event.txt` | `percentage_used>95`, `life<5` |
| 新盘无法识别 | `scsi_info.txt` → `RAID_Controller_Info.txt` | 枚举 PD，驱动加载 |

---

## 报告输出模板

```
=============================================
  服务器磁盘健康诊断报告
=============================================
诊断时间：YYYY-MM-DD HH:MM
服务器SN：[SN号]  型号：[型号]  iBMC厂商：[华为/浪潮/H3C]

【综合评级】🔴 高危  综合得分：67/100

【分项得分】
  iBMC 硬件层：  20/35  （RAID Rebuild +8, 告警 Major +12）
  SMART 错误：   27/35  （read_uncorrected=1150 +15, ID5=780 +10）
  SMART 趋势：   10/15  （elem_in_grown 14天差分 +120 → +10）
  OS I/O性能：    7/10  （I/O error 频繁 +7）
  环境寿命：      3/5   （温度52°C +3）

【触发项清单】
  [+15] read_total_uncorrected_error=1150 > 1000
  [+12] current_event.txt 含 Major 存储告警
  ……

【问题磁盘定位】
  逻辑设备：/dev/sdb  物理槽位：Slot 3  型号：[型号]  SN：[SN]

【处置建议】
  立即申请维修工单（P1），3日内完成 /dev/sdb 数据迁移，安排换盘
=============================================
```

---

## 注意事项

- **多盘并存**：disk_smart.txt 含多盘时，按设备（`/dev/sdX`）分组独立评分
- **厂商路径差异**：华为用 `fdm_output`，H3C 用 `arm_fdm_log`，浪潮用 `ErrorAnalyReport.json`
- **无历史数据**：缺少多时间点 SMART 时，跳过差分趋势分析，在报告注明
- **SSD 与 HDD 阈值不同**：SSD await >10ms 关注，HDD await >100ms 关注
- **自动评分**：可运行 `scripts/disk_score.sh [DUMP_DIR] [IC_DIR] [MSGS]` 自动完成评分
