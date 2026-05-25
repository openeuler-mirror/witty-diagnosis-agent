#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_E_inotify.sh
# 用途：inotify watch 泄漏诊断 — L3 类型层 + L4 根因层
# 使用：bash branch_E_inotify.sh [target_pid]
# 参数：
#   $1  目标 PID（可选；不指定则全系统扫描）
# =============================================================================

set -euo pipefail

TARGET_PID="${1:-}"

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  echo "用途：inotify watch 泄漏诊断"
  echo "使用：bash $0 [target_pid]"
  echo "  target_pid: 目标 PID（可选；不指定则全系统扫描）"
  exit 0
fi

echo "=================================================================="
echo " 分支E：inotify watch 泄漏 —— L3 类型层 + L4 根因层"
echo "=================================================================="

# E1. 系统 inotify 限制
echo ""
echo "【E1】系统 inotify 限制"
echo "------------------------------------------------------------------"
max_watches=$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo "N/A")
max_instances=$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo "N/A")
echo "  max_user_watches:   ${max_watches}"
echo "  max_user_instances: ${max_instances}"

# E2. 全系统 inotify FD 持有者
echo ""
echo "【E2】持有 inotify FD 的进程"
echo "------------------------------------------------------------------"
FOUND_INOTIFY=false
for pid_dir in /proc/[0-9]*/; do
  pid=$(basename "$pid_dir" | tr -d '/')
  ino_count=$(ls -la "/proc/$pid/fd" 2>/dev/null | grep -c "inotify" || true)
  if [[ $ino_count -gt 0 ]]; then
    total_watches=0
    for fdinfo in /proc/$pid/fdinfo/*; do
      [[ -r "$fdinfo" ]] && wc=$(grep -c "watch" "$fdinfo" 2>/dev/null || echo 0) && total_watches=$((total_watches + wc))
    done
    cmdline=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ' | head -c 50)
    echo "  PID $pid (${cmdline:-unknown}): ${ino_count} 个 inotify FD, ~${total_watches} 个 watch"
    if [[ "$max_watches" != "N/A" ]] && [[ $total_watches -gt $((max_watches * 80 / 100)) ]]; then
      echo "    ⚠ watch 使用率 > 80% (${total_watches}/${max_watches})"
    fi
    FOUND_INOTIFY=true
  fi
done
if ! $FOUND_INOTIFY; then
  echo "  未找到持有 inotify FD 的进程"
fi

# E3. 目标进程 inotify 详情
if [[ -n "$TARGET_PID" ]] && [[ -d "/proc/${TARGET_PID}" ]]; then
  echo ""
  echo "【E3】目标 PID ${TARGET_PID} inotify 详情"
  echo "------------------------------------------------------------------"
  my_ino=$(ls -la "/proc/${TARGET_PID}/fd" 2>/dev/null | grep -c "inotify" || echo 0)
  my_watches=0
  for fdinfo in /proc/${TARGET_PID}/fdinfo/*; do
    [[ -r "$fdinfo" ]] && grep "watch" "$fdinfo" 2>/dev/null && my_watches=$((my_watches + 1))
  done
  echo "  inotify FD 数: ${my_ino}"
  echo "  watch 数: ~${my_watches}"
  if [[ "$max_watches" != "N/A" ]]; then
    watch_ratio=$(awk "BEGIN {printf \"%.1f\", ${my_watches} / ${max_watches} * 100}" 2>/dev/null || echo "N/A")
    echo "  watch 使用率: ${watch_ratio}%"
  fi
fi

# E4. inotify 泄漏排查指引
echo ""
echo "【E4】inotify 泄漏排查指引"
echo "------------------------------------------------------------------"
cat << 'GUIDE'
  inotify 泄漏常见原因：
    1. inotify_init() 后忘记 inotify_close()
    2. fs.watch() / inotify_add_watch() 每次调用都新建实例
    3. webpack/dev-server 热重载每次重启都创建新 watcher
    4. 第三方库（如 watchdog、node-notifier）管理不当

  排查方法：
    - ls -la /proc/<PID>/fd | grep inotify   # 看有多少个 inotify 实例
    - cat /proc/<PID>/fdinfo/<ino_fd>         # 看每个实例的 watch 列表
    - 预期：一般只有 1-2 个 inotify 实例，每个实例的 watch 数合理

  修复选项：
    - 增大 fs.inotify.max_user_watches（临时缓解）
    - 修复代码确保每次 inotify_init 有对应 close
    - 使用单一 inotify 实例 + inotify_rm_watch 替代反复 init/close
GUIDE

echo ""
echo "=================================================================="
echo " 分支E 诊断结论"
echo "=================================================================="
cat << 'CONCLUSION'
  系统 max_user_watches：<N>
  目标 PID：<PID>
  inotify FD 数：<N>
  watch 数：<N>（使用率 <P>%）
  判定：[正常/接近上限/超限]
  建议：<调整 max_user_watches / 修复 watcher 清理逻辑>
CONCLUSION
