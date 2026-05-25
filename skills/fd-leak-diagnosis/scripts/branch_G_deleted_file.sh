#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_G_deleted_file.sh
# 用途：已删除文件 FD 泄漏诊断 — 进程持有已 unlink 文件的 FD
# 使用：bash branch_G_deleted_file.sh [target_pid]
# 参数：
#   $1  目标 PID（可选）
# =============================================================================

set -euo pipefail

TARGET_PID="${1:-}"

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  echo "用途：已删除文件 FD 泄漏诊断"
  echo "使用：bash $0 [target_pid]"
  echo "  target_pid: 目标 PID（可选）"
  exit 0
fi

echo "=================================================================="
echo " 分支G：已删除文件 FD 泄漏 —— L3 类型层"
echo "=================================================================="

# G1. 全系统扫描已删除但未关闭的文件
echo ""
echo "【G1】全系统已删除但仍被持有的文件"
echo "------------------------------------------------------------------"
if command -v lsof &>/dev/null; then
  lsof +L1 2>/dev/null | head -20
  echo "  ..."
  deleted_total=$(lsof +L1 2>/dev/null | wc -l)
  echo "  共计 ${deleted_total} 个已删除但仍被持有的文件"
else
  echo "  lsof 不可用，尝试通过 /proc 扫描："
  for pid_dir in /proc/[0-9]*/; do
    pid=$(basename "$pid_dir" | tr -d '/')
    for fdlink in /proc/$pid/fd/*; do
      target=$(readlink "$fdlink" 2>/dev/null || true)
      if [[ "$target" == *"(deleted)" ]]; then
        echo "  PID $pid FD $(basename $fdlink) -> $target"
      fi
    done 2>/dev/null
  done | head -20
fi

# G2. 目标进程分析
if [[ -n "$TARGET_PID" ]] && [[ -d "/proc/${TARGET_PID}" ]]; then
  echo ""
  echo "【G2】目标 PID ${TARGET_PID} 已删除文件详情"
  echo "------------------------------------------------------------------"
  deleted_count=0
  for fdlink in "/proc/${TARGET_PID}/fd"/*; do
    target=$(readlink "$fdlink" 2>/dev/null || true)
    if [[ "$target" == *"(deleted)" ]]; then
      echo "  FD $(basename $fdlink) -> $target"
      deleted_count=$((deleted_count + 1))
    fi
  done
  echo ""
  echo "  已删除但仍持有的文件数: ${deleted_count}"
  if [[ $deleted_count -gt 0 ]]; then
    echo "  影响：这些文件占用的磁盘空间无法释放！"
    echo "  解决方法：重启进程或 kill -HUP 触发日志轮转 reopen"
  fi
fi

# G3. 根因指引
echo ""
echo "【G3】已删除文件 FD 泄漏根因指引"
echo "------------------------------------------------------------------"
cat << 'GUIDE'
  已删除文件仍被进程持有的常见原因：
    1. 日志文件被 logrotate 轮转后，进程未 reopen（SIGHUP 未处理）
    2. 临时文件创建后未 close 就被 unlink
    3. mmap 文件被删除后进程仍持有映射

  解决方法：
    - 配置 logrotate 的 copytruncate 选项（无需 reopen）
    - 确保进程正确处理 SIGHUP 信号（重新打开日志文件）
    - 使用 O_CLOEXEC 防止子进程继承不需要的 FD
GUIDE

echo ""
echo "=================================================================="
echo " 分支G 诊断结论"
echo "=================================================================="
cat << 'CONCLUSION'
  全系统已删除但持有的文件数：<N>
  目标 PID 已删除文件数：<N>
  影响：<占用磁盘空间无法释放 / FD 数量虚高>
  主要文件类型：<日志文件 / 临时文件 / 其他>
  建议：<重启进程 / 配置 logrotate copytruncate / 修复信号处理>
CONCLUSION
