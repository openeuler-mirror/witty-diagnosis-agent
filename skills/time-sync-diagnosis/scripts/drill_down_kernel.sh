#!/bin/bash
function show_help() {
    cat << EOF
Usage: bash drill_down_kernel.sh
Scenario: D - 内核与交付 (Hardware & Kernel)
Methodology: 解决“不准”的问题。审计内核时钟源稳定性及虚拟化环境下的 CPU Steal Time。
EOF
}
[[ "$1" == "-h" || "$1" == "--help" ]] && show_help && exit 0

echo "[Step 1: 内核计时源审计] 正在检查当前使用的时钟源..."
cur_cs=$(cat /sys/devices/system/clocksource/clocksource0/current_clocksource)
echo "Current Clocksource: $cur_cs"

echo -e "\n[Step 2: 虚拟化调度审计] 正在检测 CPU Steal Time..."
vmstat 1 3 | tail -n 1 | awk '{if($16 > 0) print "Critical: 发现 Steal Time ("$16"%), 硬件时钟中断可能丢失"; else print "Result: 调度正常"}'