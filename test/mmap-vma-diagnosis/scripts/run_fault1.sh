#!/bin/bash
# run_fault1_exhaust.sh — 容器1: max_map_count 耗尽故障
# 让容器保持运行，供 witty agent 诊断
set -e

echo 5000 > /proc/sys/vm/max_map_count
echo "max_map_count 设为 $(cat /proc/sys/vm/max_map_count)"

/test/fault_mmap_exhaust &
FPID=$!
echo "故障进程 PID=$FPID"

# 保持容器运行
echo "容器将持续运行，等待外部诊断..."
sleep 3600
