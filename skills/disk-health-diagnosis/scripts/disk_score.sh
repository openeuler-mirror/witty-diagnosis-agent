#!/bin/bash
# disk_score.sh — 磁盘健康综合评分脚本 v2
# 用法: ./disk_score.sh [DUMP_DIR] [IC_DIR] [MESSAGES_FILE] [SMART_PREV]
#
# DUMP_DIR      iBMC dump 包解压后根目录（含 LogDump/ AppDump/）
# IC_DIR        infocollect 包解压后根目录（含 disk/ raid/ system/）
# MESSAGES_FILE /var/log/messages 路径
# SMART_PREV    可选：14天前的 disk_smart.txt，用于差分趋势计算

DUMP_DIR="${1:-./dump_info}"
IC_DIR="${2:-./infocollect_logs}"
MSGS="${3:-/var/log/messages}"
SMART_PREV="${4:-}"

SCORE=0
declare -a ALERTS
CRITICAL=false

add_score() { SCORE=$((SCORE + $1)); ALERTS+=("[+${1}] ${2}"); }
sub_score()  { SCORE=$((SCORE - $1)); ALERTS+=("[-${1}] ${2}"); }
veto()       { CRITICAL=true; ALERTS+=("[❗一票否决] ${1}"); }

smart_val() {
    local file=$1 pattern=$2
    grep -iE "$pattern" "$file" 2>/dev/null | awk '{print $NF}' | head -1
}
smart_id_raw() {
    local file=$1 id=$2
    awk -v id="$id" '$1==id {print $10; exit}' "$file" 2>/dev/null
}

echo "========================================"
echo "  磁盘健康综合评分 disk_score.sh v2"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "========================================"

# ═══════════════ Step 1: iBMC 硬件层 ═══════════════
echo "[1/5] iBMC 硬件层..."

# 华为/H3C FDM 故障（一票否决）
for f in "${DUMP_DIR}/LogDump/fdm_output" "${DUMP_DIR}/LogDump/arm_fdm_log" \
          "./LogDump/fdm_output" "./LogDump/arm_fdm_log"; do
    [[ -f "$f" ]] && grep -qi "Fault" "$f" 2>/dev/null && veto "FDM Fault: $f"
done

# H3C FDM 预告警（独有，非一票否决）
for f in "${DUMP_DIR}/LogDump/fdm_pfae_log" "./LogDump/fdm_pfae_log"; do
    if [[ -f "$f" ]]; then
        grep -qiE "warn|predict|impending" "$f" 2>/dev/null && \
            add_score 10 "H3C fdm_pfae_log 预告警: $(basename $f)"
    fi
done

# 浪潮 ErrorAnalyReport（一票否决）
for f in "onekeylog/log/ErrorAnalyReport.json" \
          "${DUMP_DIR}/../onekeylog/log/ErrorAnalyReport.json"; do
    [[ -f "$f" ]] && grep -qi "fault" "$f" 2>/dev/null && \
        veto "Inspur ErrorAnalyReport 检出 fault"
done

# 当前告警
for f in "${DUMP_DIR}/AppDump/SensorAlarm/current_event.txt" \
          "${DUMP_DIR}/AppDump/current_event.txt" "./AppDump/current_event.txt"; do
    if [[ -f "$f" ]]; then
        grep -qi "Critical" "$f" 2>/dev/null && add_score 20 "当前 Critical 告警"
        grep -qi "Major"    "$f" 2>/dev/null && add_score 12 "当前 Major 告警"
        break
    fi
done

# RAID 状态
for f in "${DUMP_DIR}/AppDump/StorageMgnt/RAID_Controller_Info.txt" \
          "${DUMP_DIR}/AppDump/RAID_Controller_Info.txt" \
          "./AppDump/RAID_Controller_Info.txt" \
          "${IC_DIR}/raid/sasraidlog.txt"; do
    if [[ -f "$f" ]]; then
        grep -qiE "VD.*Degraded|State.*Degraded" "$f" 2>/dev/null && veto "RAID VD Degraded"
        grep -qiE "VD.*Failed|State.*Failed"     "$f" 2>/dev/null && veto "RAID VD Failed"
        grep -qiE "PD.*Offline|PD.*Failed"       "$f" 2>/dev/null && veto "RAID PD Offline/Failed"
        grep -qi  "Rebuild"                       "$f" 2>/dev/null && add_score 8 "RAID Rebuild 中"
        break
    fi
done

# 存储通信
for f in "${DUMP_DIR}/AppDump/StorageMgnt/StorageMgnt_dfl.log" \
          "./AppDump/StorageMgnt/StorageMgnt_dfl.log"; do
    [[ -f "$f" ]] && grep -qi "comm lost" "$f" 2>/dev/null && add_score 5 "存储通信 comm lost"
done

# ═══════════════ Step 2: SMART 指标 ═══════════════
echo "[2/5] SMART 指标..."
SMART="${IC_DIR}/disk/disk_smart.txt"

if [[ -f "$SMART" ]]; then
    # 整体健康（一票否决）
    if grep -q "SMART overall-health" "$SMART" 2>/dev/null; then
        grep "SMART overall-health" "$SMART" | grep -qvE "PASSED|OK" && \
            veto "SMART overall-health 非 PASSED/OK"
    fi

    # ASC/ASCQ（一票否决）
    grep -qiE "ascq[^0-9]*(30|64)" "$SMART" 2>/dev/null && veto "ASCQ 30/64: 故障率100%"
    grep -qiE "ascq[^0-9]*62"      "$SMART" 2>/dev/null && veto "ASCQ 62: 故障率~100%"
    ASC_VAL=$(smart_val "$SMART" "smart_health_asc\b")
    [[ -n "$ASC_VAL" && "$ASC_VAL" != "0" ]] && add_score 12 "smart_health_asc=${ASC_VAL}"

    # 不可纠正错误
    READ_E=$(smart_val "$SMART" "read_total_uncorrected_error")
    VRFY_E=$(smart_val "$SMART" "verify_total_uncorrected_error")
    WRIT_E=$(smart_val "$SMART" "write_total_uncorrected_error")
    GROW_E=$(smart_val "$SMART" "elem_in_grown_defect_list")

    [[ ${READ_E:-0} -gt 1000 ]] && add_score 15 "read_total_uncorrected=${READ_E} >1000"
    [[ ${VRFY_E:-0} -gt 1000 ]] && add_score 15 "verify_total_uncorrected=${VRFY_E} >1000"
    [[ ${WRIT_E:-0} -gt 50   ]] && add_score 15 "write_total_uncorrected=${WRIT_E} >50"
    [[ ${GROW_E:-0} -gt 1000 ]] && add_score 12 "elem_in_grown_defect=${GROW_E} >1000"
    [[ ${GROW_E:-0} -ge 200 && ${GROW_E:-0} -le 1000 ]] && \
        add_score 6 "elem_in_grown_defect=${GROW_E} (200-1000 预警区间)"

    # 双超一票否决
    [[ ${READ_E:-0} -gt 1000 && ${VRFY_E:-0} -gt 1000 ]] && \
        veto "不可纠正错误双超: read=${READ_E} verify=${VRFY_E}"

    # SMART ID
    ID197=$(smart_id_raw "$SMART" 197); ID198=$(smart_id_raw "$SMART" 198)
    ID5=$(smart_id_raw "$SMART" 5)
    [[ ${ID197:-0} -ge 1000 ]] && add_score 12 "Pending_Sector(197)=${ID197} ≥1000"
    [[ ${ID198:-0} -ge 1000 ]] && add_score 12 "Uncorrectable(198)=${ID198} ≥1000"
    [[ ${ID5:-0}   -ge 1000 ]] && add_score 10 "Reallocated(5)=${ID5} ≥1000"
    [[ ${ID197:-0} -ge 300 && ${ID197:-0} -lt 1000 ]] && add_score 5 "Pending_Sector(197)=${ID197} 预警"
    [[ ${ID5:-0}   -ge 500 && ${ID5:-0}   -lt 1000 ]] && add_score 4 "Reallocated(5)=${ID5} 预警"

    # NVMe
    NVME_CW=$(smart_val "$SMART" "critical_warning")
    NVME_PU=$(smart_val "$SMART" "percentage_used" | tr -d '%')
    NVME_AS=$(smart_val "$SMART" "available_spare"  | tr -d '%')
    NVME_ME=$(smart_val "$SMART" "media_errors")
    [[ -n "$NVME_CW" && "$NVME_CW" != "0" && "$NVME_CW" != "0x00" ]] && \
        add_score 20 "NVMe critical_warning=${NVME_CW}"
    [[ ${NVME_PU:-0} -gt 95 ]] && add_score 18 "NVMe percentage_used=${NVME_PU}% >95%"
    [[ ${NVME_PU:-0} -gt 80 && ${NVME_PU:-0} -le 95 ]] && \
        add_score 8 "NVMe percentage_used=${NVME_PU}% 预警区间"
    [[ ${NVME_AS:-100} -lt 10 ]] && add_score 12 "NVMe available_spare=${NVME_AS}% <10%"
    [[ ${NVME_ME:-0} -gt 0 ]] && add_score 6 "NVMe media_errors=${NVME_ME}"
    [[ -n "$NVME_CW" && "$NVME_CW" != "0" && "$NVME_CW" != "0x00" \
       && ${NVME_PU:-0} -gt 95 ]] && veto "NVMe critical_warning≠0 且 percentage_used>95%"

    # SATA SSD 寿命
    SSD_LIFE=$(smart_val "$SMART" \
        "Media_Wearout_Indicator|SSD_Life_Left|Wear_Leveling_Count|Lifetime_Remaining|Percent_Lifetime_Remain")
    [[ -n "$SSD_LIFE" && $SSD_LIFE -lt 5  ]] && add_score 18 "SSD 寿命=${SSD_LIFE}% <5%"
    [[ -n "$SSD_LIFE" && $SSD_LIFE -ge 5 && $SSD_LIFE -lt 10 ]] && \
        add_score 10 "SSD 寿命=${SSD_LIFE}% <10% 预警"

else
    echo "  ⚠ SMART 文件不存在: ${SMART}"
fi

# ═══════════════ Step 3: SMART 趋势差分 ═══════════════
echo "[3/5] SMART 趋势差分..."

if [[ -f "$SMART" && -n "$SMART_PREV" && -f "$SMART_PREV" ]]; then
    calc_diff() {
        local p=$1
        local v_now v_prev
        v_now=$(smart_val  "$SMART"      "$p")
        v_prev=$(smart_val "$SMART_PREV" "$p")
        if [[ "$v_now" =~ ^[0-9]+$ && "$v_prev" =~ ^[0-9]+$ ]]; then
            echo $((v_now - v_prev))
        fi
    }

    DIFF_GROW=$(calc_diff "elem_in_grown_defect_list")
    DIFF_READ=$(calc_diff "read_total_uncorrected_error")
    DIFF_VRFY=$(calc_diff "verify_total_uncorrected_error")

    ID5_NOW=$(smart_id_raw "$SMART"      5); ID5_PRV=$(smart_id_raw "$SMART_PREV" 5)
    [[ "$ID5_NOW" =~ ^[0-9]+$ && "$ID5_PRV" =~ ^[0-9]+$ ]] && \
        DIFF_ID5=$((ID5_NOW - ID5_PRV)) || DIFF_ID5=""

    [[ -n "$DIFF_GROW" && $DIFF_GROW -gt 100 ]] && \
        add_score 10 "elem_in_grown 14天差分=${DIFF_GROW} >100（趋势高危）"
    [[ -n "$DIFF_GROW" && $DIFF_GROW -gt 50 && $DIFF_GROW -le 100 ]] && \
        add_score 6  "elem_in_grown 14天差分=${DIFF_GROW} >50（趋势预警）"
    [[ -n "$DIFF_READ" && $DIFF_READ -gt 50 ]] && \
        add_score 5  "read_uncorrected 差分=${DIFF_READ} >50"
    [[ -n "$DIFF_VRFY" && $DIFF_VRFY -gt 50 ]] && \
        add_score 5  "verify_uncorrected 差分=${DIFF_VRFY} >50"
    [[ -n "$DIFF_ID5" && $DIFF_ID5 -gt 50 && ${ID5_NOW:-0} -ge 500 ]] && \
        add_score 5  "Reallocated(5) 差分=${DIFF_ID5} >50 且绝对值≥500"
else
    echo "  ℹ 无历史 SMART 文件，跳过差分（可传入第4参数 SMART_PREV 启用）"
fi

# ═══════════════ Step 4: OS I/O 性能（上限 20 分）═══════════════
echo "[4/5] OS I/O 性能..."
DMESG="${IC_DIR}/system/dmesg.txt"

if [[ -f "$DMESG" ]]; then
    XFS_CNT=$(grep -c "xfs_force_shutdown" "$DMESG" 2>/dev/null); XFS_CNT=${XFS_CNT:-0}
    IO_CNT=$(grep -c "I/O error" "$DMESG" 2>/dev/null); IO_CNT=${IO_CNT:-0}
    FS_CNT=$(grep -c "EXT4-fs error" "$DMESG" 2>/dev/null); FS_CNT=${FS_CNT:-0}
    [[ $XFS_CNT -gt 0 ]] && add_score 12 "dmesg: xfs_force_shutdown (${XFS_CNT}次)"
    [[ $IO_CNT  -gt 10 ]] && add_score 10 "dmesg: I/O error 频繁 (${IO_CNT}次)"
    [[ $IO_CNT  -gt 0 && $IO_CNT -le 10 ]] && add_score 6 "dmesg: I/O error (${IO_CNT}次)"
    [[ $FS_CNT  -gt 0 ]] && add_score 8 "dmesg: 文件系统错误 (${FS_CNT}次)"
fi

if [[ -f "$MSGS" ]]; then
    MSG_XFS=$(grep -c "xfs_force_shutdown" "$MSGS" 2>/dev/null); MSG_XFS=${MSG_XFS:-0}
    MSG_IO=$(grep -c "I/O error" "$MSGS" 2>/dev/null); MSG_IO=${MSG_IO:-0}
    MSG_FS=$(grep -c "EXT4-fs error" "$MSGS" 2>/dev/null); MSG_FS=${MSG_FS:-0}
    MSG_SCSI=$(grep -c "SCSI error" "$MSGS" 2>/dev/null); MSG_SCSI=${MSG_SCSI:-0}
    [[ $MSG_XFS  -gt 0  ]] && add_score 12 "messages: xfs_force_shutdown (${MSG_XFS}条)"
    [[ $MSG_IO   -gt 10 ]] && add_score 10 "messages: I/O error 频繁 (${MSG_IO}条)"
    [[ $MSG_IO   -gt 0 && $MSG_IO -le 10 ]] && add_score 6 "messages: I/O error (${MSG_IO}条)"
    [[ $MSG_FS   -gt 0  ]] && add_score 8  "messages: 文件系统错误 EXT4/XFS (${MSG_FS}条)"
    [[ $MSG_SCSI -gt 5  ]] && add_score 6  "messages: SCSI error 频繁 (${MSG_SCSI}条)"
fi

IOSTAT="${IC_DIR}/system/iostat.txt"
if [[ -f "$IOSTAT" ]]; then
    HIGH_UTIL=$(awk 'NR>3 && /sd/ && $NF+0>98 {c++} END {print c+0}' "$IOSTAT" 2>/dev/null); HIGH_UTIL=${HIGH_UTIL:-0}
    [[ $HIGH_UTIL -gt 0 ]] && add_score 6 "iostat: %util >98% (${HIGH_UTIL}次采样)"
fi

BLKTRACE="${IC_DIR}/disk/blktrace_log.txt"
[[ -f "$BLKTRACE" ]] && grep -q "d2c.*high" "$BLKTRACE" 2>/dev/null &&     add_score 5 "blktrace: d2c 延迟持续异常高"

# ═══════════════ Step 5: 环境与寿命 ═══════════════
echo "[5/5] 环境与寿命..."
if [[ -f "$SMART" ]]; then
    TEMP=$(smart_val "$SMART" "Temperature_Celsius|cur_temperature" | awk '{print $1}')
    POH=$( smart_val "$SMART" "Power_On_Hours|power_on_hours")
    [[ ${TEMP:-0} -gt 50 ]] && add_score 3 "温度=${TEMP}°C >50°C"
    [[ ${TEMP:-0} -lt 15 && ${TEMP:-0} -gt 0 ]] && add_score 2 "温度=${TEMP}°C <15°C"
    [[ ${POH:-0} -gt 35000 ]] && add_score 2 "通电时间=${POH}h >35000h"
    [[ ${TEMP:-0} -ge 25 && ${TEMP:-0} -le 28 ]] && sub_score 1 "温度在最优区间(25-28°C)"
fi

# ═══════════════ 输出结果 ═══════════════
echo ""
echo "========================================"
echo "  诊断结果"
echo "========================================"
echo "综合得分: ${SCORE} / 100"
echo ""

if   $CRITICAL;               then LEVEL="🚨 极高危（一票否决触发）"
elif [[ $SCORE -ge 76 ]];     then LEVEL="🚨 极高危 (${SCORE}分)"
elif [[ $SCORE -ge 56 ]];     then LEVEL="🔴 高危 (${SCORE}分)"
elif [[ $SCORE -ge 36 ]];     then LEVEL="🟠 中风险预警 (${SCORE}分)"
elif [[ $SCORE -ge 16 ]];     then LEVEL="⚠️  低风险预警 (${SCORE}分)"
else                               LEVEL="✅ 正常 (${SCORE}分)"
fi

echo "风险等级: ${LEVEL}"
echo ""
echo "── 触发项清单 ──"
for a in "${ALERTS[@]}"; do echo "  $a"; done
echo ""
echo "── 处置建议 ──"
if   $CRITICAL || [[ $SCORE -ge 56 ]]; then
    echo "  🚨 立即隔离，停止写入，紧急申请换盘工单（P1）→ 3日内完成数据迁移"
elif [[ $SCORE -ge 36 ]]; then
    echo "  🟠 安排计划内数据迁移，7日内换盘评估（P2）"
elif [[ $SCORE -ge 16 ]]; then
    echo "  ⚠️  加强监控频率（每日），持续关注趋势变化（P3）"
else
    echo "  ✅ 按常规周期巡检（月度），无需特殊处理"
fi
echo "========================================"
