#!/bin/bash
set -euo pipefail
# diagnose_thread_pool.sh — 线程池饱和检测
# 检查: 线程状态分布、线程数、队列积压趋势
# 使用: ./diagnose_thread_pool.sh [--pid PID] [--verbose]

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
echo "线程池饱和检测"
[[ -n "$PID" ]] && echo "目标PID: $PID"
echo "========================================"

# 1. 系统线程限制
echo ""
echo "[1/5] 系统线程限制"
echo "----------------------------------------"
THREADS_MAX=$(cat /proc/sys/kernel/threads-max 2>/dev/null || echo "N/A")
echo "系统最大线程数: $THREADS_MAX"
SYS_THREADS=$(ps -eo pid | wc -l)
echo "当前总线程数: $SYS_THREADS"
if [[ "$THREADS_MAX" != "N/A" ]]; then
  PCT=$((SYS_THREADS * 100 / THREADS_MAX))
  echo "线程使用率: ${PCT}%"
fi

# 2. 进程线程信息
echo ""
echo "[2/5] 进程线程分析"
echo "----------------------------------------"
if [[ -n "$PID" ]] && [[ -d /proc/$PID ]]; then
  THREAD_COUNT=$(ls /proc/$PID/task 2>/dev/null | wc -l)
  echo "进程线程数: $THREAD_COUNT"
  
  if [[ -d /proc/$PID/task ]]; then
    STATES=$(for tid in /proc/$PID/task/*/stat; do
      [[ -r "$tid" ]] || continue
      state=$(awk '{print $3}' "$tid" 2>/dev/null)
      echo "$state"
    done | sort | uniq -c | sort -rn)
  fi
  echo "线程状态分布:"
  echo "$STATES"
  
  # CPU亲和性
  AFFINITY=$(taskset -pc $PID 2>/dev/null)
  echo "CPU亲和性: $AFFINITY"
fi

# 3. 上下文切换
echo ""
echo "[3/5] 上下文切换分析"
echo "----------------------------------------"
CTXT_BEFORE=$(awk '/ctxt/ {print $2}' /proc/stat)
sleep 2
CTXT_AFTER=$(awk '/ctxt/ {print $2}' /proc/stat)
CTXT_RATE=$(( (CTXT_AFTER - CTXT_BEFORE) / 2 ))
CPU_COUNT=$(nproc)
echo "上下文切换速率: $CTXT_RATE/s"
echo "每核速率: $((CTXT_RATE / CPU_COUNT))/s"
if [[ $CTXT_RATE -gt $((CPU_COUNT * 50000)) ]]; then
  echo "⚠ 上下文切换频繁 (> 50000/核/s)"
fi

# 4. 运行队列
echo ""
echo "[4/5] 运行队列分析"
echo "----------------------------------------"
LOAD=$(cat /proc/loadavg)
echo "负载均值: $LOAD"
LOAD_1=$(echo $LOAD | awk '{print $1}')
if [[ $(echo "$LOAD_1 > $CPU_COUNT * 2" | bc -l 2>/dev/null) -eq 1 ]]; then
  echo "⚠ 运行队列超过核心数2倍，可能存在线程池饱和"
fi

# 5. 结论
echo ""
echo "[5/5] 诊断结论"
echo "----------------------------------------"
if [ -n "$PID" ] && [ -d /proc/$PID ]; then
  PCT=${PCT:-0}
  if [[ $PCT -gt 85 ]]; then
    echo "⚠ 线程使用率 ${PCT}% > 85%，线程池可能饱和"
  elif [[ $PCT -gt 60 ]]; then
    echo "- 线程使用率 ${PCT}%，处于警告范围"
  else
    echo "- 线程使用率 ${PCT}%，正常"
  fi
fi

echo ""
echo "========================================"
echo "检测完成"
echo "========================================"
