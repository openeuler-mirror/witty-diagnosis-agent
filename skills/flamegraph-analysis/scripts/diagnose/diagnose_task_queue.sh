#!/bin/bash
set -euo pipefail
# diagnose_task_queue.sh — 任务队列积压分析
# 检查: 生产消费速率差、网络/磁盘队列、IO 吞吐
# 使用: ./diagnose_task_queue.sh [--pid PID] [--verbose]

PID=""
VERBOSE=0
while [[ $# -gt 0 ]]; do
  case $1 in --pid) PID="$2"; shift 2;; --verbose|-v) VERBOSE=1;; *) break;; esac; shift
done

echo "========================================"
echo "任务队列积压分析"
[[ -n "$PID" ]] && echo "目标PID: $PID"
echo "========================================"

# 1. IO 吞吐（生产/消费速率）
echo ""
echo "[1/4] IO 吞吐分析"
echo "----------------------------------------"
if [[ -n "$PID" ]] && [[ -r /proc/$PID/io ]]; then
  echo "进程 IO 统计:"
  cat /proc/$PID/io | head -10
  
  # 计算读写速率
  R_BEFORE=$(awk '/read_bytes/ {print $2}' /proc/$PID/io)
  W_BEFORE=$(awk '/write_bytes/ {print $2}' /proc/$PID/io)
  sleep 2
  R_AFTER=$(awk '/read_bytes/ {print $2}' /proc/$PID/io)
  W_AFTER=$(awk '/write_bytes/ {print $2}' /proc/$PID/io)
  R_RATE=$(( (R_AFTER - R_BEFORE) / 2 ))
  W_RATE=$(( (W_AFTER - W_BEFORE) / 2 ))
  echo "读取速率: $R_RATE bytes/s"
  echo "写入速率: $W_RATE bytes/s"
  if [[ $W_RATE -gt $((R_RATE * 2)) ]] && [[ $R_RATE -gt 0 ]]; then
    echo "⚠ 写入速率远超读取速率，可能存在生产者积压"
  fi
fi

# 2. 网络队列
echo ""
echo "[2/4] 网络队列分析"
echo "----------------------------------------"
if command -v ss &>/dev/null; then
  CONN=$(ss -tn | wc -l)
  echo "TCP 连接数: $CONN"
fi
if command -v netstat &>/dev/null; then
  BACKLOG=$(netstat -tn 2>/dev/null | grep -c "SYN_RECV")
  echo "SYN_RECV (积压): $BACKLOG"
fi

# 3. 磁盘队列
echo ""
echo "[3/4] 磁盘队列分析"
echo "----------------------------------------"
for dev in /sys/block/*/queue/nr_requests; do
  if [[ -r "$dev" ]]; then
    name=$(echo $dev | cut -d/ -f4)
    req=$(cat $dev)
    echo "$name: 队列深度=$req"
  fi
done

# 4. 上下文切换
echo ""
echo "[4/4] 上下文切换速率"
echo "----------------------------------------"
CTXT_BEFORE=$(awk '/ctxt/ {print $2}' /proc/stat)
sleep 2
CTXT_AFTER=$(awk '/ctxt/ {print $2}' /proc/stat)
echo "上下文切换: $(( (CTXT_AFTER - CTXT_BEFORE) / 2 ))/s"
[[ -n "$PID" ]] && echo "提示: 可对比进程级 ctxt (cat /proc/$PID/status | grep context)"

echo ""
echo "========================================"
echo "检测完成"
echo "========================================"
