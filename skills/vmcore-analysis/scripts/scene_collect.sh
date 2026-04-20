#!/bin/bash
# =============================================================================
# vmcore 故障场景分析 —— 总入口脚本
# 根据故障类型自动调用对应场景收集脚本
#
# 用法:
#   ./scene_collect.sh --scene <1-6> [--crash CMD] [--vmlinux PATH] [--vmcore PATH]
#   ./scene_collect.sh --auto   [--crash CMD] [--vmlinux PATH] [--vmcore PATH]
#
# 场景说明:
#   1 - 内核崩溃 / Kernel Panic
#   2 - 内存泄漏 / OOM / 内存耗尽
#   3 - 系统挂死 / 死锁 / 无响应
#   4 - 网络不通 / 网络崩溃
#   5 - 文件系统只读 / 挂载异常 / IO 卡顿
#   6 - 硬件故障 / 驱动崩溃
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; BLUE='\033[0;34m'; BOLD='\033[1m'; RESET='\033[0m'

# ── 默认参数 ──────────────────────────────────────────────────────────────────
CRASH_CMD="./crash"
VMLINUX="./vmlinux"
VMCORE="./vmcore"
SCENE=""
AUTO_MODE=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 使用说明 ──────────────────────────────────────────────────────────────────
usage() {
    cat <<EOF
${BOLD}vmcore 故障场景分析入口${RESET}

${CYAN}用法:${RESET}
  $0 --scene <1-6>  [选项]   # 指定场景
  $0 --auto         [选项]   # 自动识别场景（先运行基础收集再判断）

${CYAN}场景列表:${RESET}
  ${GREEN}1${RESET}  内核崩溃 / Kernel Panic        → scene1_kernel_panic.sh
  ${GREEN}2${RESET}  内存泄漏 / OOM / 内存耗尽      → scene2_oom.sh
  ${GREEN}3${RESET}  系统挂死 / 死锁 / 无响应        → scene3_deadlock.sh
  ${GREEN}4${RESET}  网络不通 / 网络崩溃             → scene4_network.sh
  ${GREEN}5${RESET}  文件系统只读 / 挂载异常 / IO   → scene5_filesystem.sh
  ${GREEN}6${RESET}  硬件故障 / 驱动崩溃             → scene6_hardware.sh

${CYAN}选项:${RESET}
  --crash   <path>   crash 命令路径  (默认: ./crash)
  --vmlinux <path>   vmlinux 路径   (默认: ./vmlinux)
  --vmcore  <path>   vmcore 路径    (默认: ./vmcore)
  -h, --help         显示帮助

${CYAN}示例:${RESET}
  # 指定场景1分析
  $0 --scene 1 --crash ./crash --vmlinux ./vmlinux --vmcore ./vmcore

  # 自动识别场景（从基础日志中推断）
  $0 --auto

  # 在故障目录中使用默认路径
  cd pcie_panic && $0 --scene 6
EOF
}

# ── 参数解析 ──────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --scene)    SCENE="$2";      shift 2 ;;
        --auto)     AUTO_MODE=true;  shift   ;;
        --crash)    CRASH_CMD="$2";  shift 2 ;;
        --vmlinux)  VMLINUX="$2";    shift 2 ;;
        --vmcore)   VMCORE="$2";     shift 2 ;;
        -h|--help)  usage; exit 0 ;;
        *) echo -e "${RED}未知参数: $1${RESET}"; usage; exit 1 ;;
    esac
done

# ── 校验 ──────────────────────────────────────────────────────────────────────
if [[ -z "$SCENE" && "$AUTO_MODE" == false ]]; then
    echo -e "${RED}[ERROR] 请指定 --scene <1-6> 或使用 --auto${RESET}"
    echo ""
    usage
    exit 1
fi

for f in "$VMLINUX" "$VMCORE"; do
    if [[ ! -f "$f" ]]; then
        echo -e "${RED}[ERROR] 文件不存在: $f${RESET}"
        exit 1
    fi
done

# ── 场景映射 ──────────────────────────────────────────────────────────────────
declare -A SCENE_SCRIPTS=(
    [1]="scene1_kernel_panic.sh"
    [2]="scene2_oom.sh"
    [3]="scene3_deadlock.sh"
    [4]="scene4_network.sh"
    [5]="scene5_filesystem.sh"
    [6]="scene6_hardware.sh"
)

declare -A SCENE_NAMES=(
    [1]="内核崩溃 / Kernel Panic"
    [2]="内存泄漏 / OOM / 内存耗尽"
    [3]="系统挂死 / 死锁 / 无响应"
    [4]="网络不通 / 网络崩溃"
    [5]="文件系统只读 / 挂载异常 / IO 卡顿"
    [6]="硬件故障 / 驱动崩溃"
)

# ── 自动识别场景 ──────────────────────────────────────────────────────────────
# 从 scene_collect crash 批量输出中截取「内核 log」段，供场景 6 仅针对 dmesg 匹配，避免 mod/ps 中符号名误报。
# 新会话在 log 前后输出 @@@VMCORE_AUTO_KERNLOG_BEGIN/END@@@（与 AUTO 2/5 标题并存，截取不依赖标题行格式）。
# 无标记的旧 autodetect 日志仍用 AUTO 2/5「内核日志」～ AUTO 3/5「崩溃调用栈」回退。
_autodetect_kernel_log_section() {
    local f="$1"
    if grep -qF "@@@VMCORE_AUTO_KERNLOG_BEGIN@@@" "$f" 2>/dev/null; then
        awk '
            index($0, "@@@VMCORE_AUTO_KERNLOG_BEGIN@@@") { fl = 1; next }
            index($0, "@@@VMCORE_AUTO_KERNLOG_END@@@")   { fl = 0; next }
            fl { print }
        ' "$f"
    else
        awk '
            index($0, "========== [AUTO 2/5]") && index($0, "内核日志") { fl = 1; next }
            index($0, "========== [AUTO 3/5]") && index($0, "崩溃调用栈") { fl = 0 }
            fl { print }
        ' "$f"
    fi
}

auto_detect_scene() {
    echo -e "${YELLOW}[AUTO] 正在从 vmcore 中提取基础日志以自动识别故障场景...${RESET}"

    local tmplog
    tmplog=$(mktemp /tmp/vmcore_autodetect_XXXXXX.log)

    "$CRASH_CMD" -s "$VMLINUX" "$VMCORE" <<'DETECT' > "$tmplog" 2>&1
echo "========== [AUTO 1/5] 系统基本信息 =========="
sys

echo "========== [AUTO 2/5] 内核日志 =========="
echo @@@VMCORE_AUTO_KERNLOG_BEGIN@@@
log
echo @@@VMCORE_AUTO_KERNLOG_END@@@

echo "========== [AUTO 3/5] 崩溃调用栈 =========="
bt

echo "========== [AUTO 4/5] 进程快照 =========="
ps

echo "========== [AUTO 5/5] 已加载模块 =========="
mod

quit
DETECT

    echo -e "${CYAN}[AUTO] 日志关键字分析结果:${RESET}"

    # 各条独立命中时都会打印；最终入口场景按固定优先级在「所有命中」中选一个：6>5>4>3>2>1
    local detected=""
    local -a matched_scenes=()

    _add_match() {
        local n="$1"
        local i
        for i in "${matched_scenes[@]}"; do
            [[ "$i" == "$n" ]] && return 0
        done
        matched_scenes+=("$n")
    }

    # 场景 6（A+B）：仅在「内核 log」段匹配；去掉裸 EDAC/ECC/MCE（避免 mod 里 skx_edac、符号表等误报），改为事件型/接口型关键字
    local kernlog
    kernlog=$(_autodetect_kernel_log_section "$tmplog")
    if [[ -n "$kernlog" ]] && grep -qiE \
        "Hardware Error|Machine Check Exception|Machine check events|Kernel machine check|\
mce:|MCE:|PCIe Bus Error|PCI Bus Error|PCI [Ee]rror|AER:|\
Multiple Uncorrected|Uncorrected error|Corrected error received|\
EDAC MC|HANDLING MCE MEMORY|UE memory|CE memory|DRAM ECC error|ECC error|\
driver crashed in module" \
        <<<"$kernlog"; then
        echo -e "  ${RED}→ 检测到硬件/驱动错误关键字（仅内核 log 段）${RESET}"
        _add_match 6
    fi

    if grep -qiE "EXT4-fs error|XFS error|xfs_force_shutdown|I/O error|remounting read-only|Aborting journal" "$tmplog"; then
        echo -e "  ${RED}→ 检测到文件系统错误关键字${RESET}"
        _add_match 5
    fi

    # 场景 4（D）：不用裸 network/eth/ens；先去掉 DMI「Hardware name:」行，避免 OpenStack Nova 等误报
    if grep -vF "Hardware name:" "$tmplog" | grep -qiE "eth[0-9]+|ens[0-9]+|enp[0-9a-z]+|eno[0-9]+|bond[0-9]+|wlan[0-9]+|ppp|tun|tap|\
tx timeout|NETDEV WATCHDOG|link down|NETDEV|netdev watchdog|carrier|xmit|rx ring|drop packet"; then
        echo -e "  ${YELLOW}→ 检测到网络相关关键字${RESET}"
        _add_match 4
    fi

    if grep -qiE "hung_task|soft lockup|RCU stall|blocked for more than|INFO: task" "$tmplog"; then
        echo -e "  ${YELLOW}→ 检测到系统挂死/死锁关键字${RESET}"
        _add_match 3
    fi

    if grep -qiE "Out of memory|OOM|killed process|Memory cgroup out of memory|oom_kill" "$tmplog"; then
        echo -e "  ${YELLOW}→ 检测到 OOM/内存耗尽关键字${RESET}"
        _add_match 2
    fi

    if grep -qiE "Kernel panic|Call Trace|RIP:|oops:|BUG:" "$tmplog"; then
        echo -e "  ${GREEN}→ 检测到 Kernel Panic/Oops 关键字${RESET}"
        _add_match 1
    fi

    # 在命中的场景中按优先级选一个作为默认入口（与 vmcore 中大量通用串词并存时仍有一个确定分支）
    local chosen=""
    local s i
    for s in 6 5 4 3 2 1; do
        for i in "${matched_scenes[@]}"; do
            [[ "$i" == "$s" ]] && { chosen="$s"; break 2; }
        done
    done
    detected="$chosen"

    # 保留本轮 sys/log/bt/ps/mod 输出，便于对照 SKILL 与人工复核（原先用临时文件仅 grep 后即删）
    local _log_cwd
    _log_cwd="$(pwd -P 2>/dev/null || pwd)"
    local autolog="${_log_cwd}/scene_collect_autodetect_$(date +%Y%m%d_%H%M%S).log"
    mv "$tmplog" "$autolog"
    echo -e "${GREEN}[AUTO] 用于关键字匹配的 crash 输出已保存: ${autolog}${RESET}"

    if [[ -z "$detected" ]]; then
        echo -e "${YELLOW}[AUTO] 无法自动识别场景，默认使用场景1（内核崩溃）${RESET}"
        echo -e "${YELLOW}       建议手动指定: --scene <1-6>${RESET}"
        detected=1
    elif [[ ${#matched_scenes[@]} -gt 1 ]]; then
        echo -e "${CYAN}[AUTO] 关键字命中多个场景，候选（按场景编号排序）:${RESET}"
        local n
        for n in 1 2 3 4 5 6; do
            for i in "${matched_scenes[@]}"; do
                if [[ "$i" == "$n" ]]; then
                    echo -e "  ${CYAN}• 场景 ${n} — ${SCENE_NAMES[$n]}${RESET}"
                    break
                fi
            done
        done
        echo -e "${GREEN}[AUTO] 按优先级可选用入口: 场景 ${detected} — ${SCENE_NAMES[$detected]}（可用 --scene 指定其它候选）${RESET}"
    else
        echo -e "${GREEN}[AUTO] 按关键字匹配的自动识别结果: 场景 ${detected} — ${SCENE_NAMES[$detected]}${RESET}"
    fi
    echo ""
    SCENE="$detected"
}

# ── 主流程 ────────────────────────────────────────────────────────────────────
print_banner() {
    echo ""
    echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════╗${RESET}"
    echo -e "${BOLD}${BLUE}║       vmcore 故障场景信息收集工具                ║${RESET}"
    echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════╝${RESET}"
    echo ""
}

print_banner

if [[ "$AUTO_MODE" == true ]]; then
    auto_detect_scene
fi

echo -e "${CYAN}[分析提示] 深入 vmcore：疑似对象地址且有候选类型时，先用 struct <type> <addr> 试解以判断是否结构体对象（详见 SKILL.md）；确认后再依赖该 dump；RIP/标量/统计勿硬套 struct。请再手动执行同目录 sceneN_*.sh 做专项收集。${RESET}"
echo ""

# 校验场景编号
if [[ ! "${SCENE_SCRIPTS[$SCENE]+_}" ]]; then
    echo -e "${RED}[ERROR] 无效场景编号: $SCENE（有效值: 1-6）${RESET}"
    exit 1
fi

# SCRIPT="${SCRIPT_DIR}/${SCENE_SCRIPTS[$SCENE]}"

# if [[ ! -f "$SCRIPT" ]]; then
#     echo -e "${RED}[ERROR] 场景脚本不存在: $SCRIPT${RESET}"
#     echo -e "${YELLOW}请确认所有 scene*.sh 脚本与本脚本在同一目录${RESET}"
#     exit 1
# fi

# echo -e "${CYAN}场景: ${BOLD}${SCENE} — ${SCENE_NAMES[$SCENE]}${RESET}"
# echo -e "${CYAN}脚本: ${SCRIPT}${RESET}"
# echo -e "${CYAN}crash  : ${CRASH_CMD}${RESET}"
# echo -e "${CYAN}vmlinux: ${VMLINUX}${RESET}"
# echo -e "${CYAN}vmcore : ${VMCORE}${RESET}"
# echo ""

# # 赋予执行权限并运行
# chmod +x "$SCRIPT"
# exec "$SCRIPT" \
#     --crash   "$CRASH_CMD" \
#     --vmlinux "$VMLINUX" \
#     --vmcore  "$VMCORE"
