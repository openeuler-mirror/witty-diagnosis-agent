#!/bin/bash
# =============================================================================
# 场景 4：网络不通 / 网络崩溃 深度信息收集脚本
# 用法: ./scene4_network.sh [--crash CMD] [--vmlinux PATH] [--vmcore PATH]
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
OUTFILE="${LOG_CWD}/scene4_network_$(date +%Y%m%d_%H%M%S).log"
echo -e "${CYAN}${BOLD}[场景4] 网络不通 / 网络崩溃 信息收集${RESET}"
echo -e "${GREEN}输出文件: ${OUTFILE}${RESET}"
echo ""

CRASH_CMDS=$(cat <<'CMDS'
echo "========== [1/14] 系统基本信息 =========="
sys

echo "========== [2/14] 内核日志 (网络相关: link/tx/rx/nic) =========="
log

echo "========== [3/14] 网络设备列表及状态 =========="
net

echo "========== [4/14] 网络设备详细信息 =========="
net -d

echo "========== [5/14] Socket 统计信息 =========="
net -s

echo "========== [6/14] ARP/路由表 =========="
net -a

echo "========== [7/14] 协议统计 =========="
net -p

echo "========== [8/14] 已加载模块（定位网卡驱动） =========="
mod

echo "========== [9/14] 崩溃调用栈 =========="
bt

echo "========== [10/14] 带行号调用栈 =========="
bt -l

echo "========== [11/14] 所有 CPU 调用栈 =========="
bt -a

echo "========== [12/14] IRQ 中断信息 =========="
irq

echo "========== [13/14] 所有进程状态 =========="
ps

echo "========== [14/14] 内存情况（网络 skb 可能耗内存） =========="
kmem -i

quit
CMDS
)

{
    echo "======================================================================"
    echo " 场景4: 网络不通 / 网络崩溃 分析报告"
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
    echo "     - link down / link up（网口状态变化）"
    echo "     - tx timeout（发送超时，驱动或硬件问题）"
    echo "     - NETDEV WATCHDOG（看门狗超时，网卡无响应）"
    echo "     - eth/ens/bond/ib（网络接口名）"
    echo "  2. 在 [3/14] net 中确认网卡接口 UP/DOWN 状态、统计计数"
    echo "  3. 在 [8/14] mod 中确认网卡驱动模块是否加载（如 mlx5_core/ixgbe）"
    echo "  4. 在 [9/14] bt 中确认崩溃是否发生在网络驱动函数中"
    echo "  5. 在 [12/14] irq 中查找对应网卡的中断是否异常（计数为0或暴增）"
    echo "  6. 若怀疑 SKB 内存泄漏可进一步用: kmem -S skbuff_head_cache"
    echo "  7. net_device/sock：有候选类型时先用 struct <type> <addr> 试解是否结构体对象；统计/计数勿 struct（详见 SKILL.md）。"
    echo "======================================================================"

} | tee "$OUTFILE"

echo ""
echo -e "${GREEN}[完成] 报告已保存至: ${OUTFILE}${RESET}"
