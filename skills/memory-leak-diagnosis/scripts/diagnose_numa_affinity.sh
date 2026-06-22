#!/bin/bash
set -euo pipefail
# diagnose_numa_affinity.sh - NUMA 不亲和检测
# 检测跨 NUMA 访问比例、本地分配率、节点内存均衡度
# 使用: ./diagnose_numa_affinity.sh [--pid PID] [--verbose]

PID=""
VERBOSE=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --pid) PID="$2"; shift 2 ;;
    --verbose|-v) VERBOSE=1; shift ;;
    *) echo "Usage: $0 [--pid PID] [--verbose]"; exit 1 ;;
  esac
done

echo "========================================"
echo "NUMA 不亲和检测报告"
[[ -n "$PID" ]] && echo "目标PID: $PID"
echo "========================================"

# 1. 硬件拓扑
echo ""
echo "[1/5] NUMA 硬件拓扑"
echo "----------------------------------------"
numactl --hardware 2>/dev/null || echo "numactl not installed"
lscpu 2>/dev/null | grep -E "NUMA|Socket|Core|Thread" || true

NODE_COUNT=$(lscpu 2>/dev/null | grep "NUMA node(s)" | awk '{print $NF}')
NODE_COUNT=${NODE_COUNT:-1}
echo "NUMA 节点数: $NODE_COUNT"

# 2. 进程 NUMA 策略
echo ""
echo "[2/5] 进程 NUMA 策略"
echo "----------------------------------------"
if [[ -n "$PID" ]] && [[ -r /proc/$PID/numa_maps ]]; then
  echo "进程 NUMA 映射:"
  cat /proc/$PID/numa_maps | head -20
  [[ $VERBOSE -eq 1 ]] && cat /proc/$PID/numa_maps
elif [[ -n "$PID" ]]; then
  echo "WARNING: 无法读取 PID $PID 的 NUMA 信息"
fi

if [[ -n "$PID" ]]; then
  echo ""
  echo "CPU 绑定:"
  taskset -pc $PID 2>/dev/null || echo "taskset not available"
fi

# 3. 本地访问率
echo ""
echo "[3/5] 跨 NUMA 访问分析"
echo "----------------------------------------"
if [[ -f /proc/vmstat ]]; then
  HIT=$(awk '/numa_hit/ {print $2}' /proc/vmstat)
  MISS=$(awk '/numa_miss/ {print $2}' /proc/vmstat)
  FOREIGN=$(awk '/numa_foreign/ {print $2}' /proc/vmstat)
  LOCAL=$(awk '/numa_local/ {print $2}' /proc/vmstat)
  TOTAL=$((HIT + MISS))
  
  if [[ $TOTAL -gt 0 ]]; then
    LOCAL_RATE=$(echo "scale=1; $LOCAL * 100 / $TOTAL" | bc)
    FOREIGN_RATE=$(echo "scale=1; $FOREIGN * 100 / $TOTAL" | bc)
    echo "NUMA hit:    $HIT"
    echo "NUMA miss:   $MISS"
    echo "NUMA foreign: $FOREIGN"
    echo "NUMA local:  $LOCAL"
    echo "本地访问率:  ${LOCAL_RATE}%"
    echo "跨节点访问率: ${FOREIGN_RATE}%"
  else
    echo "NUMA 统计不可用"
  fi
fi

if [[ -n "$PID" ]] && [[ -r /proc/$PID/numa_maps ]]; then
  echo ""
  echo "进程各节点内存分布:"
  awk '{
    for(i=1;i<=NF;i++) {
      if($i ~ /^N[0-9]=/) {
        split($i,a,"=");
        node[a[1]]+=a[2];
      }
    }
  } END {
    for(n in node) print "  " n ": " node[n] " pages";
  }' /proc/$PID/numa_maps
fi

# 4. 节点内存均衡
echo ""
echo "[4/5] 节点内存使用均衡"
echo "----------------------------------------"
for node_path in /sys/devices/system/node/node*/meminfo; do
  if [[ -r "$node_path" ]]; then
    node_name=$(echo "$node_path" | grep -oE 'node[0-9]+')
    total=$(grep "MemTotal" "$node_path" | awk '{print $2}')
    free=$(grep "MemFree" "$node_path" | awk '{print $2}')
    used=$((total - free))
    if [[ $total -gt 0 ]]; then
      echo "  $node_name: total=${total}KB used=${used}KB ($((used*100/total))%)"
    fi
  fi
done

# 5. 优化建议
echo ""
echo "[5/5] NUMA 优化建议"
echo "----------------------------------------"
LOCAL_RATE=${LOCAL_RATE:-0}

if [[ $NODE_COUNT -le 1 ]]; then
  echo "- 系统为单 NUMA 节点，无需 NUMA 优化"
elif (( $(echo "$LOCAL_RATE < 70" | bc -l 2>/dev/null) )); then
  echo "- 本地访问率 ${LOCAL_RATE}% 偏低"
  echo "- 建议: numactl --membind <node> 绑定进程到固定节点"
elif (( $(echo "$LOCAL_RATE < 90" | bc -l 2>/dev/null) )); then
  echo "- 本地访问率 ${LOCAL_RATE}% 一般"
  echo "- 建议: 监控趋势，检查是否可优化"
else
  echo "- 本地访问率 ${LOCAL_RATE}%，NUMA 亲和性良好"
fi

echo ""
echo "========================================"
echo "检测完成"
echo "========================================"
