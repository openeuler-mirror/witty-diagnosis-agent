#!/bin/bash
# 浪潮 Inspur iBMC - Step3: GRUB / OS 层检查
# 用法: bash step3_grub_os_check.sh [日志根目录]
# 输出: grub_os_check_inspur.txt

LOG_DIR="${1:-.}"
OUTPUT="grub_os_check_inspur.txt"

echo "========================================" > $OUTPUT
echo "浪潮 iBMC GRUB/OS 层检查" >> $OUTPUT
echo "分析时间: $(date)" >> $OUTPUT
echo "========================================" >> $OUTPUT

# 1. SOL 主机控制台捕获（最关键：GRUB 和内核的原始输出）
SOL_LOG=$(find "$LOG_DIR" -path "*/onekeylog/sollog/solHostCaptured.log" 2>/dev/null | head -1)
if [ -f "$SOL_LOG" ]; then
    echo "=== [solHostCaptured] SOL 控制台输出（关键行过滤）===" >> $OUTPUT
    grep -iE "(grub|rescue|error|panic|kernel|boot|partition|uuid|not found|failed|initramfs|loading|welcome|dracut)" \
        "$SOL_LOG" | head -80 >> $OUTPUT
    echo "" >> $OUTPUT
    echo "  --- 末尾 50 行（包含最终失败状态）---" >> $OUTPUT
    tail -50 "$SOL_LOG" >> $OUTPUT
else
    echo "[WARN] 未找到 onekeylog/sollog/solHostCaptured.log" >> $OUTPUT
fi

# 2. dmesg 内核日志
DMESG=$(find "$LOG_DIR" -path "*/onekeylog/log/dmesg" 2>/dev/null | head -1)
if [ -f "$DMESG" ]; then
    echo "" >> $OUTPUT
    echo "=== [dmesg] 内核错误日志 ===" >> $OUTPUT
    grep -iE "(error|panic|call trace|oops|BUG:|EXT4|XFS|btrfs|mount fail|i/o error|ata|scsi|nvme)" \
        "$DMESG" | head -60 >> $OUTPUT
else
    echo "[WARN] 未找到 onekeylog/log/dmesg" >> $OUTPUT
fi

# 3. 崩溃视频帧（CrashVideoRecordCurrent）
CRASH=$(find "$LOG_DIR" -path "*/onekeylog/log/CrashVideoRecordCurrent" 2>/dev/null | head -1)
if [ -e "$CRASH" ]; then
    echo "" >> $OUTPUT
    echo "=== [CrashVideoRecord] 崩溃视频记录 ===" >> $OUTPUT
    echo "路径: $CRASH" >> $OUTPUT
    ls -lh "$CRASH" 2>/dev/null >> $OUTPUT
    if [ -d "$CRASH" ]; then
        echo "内含文件:" >> $OUTPUT
        ls "$CRASH" 2>/dev/null | head -20 >> $OUTPUT
    fi
else
    echo "[INFO] 未找到 CrashVideoRecordCurrent（无崩溃视频）" >> $OUTPUT
fi

# 4. SMBIOS 数据（分区/设备硬件描述）
SMBIOS=$(find "$LOG_DIR" -path "*/onekeylog/runningdata/smbios.dmp" 2>/dev/null | head -1)
if [ -f "$SMBIOS" ]; then
    echo "" >> $OUTPUT
    echo "=== [smbios] 硬件描述信息 ===" >> $OUTPUT
    # smbios.dmp 通常为二进制，只提取可读字符串
    strings "$SMBIOS" 2>/dev/null | \
        grep -iE "(disk|drive|boot|storage|controller|raid|slot|bay)" | \
        head -30 >> $OUTPUT
fi

# 5. 安全/审计日志
AUDIT=$(find "$LOG_DIR" -path "*/onekeylog/log/audit.log" 2>/dev/null | head -1)
if [ -f "$AUDIT" ]; then
    echo "" >> $OUTPUT
    echo "=== [audit] 安全审计日志（加密/认证）===" >> $OUTPUT
    grep -iE "(encrypt|tpm|bitlocker|denied|fail|error|auth)" \
        "$AUDIT" | tail -30 >> $OUTPUT
fi

echo "" >> $OUTPUT
echo "======== GRUB/OS 层检查完成 ========" >> $OUTPUT
echo "[输出文件] $OUTPUT"
cat $OUTPUT
