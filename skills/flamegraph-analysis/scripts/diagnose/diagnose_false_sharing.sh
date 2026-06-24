#!/bin/bash
set -euo pipefail
# diagnose_false_sharing.sh - False sharing 缓存行竞争检测
# 检测多线程环境下缓存行争用
# 使用: ./diagnose_false_sharing.sh [--pid PID] [--duration SEC] [--verbose]

PID=""
DURATION=10
VERBOSE=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --pid) PID="$2"; shift 2 ;;
    --duration) DURATION="$2"; shift 2 ;;
    --verbose|-v) VERBOSE=1; shift ;;
    *) echo "Usage: $0 [--pid PID] [--duration SEC] [--verbose]"; exit 1 ;;
  esac
done

echo "========================================"
echo "False Sharing 检测"
[[ -n "$PID" ]] && echo "目标PID: $PID"
echo "采样时长: ${DURATION}s"
echo "========================================"

# 1. 检测 perf 支持
echo ""
echo "[1/5] 环境检查"
echo "----------------------------------------"
HAS_C2C=0
if perf c2c 2>&1 | grep -q "usage"; then
  HAS_C2C=1
  echo "perf c2c: 可用"
else
  echo "perf c2c: 不可用 (需要 Linux 4.10+ 和特定硬件)"
fi

perf stat -e cache-misses,cache-references ls >/dev/null 2>&1
if [[ $? -eq 0 ]]; then
  echo "perf stat cache events: 可用"
else
  echo "perf stat cache events: 不可用"
fi

# 2. Cache miss 率分析
echo ""
echo "[2/5] Cache Miss 率分析"
echo "----------------------------------------"
PERF_CMD="perf stat -e cache-misses,cache-references"
[[ -n "$PID" ]] && PERF_CMD="$PERF_CMD -p $PID"
PERF_CMD="$PERF_CMD --sleep $DURATION 2>&1"

CACHE_STATS=$(eval $PERF_CMD)
echo "$CACHE_STATS"

MISSES=$(echo "$CACHE_STATS" | grep "cache-misses" | awk '{print $1}' | sed 's/,//g')
REFS=$(echo "$CACHE_STATS" | grep "cache-references" | awk '{print $1}' | sed 's/,//g')

if [[ -n "$MISSES" ]] && [[ -n "$REFS" ]] && [[ "$REFS" -gt 0 ]]; then
  MISS_RATE=$(echo "scale=2; $MISSES * 100 / $REFS" | bc)
  echo ""
  echo "Cache miss rate: ${MISS_RATE}%"
else
  MISS_RATE=0
  echo "Cache miss rate: N/A"
fi

# 3. perf c2c 详细分析
echo ""
echo "[3/5] 缓存行竞争分析"
echo "----------------------------------------"
if [[ $HAS_C2C -eq 1 ]]; then
  C2C_CMD="perf c2c record -a"
  [[ -n "$PID" ]] && C2C_CMD="perf c2c record"
  C2C_CMD="$C2C_CMD -- sleep $DURATION 2>/dev/null"
  
  echo "采集 c2c 数据 (${DURATION}s)..."
  eval $C2C_CMD
  
  if [[ -f perf.data ]]; then
    echo ""
    echo "c2c 统计摘要:"
    perf c2c report --stats 2>/dev/null | head -30
    
    echo ""
    echo "热点缓存行:"
    perf c2c report 2>/dev/null | head -20
    
    rm -f perf.data
  else
    echo "c2c 数据采集失败"
  fi
else
  echo "perf c2c 不可用，尝试 perf mem:"
  perf mem record -a -- sleep $DURATION 2>/dev/null
  if [[ -f perf.data ]]; then
    perf mem report 2>/dev/null | head -20
    rm -f perf.data
  else
    echo "perf mem 不可用"
  fi
fi

# 4. 多线程扩展性检查
echo ""
echo "[4/5] 多线程扩展性检查"
echo "----------------------------------------"
if [[ -n "$PID" ]]; then
  THREAD_COUNT=$(ls /proc/$PID/task 2>/dev/null | wc -l)
  echo "线程数: $THREAD_COUNT"
  if [[ $THREAD_COUNT -gt 4 ]]; then
    echo "多线程进程，建议关注线程间数据共享模式"
  fi
fi

# 5. 结论与建议
echo ""
echo "[5/5] 诊断结论"
echo "----------------------------------------"
if (( $(echo "$MISS_RATE > 10" | bc -l 2>/dev/null) )); then
  echo "⚠ Cache miss 率偏高 (${MISS_RATE}%)，可能存在 false sharing"
  echo ""
  echo "修复建议:"
  echo "  1. 对热点变量添加 __attribute__((aligned(64))) 填充至缓存行大小"
  echo "  2. 使用 pread/pwrite 替代全局锁"
  echo "  3. 重新排列结构体字段，将读频繁字段分开到不同缓存行"
  echo "  4. 使用 __sync_fetch_and_add 等原子操作替代锁"
elif (( $(echo "$MISS_RATE > 5" | bc -l 2>/dev/null) )); then
  echo "- Cache miss 率 ${MISS_RATE}%，轻度偏高，建议监控"
else
  echo "- Cache miss 率 ${MISS_RATE}%，正常范围"
fi

echo ""
echo "========================================"
echo "检测完成"
echo "========================================"
