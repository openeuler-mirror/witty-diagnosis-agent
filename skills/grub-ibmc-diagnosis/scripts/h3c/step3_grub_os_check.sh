#!/bin/bash
# H3C iBMC - Step3: GRUB / OS 层检查
# 用法: bash step3_grub_os_check.sh [日志根目录]
# 输出: grub_os_check_h3c.txt

LOG_DIR="${1:-.}"
OUTPUT="grub_os_check_h3c.txt"

echo "========================================" > $OUTPUT
echo "H3C iBMC GRUB/OS 层检查" >> $OUTPUT
echo "分析时间: $(date)" >> $OUTPUT
echo "========================================" >> $OUTPUT

# 1. 控制台串口输出（OSDump/systemcom.tar - 最关键）
SYSCOM=$(find "$LOG_DIR" -path "*/OSDump/systemcom.tar" 2>/dev/null | head -1)
if [ -f "$SYSCOM" ]; then
    echo "=== [OSDump/systemcom.tar] 控制台串口输出 ===" >> $OUTPUT
    TMPDIR=$(mktemp -d)
    tar -xf "$SYSCOM" -C "$TMPDIR" 2>/dev/null
    find "$TMPDIR" -type f | sort | while read f; do
        FNAME=$(basename "$f")
        echo "" >> $OUTPUT
        echo "  --- 子文件: $FNAME （关键行）---" >> $OUTPUT
        grep -iE "(grub|rescue|error|panic|kernel|initramfs|boot|partition|uuid|not found|failed|loading|dracut|welcome)" \
            "$f" 2>/dev/null | head -40 >> $OUTPUT
        echo "  --- $FNAME 末尾 30 行 ---" >> $OUTPUT
        tail -30 "$f" 2>/dev/null >> $OUTPUT
    done
    rm -rf "$TMPDIR"
else
    echo "[WARN] 未找到 OSDump/systemcom.tar" >> $OUTPUT
fi

# 2. 内核崩溃截图列表
echo "" >> $OUTPUT
echo "=== [OSDump/*.jpeg] 内核崩溃截图 ===" >> $OUTPUT
IMGS=$(find "$LOG_DIR" -path "*/OSDump/*.jpeg" -o -path "*/OSDump/*.jpg" 2>/dev/null)
if [ -n "$IMGS" ]; then
    echo "$IMGS" | sort >> $OUTPUT
    echo "  [提示] 请直接查看截图确认 Kernel Panic / GRUB 错误信息" >> $OUTPUT
else
    echo "  [INFO] 未发现 OSDump 截图" >> $OUTPUT
fi

# 3. 安全日志（Secure Boot / 签名验证）
SEC_LOG=$(find "$LOG_DIR" -path "*/LogDump/security_log" 2>/dev/null | head -1)
if [ -f "$SEC_LOG" ]; then
    echo "" >> $OUTPUT
    echo "=== [LogDump/security_log] 安全日志 ===" >> $OUTPUT
    grep -iE "(fail|denied|violation|error|auth|boot|secure|sign|verify)" \
        "$SEC_LOG" | tail -40 >> $OUTPUT
else
    echo "[INFO] 未找到 LogDump/security_log" >> $OUTPUT
fi

# 4. 用户操作日志（磁盘加密/权限）
USER_LOG=$(find "$LOG_DIR" -path "*/AppDump/User_dfl.log" 2>/dev/null | head -1)
if [ -f "$USER_LOG" ]; then
    echo "" >> $OUTPUT
    echo "=== [AppDump/User_dfl.log] 用户操作日志 ===" >> $OUTPUT
    grep -iE "(encrypt|tpm|bitlocker|key|auth|fail|error|password)" \
        "$USER_LOG" | tail -30 >> $OUTPUT
else
    echo "[INFO] 未找到 AppDump/User_dfl.log" >> $OUTPUT
fi

# 5. SP 快速部署日志（特殊离线场景）
SP_LOG=$(find "$LOG_DIR" -path "*/SpLogDump/quickdeploy_debug.log" 2>/dev/null | head -1)
if [ -f "$SP_LOG" ]; then
    echo "" >> $OUTPUT
    echo "=== [SpLogDump/quickdeploy_debug] SP 部署日志 ===" >> $OUTPUT
    grep -iE "(error|fail|boot|install|grub|kernel|deploy)" \
        "$SP_LOG" | tail -30 >> $OUTPUT
fi

echo "" >> $OUTPUT
echo "======== GRUB/OS 层检查完成 ========" >> $OUTPUT
echo "[输出文件] $OUTPUT"
cat $OUTPUT
