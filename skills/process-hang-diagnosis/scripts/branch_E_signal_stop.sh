#!/bin/bash
#
# 分支 E: 信号停止/跟踪诊断
# 场景: 进程被信号停止 (State=T/t)，kill -9 杀不死
# OS 特征: State=T (SIGSTOP) 或 State=t (ptrace跟踪)
#
# 用法: bash ./scripts/branch_E_signal_stop.sh <pid> [work_dir]

set -euo pipefail

# CMD_PREFIX: 命令执行前缀，容器诊断时设置为 "docker exec <容器名>"
# 示例: CMD_PREFIX="docker exec process-hang-branch-g" bash 01_baseline_info.sh 1
: "${CMD_PREFIX:=}"

# run() — 通过 CMD_PREFIX 执行命令
run() {
  if [ -n "$CMD_PREFIX" ]; then
    $CMD_PREFIX "$@"
  else
    "$@"
  fi
}


PID="${1:?Usage: $0 <pid> [work_dir]}"
WORK_DIR="${2:-./hang_diag_${PID}}"
echo "===== 分支 E: 信号停止/跟踪诊断 ====="
mkdir -p "$WORK_DIR/proc" "$WORK_DIR/gdb_output"

# O1: 确认停止状态
echo ""
echo "--- O1: 进程信号状态 ---"
echo "全状态:"
cat /proc/$PID/status 2>/dev/null | grep -E "^State|^Sig" | tee "$WORK_DIR/proc/signal_status.txt"

STATE=$(cat /proc/$PID/status 2>/dev/null | grep "^State:" | awk '{print $2}')
echo ""
echo "State 解释:"
case "$STATE" in
    T)  echo "  T = SIGSTOP/SIGTSTP/SIGTTIN/SIGTTOU 导致停止"
        echo "  SIGSTOP 不可被阻塞、不可忽略、不可捕获"
        echo "  可能来源: gdb / kill -STOP / 作业控制 / 其他进程发送"
        ;;
    t)  echo "  t = ptrace 跟踪停止（trace stop）"
        echo "  可能来源: gdb / strace / ltrace / 调试器附加"
        echo "  父进程: $(cat /proc/$PID/status 2>/dev/null | grep "^PPid:" | awk '{print $2}')"
        ;;
    *)  echo "  $STATE = 非停止状态（本分支可能不适用）"
        ;;
esac

# O2: 信号位图分析
echo ""
echo "--- O2: 信号位图分析 ---"
SigBlk=$(cat /proc/$PID/status 2>/dev/null | grep "^SigBlk:" | awk '{print $2}')
SigCgt=$(cat /proc/$PID/status 2>/dev/null | grep "^SigCgt:" | awk '{print $2}')
SigIgn=$(cat /proc/$PID/status 2>/dev/null | grep "^SigIgn:" | awk '{print $2}')

echo "SigBlk: $SigBlk (被屏蔽的信号)"
echo "SigCgt: $SigCgt (已捕获的信号)"
echo "SigIgn: $SigIgn (已忽略的信号)"

# 检查特定信号
# bit 2 (SIGINT) => 0x2
# bit 9 (SIGKILL) => 不可屏蔽
# bit 15 (SIGTERM) => 0x4000
# bit 19 (SIGSTOP) => 不可屏蔽

echo ""
echo "关键信号检查:"
if [ -n "$SigBlk" ]; then
    sigblk_val=$((16#$SigBlk))
    if [ $((sigblk_val & 0x4000)) -ne 0 ]; then
        echo "  ⚠ SIGTERM(15) 被屏蔽 → kill -15 杀不死"
    fi
    if [ $((sigblk_val & 0x0002)) -ne 0 ]; then
        echo "  ⚠ SIGINT(2) 被屏蔽 → Ctrl+C 无效"
    fi
fi

# O3: 检查发送者
echo ""
echo "--- O3: SIGSTOP 发送者排查 ---"
if [ "$STATE" = "T" ]; then
    echo "SIGSTOP 发送者可能是:"
    echo "  1. 调试器: gdb -p $PID"
    echo "  2. 作业控制: Ctrl+Z 发送 SIGTSTP"
    echo "  3. 显式发送: kill -STOP $PID"
    echo "  4. 其他进程: 检查 scripts 或工具"
    echo ""
    echo "  PS: 无标准方法查看谁发送了 SIGSTOP"
    echo "  推荐: 检查 auditd 日志"
    if command -v ausearch &>/dev/null; then
        ausearch -sc kill -ts recent 2>/dev/null | head -20 || echo "  (ausearch 无结果)"
    fi
fi

# O4: gdb info signals
echo ""
echo "--- O4: GDB 信号配置检查 ---"
if command -v gdb &>/dev/null && kill -0 "$PID" 2>/dev/null; then
    gdb --batch -nx -ex "info signals" -p "$PID" 2>&1 | head -30 | tee "$WORK_DIR/gdb_output/gdb_info_signals.txt" || true
else
    echo "[SKIP] gdb 不可用"
fi

# 输出摘要
echo ""
echo "===== 分支 E 诊断摘要 ====="
echo "进程 $PID State=$STATE"
if [ "$STATE" = "T" ]; then
    echo "  进程被 SIGSTOP 停止。使用 'kill -CONT $PID' 恢复运行。"
elif [ "$STATE" = "t" ]; then
    echo "  进程被 ptrace 跟踪停止。检查跟踪进程 PID=$(cat /proc/$PID/status | grep PPid | awk '{print $2}')"
fi
echo "  SIGTERM 屏蔽: $([ $((16#$SigBlk & 0x4000)) -ne 0 ] && echo '是' || echo '否')"
