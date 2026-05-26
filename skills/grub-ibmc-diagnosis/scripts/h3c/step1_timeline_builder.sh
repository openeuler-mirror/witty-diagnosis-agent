#!/bin/bash
# H3C iBMC - Step1: 启动事件时间线构建
# 用法: bash step1_timeline_builder.sh [日志根目录]
# 输出: timeline_h3c.txt

LOG_DIR="${1:-.}"
OUTPUT="timeline_h3c.txt"

echo "========================================" > $OUTPUT
echo "H3C iBMC 启动事件时间线" >> $OUTPUT
echo "分析时间: $(date)" >> $OUTPUT
echo "日志目录: $(realpath $LOG_DIR)" >> $OUTPUT
echo "========================================" >> $OUTPUT

# 1. 当前事件日志（AppDump - H3C 核心告警来源）
EVENT_LOG=$(find "$LOG_DIR" -path "*/AppDump/current_event.txt" 2>/dev/null | head -1)
if [ -f "$EVENT_LOG" ]; then
    echo "" >> $OUTPUT
    echo "=== [AppDump/current_event] 当前事件日志 ===" >> $OUTPUT
    grep -iE "(error|fault|fail|critical|warn|assert|power|boot|reset|offline|degraded)" \
        "$EVENT_LOG" | tail -80 >> $OUTPUT
else
    echo "[WARN] 未找到 AppDump/current_event.txt" >> $OUTPUT
fi

# 2. FDM 故障管理日志（LogDump）
for fdm_name in "arm_fdm_log" "fdm_me_log"; do
    FDM=$(find "$LOG_DIR" -path "*/LogDump/$fdm_name" 2>/dev/null | head -1)
    if [ -f "$FDM" ]; then
        echo "" >> $OUTPUT
        echo "=== [LogDump/$fdm_name] FDM 日志 ===" >> $OUTPUT
        grep -iE "(fault|error|fail|critical|offline|degraded|assert)" \
            "$FDM" | tail -40 >> $OUTPUT
    else
        echo "[WARN] 未找到 LogDump/$fdm_name" >> $OUTPUT
    fi
done

# 3. df_info（RTOSDump - 系统文件系统状态）
DF_INFO=$(find "$LOG_DIR" -path "*/RTOSDump/df_info" 2>/dev/null | head -1)
if [ -f "$DF_INFO" ]; then
    echo "" >> $OUTPUT
    echo "=== [RTOSDump/df_info] 磁盘挂载状态 ===" >> $OUTPUT
    cat "$DF_INFO" >> $OUTPUT
else
    echo "[WARN] 未找到 RTOSDump/df_info" >> $OUTPUT
fi

# 4. kbox_info（内核崩溃黑匣子）
KBOX=$(find "$LOG_DIR" -path "*/RTOSDump/kbox_info" 2>/dev/null | head -1)
if [ -f "$KBOX" ]; then
    echo "" >> $OUTPUT
    echo "=== [RTOSDump/kbox_info] 内核崩溃记录 ===" >> $OUTPUT
    grep -iE "(panic|oops|bug|call trace|error|crash|reboot|fault)" \
        "$KBOX" | head -50 >> $OUTPUT
    echo "  --- 末尾 30 行 ---" >> $OUTPUT
    tail -30 "$KBOX" >> $OUTPUT
else
    echo "[INFO] 未找到 RTOSDump/kbox_info（可能无内核崩溃）" >> $OUTPUT
fi

echo "" >> $OUTPUT
echo "======== 时间线构建完成 ========" >> $OUTPUT
echo "[输出文件] $OUTPUT"
cat $OUTPUT
