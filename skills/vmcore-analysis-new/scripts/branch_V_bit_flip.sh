#!/usr/bin/env bash
# =============================================================================
# E4 专项验证：1-Bit Flip 真实性验证 v2
#
# 优化点：
#   1. 新增三层 expected/actual 提取（对齐 branch_V_bit_flip.sh）
#      来源1: Bad page / slab poison log（最可靠）
#      来源2: ECC/EDAC syndrome（硬件直接给差异位图）
#      来源3: CR2 vs per-cpu 期望地址 XOR（原脚本逻辑，作为兜底）
#   2. Bit Flip 结果最优先打印
#   3. 删除冗余的备用路径（只保留最短路径）
#   4. crash 命令并行执行（log/bt/percpu/preempt 四路同时采集）
#   5. Python3 精确 64-bit 计算 + 二进制对比可视化
# =============================================================================

set -uo pipefail

CRASH_DIR="/home/chentb/crash/11-2"
VMCORE="${CRASH_DIR}/vmcore"
VMLINUX="${CRASH_DIR}/vmlinux"
CRASH_BIN="${CRASH_DIR}/crash"
EXPECTED_CPU="23"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

pass() { echo -e "${GREEN}  [PASS]${NC} $*"; }
fail() { echo -e "${RED}  [FAIL]${NC} $*"; }
warn() { echo -e "${YELLOW}  [WARN]${NC} $*"; }
info() { echo -e "${CYAN}  [INFO]${NC} $*"; }
sect() {
    echo -e "\n${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  $*${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

run_crash() {
    printf '%s\nquit\n' "$1" \
        | "${CRASH_BIN}" "${VMLINUX}" "${VMCORE}" 2>/dev/null \
        | grep -v '^crash>' | grep -v '^$' || true
}

# =============================================================================
# 【并行采集】四路 crash 命令同时执行，结果写临时文件
# =============================================================================
TMP_DIR=$(mktemp -d)
trap 'rm -rf "${TMP_DIR}"' EXIT

sect "并行采集：log / bt -r / per_cpu_offset / preempt_count"

# 并行启动四个 crash 子进程
run_crash "log"                                   > "${TMP_DIR}/log.txt"    &  PID_LOG=$!
run_crash "bt -r"                                 > "${TMP_DIR}/btreg.txt"  &  PID_BT=$!
run_crash "p __per_cpu_offset[${EXPECTED_CPU}]"   > "${TMP_DIR}/percpu.txt" &  PID_PC=$!
run_crash "p &__preempt_count"                    > "${TMP_DIR}/preempt.txt"&  PID_PM=$!

wait $PID_LOG $PID_BT $PID_PC $PID_PM
info "四路并行采集完成"

RAW_LOG=$(cat "${TMP_DIR}/log.txt")
BT_REG=$(cat  "${TMP_DIR}/btreg.txt")
PERCPU_OUT=$(cat "${TMP_DIR}/percpu.txt")
PREEMPT_OUT=$(cat "${TMP_DIR}/preempt.txt")

# =============================================================================
# ★ 优先打印：三层 expected/actual 提取 + Bit Flip 结论
#   （结果最先呈现，其余步骤细节在后面展开）
# =============================================================================
sect "★ Bit Flip 快速结论（优先输出）"

EXPECTED_STR=""; ACTUAL_STR=""; SYNDROME_STR=""
EXTRACT_SOURCE=""; XOR_VAL=0; XOR_HEX=""

# ── 来源1：Bad page / slab poison ──────────────────────────────────────────
extract_from_bad_page() {
    local line
    # 格式1: raw: expected:HEX actual:HEX
    line=$(echo "$RAW_LOG" | grep -m1 -E 'expected:[0-9a-fA-F]+ actual:[0-9a-fA-F]+')
    if [[ -n "$line" ]]; then
        EXPECTED_STR="0x$(echo "$line" | grep -oP 'expected:\K[0-9a-fA-F]+')"
        ACTUAL_STR="0x$(echo "$line" | grep -oP 'actual:\K[0-9a-fA-F]+')"
        EXTRACT_SOURCE="来源1-BadPage/SlabPoison（内核直接打印）"
        return 0
    fi
    # 格式2: expected 0xHEX, actual 0xHEX
    line=$(echo "$RAW_LOG" | grep -m1 -E 'expected 0x[0-9a-fA-F]+.*actual 0x[0-9a-fA-F]+')
    if [[ -n "$line" ]]; then
        EXPECTED_STR=$(echo "$line" | grep -oP 'expected \K0x[0-9a-fA-F]+')
        ACTUAL_STR=$(echo "$line" | grep -oP 'actual \K0x[0-9a-fA-F]+')
        EXTRACT_SOURCE="来源1-BadPage/SlabPoison（内核直接打印）"
        return 0
    fi
    return 1
}

# ── 来源2：ECC/EDAC syndrome ────────────────────────────────────────────────
extract_from_edac() {
    local line
    line=$(echo "$RAW_LOG" | grep -m1 -iE 'syndrome[: =]+0x[0-9a-fA-F]+')
    if [[ -n "$line" ]]; then
        SYNDROME_STR=$(echo "$line" | grep -oP '(?i)syndrome[: =]+\K0x[0-9a-fA-F]+')
        EXTRACT_SOURCE="来源2-ECC/EDAC（syndrome 即翻转 bit 位图，直接使用）"
        return 0
    fi
    return 1
}

# ── 来源3：CR2 vs per-cpu 期望地址 XOR（原脚本核心逻辑）────────────────────
extract_from_cr2_percpu() {
    # 从 bt -r 提取 CR2
    # crash 输出格式示例：  CR2: ffff8f26fe4d5c10
    # 用 grep -i 找含 CR2 的行，再用 grep -oE 取 12~16 位十六进制串（避免变长 lookbehind）
    local CR2_RAW
    CR2_RAW=$(echo "${BT_REG}" \
        | grep -i 'CR2' \
        | grep -oE '[0-9a-fA-F]{12,16}' \
        | head -1 || true)
    # bt -r 找不到时，回退到 dmesg log
    [[ -z "${CR2_RAW}" ]] && \
        CR2_RAW=$(echo "${RAW_LOG}" \
            | grep -i 'CR2' \
            | grep -oE '[0-9a-fA-F]{12,16}' | head -1 || true)

    [[ -z "${CR2_RAW}" ]] && { warn "CR2 无法提取，来源3 跳过"; return 1; }

    # 提取 per-cpu base
    # crash 输出格式示例：
    #   __per_cpu_offset[23] = 0xffff8fa6fe4c0000
    #   $1 = 18446612134651961344       ← 十进制，无 0x
    # 用 awk 按 = 号切割取最后一列，再过滤十六进制/十进制数值，兼容所有格式
    local PERCPU_BASE
    PERCPU_BASE=$(echo "${PERCPU_OUT}" | awk -F'=' '{print $NF}' \
        | grep -oE '(0x)?[0-9a-fA-F]{12,16}' | head -1 | sed 's/0x//' || true)
    # 若 crash 输出的是十进制大整数，用 python3 转换
    if [[ -z "${PERCPU_BASE}" ]]; then
        local DEC_VAL
        DEC_VAL=$(echo "${PERCPU_OUT}" | awk -F'=' '{print $NF}' \
            | grep -oE '[0-9]{15,20}' | head -1 || true)
        [[ -n "${DEC_VAL}" ]] && \
            PERCPU_BASE=$(python3 -c "print(format(${DEC_VAL}, 'x'))" 2>/dev/null || true)
    fi
    [[ -z "${PERCPU_BASE}" ]] && { warn "__per_cpu_offset 无法提取，来源3 跳过"; return 1; }

    # 提取 __preempt_count 偏移（同样用 awk + 宽字符类正则，避免变长 lookbehind）
    local PREEMPT_OFFSET
    PREEMPT_OFFSET=$(echo "${PREEMPT_OUT}" | awk -F'=' '{print $NF}' \
        | grep -oE '(0x)?[0-9a-fA-F]{4,16}' | head -1 | sed 's/0x//' || true)
    [[ -z "${PREEMPT_OFFSET}" ]] && { warn "__preempt_count 偏移无法提取，来源3 跳过"; return 1; }

    local INT_BASE INT_OFFSET INT_EXPECTED
    INT_BASE=$((16#${PERCPU_BASE}))
    INT_OFFSET=$((16#${PREEMPT_OFFSET}))
    INT_EXPECTED=$(( INT_BASE + INT_OFFSET ))
    ADDR_EXPECTED=$(printf "%016x" ${INT_EXPECTED})

    EXPECTED_STR="0x${ADDR_EXPECTED}"
    ACTUAL_STR="0x${CR2_RAW,,}"
    EXTRACT_SOURCE="来源3-CR2 vs per-cpu 期望地址（__per_cpu_offset[${EXPECTED_CPU}]=0x${PERCPU_BASE} + offset=0x${PREEMPT_OFFSET}）"
    return 0
}

# ── 按优先级尝试三种来源 ────────────────────────────────────────────────────
if extract_from_bad_page; then
    info "✅ ${EXTRACT_SOURCE}"
elif extract_from_edac; then
    info "✅ ${EXTRACT_SOURCE}"
elif extract_from_cr2_percpu; then
    info "✅ ${EXTRACT_SOURCE}"
else
    fail "三种来源均未能提取期望值/实际值，请参考手动步骤"
    echo ""
    warn "手动操作提示："
    warn "  crash> log | grep -E 'expected|actual|EDAC|syndrome'"
    warn "  crash> bt -r  # 找 CR2"
    warn "  crash> p __per_cpu_offset[CPU_ID]"
    exit 1
fi

# ── Python3 精确计算 + 可视化输出 ────────────────────────────────────────────
python3 - "$EXPECTED_STR" "$ACTUAL_STR" "$SYNDROME_STR" "$EXTRACT_SOURCE" <<'PY'
import sys

def bit_positions(n):
    positions = []
    pos = 0
    while n:
        if n & 1:
            positions.append(pos)
        n >>= 1
        pos += 1
    return positions

def print_bitflip_result(xor, e=None, a=None, source=""):
    print()
    print("  ┌──────────────────────────────────────────────────────────────┐")
    print("  │                Bit Flip 验证结果                            │")
    print("  └──────────────────────────────────────────────────────────────┘")
    print(f"  值来源 : {source}")
    print()
    if e is not None and a is not None:
        print(f"  期望值（expected）: 0x{e:016x}")
        print(f"  实际值（actual）  : 0x{a:016x}")
        print(f"  XOR 差值          : 0x{xor:016x}  ({xor})")
    else:
        print(f"  syndrome（翻转位图）: 0x{xor:016x}  ({xor})")
        print("  说明：syndrome 由 ECC 硬件计算，直接等于 expected XOR actual")

    if xor == 0:
        print()
        print("  ⚠️  XOR = 0，两值完全相同，无翻转，请确认提取是否正确")
        return

    # 二进制对比（高48位，bit47~0 翻转区域）
    if e is not None and a is not None:
        print()
        print("  64-bit 二进制对比（bit 47～32 区域）：")
        e_bin = f"{e:064b}"
        a_bin = f"{a:064b}"
        xor_bin = f"{xor:064b}"
        markers  = ''.join('^' if c == '1' else ' ' for c in xor_bin)
        print(f"    期望: {e_bin}")
        print(f"    实际: {a_bin}")
        print(f"    差异: {xor_bin}")
        print(f"    标记: {markers}")

    flipped = bit_positions(xor)
    bc = len(flipped)
    print()
    print(f"  翻转 bit 数量 : {bc} 位")
    print(f"  翻转 bit 位置 : {', '.join(f'bit{p}' for p in flipped)}")

    if bc == 1:
        p = flipped[0]
        if e is not None and a is not None:
            direction = "0→1" if (a >> p) & 1 else "1→0"
        else:
            direction = "未知（syndrome 模式）"
        print()
        print(f"  ✅ 严格单 bit flip —— bit{p}  ({direction})  差异值 = 2^{p} = {xor}")
        if p == 39:
            print("  ✅ bit 编号 = 39，与报告描述完全一致 ✓")
        print()
        print("  ┌─────────────────────────────────────────────────────┐")
        print("  │ ✅ 1-Bit Flip 真实存在，报告结论成立               │")
        print("  ├─────────────────────────────────────────────────────┤")
        print("  │ 根因推断：                                          │")
        print("  │   首选：DRAM DIMM 颗粒缺陷（老化/电压/宇宙射线）   │")
        print("  │   次选：CPU Cache 一致性硬件 Bug                    │")
        print("  ├─────────────────────────────────────────────────────┤")
        print("  │ 处置建议：                                          │")
        print("  │   1. 立即隔离该物理宿主机，下线业务                 │")
        print("  │   2. 查 BMC SEL / EDAC 日志确认 CE/UE 历史告警     │")
        print("  │   3. memtest86+ 全内存压测（至少 2 轮）             │")
        print("  │   4. 更换对应插槽 DIMM 内存条                       │")
        print("  │   5. 复测通过后重新上线                             │")
        print("  └─────────────────────────────────────────────────────┘")
    else:
        print()
        print(f"  ❌ 多 bit 翻转（{bc} 位），不符合单 bit 硬件翻转特征")
        print("  可能原因：软件写坏（UAF/OOB/并发竞争），或自动提取的值有误")
        print("  建议：人工核对 log 原始输出，并排查软件路径")

def main():
    exp_str, act_str, syn_str, source = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
    # 来源2：syndrome 直通
    if syn_str:
        try:
            xor = int(syn_str, 0)
        except ValueError:
            print(f"  错误：syndrome 解析失败（{syn_str}）")
            sys.exit(1)
        print_bitflip_result(xor, source=source)
        return
    # 来源1/3：expected ^ actual
    try:
        e = int(exp_str, 0)
        a = int(act_str, 0)
    except ValueError:
        print(f"  错误：数值解析失败（expected={exp_str}, actual={act_str}）")
        sys.exit(1)
    print_bitflip_result(e ^ a, e=e, a=a, source=source)

if __name__ == "__main__":
    main()
PY

# =============================================================================
# 后续详细步骤（细节展开，供人工复核）
# =============================================================================

sect "Step 1  CR2 / log 关键字原始输出"
echo "${BT_REG}" | grep -A2 -B2 -i "cr2" || echo "${RAW_LOG}" | grep -iE 'cr2|expected|actual|EDAC|syndrome' | head -20

sect "Step 2  __per_cpu_offset[${EXPECTED_CPU}] 原始输出"
echo "${PERCPU_OUT}"

sect "Step 3  __preempt_count 偏移原始输出"
echo "${PREEMPT_OUT}"

sect "Step 4  地址合法性交叉验证"

# 并行验证两个地址的可读性
ADDR_EXP_HEX=$(echo "${EXPECTED_STR}" | sed 's/0x//')
ADDR_ACT_HEX=$(echo "${ACTUAL_STR}"   | sed 's/0x//')

run_crash "rd 0x${ADDR_EXP_HEX}" > "${TMP_DIR}/rd_exp.txt" &  PID_RE=$!
run_crash "rd 0x${ADDR_ACT_HEX}" > "${TMP_DIR}/rd_act.txt" &  PID_RA=$!
wait $PID_RE $PID_RA

RD_EXP=$(cat "${TMP_DIR}/rd_exp.txt")
RD_ACT=$(cat "${TMP_DIR}/rd_act.txt")

if echo "${RD_EXP}" | grep -qP "[0-9a-f]{16}"; then
    pass "期望地址 0x${ADDR_EXP_HEX} 可正常读取 → 合法 per-cpu 内存 ✓"
else
    warn "期望地址读取结果: ${RD_EXP}"
fi

if echo "${RD_ACT}" | grep -qi "cannot access\|invalid\|error\|fault\|inaccessible"; then
    # 【严重错误确证】
    # 这是一个决定性的证据！
    # 期望地址是合法可读的，但与之仅差 1 bit 的实际地址（CR2）完全无法读取（未映射/受保护）。
    # 这从物理层面证明了：原本正常的指针发生了位翻转，导致 CPU 瞬间踩到了非法内存黑洞，从而触发 Page Fault 宕机。
    pass "实际地址（CR2）0x${ADDR_ACT_HEX} 不可读 → 确认为非法地址 ✓"
else
    # 【巧合警告】
    # 如果翻转后的地址竟然能读出数据，说明指针翻转后“碰巧”落在了另一个合法的内存页。
    # 这依然是严重的错误，会导致内核读到脏数据并发生逻辑崩溃，但不会直接引发 CR2 缺页异常，需要人工额外留意。
    warn "实际地址读取结果: ${RD_ACT}（若能读取，说明翻转后地址碰巧映射到其他区域）"
fi
