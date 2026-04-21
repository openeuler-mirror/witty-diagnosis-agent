#!/bin/bash
# =============================================================================
# 场景 2：内核崩溃 / Kernel Panic 深度信息收集脚本
# 用法: ./scene2_kernel_panic.sh [--crash CMD] [--vmlinux PATH] [--vmcore PATH]
# =============================================================================

set -euo pipefail

# ── 颜色输出 ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ── 默认参数 ──────────────────────────────────────────────────────────────────
CRASH_CMD="./crash"
VMLINUX="./vmlinux"
VMCORE="./vmcore"

# ── 参数解析 ──────────────────────────────────────────────────────────────────
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

# ── 检查文件 ──────────────────────────────────────────────────────────────────
for f in "$VMLINUX" "$VMCORE"; do
    if [[ ! -f "$f" ]]; then
        echo -e "${RED}[ERROR] 文件不存在: $f${RESET}"
        exit 1
    fi
done

LOG_CWD="$(pwd -P 2>/dev/null || pwd)"
OUTFILE="${LOG_CWD}/scene2_panic_$(date +%Y%m%d_%H%M%S).log"
echo -e "${CYAN}${BOLD}[场景2] 内核崩溃 / Kernel Panic 信息收集${RESET}"
echo -e "${GREEN}输出文件: ${OUTFILE}${RESET}"
echo ""

# ── Crash 命令集 ──────────────────────────────────────────────────────────────
# 每条命令用 <<<EOF 分隔，便于阅读
CRASH_CMDS=$(cat <<'CMDS'
echo "========== [1/13] 系统基本信息 =========="
sys

echo "========== [2/13] 内核崩溃日志 (panic/oops/trace) =========="
log

echo "========== [3/13] 崩溃时主调用栈 =========="
bt

echo "========== [4/13] 调用栈 + 源码行号 =========="
bt -l

echo "========== [5/13] 调用栈 + 完整帧信息 =========="
bt -f

echo "========== [6/13] 调用栈 + 帧内对象类型 (bt -F，Identity 用) =========="
bt -F

echo "========== [7/13] 所有 CPU 的当前调用栈 =========="
bt -a

echo "========== [8/13] 进程（ps -G，轻量；需任务状态可交互 ps）=========="
ps -G

echo "========== [9/13] 已加载内核模块列表 =========="
mod

echo "========== [10/13] CPU 寄存器状态 =========="
bt -r

echo "========== [11/13] 内核异常向量/中断信息 =========="
irq

echo "========== [12/13] 内存使用概览 =========="
kmem -i

echo "========== [13/13] 运行队列状态 =========="
runq

quit
CMDS
)

# ── 分析提示（写入日志末尾，并打印到终端）────────────────────────────────────
emit_analysis_hints() {
    echo ""
    echo "======================================================================"
    echo " [分析提示]"
    echo "  【Agent 强制】写根因前须 Read 本 skill 全文: ./references/scene2-kernel-panic.md（不可只读 SKILL 摘要）。"
    echo "  1. 在 [2/13] log 中搜索: Kernel panic / Call Trace / RIP / oops"
    echo "  2. 在 [3/13] bt  中确认崩溃函数与调用链"
    echo "  3. 在 [4/13] bt -l 中获取源码行号，结合 src/ 目录定位代码"
    echo "  4. 在 [6/13] bt -F：取 __exit_signal/release_task 帧内 task_struct* 地址，与 task 的 TASK 逐地址比较（禁止仅用 bt 顶栏 TASK 断言 Identity；见 ./references/scene2-kernel-panic.md §1–§3）"
    echo "  5. 在 [9/13] mod 中确认是哪个内核模块触发崩溃"
    echo "  6. 若寄存器值含高位突变（如 0x08000045），需运行 check_bitflip.sh"
    echo "  7. 栈上对象：有候选类型时先用 struct <type> <addr> 试解是否结构体对象；RIP 用 dis -r/-l，勿对指令地址当 struct（详见 SKILL.md）。"
    echo "----------------------------------------------------------------------"
    echo " [何时查阅 ./references/scene2-kernel-panic.md]"
    echo "  • 建议在：已浏览本报告 [2/13]log / [3/13]bt / [6/13]bt -F，并准备对崩溃 RIP 做 dis 或写根因时再打开，作命令顺序与横切核对清单。"
    echo "  • 若 bt 中出现 release_task / exit_notify / __exit_signal / detach_pid / __change_pid / set_pid_unused / free_pid / task_pid_reserved 等：按该文 §3–§5（Identity、PID 符号、__change_pid 与 CONFIG_PID_RESERVE/reserved_data）对照，不必在仅跑完采集、尚未读栈时通读。"
    echo "======================================================================"
}

# ── 执行：crash 仅写入日志；分析提示追加到日志并输出终端 ─────────────────────
{
    echo "======================================================================"
    echo " 场景2: 内核崩溃 / Kernel Panic 分析报告"
    echo " 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo " vmlinux : $VMLINUX"
    echo " vmcore  : $VMCORE"
    echo "======================================================================"
    echo ""

    "$CRASH_CMD" -s "$VMLINUX" "$VMCORE" <<< "$CRASH_CMDS" 2>&1

} > "$OUTFILE"

emit_analysis_hints | tee -a "$OUTFILE"

echo ""
echo -e "${GREEN}[完成] 报告已保存至: ${OUTFILE}${RESET}"
