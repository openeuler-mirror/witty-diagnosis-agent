#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_G_lifecycle.sh
# 用途：进程生命周期异常诊断 — 双轨分析
# 使用：bash branch_G_lifecycle.sh [output_dir]
# 参数：
#   $1  输出目录（来自 01_baseline_info.sh 的输出）
# =============================================================================

set -euo pipefail

OUT_DIR="${1:-/tmp/syscall_diag_$(date +%Y%m%d%H%M%S)}"

echo "=================================================================="
echo " 分支G：进程生命周期异常 —— 双轨分析"
echo "=================================================================="

BASELINE_TARGET="${OUT_DIR}/process_status.txt"
STDERR="${OUT_DIR}/strace_all.txt"
SUMMARY="${OUT_DIR}/strace_summary.txt"
TARGET_PID=$(grep "^Pid:" "$BASELINE_TARGET" 2>/dev/null | awk '{print $2}' || echo "")

# --------------------------------------------------------------------------
# T1 - fork/clone 分析
# --------------------------------------------------------------------------
echo ""
echo "【T1】fork/clone 活动分析"
echo "------------------------------------------------------------------"
if [ -f "$STDERR" ]; then
  CLONE_COUNT=$(grep -cE "^clone\b|^fork\b" "$STDERR" 2>/dev/null || echo 0)
  echo "  fork/clone 次数: ${CLONE_COUNT}"

  if [ "$CLONE_COUNT" -gt 0 ]; then
    echo "  ⚠ 进程/线程创建频繁，可能原因:"
    echo "    · 短生命周期线程池（每次新建线程）"
    echo "    · 进程 fork 风暴"
    echo "    · 协程/goroutine 每次新建系统线程"
  fi

  # wait4 分析
  WAIT_COUNT=$(grep -cE "^wait4\b|^waitid\b" "$STDERR" 2>/dev/null || echo 0)
  echo "  wait4/waitid 次数: ${WAIT_COUNT}"
  if [ "$WAIT_COUNT" -eq 0 ] && [ "$CLONE_COUNT" -gt 10 ]; then
    echo "  ⚠ 子进程创建多但几乎不 wait → 可能产生僵尸进程"
  fi
fi

echo ""

# --------------------------------------------------------------------------
# T2 - execve 分析
# --------------------------------------------------------------------------
echo ""
echo "【T2】execve 分析"
echo "------------------------------------------------------------------"
if [ -f "$STDERR" ]; then
  EXEC_COUNT=$(grep -c "^execve\b" "$STDERR" 2>/dev/null || echo 0)
  EXEC_ERR=$(grep "execve" "$STDERR" 2>/dev/null | grep -c "\-1" || echo 0)

  echo "  execve 调用: ${EXEC_COUNT} 次"
  echo "  execve 失败: ${EXEC_ERR} 次"

  if [ "$EXEC_ERR" -gt 0 ]; then
    echo ""
    echo "  execve 失败详情:"
    grep "^execve" "$STDERR" 2>/dev/null | grep "\-1" | head -10 || true
  fi
fi

echo ""

# --------------------------------------------------------------------------
# T3 - 僵尸进程检测
# --------------------------------------------------------------------------
echo ""
echo "【T3】僵尸进程检测"
echo "------------------------------------------------------------------"
ZOMBIE_COUNT=$(ps -eo pid,ppid,stat,comm 2>/dev/null | awk '$3 ~ /^Z/ {print}' | wc -l)
echo "  系统级僵尸进程: ${ZOMBIE_COUNT} 个"
if [ "$ZOMBIE_COUNT" -gt 0 ]; then
  echo ""
  echo "  僵尸进程列表:"
  ps -eo pid,ppid,stat,comm 2>/dev/null | awk '$3 ~ /^Z/ {print "    PID=" $1 " PPID=" $2 " CMD=" $4}' | head -20
  echo ""
  echo "  ⚠ 僵尸进程需要其父进程调用 wait() 回收"
  echo "    确认父进程是否阻塞在 syscall 中"
fi

echo ""

# --------------------------------------------------------------------------
# T4 - 线程分析
# --------------------------------------------------------------------------
echo ""
echo "【T4】线程分析"
echo "------------------------------------------------------------------"
if [ -n "$TARGET_PID" ]; then
  THREAD_COUNT=$(ls /proc/${TARGET_PID}/task 2>/dev/null | wc -l || echo 0)
  THREAD_LIMIT=$(ulimit -u 2>/dev/null || echo "N/A")
  echo "  线程数: ${THREAD_COUNT}"
  echo "  线程上限 (ulimit -u): ${THREAD_LIMIT}"

  echo ""
  echo "  线程列表:"
  for tid in $(ls /proc/${TARGET_PID}/task 2>/dev/null); do
    comm=$(cat /proc/${TARGET_PID}/task/$tid/comm 2>/dev/null || echo "?")
    state=$(cat /proc/${TARGET_PID}/task/$tid/status 2>/dev/null | grep "^State" | awk '{print $2}' || echo "?")
    echo "    TID=${tid} ${state} ${comm}"
  done 2>/dev/null | head -20
fi

echo ""

echo "【T5】调用轨迹轨道结论"
echo "------------------------------------------------------------------"
{
  echo "  fork/clone: ${CLONE_COUNT:-0}"
  echo "  execve 失败: ${EXEC_ERR:-0}"
  echo "  僵尸进程: ${ZOMBIE_COUNT}"
  echo "  调用轨迹归因假设: 进程生命周期异常定位"
} | tee -a "${OUT_DIR}/branch_G_metrics.txt"

# ==========================================================================
echo ""
echo "=================================================================="
echo " ▶ 内核语义轨道"
echo "=================================================================="
cat << 'SRCGUIDE'
  fork/clone 风暴:
    · 线程池实现不当（每次任务新建线程而非复用）
    · fork 炸弹或递归 fork
    · 检查: strace -e trace=clone -c -p <PID>
    · 修复: 使用线程池、协程或 reactor 模型

  execve 失败:
    · 可执行文件不存在（ENOENT）
    · 权限不足（EACCES）
    · 脚本解释器不存在（#! 路径错误）
    · 检查: ldd <binary>

  僵尸进程:
    · 父进程未调 wait4/waitpid
    · 父进程卡住或死循环
    · 修复: signal(SIGCHLD, SIG_IGN) 或 wait 循环

  线程上限:
    · /proc/sys/kernel/threads-max 系统上限
    · ulimit -u 用户上限
    · cgroup pids.max 控制组上限
SRCGUIDE

echo ""
echo "=================================================================="
echo " ▶ 最终结论"
echo "=================================================================="
cat << 'CONCLUSION'

  故障模式: 进程生命周期异常
  处理建议:
    · fork 风暴 → 检查线程池实现
    · execve 失败 → 检查路径/权限/解释器
    · 僵尸进程 → 父进程增加 wait 处理
    · 线程超限 → 增大线程上限或修复泄漏
    
    【验证】
      - 修复后 strace -c 确认 fork/clone 次数下降
      - ps 确认无僵尸进程增长
CONCLUSION
