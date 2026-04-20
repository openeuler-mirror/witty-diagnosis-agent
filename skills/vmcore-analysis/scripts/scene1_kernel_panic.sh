#!/bin/bash
# =============================================================================
# 场景 1：内核崩溃 / Kernel Panic 深度信息收集脚本
# 用法: ./scene1_kernel_panic.sh [--crash CMD] [--vmlinux PATH] [--vmcore PATH]
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
OUTFILE="${LOG_CWD}/scene1_panic_$(date +%Y%m%d_%H%M%S).log"
echo -e "${CYAN}${BOLD}[场景1] 内核崩溃 / Kernel Panic 信息收集${RESET}"
echo -e "${GREEN}输出文件: ${OUTFILE}${RESET}"
echo ""

# ── Crash 命令集 ──────────────────────────────────────────────────────────────
# 每条命令用 <<<EOF 分隔，便于阅读
CRASH_CMDS=$(cat <<'CMDS'
echo "========== [1/12] 系统基本信息 =========="
sys

echo "========== [2/12] 内核崩溃日志 (panic/oops/trace) =========="
log

echo "========== [3/12] 崩溃时主调用栈 =========="
bt

echo "========== [4/12] 调用栈 + 源码行号 =========="
bt -l

echo "========== [5/12] 调用栈 + 完整帧信息 =========="
bt -f

echo "========== [6/12] 所有 CPU 的当前调用栈 =========="
bt -a

echo "========== [7/12] 崩溃时所有进程状态 =========="
ps

echo "========== [8/12] 已加载内核模块列表 =========="
mod

echo "========== [9/12] CPU 寄存器状态 =========="
bt -r

echo "========== [10/12] 内核异常向量/中断信息 =========="
irq

echo "========== [11/12] 内存使用概览 =========="
kmem -i

echo "========== [12/12] 运行队列状态 =========="
runq

quit
CMDS
)

# ── 执行并输出 ────────────────────────────────────────────────────────────────
{
    echo "======================================================================"
    echo " 场景1: 内核崩溃 / Kernel Panic 分析报告"
    echo " 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo " vmlinux : $VMLINUX"
    echo " vmcore  : $VMCORE"
    echo "======================================================================"
    echo ""

    "$CRASH_CMD" -s "$VMLINUX" "$VMCORE" <<< "$CRASH_CMDS" 2>&1

    echo ""
    echo "======================================================================"
    echo " [分析提示]"
    echo "  1. 在 [2/12] log 中搜索: Kernel panic / Call Trace / RIP / oops"
    echo "  2. 在 [3/12] bt  中确认崩溃函数与调用链"
    echo "  3. 在[4/12] bt -l 中获取源码行号，结合 src/ 目录定位代码"
    echo "  4. 在 [8/12] mod 中确认是哪个内核模块触发崩溃"
    echo "  5. 若寄存器值含高位突变（如 0x08000045），需运行 check_bitflip.sh"
    echo "  6. 栈上对象：有候选类型时先用 struct <type> <addr> 试解是否结构体对象；RIP 用 dis -r/-l，勿对指令地址当 struct（详见 SKILL.md）。"
    echo "======================================================================"

} | tee "$OUTFILE"

echo ""
echo -e "${GREEN}[完成] 报告已保存至: ${OUTFILE}${RESET}"
