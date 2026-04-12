#!/bin/bash
# Description: V5 Critical Hardware Fault Analysis
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0"
    echo "定位底层硬件致命错误，包括 MCE、ECC 及存储坏道。"
    exit 0
fi

echo "[STEP 1] 正在检索 MCE (Machine Check Exception) 硬件日志..."
if command -v ras-mc-ctl &> /dev/null; then
    ras-mc-ctl --summary | sed 's/^/  [MCE_SUMMARY] /'
    ras-mc-ctl --errors | tail -n 5 | sed 's/^/  [MCE_DETAIL] /'
else
    echo "  [WARN] 未检测到 rasdaemon，尝试检查 dmesg 中的硬件错误..."
    dmesg | grep -Ei "MCE|Machine Check" | tail -n 3 | sed 's/^/  [KERNEL_HW] /'
fi

echo "[STEP 2] 正在执行关键存储介质健康扫描..."
for d in $(lsblk -dno NAME | head -n 3); do 
    echo "  [DISK_$d] $(smartctl -H /dev/$d 2>/dev/null | grep "result")"
done

echo "[STEP 3] 正在检查 PCIe 总线异常 (AER)..."
dmesg | grep -i "AER" | tail -n 2 | sed 's/^/  [PCIe_AER] /'