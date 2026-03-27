#!/bin/bash
# H3C iBMC - Step2: 硬件层异常检查（RAID / SMART / PHY / 通信）
# 用法: bash step2_hardware_check.sh [日志根目录]
# 输出: hardware_check_h3c.txt

LOG_DIR="${1:-.}"
OUTPUT="hardware_check_h3c.txt"

echo "========================================" > $OUTPUT
echo "H3C iBMC 硬件层故障检查" >> $OUTPUT
echo "分析时间: $(date)" >> $OUTPUT
echo "========================================" >> $OUTPUT

# 1. RAID 控制器信息（AppDump）
RAID_INFO=$(find "$LOG_DIR" -path "*/AppDump/RAID_Controller_Info.txt" 2>/dev/null | head -1)
if [ -f "$RAID_INFO" ]; then
    echo "=== [AppDump/RAID_Controller_Info] RAID 控制器状态 ===" >> $OUTPUT
    grep -iE "(state|status|degraded|offline|rebuild|failed|missing|optimal|error|foreign|pd |vd |ld )" \
        "$RAID_INFO" | head -60 >> $OUTPUT
else
    echo "[WARN] 未找到 AppDump/RAID_Controller_Info.txt" >> $OUTPUT
fi

# 2. LSI RAID 控制器详细日志（LogDump）
LSI_LOG=$(find "$LOG_DIR" -path "*/LogDump/LSI_RAID_Controller_Log" 2>/dev/null | head -1)
if [ -f "$LSI_LOG" ]; then
    echo "" >> $OUTPUT
    echo "=== [LogDump/LSI_RAID_Controller_Log] LSI 日志 ===" >> $OUTPUT
    grep -iE "(error|fail|degraded|offline|rebuild|pd |vd |ld |disk|drive)" \
        "$LSI_LOG" | tail -60 >> $OUTPUT
else
    echo "[WARN] 未找到 LogDump/LSI_RAID_Controller_Log" >> $OUTPUT
fi

# 3. 物理磁盘 SMART 信息（每块盘单独文件）
echo "" >> $OUTPUT
echo "=== [LogDump/PD_SMART_INFO_*] 磁盘 SMART 状态 ===" >> $OUTPUT
SMART_FILES=$(find "$LOG_DIR" -path "*/LogDump/PD_SMART_INFO_C*" 2>/dev/null)
if [ -n "$SMART_FILES" ]; then
    echo "$SMART_FILES" | while read smart_file; do
        DISK_ID=$(basename "$smart_file")
        echo "--- 磁盘: $DISK_ID ---" >> $OUTPUT
        # 提取关键 SMART 属性：重分配扇区/待定扇区/不可纠正错误
        grep -iE "(reallocated|pending|uncorrectable|offline uncorrectable|raw read error|spin retry|health|overall|id #)" \
            "$smart_file" | head -15 >> $OUTPUT
    done
else
    echo "[WARN] 未找到 PD_SMART_INFO_C* 文件" >> $OUTPUT
fi

# 4. 物理驱动器日志（drivelog）
echo "" >> $OUTPUT
echo "=== [LogDump/drivelog/] 物理驱动器日志 ===" >> $OUTPUT
DRIVE_LOGS=$(find "$LOG_DIR" -path "*/LogDump/drivelog/*" -type f 2>/dev/null)
if [ -n "$DRIVE_LOGS" ]; then
    echo "$DRIVE_LOGS" | while read f; do
        echo "--- $(basename $f) ---" >> $OUTPUT
        grep -iE "(error|fail|timeout|reset|abort|sense|cmd)" "$f" | head -15 >> $OUTPUT
    done
else
    echo "[INFO] 未找到 drivelog/ 文件" >> $OUTPUT
fi

# 5. PHY 接口日志（链路层连接）
echo "" >> $OUTPUT
echo "=== [LogDump/phy/] PHY 接口日志 ===" >> $OUTPUT
PHY_LOGS=$(find "$LOG_DIR" -path "*/LogDump/phy/*" -type f 2>/dev/null)
if [ -n "$PHY_LOGS" ]; then
    echo "$PHY_LOGS" | while read f; do
        grep -iE "(error|reset|link|lost|down|fail|phy)" "$f" | tail -10 >> $OUTPUT
    done
else
    echo "[INFO] 未找到 phy/ 文件" >> $OUTPUT
fi

# 6. 组件通信日志
echo "" >> $OUTPUT
echo "=== [LogDump/*_com_log] 组件通信日志 ===" >> $OUTPUT
COM_LOGS=$(find "$LOG_DIR" -path "*/LogDump/*_com_log" 2>/dev/null)
if [ -n "$COM_LOGS" ]; then
    echo "$COM_LOGS" | while read f; do
        echo "--- $(basename $f) ---" >> $OUTPUT
        grep -iE "(error|timeout|fail|lost|disconnect|comm)" "$f" | tail -15 >> $OUTPUT
    done
else
    echo "[INFO] 未找到 *_com_log 文件" >> $OUTPUT
fi

echo "" >> $OUTPUT
echo "======== 硬件层检查完成 ========" >> $OUTPUT
echo "[输出文件] $OUTPUT"
cat $OUTPUT
