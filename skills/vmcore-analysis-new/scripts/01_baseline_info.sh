#!/usr/bin/env bash
# =============================================================================
# 脚本：01_baseline_info.sh
# 用途：VMcore 基础信息收集、快速定性，并检测源码目录以决定分析路径
# 使用：bash 01_baseline_info.sh <vmcore_path> <vmlinux_path> [src_dir]
# 参数：
#   $1  vmcore 路径（默认 /var/crash/vmcore）
#   $2  vmlinux 路径（默认系统路径）
#   $3  源码目录（可选，若提供且存在则输出源码分析指引）
# =============================================================================

set -euo pipefail

VMCORE="${1:-/var/crash/vmcore}"
VMLINUX="${2:-/usr/lib/debug/lib/modules/$(uname -r)/vmlinux}"
SRC_DIR="${3:-}"

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  echo "用途：VMcore 基础信息收集与快速定性（所有分析的第一步）"
  echo "使用：bash $0 <vmcore> <vmlinux> [src_dir]"
  echo ""
  echo "  src_dir: 可选，内核/驱动源码根目录"
  echo "           若提供，输出将包含源码路径的分析建议"
  echo ""
  echo "输出内容："
  echo "  - 内核版本、架构"
  echo "  - panic 类型（22类关键字匹配，含 bt 层比特翻转关键字）"
  echo "  - 调用栈 + 寄存器"
  echo "  - 分支决策推荐"
  echo "  - 分析路径推荐（源码主导 / 纯vmcore）"
  exit 0
fi

OUT_DIR="/tmp/vmcore_analysis_$(date +%Y%m%d%H%M%S)"
mkdir -p "${OUT_DIR}"
echo "并行收集临时目录: ${OUT_DIR}"

CRASH_TIMEOUT_COMMON="${CRASH_TIMEOUT_COMMON:-600s}"
CRASH_TIMEOUT_LOG="${CRASH_TIMEOUT_LOG:-900s}"
CRASH_TIMEOUT_BT_A="${CRASH_TIMEOUT_BT_A:-900s}"
CRASH_TIMEOUT_DIS="${CRASH_TIMEOUT_DIS:-180s}"

# 封装 crash 命令执行，改为后台并行执行并输出到文件
# 参数1: crash内部命令, 参数2: 输出文件名, 参数3: 描述信息
run_crash_async() {
  local cmd="$1"
  local out_file="${OUT_DIR}/$2"
  local raw_file="${out_file}.raw"
  local err_file="${out_file}.err"
  local desc="$3"
  local timeout_s="${4:-${CRASH_TIMEOUT_COMMON}}"
  echo "正在收集: ${desc} ..."
  (
    if ! command -v crash >/dev/null 2>&1; then
      echo "crash 命令不存在（PATH: ${PATH}）" > "${err_file}"
      : > "${out_file}"
      echo "  [失败] ${desc} -> ${out_file} (stderr: ${err_file})" >> "${OUT_DIR}/summary.txt"
      exit 0
    fi

    set +e
    printf '%s\nquit\n' "$cmd" | timeout "${timeout_s}" crash -s "${VMLINUX}" "${VMCORE}" > "${raw_file}" 2>"${err_file}"
    local crash_rc=$?
    set -e

    grep -v "^WARNING: active task" "${raw_file}" > "${out_file}" || true

    if [[ $crash_rc -eq 0 ]]; then
      rm -f "${raw_file}" "${err_file}" || true
      echo "  [成功] ${desc} -> ${out_file}" >> "${OUT_DIR}/summary.txt"
    else
      echo "  [失败/超时 rc=${crash_rc}] ${desc} -> ${out_file} (stderr: ${err_file})" >> "${OUT_DIR}/summary.txt"
    fi
  ) &
}

run_crash_sync() {
  local cmd="$1"
  local out_file="${OUT_DIR}/$2"
  local raw_file="${out_file}.raw"
  local err_file="${out_file}.err"
  local desc="$3"
  local timeout_s="$4"

  echo "正在收集: ${desc} ..."
  if ! command -v crash >/dev/null 2>&1; then
    echo "crash 命令不存在（PATH: ${PATH}）" > "${err_file}"
    : > "${out_file}"
    echo "  [失败] ${desc} -> ${out_file} (stderr: ${err_file})" >> "${OUT_DIR}/summary.txt"
    return 0
  fi

  set +e
  printf '%s\nquit\n' "$cmd" | timeout "${timeout_s}" crash -s "${VMLINUX}" "${VMCORE}" > "${raw_file}" 2>"${err_file}"
  local crash_rc=$?
  set -e

  grep -v "^WARNING: active task" "${raw_file}" > "${out_file}" || true

  if [[ $crash_rc -eq 0 ]]; then
    rm -f "${raw_file}" "${err_file}" || true
    echo "  [成功] ${desc} -> ${out_file}" >> "${OUT_DIR}/summary.txt"
  else
    echo "  [失败/超时 rc=${crash_rc}] ${desc} -> ${out_file} (stderr: ${err_file})" >> "${OUT_DIR}/summary.txt"
  fi
}

# 检测源码目录
HAS_SRC=false
SRC_STATUS="未提供（将使用纯vmcore分析路径）"
if [[ -n "${SRC_DIR}" && -d "${SRC_DIR}" ]]; then
  HAS_SRC=true
  SRC_COUNT=$(find "${SRC_DIR}" -name "*.c" 2>/dev/null | wc -l)
  SRC_STATUS="已找到：${SRC_DIR}（包含 ${SRC_COUNT} 个 .c 文件）→ 将使用源码主导分析路径"
fi

echo "==================================================================" > "${OUT_DIR}/summary.txt"
echo " VMcore 基础信息收集汇总报告" >> "${OUT_DIR}/summary.txt"
echo " 生成时间：$(date)" >> "${OUT_DIR}/summary.txt"
echo " vmcore  ：${VMCORE}" >> "${OUT_DIR}/summary.txt"
echo " vmlinux ：${VMLINUX}" >> "${OUT_DIR}/summary.txt"
echo " 源码目录：${SRC_STATUS}" >> "${OUT_DIR}/summary.txt"
echo " 超时设置：common=${CRASH_TIMEOUT_COMMON}, log=${CRASH_TIMEOUT_LOG}, bt-a=${CRASH_TIMEOUT_BT_A}, dis=${CRASH_TIMEOUT_DIS}" >> "${OUT_DIR}/summary.txt"
echo " 结果目录：${OUT_DIR}" >> "${OUT_DIR}/summary.txt"
echo "==================================================================" >> "${OUT_DIR}/summary.txt"
echo "" >> "${OUT_DIR}/summary.txt"
echo "【执行状态概览】" >> "${OUT_DIR}/summary.txt"

echo ""
echo "正在并行收集各项信息，请耐心等待..."
echo "------------------------------------------------------------------"

run_crash_async 'sys'    "sys.txt"    "系统基础信息 (sys)" "${CRASH_TIMEOUT_COMMON}"
run_crash_async 'log'    "log.txt"    "内核日志 (log)" "${CRASH_TIMEOUT_LOG}"
run_crash_async 'bt'     "bt.txt"     "当前崩溃调用栈 (bt)" "${CRASH_TIMEOUT_COMMON}"
run_crash_async 'bt -l'  "bt_l.txt"  "带行号调用栈 (bt -l)" "${CRASH_TIMEOUT_COMMON}"
run_crash_async 'bt -a'  "bt_a.txt"  "所有CPU调用栈 (bt -a)" "${CRASH_TIMEOUT_BT_A}"
run_crash_async 'bt -f'  "bt_f.txt"  "调用栈与寄存器 (bt -f)" "${CRASH_TIMEOUT_COMMON}"
run_crash_async 'mod'    "mod.txt"    "已加载内核模块 (mod)" "${CRASH_TIMEOUT_COMMON}"
run_crash_async 'kmem -i' "kmem_i.txt" "内存状态概览 (kmem -i)" "${CRASH_TIMEOUT_COMMON}"
run_crash_async 'ps'     "ps.txt"     "进程状态概览 (ps)" "${CRASH_TIMEOUT_COMMON}"

wait

# --------------------------------------------------------------------------
# 崩溃地址反汇编（依赖 bt 结果，wait 后执行）
# --------------------------------------------------------------------------
RIP_FUNC=$(grep -m 1 -E '^ *#0' "${OUT_DIR}/bt.txt" 2>/dev/null | awk '{print $NF}' || true)
if [[ -n "$RIP_FUNC" ]]; then
  run_crash_sync "dis -l ${RIP_FUNC}" "dis_l.txt" "崩溃地址反汇编 (dis -l ${RIP_FUNC})" "${CRASH_TIMEOUT_DIS}"
else
  echo "  [跳过] 崩溃地址反汇编 (dis) -> 未提取到 RIP_FUNC" >> "${OUT_DIR}/summary.txt"
fi

echo ""
echo "信息收集完成，所有结果已保存在: ${OUT_DIR}"
echo "------------------------------------------------------------------"

echo "" >> "${OUT_DIR}/summary.txt"
echo "【核心内容摘要】" >> "${OUT_DIR}/summary.txt"
echo "------------------------------------------------------------------" >> "${OUT_DIR}/summary.txt"

# --------------------------------------------------------------------------
# 关键字匹配（22类故障模式）
# 匹配来源：
#   - 大多数分支：log.txt（内核日志）
#   - 分支V（疑似Bit Flip）：额外扫描 bt.txt / bt_f.txt，
#     因为比特翻转在 log 中可能无明显关键字，
#     而在 bt 调用栈中会呈现栈帧损坏、非法地址、opcode异常等特征
# --------------------------------------------------------------------------
echo "1. 故障类型关键字匹配结果：" >> "${OUT_DIR}/summary.txt"
declare -A BRANCH_MAP

# ── A~U：从内核日志（log.txt）匹配 ──────────────────────────────────────────
BRANCH_MAP["NULL pointer dereference|unable to handle kernel NULL"]="分支A: 空指针解引用    → scripts/branch_A_null_ptr.sh"
BRANCH_MAP["KASAN: slab-out-of-bounds|KASAN.*out-of-bounds"]="分支B: 内存越界OOB      → scripts/branch_B_oob.sh"
BRANCH_MAP["KASAN: use-after-free|use-after-free"]="分支C: Use-After-Free   → scripts/branch_C_uaf.sh"
BRANCH_MAP["stack-protector|stack overflow|stack guard"]="分支D: 内核栈溢出       → scripts/branch_D_stack_overflow.sh"
BRANCH_MAP["Machine check:|mce.*bank|MCE.*PROCESSOR"]="分支E: 硬件MCE          → scripts/branch_E_mce.sh"
BRANCH_MAP["EDAC.*UE|uncorrectable.*error"]="分支F: 内存UE           → scripts/branch_F_memory_ue.sh"
BRANCH_MAP["possible circular locking|LOCKDEP.*circular"]="分支G: 死锁             → scripts/branch_G_deadlock.sh"
BRANCH_MAP["soft lockup|softlockup"]="分支H: Soft Lockup      → scripts/branch_H_soft_lockup.sh"
BRANCH_MAP["hard LOCKUP|NMI watchdog.*LOCKUP"]="分支I: Hard Lockup      → scripts/branch_I_hard_lockup.sh"
BRANCH_MAP["kernel BUG at|BUG.*line"]="分支J: BUG()触发        → scripts/branch_J_bug_trigger.sh"
BRANCH_MAP["Out of memory|oom_kill|Killed process"]="分支K: OOM Killer       → scripts/branch_K_oom.sh"
BRANCH_MAP["sleeping function called from invalid|might sleep"]="分支L: 原子上下文睡眠   → scripts/branch_L_atomic_sleep.sh"
BRANCH_MAP["rcu_sched detected stalls|RCU stall"]="分支M: RCU Stall        → scripts/branch_M_rcu_stall.sh"
BRANCH_MAP["EXT4-fs error|XFS.*corruption|btrfs.*corrupt"]="分支N: 文件系统崩溃     → scripts/branch_N_fs_corruption.sh"
BRANCH_MAP["double free.*skb|kfree_skb.*double|skb.*poison"]="分支O: 网络子系统崩溃   → scripts/branch_O_network.sh"
BRANCH_MAP["DMA mapping error|I/O timeout.*abort|blk.*abort"]="分支P: 存储IO崩溃       → scripts/branch_P_storage_io.sh"
BRANCH_MAP["vmx_exit|kvm_.*exit|VMX.*exit reason"]="分支Q: KVM/vCPU异常     → scripts/branch_Q_kvm.sh"
BRANCH_MAP["acpi_.*error|AE_BAD_ADDRESS|ACPI Error"]="分支R: ACPI固件异常     → scripts/branch_R_acpi.sh"
BRANCH_MAP["migrate_pages.*fail|offline_pages.*error|page migration"]="分支S: 热插拔/页迁移    → scripts/branch_S_hotplug.sh"
BRANCH_MAP["memory_failure|hwpoison|HardwareCorrupted"]="分支F+V: 内存硬件故障   → scripts/branch_F_memory_ue.sh / branch_V_bit_flip.sh"

MATCHED=()
for pattern in "${!BRANCH_MAP[@]}"; do
  if grep -iEq "${pattern}" "${OUT_DIR}/log.txt" 2>/dev/null; then
    echo "  ✓ MATCHED: ${BRANCH_MAP[$pattern]}" >> "${OUT_DIR}/summary.txt"
    MATCHED+=("${BRANCH_MAP[$pattern]}")
  fi
done

# ── 分支V：疑似 Bit Flip ───────────────────────────────────────────────────
# 扫描来源：log.txt + bt.txt + bt_f.txt
# 关键字说明：
#   log 层：地址访问异常（paging request / Data Abort），直接指向非法地址访问
#   bt  层：
#     - 无符号解析的裸地址帧（RIP 无法映射到函数名）
#     - 栈帧损坏标记（invalid / no return address / corrupted / read error）
#     - 函数指针跳转到非法指令（invalid opcode / undefined instruction / general protection fault）
#     - 数据结构损坏（list_del corruption / list_add corruption / slab corruption /
#                    BUG: Bad page / Corrupted page table / corrupted stack end）
#     - task 指针异常（init_task / swapper 出现在非 idle 进程栈）
#     - 地址越界访问但非空指针（spurious page fault / bad area / bad page state）
BIT_FLIP_PATTERN="paging request|Data Abort|unable to handle kernel paging request"
BIT_FLIP_PATTERN+="|spurious page fault|bad area|bad page state"
BIT_FLIP_PATTERN+="|invalid opcode|undefined instruction|general protection fault|trap: invalid opcode"
BIT_FLIP_PATTERN+="|list_del corruption|list_add corruption|slab corruption"
BIT_FLIP_PATTERN+="|BUG: Bad page|Corrupted page table|corrupted stack end"
BIT_FLIP_PATTERN+="|\(invalid\)|no return address|<no return>|bt: read error|cannot read"

BIT_FLIP_LABEL="分支V: 疑似Bit Flip → scripts/branch_V_bit_flip.sh"

ALREADY_V=false
for m in "${MATCHED[@]}"; do
  [[ "$m" == *"branch_V"* ]] && ALREADY_V=true && break
done

if ! $ALREADY_V; then
  # 同时扫描 log / bt / bt_f 三个文件
  for src_file in "${OUT_DIR}/log.txt" "${OUT_DIR}/bt.txt" "${OUT_DIR}/bt_f.txt"; do
    if grep -iEq "${BIT_FLIP_PATTERN}" "${src_file}" 2>/dev/null; then
      SRC_LABEL=$(basename "${src_file}" .txt)
      echo "  ✓ MATCHED [${SRC_LABEL}]: ${BIT_FLIP_LABEL}" >> "${OUT_DIR}/summary.txt"
      MATCHED+=("${BIT_FLIP_LABEL}")
      ALREADY_V=true
      break
    fi
  done
fi

if [ ${#MATCHED[@]} -eq 0 ]; then
  echo "  ✗ 无明确故障类型关键字，需通过调用栈进一步判断" >> "${OUT_DIR}/summary.txt"
fi

# --------------------------------------------------------------------------
# D 状态进程
# --------------------------------------------------------------------------
echo "" >> "${OUT_DIR}/summary.txt"
echo "2. D 状态进程（可能与崩溃相关）Top 20：" >> "${OUT_DIR}/summary.txt"
grep " D " "${OUT_DIR}/ps.txt" 2>/dev/null | head -20 >> "${OUT_DIR}/summary.txt" || true

# --------------------------------------------------------------------------
# 综合决策输出
# --------------------------------------------------------------------------
echo "" >> "${OUT_DIR}/summary.txt"
echo "==================================================================" >> "${OUT_DIR}/summary.txt"
echo " 后续分析脚本指引" >> "${OUT_DIR}/summary.txt"
echo "==================================================================" >> "${OUT_DIR}/summary.txt"

if [ ${#MATCHED[@]} -gt 0 ]; then
  for b in "${MATCHED[@]}"; do
    SCRIPT=$(echo "$b" | grep -oP 'scripts/\S+')
    if [[ -n "$SCRIPT" ]]; then
      if $HAS_SRC; then
        echo "建议执行: bash ${SCRIPT} ${VMCORE} ${VMLINUX} ${SRC_DIR}" >> "${OUT_DIR}/summary.txt"
      else
        echo "建议执行: bash ${SCRIPT} ${VMCORE} ${VMLINUX}" >> "${OUT_DIR}/summary.txt"
      fi
    fi
  done
else
  echo "未匹配到特定故障分支，需根据调用栈进行进一步分析。" >> "${OUT_DIR}/summary.txt"
fi
echo "==================================================================" >> "${OUT_DIR}/summary.txt"

# 最终输出
cat "${OUT_DIR}/summary.txt"
