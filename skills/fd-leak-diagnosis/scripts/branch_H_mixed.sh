#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_H_mixed.sh
# 用途：混合/复杂 FD 泄漏诊断 — 全链路综合分析
# 使用：bash branch_H_mixed.sh [target_pid] [--full]
# 参数：
#   $1  目标 PID（可选）
#   $2  --full  执行完整诊断（含 strace 采样）
# =============================================================================

set -euo pipefail

TARGET_PID="${1:-}"
FULL_MODE=false
[[ "${2:-}" == "--full" ]] && FULL_MODE=true

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  echo "用途：混合/复杂 FD 泄漏全链路诊断"
  echo "使用：bash $0 [target_pid] [--full]"
  echo "  target_pid: 目标 PID（可选）"
  echo "  --full:      执行完整诊断（含 strace 系统调用追踪）"
  exit 0
fi

echo "=================================================================="
echo " 分支H：混合/复杂 FD 泄漏 —— 全链路综合分析"
echo "=================================================================="

# H1. 系统基本信息
echo ""
echo "【H1】系统级概览"
echo "------------------------------------------------------------------"
if [[ -f /proc/sys/fs/file-nr ]]; then
  read -r allocated free max <<< "$(cat /proc/sys/fs/file-nr)"
  echo "  file-nr: $allocated / $free / $max"
fi
echo "  CLOSE_WAIT总数: $(ss -Htn state close-wait 2>/dev/null | wc -l)"

# H2. 进程排行
echo ""
echo "【H2】FD 消费 Top 10 进程"
echo "------------------------------------------------------------------"
for pid_dir in /proc/[0-9]*/; do
  pid=$(basename "$pid_dir" | tr -d '/')
  c=$(ls -1 "/proc/$pid/fd" 2>/dev/null | wc -l)
  lim=$(cat "/proc/$pid/limits" 2>/dev/null | grep "Max open files" | awk '{print $4}')
  name=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ' | head -c 40)
  [[ $c -gt 0 ]] && echo "$c $pid ${lim:-N/A} ${name:--}"
done | sort -rn -k1 | head -10 | awk '{printf "  FD数:%-8s PID:%-8s 限制:%-8s %s\n", $1, $2, $3, $4}'

# H3. 目标进程综合诊断
if [[ -n "$TARGET_PID" ]] && [[ -d "/proc/${TARGET_PID}" ]]; then
  echo ""
  echo "【H3】目标 PID ${TARGET_PID} 综合诊断"
  echo "------------------------------------------------------------------"

  # 基础信息
  name=$(cat "/proc/${TARGET_PID}/cmdline" 2>/dev/null | tr '\0' ' ' | head -c 60)
  fd_count=$(ls -1 "/proc/${TARGET_PID}/fd" 2>/dev/null | wc -l)
  echo "  进程: ${name:-unknown}"
  echo "  FD 数: ${fd_count}"

  # ulimit
  if [[ -r "/proc/${TARGET_PID}/limits" ]]; then
    grep "Max open files" "/proc/${TARGET_PID}/limits"
    soft=$(grep "Max open files" "/proc/${TARGET_PID}/limits" | awk '{print $4}')
    ratio=$(awk "BEGIN {printf \"%.1f\", ${fd_count} / ${soft} * 100}" 2>/dev/null || echo "N/A")
    echo "  使用率: ${ratio}%"
  fi

  # FD 类型分布
  echo ""
  echo "  FD 类型分布:"
  if command -v lsof &>/dev/null; then
    lsof -p "${TARGET_PID}" 2>/dev/null | awk '{print $5}' | sort | uniq -c | sort -rn | head -8
  fi

  # CLOSE_WAIT
  cw=$(ss -tnp state close-wait 2>/dev/null | grep -c "pid=${TARGET_PID}" || echo 0)
  echo "  CLOSE_WAIT: ${cw}"

  # epoll
  epc=$(ls -la "/proc/${TARGET_PID}/fd" 2>/dev/null | grep -c "eventpoll" || echo 0)
  echo "  epoll FD: ${epc}"

  # inotify
  ino=$(ls -la "/proc/${TARGET_PID}/fd" 2>/dev/null | grep -c "inotify" || echo 0)
  echo "  inotify FD: ${ino}"

  # 已删除文件
  del=0
  for f in "/proc/${TARGET_PID}/fd"/*; do
    [[ "$(readlink "$f" 2>/dev/null)" == *"(deleted)"* ]] && del=$((del + 1))
  done
  echo "  已删除但仍持有的文件: ${del}"

  # 综合分析
  echo ""
  echo "  ═══ 综合分析 ═══"
  issues=()
  if [[ $(echo "${ratio:-0} > 80" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then issues+=("FD 使用率 ${ratio}% > 80%"); fi
  if [[ $cw -gt 1000 ]]; then issues+=("CLOSE_WAIT ${cw} > 1000"); fi
  if [[ $epc -gt 2 ]]; then issues+=("epoll FD ${epc} > 2"); fi
  if [[ $ino -gt 2 ]]; then issues+=("inotify FD ${ino} > 2"); fi
  if [[ $del -gt 0 ]]; then issues+=("已删除文件 ${del} 个"); fi

  if [[ ${#issues[@]} -eq 0 ]]; then
    echo "  未发现明显异常"
  else
    echo "  发现 ${#issues[@]} 个问题:"
    for issue in "${issues[@]}"; do echo "    ⚠ ${issue}"; done
  fi

  # strace（仅 --full 模式）
  if $FULL_MODE && command -v strace &>/dev/null; then
    echo ""
    echo "  strace 系统调用采样（10 秒）..."
    timeout 10 strace -p "${TARGET_PID}" -e trace=open,openat,creat,socket,close -c 2>&1 || true
  fi
fi

echo ""
echo "=================================================================="
echo " 分支H 诊断结论"
echo "=================================================================="
cat << 'CONCLUSION'
  目标 PID：<PID>
  进程名：<name>
  FD 总数：<N> / <soft_limit>（<ratio>%）
  CLOSE_WAIT：<N>  | epoll：<N>  | inotify：<N>  | 已删除文件：<N>
  问题数：<N>
  主要问题：<Top 问题描述>
  判定：[正常/可疑/泄漏/严重]
  建议：
    <综合修复建议>
CONCLUSION
