#!/bin/bash
set -euo pipefail
# diagnose_parallelism.sh — 并行度不足识别
# 检查: CPU 利用率 vs 核心数、运行队列、GPU 利用率
# 使用: ./diagnose_parallelism.sh [--verbose]

VERBOSE=0
while [[ $# -gt 0 ]]; do case $1 in --verbose|-v) VERBOSE=1;; *) break;; esac; shift; done

echo "========================================"
echo "并行度不足识别"
echo "========================================"

CPU_CORES=$(nproc)
LOAD=$(cat /proc/loadavg | awk '{print $1}')

# 1. CPU 利用率
echo ""
echo "[1/4] CPU 利用率"
echo "----------------------------------------"
CPU_IDLE=$(top -b -n1 2>/dev/null | grep "%Cpu" | awk '{print $8}')
if [[ -n "$CPU_IDLE" ]]; then
  CPU_USED=$((100 - ${CPU_IDLE%.*}))
  echo "CPU 使用率: $CPU_USED%"
  echo "可用核心: $CPU_CORES"
  PARALLEL_PCT=$((CPU_USED * 100 / (CPU_CORES * 1)))
  echo "并行利用率: ${PARALLEL_PCT}%"
fi

# 2. 运行队列分析
echo ""
echo "[2/4] 运行队列分析"
echo "----------------------------------------"
echo "负载均值: $(cat /proc/loadavg)"
echo "运行队列/核心: $(echo "scale=2; $LOAD / $CPU_CORES" | bc -l 2>/dev/null)"

# 3. 进程状态分布
echo ""
echo "[3/4] 进程状态分布"
echo "----------------------------------------"
for state in R S D T Z; do
  count=$(ps -eo stat 2>/dev/null | grep -c "^$state" || echo 0)
  echo "  State $state: $count"
done

# 每核心可运行线程
RUNNABLE=$(ps -eo stat 2>/dev/null | grep -c "^R" || echo 0)
echo "可运行线程: $RUNNABLE (每核: $(echo "scale=1; $RUNNABLE/$CPU_CORES" | bc -l 2>/dev/null))"

# 4. 结论
echo ""
echo "[4/4] 诊断结论"
echo "----------------------------------------"
CPU_USED=${CPU_USED:-0}
if [[ $CPU_USED -lt 50 ]] && [[ $(echo "$LOAD < $CPU_CORES * 0.5" | bc -l 2>/dev/null) -eq 1 ]]; then
  echo "⚠ 并行度不足: CPU ${CPU_USED}%, 队列 ${LOAD} < 核心 ${CPU_CORES} 的一半"
  echo "  可能原因: 应用未充分利用多核、I/O 等待、锁竞争"
elif [[ $CPU_USED -lt 50 ]]; then
  echo "⚠ CPU 利用率 ${CPU_USED}% 偏低"
elif [[ $CPU_USED -gt 80 ]]; then
  echo "- CPU 利用率 ${CPU_USED}%，接近饱和"
else
  echo "- CPU 利用率 ${CPU_USED}%，并行度正常"
fi

echo ""
echo "========================================"
echo "检测完成"
echo "========================================"
