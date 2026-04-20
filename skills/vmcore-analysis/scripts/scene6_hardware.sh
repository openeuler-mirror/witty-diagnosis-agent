#!/bin/bash
# =============================================================================
# 场景 6：硬件故障 / 驱动崩溃 深度信息收集脚本
# 用法: ./scene6_hardware.sh [--crash CMD] [--vmlinux PATH] [--vmcore PATH]
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
OUTFILE="${LOG_CWD}/scene6_hardware_$(date +%Y%m%d_%H%M%S).log"
echo -e "${CYAN}${BOLD}[场景6] 硬件故障 / 驱动崩溃 信息收集${RESET}"
echo -e "${GREEN}输出文件: ${OUTFILE}${RESET}"
echo ""

CRASH_CMDS=$(cat <<'CMDS'
echo "========== [1/15] 系统基本信息 =========="
sys

echo "========== [2/15] 内核日志 (MCE/PCI/Hardware Error/driver crash) =========="
log

echo "========== [3/15] 已加载驱动模块列表 =========="
mod

echo "========== [4/15] 崩溃调用栈 =========="
bt

echo "========== [5/15] 带行号调用栈（定位驱动代码行） =========="
bt -l

echo "========== [6/15] 带完整帧信息调用栈 =========="
bt -f

echo "========== [7/15] 所有 CPU 调用栈 =========="
bt -a

echo "========== [8/15] CPU 寄存器快照 =========="
bt -r

echo "========== [9/15] IRQ 中断统计（检查硬件中断异常） =========="
irq

echo "========== [10/15] 所有进程状态 =========="
ps

echo "========== [11/15] 运行队列（检查 CPU 阻塞） =========="
runq

echo "========== [12/15] 内存信息（硬件故障可能导致内存损坏） =========="
kmem -i

echo "========== [13/15] 页面错误统计 =========="
kmem -p | head -40

echo "========== [14/15] 网络设备（检查网卡驱动崩溃） =========="
net -d

echo "========== [15/15] 挂载信息（IO 控制器故障影响） =========="
mount

quit
CMDS
)

{
    echo "======================================================================"
    echo " 场景6: 硬件故障 / 驱动崩溃 分析报告"
    echo " 生成时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo " vmlinux : $VMLINUX"
    echo " vmcore  : $VMCORE"
    echo "======================================================================"
    echo ""

    "$CRASH_CMD" -s "$VMLINUX" "$VMCORE" <<< "$CRASH_CMDS" 2>&1

    echo ""
    echo "======================================================================"
    echo " [分析提示]"
    echo "  1. 在 [2/15] log 中搜索:"
    echo "     - Machine Check Exception (MCE) / Hardware Error"
    echo "     - PCI error / AER / DMAR"
    echo "     - EDAC / ECC / memory error / corrected / uncorrected"
    echo "     - driver crashed in module / BUG: unable to handle"
    echo "  2. 在 [3/15] mod 中确认崩溃时加载的驱动模块版本"
    echo "     对比 bt 调用栈，确认崩溃函数属于哪个模块"
    echo "  3. 在 [4/15] bt 中检查崩溃函数是否属于驱动模块"
    echo "     驱动函数特征: 模块名出现在栈帧末尾，如 [mlx5_core]"
    echo "  4. 在 [8/15] bt -r 中检查寄存器异常值（高位突变）"
    echo "     若发现异常，运行: ./scripts/check_bitflip.sh <期望值> <实际值>"
    echo "  5. 在 [9/15] irq 中检查中断计数异常（某 CPU 独占或全为0）"
    echo "  6. MCE 确认方法: log 中包含 'Machine check events logged'"
    echo "     或 'mce: [Hardware Error]: Machine check events logged'"
    echo "  7. PCI 故障: 搜索 'pcieport' / 'aer_recover_work_func' / 'AER'"
    echo "  8. PCI/设备：有候选类型时先用 struct <type> <addr> 试解是否结构体对象；无可用地址时以 log 为主勿强行 struct（详见 SKILL.md）。"
    echo "======================================================================"

} | tee "$OUTFILE"

echo ""
echo -e "${GREEN}[完成] 报告已保存至: ${OUTFILE}${RESET}"
