#!/bin/bash
set -euo pipefail
# diagnose_large_object.sh - 大对象分配热点识别
# 检测超过阈值的大对象分配路径
# 使用: ./diagnose_large_object.sh [--threshold BYTES] [--pid PID] [--verbose]

THRESHOLD=1048576  # 默认 1MB
PID=""
VERBOSE=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --threshold) THRESHOLD="$2"; shift 2 ;;
    --pid) PID="$2"; shift 2 ;;
    --verbose|-v) VERBOSE=1; shift ;;
    *) echo "Usage: $0 [--threshold BYTES] [--pid PID] [--verbose]"; exit 1 ;;
  esac
done

THRESHOLD_MB=$((THRESHOLD / 1048576))
echo "========================================"
echo "大对象分配热点检测"
echo "阈值: ${THRESHOLD_MB}MB (${THRESHOLD} bytes)"
[[ -n "$PID" ]] && echo "目标PID: $PID"
echo "========================================"

# 1. /proc/pid/maps 大块映射扫描
echo ""
echo "[1/4] 映射段大小分析"
echo "----------------------------------------"
if [[ -n "$PID" ]] && [[ -r /proc/$PID/maps ]]; then
  echo "超过 ${THRESHOLD_MB}MB 的映射段:"
  awk -v thr="$THRESHOLD" '{
    split($1, a, "-");
    size = strtonum("0x" a[2]) - strtonum("0x" a[1]);
    if(size > thr) printf "  %6.1f MB  %-50s %s\n", size/1048576, $NF, $1;
  }' /proc/$PID/maps 2>/dev/null | sort -rn | head -20
elif [[ -z "$PID" ]]; then
  echo "TOP 20 进程中大映射段:"
  for p in $(ps aux --sort=-%mem | awk 'NR>1 && NR<21 {print $2}'); do
    if [[ -r /proc/$p/maps ]]; then
      total=$(awk -v thr="$THRESHOLD" '{
        split($1,a,"-"); size=strtonum("0x" a[2])-strtonum("0x" a[1]);
        if(size>thr) s+=size
      } END {print s/1048576}' /proc/$p/maps 2>/dev/null)
      if (( $(echo "$total > 0" | bc -l 2>/dev/null) )); then
        name=$(cat /proc/$p/comm 2>/dev/null)
        echo "  PID=$p ($name): ${total}MB 大块内存"
      fi
    fi
  done
else
  echo "WARNING: PID $PID 不可访问"
fi

# 2. THP (透明大页) 使用
echo ""
echo "[2/4] 透明大页使用"
echo "----------------------------------------"
if [[ -n "$PID" ]] && [[ -r /proc/$PID/smaps ]]; then
  THP_KB=$(grep "AnonHugePages:" /proc/$PID/smaps 2>/dev/null | awk '{s+=$2} END {print s}')
  echo "THP 总计: ${THP_KB:-0} KB"
fi

if [[ -f /sys/kernel/mm/transparent_hugepage/enabled ]]; then
  echo "THP 状态: $(cat /sys/kernel/mm/transparent_hugepage/enabled)"
fi

# 3. 大页分配统计
echo ""
echo "[3/4] 大页分配统计"
echo "----------------------------------------"
if [[ -f /proc/meminfo ]]; then
  grep -E "HugePages|Hugepage" /proc/meminfo
fi

# 4. 分配热点建议
echo ""
echo "[4/4] 优化建议"
echo "----------------------------------------"
THP_KB=${THP_KB:-0}
if [[ "$THP_KB" -gt 1048576 ]]; then
  echo "- 检测到 ${THP_KB}MB THP 使用，若为数据库类应用建议关闭 THP"
fi
echo "- 大对象阈值: ${THRESHOLD_MB}MB"
echo "- 建议检查 mmap 映射和堆分配策略"
echo "- 使用 perf record -e syscalls:sys_enter_brk 追踪 brk 调用"

echo ""
echo "========================================"
echo "检测完成"
echo "========================================"
