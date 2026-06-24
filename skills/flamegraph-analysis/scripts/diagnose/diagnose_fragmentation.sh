#!/bin/bash
set -euo pipefail
# diagnose_fragmentation.sh - 内存碎片化检测
# 检查: 外部碎片率、Slab 利用率、分配大小分布
# 使用: ./diagnose_fragmentation.sh [--threshold PCT] [--verbose]

THRESHOLD=30
VERBOSE=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --threshold) THRESHOLD="$2"; shift 2 ;;
    --verbose|-v) VERBOSE=1; shift ;;
    *) echo "Usage: $0 [--threshold PCT] [--verbose]"; exit 1 ;;
  esac
done

echo "========================================"
echo "内存碎片化检测报告"
echo "========================================"

# 1. 外部碎片检查 (buddyinfo)
echo ""
echo "[1/4] 外部碎片分析 (buddyinfo)"
echo "----------------------------------------"
if [[ -r /proc/buddyinfo ]]; then
  cat /proc/buddyinfo
else
  echo "WARNING: /proc/buddyinfo 不可读"
fi

# 计算碎片率
FRAG_RATE=$(awk '
  {
    max_order_free = 0;
    total_free = 0;
    for(i=4;i<=NF;i++) {
      total_free += $i * 2^(i-4);
      if($i > 0) max_order = i-4;
    }
    if(total_free > 0) {
      max_contig = 2^max_order;
      rate = 1 - (max_contig * 4096) / (total_free * 4096);
      printf "Node %s: 碎片率=%.1f%% 最大连续=%dMB 合计=%dMB\n", $2, rate*100, max_contig*4/1024, total_free*4/1024;
    }
  }' /proc/buddyinfo 2>/dev/null)

echo ""
echo "$FRAG_RATE"

# 2. Slab 利用率
echo ""
echo "[2/4] Slab 利用率分析"
echo "----------------------------------------"
if [[ -r /proc/slabinfo ]]; then
  TOTAL_SLAB=$(awk 'NR>2 {a+=$2*$4} END {print a/1024}' /proc/slabinfo)
  USED_SLAB=$(awk 'NR>2 {a+=$3*$4} END {print a/1024}' /proc/slabinfo)
  UTIL_RATE=$(awk "BEGIN {printf \"%.1f\", $USED_SLAB/$TOTAL_SLAB*100}")
  echo "Slab 总计: ${TOTAL_SLAB%.*} KB"
  echo "Slab 使用: ${USED_SLAB%.*} KB"
  echo "Slab 利用率: ${UTIL_RATE}%"

  # 低利用率缓存
  echo ""
  echo "低利用率缓存 (< 30%):"
  cat /proc/slabinfo | awk 'NR>2 && $3>0 && $4/$3 < 0.3 {printf "  %-30s objects=%6d active=%6d 利用率=%3.0f%%\n", $1, $2, $3, $4/$3*100}' | sort -k5 -rn | head -20
else
  echo "WARNING: /proc/slabinfo 不可读"
fi

# 3. 页分配分布
echo ""
echo "[3/4] 页分配分布"
echo "----------------------------------------"
if [[ -r /proc/pagetypeinfo ]]; then
  grep -E "Node|DMA|Normal|Movable|Reclaimable|Unmovable" /proc/pagetypeinfo | head -30
else
  echo "WARNING: /proc/pagetypeinfo 不可读"
fi

# 4. 碎片化等级判定
echo ""
echo "[4/4] 碎片化等级判定"
echo "----------------------------------------"

FRAG_NUM=$(echo "$FRAG_RATE" | grep -oP '碎片率=\K[0-9.]+' | head -1)
FRAG_NUM=${FRAG_NUM:-0}

if (( $(echo "$FRAG_NUM < 10" | bc -l 2>/dev/null) )); then
  echo "等级: 正常 (碎片率 ${FRAG_NUM}%)"
  echo "建议: 无需处理"
elif (( $(echo "$FRAG_NUM < 30" | bc -l 2>/dev/null) )); then
  echo "等级: 轻度 (碎片率 ${FRAG_NUM}%)"
  echo "建议: 监控趋势，关注内存使用变化"
elif (( $(echo "$FRAG_NUM < 50" | bc -l 2>/dev/null) )); then
  echo "等级: 严重 (碎片率 ${FRAG_NUM}%)"
  echo "建议: 触发碎片整理 (echo 1 > /proc/sys/vm/compact_memory)"
else
  echo "等级: 危急 (碎片率 ${FRAG_NUM}%)"
  echo "建议: 需立即处理，考虑重启或迁移"
fi

echo ""
echo "========================================"
echo "检测完成"
echo "========================================"
