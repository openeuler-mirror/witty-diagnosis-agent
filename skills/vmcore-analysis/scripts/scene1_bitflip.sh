#!/bin/bash
# =============================================================================
# 场景 1：比特翻转 / Bit Flip 专项信息收集（页异常、寄存器与数据路径）
# 用法: ./scene1_bitflip.sh [--crash CMD] [--vmlinux PATH] [--vmcore PATH] [--deep|--kmem-o]
#       --deep / --kmem-o : 追加 kmem -o（per-CPU 对象布局，输出可能很长）
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

CRASH_CMD="./crash"
VMLINUX="./vmlinux"
VMCORE="./vmcore"
DEEP=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --crash)    CRASH_CMD="$2"; shift 2 ;;
        --vmlinux)  VMLINUX="$2";   shift 2 ;;
        --vmcore)   VMCORE="$2";    shift 2 ;;
        --deep|--kmem-o) DEEP=true; shift ;;
        -h|--help)
            echo "用法: $0 [--crash CMD] [--vmlinux PATH] [--vmcore PATH] [--deep|--kmem-o]"
            echo "  --deep / --kmem-o  在基础采集后追加 crash: kmem -o（输出可能很长，用于 per-CPU 布局）"
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
OUTFILE="${LOG_CWD}/scene1_bitflip_$(date +%Y%m%d_%H%M%S).log"
echo -e "${CYAN}${BOLD}[场景1] 比特翻转 / Bit Flip 信息收集${RESET}"
if [[ "$DEEP" == true ]]; then
    echo -e "${YELLOW}已启用 --deep：将追加 kmem -o（输出可能较长）${RESET}"
fi
echo -e "${GREEN}输出文件: ${OUTFILE}${RESET}"
echo ""

CRASH_CMDS=$(cat <<'CMDS'
echo "========== [1/9] 系统基本信息（FAR/CR2 等）=========="
sys

echo "========== [2/9] 内核日志 =========="
log

echo "========== [3/9] 崩溃调用栈 =========="
bt

echo "========== [4/9] 调用栈 + 寄存器（Bit Flip 重点）=========="
bt -r

echo "========== [5/9] 调用栈 + 源码行号 =========="
bt -l

echo "========== [6/9] 调用栈 + 完整帧 =========="
bt -f

echo "========== [7/9] 进程快照（ps -G，轻量；全量 ps 极慢可交互补跑）=========="
ps -G

echo "========== [8/9] 已加载模块 =========="
mod

echo "========== [9/9] 内存概览 =========="
kmem -i

CMDS
)

if [[ "$DEEP" == true ]]; then
    CRASH_CMDS+=$(cat <<'CMDS'

echo "========== [深度] per-CPU 对象布局（kmem -o，输出可能很长）=========="
kmem -o
CMDS
)

fi

CRASH_CMDS+=$'\nquit\n'

{
    echo "======================================================================"
    echo " 场景1: 比特翻转 / Bit Flip 分析报告"
    echo " 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo " vmlinux : $VMLINUX"
    echo " vmcore  : $VMCORE"
    if [[ "$DEEP" == true ]]; then
        echo " 选项    : --deep（已采集 kmem -o）"
    fi
    echo "======================================================================"
    echo ""

    "$CRASH_CMD" -s "$VMLINUX" "$VMCORE" <<< "$CRASH_CMDS" 2>&1

    echo ""
    echo "======================================================================"
    echo " [分析提示]（与 test/vmcore-analysis/SKILL.md 场景 1 对齐）"
    echo "  1. 在 [1/9] sys、[2/9] log 中确认页异常与 FAR/CR2；非全 0 时优先怀疑参与寻址/控制的数据字，而非默认对 FAR 做 XOR。"
    echo "  2. 链式一致：sys/PANIC 中的 task、本任务、bt 所示崩溃 CPU、以及 kmem -o 中选取的 CPU N 须为同一逻辑 CPU，再对照反汇编。"
    echo "  3. 地址侧（含 per-CPU）：在 bt 顶层帧取 PC/RIP 后执行 dis -r；可选 dis -l 对齐源码。按需 kmem -o 中定位「CPU N」行（N 与 bt 一致）取 per-CPU 区域基址。"
    echo "  4. 使用 ./scripts/check_bitflip.sh <预期值> <实际值>：两参数须来自 dis + kmem/struct/布局锁定的字，勿默认填入 FAR/CR2。"
    echo "  5. 若 sys 显示 PARTIAL dump 或信息不全，per-CPU/模块可能对不齐，结论宜保守并交叉 log 与其它场景。"
    echo "  6. 有候选类型时先用 struct <type> <addr> 试解是否结构体对象，确认后再深入（详见 SKILL.md）；RIP/标量/kmem 比对勿硬套 struct。"
    echo "======================================================================"

} | tee "$OUTFILE"

echo ""
echo -e "${GREEN}[完成] 报告已保存至: ${OUTFILE}${RESET}"
