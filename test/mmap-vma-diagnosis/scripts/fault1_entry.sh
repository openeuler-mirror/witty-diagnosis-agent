#!/bin/bash
# fault1_entry.sh — 容器1入口: 设定低 max_map_count 并注入故障
echo 2000 > /proc/sys/vm/max_map_count
echo "max_map_count=$(cat /proc/sys/vm/max_map_count)"
/test/fault_mmap_exhaust
echo "故障注入完毕，保持运行等待诊断..."
sleep 3600
