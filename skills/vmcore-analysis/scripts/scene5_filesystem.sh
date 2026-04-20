#!/bin/bash
# =============================================================================
# 场景 5：文件系统只读 / 挂载异常 / IO 卡顿 深度信息收集脚本
# 用法: ./scene5_filesystem.sh [--crash CMD] [--vmlinux PATH] [--vmcore PATH]
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
OUTFILE="${LOG_CWD}/scene5_filesystem_$(date +%Y%m%d_%H%M%S).log"
echo -e "${CYAN}${BOLD}[场景5] 文件系统只读 / 挂载异常 / IO 卡顿 信息收集${RESET}"
echo -e "${GREEN}输出文件: ${OUTFILE}${RESET}"
echo ""

CRASH_CMDS=$(cat <<'CMDS'
echo "========== [1/14] 系统基本信息 =========="
sys

echo "========== [2/14] 内核日志 (EXT4/XFS/IO/mount 错误) =========="
log

echo "========== [3/14] 当前挂载点列表 =========="
mount

echo "========== [4/14] 打开的文件列表 =========="
files

echo "========== [5/14] VFS 超级块信息 =========="
super

echo "========== [6/14] 磁盘/块设备 IO 统计 =========="
kmem -i

echo "========== [7/14] 崩溃调用栈 =========="
bt

echo "========== [8/14] 带行号调用栈 =========="
bt -l

echo "========== [9/14] 带完整帧的调用栈 =========="
bt -f

echo "========== [10/14] 所有 CPU 调用栈 =========="
bt -a

echo "========== [11/14] 所有进程状态（关注 D 状态，IO 等待） =========="
ps

echo "========== [12/14] 运行队列 =========="
runq

echo "========== [13/14] 已加载模块（存储/文件系统驱动） =========="
mod

echo "========== [14/14] IRQ 中断（磁盘控制器中断） =========="
irq

quit
CMDS
)

{
    echo "======================================================================"
    echo " 场景5: 文件系统只读 / 挂载异常 / IO 卡顿 分析报告"
    echo " 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo " vmlinux : $VMLINUX"
    echo " vmcore  : $VMCORE"
    echo "======================================================================"
    echo ""

    "$CRASH_CMD" -s "$VMLINUX" "$VMCORE" <<< "$CRASH_CMDS" 2>&1

    echo ""
    echo "======================================================================"
    echo " [分析提示]"
    echo "  1. 在 [2/14] log 中搜索:"
    echo "     - EXT4-fs error / XFS error / xfs_force_shutdown"
    echo "     - I/O error / Buffer I/O error / blk_update_request"
    echo "     - remounting read-only（文件系统被迫设为只读）"
    echo "     - Aborting journal / journal commit I/O error"
    echo "  2. 在 [3/14] mount 中确认各分区挂载状态（ro 表示已变只读）"
    echo "  3. 在 [4/14] files 中查看进程打开的文件及所在文件系统"
    echo "  4. 在 [5/14] super 中查看超级块状态，确认文件系统类型和标志"
    echo "  5. 在 [11/14] ps 中筛选 D 状态进程（阻塞在 IO 上）"
    echo "  6. 在 [7/14] bt 中确认崩溃是否在 IO 路径（如 submit_bio）"
    echo "  7. 结合 Scene6 脚本排查底层存储硬件问题"
    echo "  8. super/inode/dentry：有候选类型时先用 struct <type> <addr> 试解是否结构体对象；仅日志无对象地址勿硬套 struct（详见 SKILL.md）。"
    echo "======================================================================"

} | tee "$OUTFILE"

echo ""
echo -e "${GREEN}[完成] 报告已保存至: ${OUTFILE}${RESET}"
