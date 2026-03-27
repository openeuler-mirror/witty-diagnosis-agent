#!/bin/bash
# 华为 iBMC - Step1: 启动事件时间线构建
# 用法: bash step1_timeline_builder.sh [日志根目录]
# 输出: timeline_huawei.txt

LOG_DIR="${1:-.}"
OUTPUT="timeline_huawei.txt"

echo "========================================" > $OUTPUT
echo "华为 iBMC 启动事件时间线" >> $OUTPUT
echo "分析时间: $(date)" >> $OUTPUT
echo "日志目录: $(realpath $LOG_DIR)" >> $OUTPUT
echo "========================================" >> $OUTPUT

# 1. SEL 系统事件日志
SEL_FILE=$(find "$LOG_DIR" -name "sel.db" -o -name "sel.log" -o -name "SEL*.txt" 2>/dev/null | head -1)
if [ -f "$SEL_FILE" ]; then
    echo "" >> $OUTPUT
    echo "=== [SEL] 系统事件日志（关键告警）===" >> $OUTPUT
    grep -iE "(assert|deassert|critical|error|fault|fail|warn|power on|power off|reset|boot)" \
        "$SEL_FILE" | tail -100 >> $OUTPUT
else
    echo "[WARN] 未找到 sel.db / sel.log" >> $OUTPUT
fi

# 2. FDM 故障管理日志
FDM_FILE=$(find "$LOG_DIR" -name "fdm_output" -o -name "fdm_output.txt" 2>/dev/null | head -1)
if [ -f "$FDM_FILE" ]; then
    echo "" >> $OUTPUT
    echo "=== [FDM] 故障管理日志（Fault 事件）===" >> $OUTPUT
    grep -iE "(fault|error|fail|critical|offline|degraded)" \
        "$FDM_FILE" | head -80 >> $OUTPUT
else
    echo "[WARN] 未找到 fdm_output" >> $OUTPUT
fi

# 3. BMC 系统日志
BMC_LOG=$(find "$LOG_DIR" -name "BMC_dfl.log" -o -name "bmc_dfl.log" 2>/dev/null | head -1)
if [ -f "$BMC_LOG" ]; then
    echo "" >> $OUTPUT
    echo "=== [BMC] 系统日志（ERROR/EXCEPTION）===" >> $OUTPUT
    grep -iE "(error|exception|critical|fault|reboot|power)" \
        "$BMC_LOG" | tail -60 >> $OUTPUT
else
    echo "[WARN] 未找到 BMC_dfl.log" >> $OUTPUT
fi

# 4. BIOS 日志
BIOS_LOG=$(find "$LOG_DIR" -name "BIOS_dfl.log" 2>/dev/null | head -1)
if [ -f "$BIOS_LOG" ]; then
    echo "" >> $OUTPUT
    echo "=== [BIOS] 启动配置日志 ===" >> $OUTPUT
    grep -iE "(fail|error|config|boot|uefi|legacy|secure)" \
        "$BIOS_LOG" | tail -50 >> $OUTPUT
else
    echo "[WARN] 未找到 BIOS_dfl.log" >> $OUTPUT
fi

echo "" >> $OUTPUT
echo "======== 时间线构建完成 ========" >> $OUTPUT
echo "[输出文件] $OUTPUT"
cat $OUTPUT
