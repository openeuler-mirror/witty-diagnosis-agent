#!/bin/bash
# Description: V1 Power & Infrastructure Deep Analysis
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0"
    echo "深度分析供电链路、PSU冗余状态及机箱物理事件。"
    exit 0
fi

echo "[STEP 1] 正在检查电源模块 (PSU) 实时状态..."
if command -v ipmitool &> /dev/null; then
    # 提取所有电源实体的状态
    ipmitool sdr type "Power Supply" | sed 's/^/  [PSU_SDR] /'
    
    echo "[STEP 2] 正在回溯历史掉电与恢复事件 (SEL)..."
    # 定位最近 5 条与电源相关的严重告警
    ipmitool sel elist | grep -Ei "Power Lost|Power Restored|ACPI" | tail -n 5 | sed 's/^/  [SEL_EVENT] /'
    
    echo "[STEP 3] 正在核对机箱开启/搬动记录..."
    ipmitool sel elist | grep -i "Chassis" | tail -n 2 | sed 's/^/  [CHASSIS] /'
else
    echo "  [ERROR] 未检测到 ipmitool，无法执行硬件层诊断。"
fi