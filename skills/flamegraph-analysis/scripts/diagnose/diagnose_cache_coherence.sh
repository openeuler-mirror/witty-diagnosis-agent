#!/bin/bash
set -euo pipefail
# diagnose_cache_coherence.sh — Cache coherence 开销分析
# 检查: cache miss 率、LLC miss 率、缓存一致性流量
# 使用: ./diagnose_cache_coherence.sh [--duration SEC] [--verbose]

DURATION=5
VERBOSE=0
while [[ $# -gt 0 ]]; do
  case $1 in --duration) DURATION="$2"; shift 2;; --verbose|-v) VERBOSE=1;; *) break;; esac; shift
done

echo "========================================"
echo "Cache Coherence 开销分析"
echo "采样时长: ${DURATION}s"
echo "========================================"

HAS_PERF=0
command -v perf &>/dev/null && HAS_PERF=1

# 1. 环境检查
echo ""
echo "[1/5] 环境检查"
echo "----------------------------------------"
echo "CPU: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
echo "核心数: $(nproc)"
if [[ $HAS_PERF -eq 1 ]]; then
  echo "perf: 可用"
else
  echo "perf: 不可用 (安装: apt install linux-tools-common)"
fi

# 2. Cache miss 分析
echo ""
echo "[2/5] Cache Miss 分析"
echo "----------------------------------------"
if [[ $HAS_PERF -eq 1 ]]; then
  perf stat -e cache-misses,cache-references,LLC-loads,LLC-stores -a --sleep $DURATION 2>&1 | tail -10
else
  echo "perf 不可用，尝试读取 /sys/devices/cpu/events/"
  for event in cache-misses cache-references; do
    ev_file="/sys/devices/cpu/events/$event"
    [[ -r "$ev_file" ]] && echo "$event: $(cat $ev_file)" || echo "$event: N/A"
  done
fi

# 3. Cache 信息
echo ""
echo "[3/5] Cache 信息"
echo "----------------------------------------"
for level in L1 L2 L3; do
  for type in data instruction unified; do
    size=$(grep "${level}.*${type}" /proc/cpuinfo 2>/dev/null | head -1 | awk '{print $3}')
    [[ -n "$size" ]] && echo "${level} ${type}: ${size}KB" && break
  done
done

# 4. snoop/一致性流量
echo ""
echo "[4/5] 缓存一致性流量"
echo "----------------------------------------"
if [[ $HAS_PERF -eq 1 ]]; then
  # 尝试列出 snoop/HITM 相关事件
  HITM=$(perf list 2>/dev/null | grep -i "hitm\|snoop\|coheren" | head -5)
  if [[ -n "$HITM" ]]; then
    echo "一致性事件:"
    echo "$HITM"
  else
    echo "HITM/snoop 事件不可用 (需要特定硬件)"
  fi
else
  echo "需要 perf 支持"
fi

# 5. 结论
echo ""
echo "[5/5] 诊断结论"
echo "----------------------------------------"
echo "建议:"
echo "- 如果 cache miss rate > 10%，可能存在 false sharing"
echo "- 如果 LLC load miss > 30%，检查数据访问局部性"
echo "- 多线程应用关注 snoop/HITM 占比"

echo ""
echo "========================================"
echo "检测完成"
echo "========================================"
