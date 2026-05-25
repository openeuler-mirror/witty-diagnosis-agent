#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_B_process_fd.sh
# 用途：进程级 FD 泄漏诊断 — L2 进程层深度分析
# 使用：bash branch_B_process_fd.sh <target_pid>
# 参数：
#   $1  目标 PID
# =============================================================================

set -euo pipefail

TARGET_PID="${1:-}"

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]] || [[ -z "$TARGET_PID" ]]; then
  echo "用途：进程级 FD 泄漏诊断"
  echo "使用：bash $0 <target_pid>"
  echo "  target_pid: 目标进程 PID"
  exit 0
fi

if [[ ! -d "/proc/${TARGET_PID}" ]]; then
  echo "[错误] PID ${TARGET_PID} 不存在"
  exit 1
fi

echo "=================================================================="
echo " 分支B：进程级 FD 泄漏 —— L2 进程层深度分析"
echo " 目标 PID: ${TARGET_PID}"
echo "=================================================================="

# B1. 基础信息
echo ""
echo "【B1】进程基础信息"
echo "------------------------------------------------------------------"
cmdline=$(cat "/proc/${TARGET_PID}/cmdline" 2>/dev/null | tr '\0' ' ' | head -c 100)
echo "  进程名: ${cmdline:-unknown}"
fd_count=$(ls -1 "/proc/${TARGET_PID}/fd" 2>/dev/null | wc -l)
echo "  当前 FD 数: ${fd_count}"
if [[ -r "/proc/${TARGET_PID}/limits" ]]; then
  grep "Max open files" "/proc/${TARGET_PID}/limits"
  soft_limit=$(grep "Max open files" "/proc/${TARGET_PID}/limits" | awk '{print $4}')
  hard_limit=$(grep "Max open files" "/proc/${TARGET_PID}/limits" | awk '{print $5}')
  ratio=$(awk "BEGIN {printf \"%.1f\", ${fd_count} / ${soft_limit} * 100}" 2>/dev/null || echo "N/A")
  echo "  使用率: ${ratio}% (${fd_count}/${soft_limit})"
fi

# B2. FD 类型分布
echo ""
echo "【B2】FD 类型分布（按类型统计，Top 10）"
echo "------------------------------------------------------------------"
if command -v lsof &>/dev/null; then
  lsof -p "${TARGET_PID}" 2>/dev/null | awk '{print $5}' | sort | uniq -c | sort -rn | head -10
else
  echo "  lsof 不可用，从 /proc/fd 推断类型："
  for fdlink in "/proc/${TARGET_PID}/fd"/*; do
    target=$(readlink "$fdlink" 2>/dev/null || echo "?")
    case "$target" in
      socket:*)       echo "socket" ;;
      pipe:*)         echo "pipe" ;;
      anon_inode:*)   echo "${target#anon_inode:}" ;;
      /dev/pts/*)     echo "pty" ;;
      /dev/*)         echo "device" ;;
      *)              echo "file/other" ;;
    esac
  done 2>/dev/null | sort | uniq -c | sort -rn | head -10
fi

# B3. FD 清单 - 重复条目检测
echo ""
echo "【B3】FD 清单分析（重复条目检测）"
echo "------------------------------------------------------------------"
echo "  相同目标的 FD 数（>3 个相同的可能可疑）："
readlink "/proc/${TARGET_PID}/fd"/* 2>/dev/null | sort | uniq -c | sort -rn | head -15

# B4. 进程 FD 上限评估
echo ""
echo "【B4】泄漏评估"
echo "------------------------------------------------------------------"
if [[ -n "${soft_limit:-}" ]]; then
  if [[ $(echo "${ratio:-0} > 80" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
    echo "  状态: ⚠ 严重！FD 使用率 ${ratio}% 超过 80%"
  elif [[ $(echo "${ratio:-0} > 60" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
    echo "  状态: ! 可疑，FD 使用率 ${ratio}% 超过 60%"
  else
    echo "  状态: 正常，FD 使用率 ${ratio}%"
  fi
fi

# B5. 趋势建议
echo ""
echo "【B5】趋势监控建议"
echo "------------------------------------------------------------------"
echo "  建议在 5-10 分钟后再次运行本脚本，对比 FD 数量变化。"
echo "  实时监控: watch -n 5 'ls -1 /proc/${TARGET_PID}/fd | wc -l'"
echo "  若 FD 数持续增长（>1 FD/min）则为泄漏。"
echo ""
echo "  结合其他分支做进一步诊断："
echo "    - 大量 socket     → bash branch_C_close_wait.sh ${TARGET_PID}"
echo "    - 大量 eventpoll  → bash branch_D_epoll.sh ${TARGET_PID}"
echo "    - 大量 inotify    → bash branch_E_inotify.sh ${TARGET_PID}"
echo "    - 需 strace 确认  → bash branch_F_syscall.sh ${TARGET_PID}"

echo ""
echo "=================================================================="
echo " 分支B 诊断结论"
echo "=================================================================="
cat << 'CONCLUSION'
  目标 PID：<PID>
  进程名：<name>
  FD 数量：<N> / ulimit <soft>（<ratio>%）
  FD 类型分布：<Top3 类型及数量>
  泄漏判定：[正常/可疑/泄漏]
  建议：<进一步操作>
CONCLUSION
