#!/usr/bin/env bash
# =============================================================================
# 脚本：01_baseline_info.sh
# 用途：FD 泄漏基线信息采集与分支推荐（所有分析的第一步）
# 使用：bash 01_baseline_info.sh [target_pid] [target_process_name]
# 参数：
#   $1  目标 PID（可选；不提供则扫描全系统）
#   $2  进程名关键字（可选；模糊匹配）
# =============================================================================

set -euo pipefail

TARGET_PID="${1:-}"
TARGET_NAME="${2:-}"

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  echo "用途：FD 泄漏基线信息采集与分支推荐"
  echo "使用：bash $0 [target_pid] [target_process_name]"
  echo ""
  echo "  target_pid:         目标 PID（不提供则扫描全系统 Top 进程）"
  echo "  target_process_name: 进程名关键字（可选，模糊匹配）"
  echo ""
  echo "输出内容："
  echo "  - 系统 FD 水位（file-nr / file-max）"
  echo "  - 系统关键 FD 限制（inotify / epoll）"
  echo "  - 进程 FD 排行 Top 10"
  echo "  - 目标进程 FD 详情（若指定）"
  echo "  - CLOSE_WAIT 数量"
  echo "  - 分支决策推荐"
  exit 0
fi

OUT_DIR="/tmp/fd_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "${OUT_DIR}"
echo "诊断输出目录: ${OUT_DIR}"

# =============================================================================
# L1: 系统级 FD 信息
# =============================================================================
echo ""
echo "=================================================================="
echo " L1: 系统级 FD 信息"
echo "=================================================================="

# 系统 FD 水位
if [[ -f /proc/sys/fs/file-nr ]]; then
  read -r allocated free max <<< "$(cat /proc/sys/fs/file-nr)"
  usage_percent=$(awk "BEGIN {printf \"%.1f\", $allocated / $max * 100}")
  echo "  file-nr: ${allocated} / ${free} / ${max}  (使用率 ${usage_percent}%)"
else
  echo "  [跳过] /proc/sys/fs/file-nr 不存在"
fi

# 内核告警
if dmesg 2>/dev/null | grep -qi "VFS: file-max limit" 2>/dev/null; then
  echo "  ⚠ 内核告警：存在 VFS: file-max limit reached 记录！"
  dmesg 2>/dev/null | grep "VFS: file-max limit" | tail -3
else
  echo "  内核告警：无 file-max limit 记录"
fi

# inotify 限制
if [[ -f /proc/sys/fs/inotify/max_user_watches ]]; then
  echo "  inotify max_user_watches: $(cat /proc/sys/fs/inotify/max_user_watches)"
  echo "  inotify max_user_instances: $(cat /proc/sys/fs/inotify/max_user_instances)"
fi

# epoll 限制
if [[ -f /proc/sys/fs/epoll/max_user_watches ]]; then
  echo "  epoll max_user_watches: $(cat /proc/sys/fs/epoll/max_user_watches)"
fi

# =============================================================================
# L2: 进程级 FD 信息
# =============================================================================
echo ""
echo "=================================================================="
echo " L2: 进程级 FD 信息"
echo "=================================================================="

if [[ -n "$TARGET_PID" ]]; then
  # 指定 PID 模式
  if [[ ! -d "/proc/${TARGET_PID}" ]]; then
    echo "  [错误] PID ${TARGET_PID} 不存在"
    exit 1
  fi
  echo "  目标 PID: ${TARGET_PID}"
  cmdline=$(cat "/proc/${TARGET_PID}/cmdline" 2>/dev/null | tr '\0' ' ' | head -c 80)
  echo "  进程名: ${cmdline:-unknown}"
  fd_count=$(ls -1 "/proc/${TARGET_PID}/fd" 2>/dev/null | wc -l)
  echo "  FD 数量: ${fd_count}"
  if [[ -r "/proc/${TARGET_PID}/limits" ]]; then
    grep "Max open files" "/proc/${TARGET_PID}/limits" | awk '{print "  ulimit 软限制:", $4, "  硬限制:", $5}'
    soft_limit=$(grep "Max open files" "/proc/${TARGET_PID}/limits" | awk '{print $4}')
    ratio=$(awk "BEGIN {printf \"%.1f\", ${fd_count} / ${soft_limit} * 100}" 2>/dev/null || echo "N/A")
    echo "  使用率: ${ratio}%"
  fi
  # FD 类型分布
  echo ""
  echo "  FD 类型分布:"
  if command -v lsof &>/dev/null; then
    lsof -p "${TARGET_PID}" 2>/dev/null | awk '{print $5}' | sort | uniq -c | sort -rn | head -10
  else
    echo "    lsof 不可用，使用 /proc 枚举"
    for fdlink in /proc/${TARGET_PID}/fd/*; do
      target=$(readlink "$fdlink" 2>/dev/null || echo "?")
      case "$target" in
        socket:*) echo "socket" ;;
        pipe:*) echo "pipe" ;;
        anon_inode:*) echo "${target#anon_inode:}" ;;
        /dev/*) echo "device" ;;
        *) echo "file" ;;
      esac
    done 2>/dev/null | sort | uniq -c | sort -rn | head -10
  fi
else
  # 全系统扫描模式 — 按 FD 数量排行
  echo "  全系统 FD 消费 Top 10:"
  echo "  PID       FD数  限制    进程名"
  echo "  ----------------------------------------------"
  for pid_dir in /proc/[0-9]*/; do
    pid=$(basename "$pid_dir" | tr -d '/')
    if [[ -d "/proc/$pid/fd" ]] && [[ -r "/proc/$pid/fd" ]]; then
      c=$(ls -1 "/proc/$pid/fd" 2>/dev/null | wc -l)
      [[ $c -gt 0 ]] && echo "$c $pid $(cat /proc/$pid/limits 2>/dev/null | grep 'Max open files' | awk '{print $4}') $(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ' | head -c 50)"
    fi
  done | sort -rn -k1 | head -10 | while read -r c pid limit cmd; do
    printf "  %-8s %-8s %-8s %s\n" "$c" "$pid" "${limit:-N/A}" "${cmd:--}"
  done
fi

# =============================================================================
# L3: CLOSE_WAIT 检测
# =============================================================================
echo ""
echo "=================================================================="
echo " L3: CLOSE_WAIT Socket 检测"
echo "=================================================================="

if command -v ss &>/dev/null; then
  cw_count=$(ss -Htn state close-wait 2>/dev/null | wc -l)
  est_count=$(ss -Htn state established 2>/dev/null | wc -l)
  echo "  ESTABLISHED: ${est_count} | CLOSE_WAIT: ${cw_count}"
  if [[ $cw_count -gt 1000 ]]; then
    echo "  ⚠ CLOSE_WAIT 数量超过 1000！"
  elif [[ $cw_count -gt 100 ]]; then
    echo "  ! CLOSE_WAIT 数量偏高 (${cw_count})"
  else
    echo "  CLOSE_WAIT 数量正常"
  fi

  # 如果指定了 PID，列出该进程的 CLOSE_WAIT
  if [[ -n "$TARGET_PID" ]]; then
    my_cw=$(ss -tnp state close-wait 2>/dev/null | grep -c "pid=${TARGET_PID}" || echo 0)
    echo "  目标进程 CLOSE_WAIT: ${my_cw}"
  fi
else
  echo "  ss 命令不可用，跳过 CLOSE_WAIT 检测"
fi

# =============================================================================
# 分支推荐
# =============================================================================
echo ""
echo "=================================================================="
echo " 分支推荐（基于以上信息）"
echo "=================================================================="

MATCHED=0

# 分支A: 系统级 FD 耗尽
if [[ -f /proc/sys/fs/file-nr ]]; then
  read -r allocated _ max <<< "$(cat /proc/sys/fs/file-nr)"
  usage=$(awk "BEGIN {printf \"%.1f\", $allocated / $max * 100}")
  if [[ $(echo "$usage > 80" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
    echo "  ✓ 推荐: bash scripts/branch_A_system_fd.sh   (file-nr 使用率 ${usage}% > 80%)"
    MATCHED=$((MATCHED + 1))
  fi
fi

# 分支C: CLOSE_WAIT 堆积
if command -v ss &>/dev/null; then
  cw=$(ss -Htn state close-wait 2>/dev/null | wc -l)
  if [[ $cw -gt 1000 ]]; then
    echo "  ✓ 推荐: bash scripts/branch_C_close_wait.sh    (CLOSE_WAIT ${cw} > 1000)"
    MATCHED=$((MATCHED + 1))
  fi
fi

# 分支B: 进程级 FD 泄漏（针对目标进程）
if [[ -n "$TARGET_PID" ]] && [[ -n "${soft_limit:-}" ]]; then
  r=$(awk "BEGIN {printf \"%.1f\", ${fd_count:-0} / ${soft_limit:-65536} * 100}" 2>/dev/null)
  if [[ $(echo "${r:-0} > 80" | bc -l 2>/dev/null || echo 0) -eq 1 ]]; then
    echo "  ✓ 推荐: bash scripts/branch_B_process_fd.sh    (PID ${TARGET_PID} FD 使用率 ${r}% > 80%)"
    MATCHED=$((MATCHED + 1))
  fi
fi

if [[ $MATCHED -eq 0 ]]; then
  echo "  未匹配到特定分支，建议手动分析或执行以下全量脚本："
  echo "  - bash scripts/branch_H_mixed.sh [target_pid]"
fi

echo ""
echo "=================================================================="
echo " 基线信息采集完成。结果目录: ${OUT_DIR}"
echo " 按分支推荐执行对应的 branch_*.sh 脚本进入深度诊断。"
echo "=================================================================="
