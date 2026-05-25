#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_A_system_fd.sh
# 用途：系统级 FD 耗尽诊断 — L1 系统层深度分析
# 使用：bash branch_A_system_fd.sh
# 说明：无参数，仅检查系统全局 FD 状态
# =============================================================================

set -euo pipefail

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  echo "用途：系统级 FD 耗尽诊断"
  echo "使用：bash $0"
  echo "说明：检查 /proc/sys/fs/file-nr 及相关系统级 FD 参数"
  exit 0
fi

echo "=================================================================="
echo " 分支A：系统级 FD 耗尽 —— L1 系统层深度分析"
echo "=================================================================="

# A1. 系统 FD 水位
echo ""
echo "【A1】系统 FD 水位（/proc/sys/fs/file-nr）"
echo "------------------------------------------------------------------"
if [[ -f /proc/sys/fs/file-nr ]]; then
  read -r allocated free max <<< "$(cat /proc/sys/fs/file-nr)"
  usage_percent=$(awk "BEGIN {printf \"%.1f\", $allocated / $max * 100}")
  echo "  已分配: ${allocated}"
  echo "  空闲:   ${free}"
  echo "  最大:   ${max}"
  echo "  使用率: ${usage_percent}%"
  if [[ $(echo "${usage_percent} > 90" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
    echo "  状态: ⚠ 严重！系统 FD 即将耗尽"
  elif [[ $(echo "${usage_percent} > 80" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
    echo "  状态: ! 告警，系统 FD 水位偏高"
  else
    echo "  状态: 正常"
  fi
else
  echo "  /proc/sys/fs/file-nr 不可读"
fi

# A2. 内核日志告警
echo ""
echo "【A2】内核日志 FD 耗尽告警"
echo "------------------------------------------------------------------"
if dmesg 2>/dev/null | grep -qi "VFS: file-max limit" 2>/dev/null; then
  echo "  ⚠ 检测到系统级 FD 耗尽事件！"
  dmesg 2>/dev/null | grep "VFS: file-max" | tail -5
else
  echo "  无 file-max limit 告警记录"
fi

# A3. 系统限制参数
echo ""
echo "【A3】系统 FD 相关限制参数"
echo "------------------------------------------------------------------"
echo "  file-max:     $(cat /proc/sys/fs/file-max 2>/dev/null || echo 'N/A')"
echo "  file-nr:      $(cat /proc/sys/fs/file-nr 2>/dev/null || echo 'N/A')"
echo "  inotify max_user_watches:   $(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo 'N/A')"
echo "  inotify max_user_instances: $(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo 'N/A')"
echo "  epoll max_user_watches:     $(cat /proc/sys/fs/epoll/max_user_watches 2>/dev/null || echo 'N/A')"

# A4. 各进程 FD 使用汇总
echo ""
echo "【A4】系统各进程 FD 使用分布"
echo "------------------------------------------------------------------"
echo "  FD 数范围    进程数"
echo "  --------------------------------"
declare -a ranges=("1-100" "101-500" "501-1000" "1001-5000" "5001+")
declare -a counts=(0 0 0 0 0)
for pid_dir in /proc/[0-9]*/; do
  pid=$(basename "$pid_dir" | tr -d '/')
  c=$(ls -1 "/proc/$pid/fd" 2>/dev/null | wc -l) || continue
  if   [[ $c -le 100 ]];   then counts[0]=$((counts[0] + 1))
  elif [[ $c -le 500 ]];   then counts[1]=$((counts[1] + 1))
  elif [[ $c -le 1000 ]];  then counts[2]=$((counts[2] + 1))
  elif [[ $c -le 5000 ]];  then counts[3]=$((counts[3] + 1))
  else                         counts[4]=$((counts[4] + 1))
  fi
done
for i in "${!ranges[@]}"; do
  printf "  %-14s %d\n" "${ranges[$i]}" "${counts[$i]}"
done

echo ""
echo "=================================================================="
echo " 分支A 诊断结论"
echo "=================================================================="
cat << 'CONCLUSION'
  系统 FD 使用率：<usage_percent>%
  file-max：<max>
  内核告警：[有/无] VFS: file-max limit reached
  FD 分布：Top 进程占全部 FD 的 <估算百分比>%
  结论：<系统 FD 使用正常/偏高/严重>
  建议：
    - 若使用率 > 80% 且持续上升：排查 Top FD 消费进程
    - 若触发 file-max：考虑增大 fs.file-max
    - 若触发 inotify 限制：增大 fs.inotify.max_user_watches
CONCLUSION
