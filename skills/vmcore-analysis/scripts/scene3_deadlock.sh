#!/bin/bash
# =============================================================================
# 场景 3：系统挂死 / 死锁 / 无响应 深度信息收集脚本
# 用法: ./scene3_deadlock.sh [--crash CMD] [--vmlinux PATH] [--vmcore PATH]
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

CRASH_CMD="./crash"
VMLINUX="./vmlinux"
VMCORE="./vmcore"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --crash)    CRASH_CMD="$2"; shift 2 ;;
        --vmlinux)  VMLINUX="$2";   shift 2 ;;
        --vmcore)   VMCORE="$2";    shift 2 ;;
        -h|--help)
            echo "用法: $0 [--crash CMD] [--vmlinux PATH] [--vmcore PATH]"
            exit 0 ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
done

for f in "$VMLINUX" "$VMCORE"; do
    if [[ ! -f "$f" ]]; then
        echo -e "${RED}[ERROR] 文件不存在: $f${RESET}"
        exit 1
    fi
done

LOG_CWD="$(pwd -P 2>/dev/null || pwd)"
OUTFILE="${LOG_CWD}/scene3_deadlock_$(date +%Y%m%d_%H%M%S).log"
echo -e "${CYAN}${BOLD}[场景3] 系统挂死 / 死锁 / 无响应 信息收集${RESET}"
echo -e "${GREEN}输出文件: ${OUTFILE}${RESET}"
echo ""

CRASH_CMDS=$(cat <<'CMDS'
echo "========== [1/13] 系统基本信息 =========="
sys

echo "========== [2/13] 内核日志 (hung_task/softlockup/watchdog) =========="
log

echo "========== [3/13] 所有进程状态（重点看 D/UN 状态） =========="
ps

echo "========== [4/13] 所有 CPU 运行队列 =========="
runq

echo "========== [5/13] 崩溃进程调用栈 =========="
bt

echo "========== [6/13] 所有进程的调用栈 =========="
bt -a

echo "========== [7/13] 带帧信息的完整调用栈 =========="
bt -f

echo "========== [8/13] 带行号的调用栈 =========="
bt -l

echo "========== [9/13] 等待队列 / 信号量 / mutex 状态 =========="
waitq

echo "========== [10/13] 内核 mutex 锁信息 =========="
mutex -t

echo "========== [11/13] RW 锁状态 =========="
rwlock

echo "========== [12/13] 内存使用情况 =========="
kmem -i

echo "========== [13/13] 已加载模块 =========="
mod

quit
CMDS
)

{
    echo "======================================================================"
    echo " 场景3: 系统挂死 / 死锁 / 无响应 分析报告"
    echo " 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo " vmlinux : $VMLINUX"
    echo " vmcore  : $VMCORE"
    echo "======================================================================"
    echo ""

    "$CRASH_CMD" -s "$VMLINUX" "$VMCORE" <<< "$CRASH_CMDS" 2>&1

    echo ""
    echo "======================================================================"
    echo " [分析提示]"
    echo "  1. 在 [2/13] log 中搜索: hung_task / soft lockup / watchdog"
    echo "     搜索: INFO: task blocked / RCU stall"
    echo "  2. 在 [3/13] ps  中筛选状态为 D(不可中断睡眠) 或 UN 的进程"
    echo "  3. 在 [4/13] runq 中确认各 CPU 是否阻塞在同一函数"
    echo "  4. 在 [6/13] bt -a 中查看所有进程栈，寻找相互等待的锁链"
    echo "     重点关注: mutex_lock / down / __schedule / io_schedule"
    echo "  5. 死锁识别: 进程A等待锁X，持有锁X的进程B又等待进程A持有的锁Y"
    echo "  6. 可用 foreach un bt 命令单独收集 UN 状态进程的调用栈"
    echo "  7. task/锁/waitqueue：有候选类型时先用 struct <type> <addr> 试解是否结构体对象；纯寄存器/计数值勿硬套 struct（详见 SKILL.md）。"
    echo "======================================================================"

} | tee "$OUTFILE"

echo ""
echo -e "${GREEN}[完成] 报告已保存至: ${OUTFILE}${RESET}"
