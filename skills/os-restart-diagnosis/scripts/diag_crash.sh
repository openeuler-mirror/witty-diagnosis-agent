#!/bin/bash
# Description: V4 Kernel Crash & Panic Analysis
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0"
    echo "解析内核转储文件 (vmcore) 并提取调用栈 (Backtrace)。"
    exit 0
fi

echo "[STEP 1] 正在自动检索最新的 vmcore 转储文件..."
VCORE=$(find /var/crash -name "vmcore" -type f | sort | tail -1)
if [[ -n "$VCORE" ]]; then
    echo "  [INFO] 发现转储文件: $VCORE"
    echo "[STEP 2] 正在利用 crash 工具提取函数调用栈..."
    # 自动化执行 bt 命令
    crash -s -i <(echo "bt; quit") /usr/lib/debug/boot/vmlinux-$(uname -r) "$VCORE" 2>/dev/null | grep -E "\[.*\]" | sed 's/^/    /'
else
    echo "  [WARN] 未发现 vmcore，尝试读取 pstore 离线记录..."
    cat /sys/fs/pstore/console-ramoops-0 2>/dev/null | tail -n 10 | sed 's/^/  [PSTORE] /'
fi