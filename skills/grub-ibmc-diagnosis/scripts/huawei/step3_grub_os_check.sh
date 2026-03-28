#!/bin/bash
# 华为 iBMC - Step3: GRUB / OS 层检查（控制台 / 内核 / 文件系统）
# 用法: bash step3_grub_os_check.sh [日志根目录]
# 输出: grub_os_check_huawei.txt

LOG_DIR="${1:-.}"
OUTPUT="grub_os_check_huawei.txt"

echo "========================================" > $OUTPUT
echo "华为 iBMC GRUB/OS 层故障检查" >> $OUTPUT
echo "分析时间: $(date)" >> $OUTPUT
echo "========================================" >> $OUTPUT

# 1. 控制台串口输出（最关键 - GRUB/内核原始输出）
SYSCOM=$(find "$LOG_DIR" -path "*/OSDump/systemcom.tar" 2>/dev/null | head -1)
if [ -f "$SYSCOM" ]; then
    echo "" >> $OUTPUT
    echo "=== [OSDump/systemcom.tar] 控制台串口输出 ===" >> $OUTPUT
    TMPDIR=$(mktemp -d)
    tar -xf "$SYSCOM" -C "$TMPDIR" 2>/dev/null
    find "$TMPDIR" -type f | sort | while read f; do
        echo "--- 子文件: $(basename $f) ---" >> $OUTPUT
        grep -iE "(grub|rescue|error|panic|kernel|initramfs|boot|partition|uuid|not found|failed|loading)" \
            "$f" 2>/dev/null | head -40 >> $OUTPUT
        echo "  [末尾30行]" >> $OUTPUT
        tail -30 "$f" 2>/dev/null >> $OUTPUT
    done
    rm -rf "$TMPDIR"
else
    echo "[WARN] 未找到 OSDump/systemcom.tar" >> $OUTPUT
fi

# 2. 内核崩溃截图（Kernel Panic 视觉证据）
echo "" >> $OUTPUT
echo "=== [OSDump] 内核崩溃截图列表 ===" >> $OUTPUT
IMGS=$(find "$LOG_DIR" -path "*/OSDump/*.jpeg" -o -path "*/OSDump/*.jpg" 2>/dev/null)
if [ -n "$IMGS" ]; then
    echo "$IMGS" | sort >> $OUTPUT
    echo "  [提示] 请通过 iBMC WebUI 或直接查看截图文件确认 Kernel Panic 信息" >> $OUTPUT
else
    echo "  [INFO] 未发现 OSDump 截图" >> $OUTPUT
fi

# 3. dmesg 内核日志
DMESG=$(find "$LOG_DIR" -name "dmesg_info" -o -name "dmesg" 2>/dev/null | head -1)
if [ -f "$DMESG" ]; then
    echo "" >> $OUTPUT
    echo "=== [dmesg] 内核错误信息 ===" >> $OUTPUT
    grep -iE "(error|panic|call trace|oops|BUG|EXT4|XFS|btrfs|mount|fail|ata|scsi)" \
        "$DMESG" | head -60 >> $OUTPUT
else
    echo "[WARN] 未找到 dmesg_info" >> $OUTPUT
fi

# 4. 文件系统磁盘使用情况
DF_INFO=$(find "$LOG_DIR" -name "df_info" 2>/dev/null | head -1)
if [ -f "$DF_INFO" ]; then
    echo "" >> $OUTPUT
    echo "=== [df_info] 磁盘挂载与使用情况 ===" >> $OUTPUT
    cat "$DF_INFO" >> $OUTPUT
else
    echo "[WARN] 未找到 df_info" >> $OUTPUT
fi

# 5. agentless 连接日志（OS 层可达性）
AGENT_LOG=$(find "$LOG_DIR" -name "agentless_dfl.log" 2>/dev/null | head -1)
if [ -f "$AGENT_LOG" ]; then
    echo "" >> $OUTPUT
    echo "=== [agentless] OS 连接状态 ===" >> $OUTPUT
    grep -iE "(connection lost|timeout|error|fail)" \
        "$AGENT_LOG" | tail -30 >> $OUTPUT
fi

echo "" >> $OUTPUT
echo "======== GRUB/OS 层检查完成 ========" >> $OUTPUT
echo "[输出文件] $OUTPUT"
cat $OUTPUT
