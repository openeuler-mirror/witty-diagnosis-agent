#!/bin/bash
set -euo pipefail
# diagnose_work_stealing.sh — Work stealing 不均衡分析
# 检查各 CPU 利用率分布、软硬中断分布、不均衡系数
# 使用: ./diagnose_work_stealing.sh [--verbose]

VERBOSE=0
while [[ $# -gt 0 ]]; do case $1 in --verbose|-v) VERBOSE=1;; *) break;; esac; shift; done

echo "========================================"
echo "Work Stealing 不均衡分析"
echo "========================================"

CPU_COUNT=$(nproc)

# 1. 各 CPU 利用率
echo ""
echo "[1/4] CPU 利用率分布"
echo "----------------------------------------"
if command -v mpstat &>/dev/null; then
  mpstat -P ALL 1 1 2>/dev/null | tail -n +4 | awk '{
    if($3 ~ /^[0-9]/) printf "CPU %s: %.1f%%\n", $3, $NF
  }'
else
  echo "mpstat not available"
fi

# 2. 不均衡系数计算
echo ""
echo "[2/4] 不均衡系数"
echo "----------------------------------------"
mpstat -P ALL 1 1 2>/dev/null | tail -n +4 | awk '
  /^[0-9]/ {
    vals[NR]=$NF; sum+=$NF; count++
  } END {
    if(count>0) {
      avg=sum/count; sq=0
      for(v in vals) sq+=((vals[v]-avg)^2)
      std=sqrt(sq/count)
      coeff=(avg>0?std/avg:0)
      printf "平均利用率: %.1f%%\n", avg
      printf "标准差: %.2f\n", std
      printf "不均衡系数: %.2f\n", coeff
      if(coeff<0.2) print "等级: 均衡"
      else if(coeff<0.5) print "等级: 轻度不均衡"
      else print "等级: 严重不均衡"
    }
  }' || echo "mpstat not available"

# 3. 软中断分布
echo ""
echo "[3/4] 软中断分布"
echo "----------------------------------------"
if [[ -r /proc/softirqs ]]; then
  head -1 /proc/softirqs
  for irq in TIMER NET_RX NET_TX BLOCK SCHED; do
    line=$(grep "^$irq" /proc/softirqs 2>/dev/null)
    if [[ -n "$line" ]]; then
      values=($line)
      echo "$irq: ${values[@]:1}"
    fi
  done
fi

# 4. 结论
echo ""
echo "[4/4] 诊断结论"
echo "----------------------------------------"
LOAD_1=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}')
echo "负载: $LOAD_1 / 核心: $CPU_COUNT"
echo "建议: 如果各 CPU 利用率偏差 > 20%，检查中断亲和性和绑核配置"

echo ""
echo "========================================"
echo "检测完成"
echo "========================================"
