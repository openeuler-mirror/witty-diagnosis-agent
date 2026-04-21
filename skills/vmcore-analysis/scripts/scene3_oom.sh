#!/bin/bash
# =============================================================================
# 场景 3：内存泄漏 / OOM / 内存耗尽 深度信息收集脚本
# 用法: ./scene3_oom.sh [--crash CMD] [--vmlinux PATH] [--vmcore PATH]
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
OUTFILE="${LOG_CWD}/scene3_oom_$(date +%Y%m%d_%H%M%S).log"
echo -e "${CYAN}${BOLD}[场景3] OOM / 内存泄漏 / 内存耗尽 信息收集${RESET}"
echo -e "${GREEN}输出文件: ${OUTFILE}${RESET}"
echo ""

CRASH_CMDS=$(cat <<'CMDS'
echo "========== [1/13] 系统基本信息 =========="
sys

echo "========== [2/13] 内核日志 (OOM/killer/cgroup) =========="
log

echo "========== [3/13] 内存整体使用分布 =========="
kmem -i

echo "========== [4/13] Slab 缓存使用详情（按占用排序） =========="
kmem -s

echo "========== [5/13] 进程 RSS Top 20（ps -G｜sort；已去掉全量 ps 以加速）=========="
ps -G | sort -k 8 -rn | head -20

echo "========== [6/13] 页面分配统计 =========="
kmem -p | head -60

echo "========== [7/13] Zone 内存分布 =========="
kmem -z

echo "========== [8/13] Buddy 系统空闲页统计 =========="
kmem -f

echo "========== [9/13] Hugepage 使用情况 =========="
kmem -h

echo "========== [10/13] 调用栈（确认是否在内存分配路径崩溃） =========="
bt

echo "========== [11/13] 带行号的调用栈 =========="
bt -l

echo "========== [12/13] 运行队列（确认是否有 D 状态进程） =========="
runq

echo "========== [13/13] 虚拟内存统计 =========="
vm

quit
CMDS
)

{
    echo "======================================================================"
    echo " 场景3: 内存泄漏 / OOM / 内存耗尽 分析报告"
    echo " 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo " vmlinux : $VMLINUX"
    echo " vmcore  : $VMCORE"
    echo "======================================================================"
    echo ""

    "$CRASH_CMD" -s "$VMLINUX" "$VMCORE" <<< "$CRASH_CMDS" 2>&1

    echo ""
    echo "======================================================================"
    echo " [分析提示]"
    echo "  1. 在 [2/13] log 中搜索: Out of memory / OOM / killed process"
    echo "     搜索: Memory cgroup out of memory / oom_kill_process"
    echo "  2. 在 [3/13] kmem -i 中查看: FREE / SLAB / MLOCKED 比例"
    echo "  3. 在 [4/13] kmem -s 中查找占用异常大的 slab（如 > 1GB）"
    echo "  4. 在 [5/13] ps -G Top 20 中对照 RSS/VSZ 与 OOM 日志；需全量表可交互 ps"
    echo "  5. 结合 [5/13] Top 20 与 kmem，对照 OOM 日志中的 adj 值"
    echo "  6. 若 slab 占用异常，可进一步用: kmem -S <slab_name> 深入分析"
    echo "  7. task/mm/cgroup：有候选类型时先用 struct <type> <addr> 试解是否结构体对象；RSS/VSZ 等数值勿 struct（详见 SKILL.md）。"
    echo "======================================================================"

} | tee "$OUTFILE"

echo ""
echo -e "${GREEN}[完成] 报告已保存至: ${OUTFILE}${RESET}"
