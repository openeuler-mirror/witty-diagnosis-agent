#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_D_fd_leak.sh
# 用途：文件描述符/资源泄漏诊断 — 双轨分析
# 使用：bash branch_D_fd_leak.sh [output_dir]
# 参数：
#   $1  输出目录（来自 01_baseline_info.sh 的输出）
# =============================================================================

set -euo pipefail

OUT_DIR="${1:-/tmp/syscall_diag_$(date +%Y%m%d%H%M%S)}"

echo "=================================================================="
echo " 分支D：文件描述符/资源泄漏 —— 双轨分析"
echo "=================================================================="

BASELINE_TARGET="${OUT_DIR}/process_status.txt"
TARGET_PID=$(grep "^Pid:" "$BASELINE_TARGET" 2>/dev/null | awk '{print $2}' || echo "")

# --------------------------------------------------------------------------
# T1 - FD 现状
# --------------------------------------------------------------------------
echo ""
echo "【T1】FD 现状快照"
echo "------------------------------------------------------------------"
if [ -n "$TARGET_PID" ] && [ -d "/proc/${TARGET_PID}" ]; then
  FD_COUNT=$(ls /proc/${TARGET_PID}/fd 2>/dev/null | wc -l)
  FD_LIMIT=$(cat /proc/${TARGET_PID}/limits 2>/dev/null | grep "open files" | awk '{print $5}' || echo "N/A")

  echo "  当前 FD 数量: ${FD_COUNT}"
  echo "  FD 硬限制:    ${FD_LIMIT}"
  if [ "$FD_LIMIT" != "N/A" ] && [ "$FD_COUNT" -gt 0 ]; then
    USE_PCT=$(( FD_COUNT * 100 / $(echo $FD_LIMIT | grep -oP '\d+' || echo 1) ))
    echo "  使用率:       ${USE_PCT}%"
    [ "$USE_PCT" -gt 80 ] && echo "  ⚠ FD 使用率 > 80%，可能接近上限"
  fi

  echo ""
  echo "  FD 类型分布:"
  for fd_link in /proc/${TARGET_PID}/fd/*; do
    target=$(readlink "$fd_link" 2>/dev/null || echo "?")
    fd_num=$(basename "$fd_link")
    echo "    fd=${fd_num} -> ${target}"
  done 2>/dev/null | head -40

  echo ""
  echo "  FD 类型统计:"
  for fd_link in /proc/${TARGET_PID}/fd/*; do
    readlink "$fd_link" 2>/dev/null
  done 2>/dev/null | sed 's/[0-9].*$//' | sort | uniq -c | sort -rn | head -10 || true
else
  echo "  PID $TARGET_PID 不可用"
fi

echo ""

# --------------------------------------------------------------------------
# T2 - 泄漏趋势检测
# --------------------------------------------------------------------------
echo ""
echo "【T2】泄漏趋势检测（5 秒采样 3 次）"
echo "------------------------------------------------------------------"
if [ -n "$TARGET_PID" ] && [ -d "/proc/${TARGET_PID}" ]; then
  for i in 1 2 3; do
    count=$(ls /proc/${TARGET_PID}/fd 2>/dev/null | wc -l)
    echo "  采样 $i: FD=${count} (t=${i}s)"
    sleep 1
  done
  FIRST=$(ls /proc/${TARGET_PID}/fd 2>/dev/null | wc -l)
  sleep 2
  LAST=$(ls /proc/${TARGET_PID}/fd 2>/dev/null | wc -l)
  DIFF=$(( LAST - FIRST ))
  echo ""
  echo "  5 秒变化: ${DIFF} FD"
  if [ "$DIFF" -gt 10 ]; then
    echo "  🔴 FD 数量快速增长（+${DIFF}/5s），疑似泄漏"
  elif [ "$DIFF" -gt 0 ]; then
    echo "  🟡 FD 数量缓慢增长（+${DIFF}/5s），需持续观察"
  else
    echo "  🟢 FD 数量稳定（变化 ${DIFF}）"
  fi
fi

echo ""

# --------------------------------------------------------------------------
# T3 - strace FD 操作追踪
# --------------------------------------------------------------------------
echo ""
echo "【T3】strace FD 操作追踪（5s）"
echo "------------------------------------------------------------------"
if command -v strace &>/dev/null && [ -n "$TARGET_PID" ]; then
  timeout 5 strace -e trace=open,openat,close,dup,dup2,epoll_create,socket,accept -p "${TARGET_PID}" 2>&1 | \
    awk '{print $1}' | sort | uniq -c | sort -rn | head -10 || echo "  追踪失败"
fi

echo ""

# --------------------------------------------------------------------------
# T4 - mmap 映射分析
# --------------------------------------------------------------------------
echo ""
echo "【T4】mmap 映射分析"
echo "------------------------------------------------------------------"
if [ -n "$TARGET_PID" ]; then
  MAPS_COUNT=$(cat /proc/${TARGET_PID}/maps 2>/dev/null | wc -l || echo 0)
  MAX_MAP=$(sysctl vm.max_map_count 2>/dev/null | awk '{print $3}' || echo "N/A")
  echo "  当前映射区域: ${MAPS_COUNT}"
  echo "  max_map_count: ${MAX_MAP}"
  if [ "$MAX_MAP" != "N/A" ] && [ "$MAPS_COUNT" -gt 0 ]; then
    PCT=$(( MAPS_COUNT * 100 / MAX_MAP ))
    echo "  使用率: ${PCT}%"
    [ "$PCT" -gt 80 ] && echo "  ⚠ 映射区域接近上限"
  fi
fi

echo ""

# ==========================================================================
echo ""
echo "=================================================================="
echo " ▶ 内核语义轨道"
echo "=================================================================="
cat << 'SRCGUIDE'
  FD 泄漏常见原因:
    · 主循环中 open 后未 close（错误路径遗漏最常见）
    · accept 未设置 FD_CLOEXEC，fork 后泄漏到子进程
    · 连接池未正确回收
  
  排查方法:
    · strace -e trace=close -p <PID>      # 看 close 是否配对
    · lsof -p <PID> | wc -l              # 跨时间点对比
    · /proc/<PID>/fdinfo/<fd> pos=0     # pos 持续 0 说明未使用（可能是泄漏）

  mmap 泄漏:
    · strace -e trace=mmap,munmap -c -p <PID>
    · /proc/PID/maps 查看增长趋势
SRCGUIDE

echo ""
echo "=================================================================="
echo " ▶ 最终结论"
echo "=================================================================="
cat << 'CONCLUSION'

  故障模式: 文件描述符/资源泄漏
  处理建议:
    · 泄漏已确认 → 修复 open/accept 路径中遗漏的 close
    · FD 接近上限 → 增大 ulimit -n 或 fs.file-max
    · mmap 过多 → 检查 munmap 配对
    · 通用: strace -e trace=open,close -p <PID> 对比配对情况
    
    【验证】
      - 调整后观察 FD 数是否稳定或下降
CONCLUSION
