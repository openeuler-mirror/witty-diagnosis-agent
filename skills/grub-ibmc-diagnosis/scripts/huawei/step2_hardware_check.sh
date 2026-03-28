#!/bin/bash
# 华为 iBMC - Step2: 硬件层异常检查（磁盘 / RAID / 控制器）
# 用法: bash step2_hardware_check.sh [日志根目录]
# 输出: hardware_check_huawei.txt

LOG_DIR="${1:-.}"
OUTPUT="hardware_check_huawei.txt"

echo "========================================" > $OUTPUT
echo "华为 iBMC 硬件层故障检查" >> $OUTPUT
echo "分析时间: $(date)" >> $OUTPUT
echo "========================================" >> $OUTPUT

# 1. RAID 控制器状态
RAID_INFO=$(find "$LOG_DIR" -name "RAID_Controller_Info.txt" 2>/dev/null | head -1)
if [ -f "$RAID_INFO" ]; then
    echo "" >> $OUTPUT
    echo "=== [RAID] 控制器整体状态 ===" >> $OUTPUT
    grep -iE "(state|status|degraded|offline|rebuild|failed|missing|optimal|error)" \
        "$RAID_INFO" | head -60 >> $OUTPUT
    echo "--- 逻辑卷 (LD/VD) 状态 ---" >> $OUTPUT
    grep -iE "(logical|vd |ld )" "$RAID_INFO" | \
        grep -iE "(state|status|degraded|offline)" | head -30 >> $OUTPUT
else
    echo "[WARN] 未找到 RAID_Controller_Info.txt" >> $OUTPUT
fi

# 2. 存储管理通信日志
STOR_LOG=$(find "$LOG_DIR" -name "StorageMgnt_dfl.log" 2>/dev/null | head -1)
if [ -f "$STOR_LOG" ]; then
    echo "" >> $OUTPUT
    echo "=== [StorageMgnt] 存储通信日志 ===" >> $OUTPUT
    grep -iE "(comm lost|error|fail|timeout|offline|rebuild|degraded)" \
        "$STOR_LOG" | tail -60 >> $OUTPUT
else
    echo "[WARN] 未找到 StorageMgnt_dfl.log" >> $OUTPUT
fi

# 3. 卡管理日志（控制器识别）
CARD_LOG=$(find "$LOG_DIR" -name "card_manage_dfl.log" 2>/dev/null | head -1)
if [ -f "$CARD_LOG" ]; then
    echo "" >> $OUTPUT
    echo "=== [CardMgmt] 控制器识别日志 ===" >> $OUTPUT
    grep -iE "(error|init|fail|card|controller|not found)" \
        "$CARD_LOG" | tail -40 >> $OUTPUT
else
    echo "[WARN] 未找到 card_manage_dfl.log" >> $OUTPUT
fi

# 4. SEL 中磁盘相关告警
SEL_FILE=$(find "$LOG_DIR" -name "sel.db" -o -name "sel.log" 2>/dev/null | head -1)
if [ -f "$SEL_FILE" ]; then
    echo "" >> $OUTPUT
    echo "=== [SEL] 磁盘/存储相关告警 ===" >> $OUTPUT
    grep -iE "(disk|drive|hdd|ssd|nvme|storage|assert)" \
        "$SEL_FILE" | tail -50 >> $OUTPUT
fi

echo "" >> $OUTPUT
echo "======== 硬件层检查完成 ========" >> $OUTPUT
echo "[输出文件] $OUTPUT"
cat $OUTPUT
