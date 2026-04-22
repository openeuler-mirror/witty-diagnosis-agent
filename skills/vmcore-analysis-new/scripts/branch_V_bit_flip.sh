#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_V_bit_flip.sh
# 用途：分支V —— Bit Flip 硬件比特翻转完整分析
# 使用：bash branch_V_bit_flip.sh <vmcore_path> <vmlinux_path> [src_dir]
#
# 说明：
#   脚本会自动从 vmcore log 中提取期望值（expected）和实际值（actual），
#   按以下优先级依次尝试：
#     来源1：Bad page / slab poison —— 内核直接打印 expected/actual（最可靠）
#     来源2：ECC/EDAC syndrome     —— 硬件纠错记录，syndrome 编码翻转的 bit
#     来源3：手动兜底               —— 自动读 pfn 对应内存，对照 poison 常量推算
#
#   注意：vmcore 中 rd 读到的值已是翻转【之后】的值，
#         真正的 actual 只能从内核 log 打印或 ECC syndrome 中获取。
# =============================================================================

VMCORE="${1:-/var/crash/vmcore}"
VMLINUX="${2:-/usr/lib/debug/lib/modules/$(uname -r)/vmlinux}"
SRC_DIR="${3:-}"
# expected / actual 由脚本自动提取，不再依赖用户传参
EXPECTED_STR=""
ACTUAL_STR=""
EXTRACT_SOURCE=""   # 记录值的来源，用于最终报告

CRASH_CMD="crash -s ${VMLINUX} ${VMCORE}"

# =============================================================================
# --help
# =============================================================================
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  cat <<HELP
用途：分支V（bit_flip）完整分析

使用：
  bash $0 <vmcore> <vmlinux> [src_dir]

参数：
  vmcore    vmcore 路径
  vmlinux   带调试信息的 vmlinux 路径
  src_dir   源码目录（可选，有则启用源码双轨分析）

说明：
  期望值（expected）和实际值（actual）由脚本自动从 vmcore log 提取，
  无需手动传参。提取优先级：
    来源1  Bad page / slab poison  内核直接打印 expected/actual，最可靠
    来源2  ECC/EDAC syndrome       硬件纠错记录，syndrome 编码翻转 bit
    来源3  手动兜底                自动读 pfn 内存 + poison 常量推算

示例：
  bash $0 /var/crash/vmcore /usr/lib/debug/vmlinux
  bash $0 /var/crash/vmcore /usr/lib/debug/vmlinux /src
HELP
  exit 0
fi

# =============================================================================
# 工具函数
# =============================================================================
section() { echo ""; echo "======================================================================"; echo "【$1】$2"; echo "======================================================================"; }
info()    { echo "  → $*"; }
warn()    { echo "  ⚠️  $*"; }

is_valid_number() {
  [[ "$1" =~ ^[0-9]+$ ]] || [[ "$1" =~ ^0[xX][0-9a-fA-F]+$ ]]
}

# =============================================================================
# 基础信息
# =============================================================================
HAS_SRC=false
[[ -n "${SRC_DIR}" && -d "${SRC_DIR}" ]] && HAS_SRC=true

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║            分支V（Bit Flip 硬件比特翻转）完整分析               ║"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""
info "vmcore  : ${VMCORE}"
info "vmlinux : ${VMLINUX}"
info "src_dir : ${SRC_DIR:-（未提供，走纯vmcore轨道）}"
info "分析模式: $( $HAS_SRC && echo '双轨（vmcore + 源码）' || echo '单轨（纯vmcore）' )"

# =============================================================================
# 【1】日志关键信息
# =============================================================================
section "1" "日志关键信息（panic 类型 / 故障特征）"
${CRASH_CMD} --no_scroll << 'EOF'
log | tail -150
EOF

# =============================================================================
# 【2】Bit Flip 特征关键字提取
# =============================================================================
section "2" "Bit Flip 特征关键字提取"
echo ""
echo "--- 2a. 期望值/实际值（Bad page / slab poison 场景）---"
${CRASH_CMD} --no_scroll << 'EOF'
log | grep -A 5 -E "expected|actual|Bad page|bad_page"
EOF

echo ""
echo "--- 2b. ECC / EDAC 硬件纠错记录 ---"
${CRASH_CMD} --no_scroll << 'EOF'
log | grep -E "EDAC|syndrome|Corrected|Uncorrected|CE |UE |memory read error"
EOF

echo ""
echo "--- 2c. MCE（Machine Check Exception）硬件异常 ---"
${CRASH_CMD} --no_scroll << 'EOF'
log | grep -B 2 -A 10 -E "Machine check|mce:|MCE|BANK[0-9]"
EOF

echo ""
echo "--- 2d. Slab/Redzone 覆写 ---"
${CRASH_CMD} --no_scroll << 'EOF'
log | grep -A 10 -E "BUG.*kmalloc|BUG.*slab|Redzone|Object "
EOF

info "说明：以上任一场景输出中的 expected/actual/syndrome 即为期望值和实际值的直接来源"
warn "vmcore 内存快照（rd 命令读到的）是翻转【之后】的值，不是翻转前的原始值"
warn "真正的 actual 只能从内核 log 打印或 ECC syndrome 中获取"

# =============================================================================
# 【3】调用栈
# =============================================================================
section "3" "调用栈（崩溃现场还原）"
echo ""
echo "--- 3a. 完整调用栈（含栈帧内容）---"
${CRASH_CMD} --no_scroll << 'EOF'
bt -f
EOF

echo ""
echo "--- 3b. 调用栈（含源码行号）---"
${CRASH_CMD} --no_scroll << 'EOF'
bt -l
EOF

echo ""
echo "--- 3c. 所有CPU调用栈 ---"
${CRASH_CMD} --no_scroll << 'EOF'
bt -a
EOF

# =============================================================================
# 【4】内存/进程状态
# =============================================================================
section "4" "内存 / 进程状态"
${CRASH_CMD} --no_scroll << 'EOF'
kmem -i
ps | grep " D " | head -10
mod
EOF

# =============================================================================
# 【5】手动计算期望值/实际值（内核未打印时的兜底方法）
# =============================================================================
section "5" "手动计算期望值/实际值（兜底方法，仅在内核未打印时使用）"
cat <<'MANUAL'

前提说明
────────
  • 方法一（log grep）和方法二（ECC syndrome）是首选，优先用。
  • 本节手动方法用于内核未明确打印 expected/actual 的场景。
  • 手动方法的本质：
      期望值 = 内核初始化时写入的已知常量（软件定义死的）
      实际值 = rd 命令读出的值（已是翻转后）
    两者 XOR → 翻转的 bit 位图（不代表翻转前的真实业务数据）

步骤一：pfn → 物理地址 → 虚拟地址
────────────────────────────────────
  crash> log | grep pfn                    # 取 pfn 值，如 0x1a2b3c
  crash> ptob 0x1a2b3c                     # pfn → 物理地址
  crash> ptov <物理地址>                   # 物理地址 → 虚拟地址

步骤二：读出内存实际内容（翻转后）
────────────────────────────────────
  crash> rd -8 <虚拟地址> 64               # 以字节读，找异常字节
  crash> rd -p <物理地址> 64              # 或直接读物理地址

步骤三：确定期望值（poison 常量）
────────────────────────────────────
  场景                   期望值（hex）   说明
  ─────────────────────  ─────────────  ──────────────────────────
  已释放 slab 对象        0x6b           POISON_FREE
  使用中 slab 对象        0x6a           POISON_INUSE
  page poison            0xaa           PAGE_POISON
  page flags 清零场景     0x00           正常页 flags 基准
  page flags 对比法       相邻正常页值    crash> page <相邻页地址>

  page flags 对比法示例：
    crash> page <出错页虚拟地址>           # 查看 flags 实际值
    crash> page <相邻页虚拟地址±0x40>      # 对比相邻正常页的 flags
    期望值 = 相邻页的 flags（正常基准）
    实际值 = 出错页的 flags（已翻转）

步骤四：XOR 计算翻转 bit
────────────────────────────────────
  crash> eval 0x6b ^ 0xeb                 # 结果 0x80 → bit7 翻转
  crash> eval <期望值> ^ <实际值>

步骤五：判断翻转类型
────────────────────────────────────
  XOR 结果为 2 的幂次（如 0x1/0x2/0x4/0x80...）→ 单 bit 翻转，硬件故障特征
  XOR 结果含多个 bit                             → 多 bit 翻转或软件写坏，继续软件排查

MANUAL

# =============================================================================
# 【6】源码双轨分析（有源码时）
# =============================================================================
if $HAS_SRC; then
  section "6" "源码双轨分析（源码目录：${SRC_DIR}）"
  cat <<SRCGUIDE

  遵循源码五步法：
    Step S1  以 vmcore 崩溃帧为入口（取 bt #0 函数名 + RIP 地址）
    Step S2  源码-汇编对齐（crash> dis -l <崩溃函数名>，确认行号匹配）
    Step S3  调用栈逐帧源码追踪（区分崩溃帧 vs 根因帧）
    Step S4  数据流溯源（异常值生命周期追踪，找状态被污染的那一刻）
    Step S5  反事实验证（正向推演结果必须与 vmcore 现象自洽）

  注意：Bit Flip 场景源码侧往往找不到代码缺陷（逻辑完全正确）。
  若源码五步法走完无异常 → 强烈支持硬件故障结论。

SRCGUIDE
fi

# =============================================================================
# 【7】自动提取期望值 / 实际值，并计算 XOR 差异
# =============================================================================
section "7" "自动提取期望值/实际值 + Bit Flip 验证"

# -----------------------------------------------------------------------------
# 从 vmcore log 提取原始文本（只调用一次 crash，避免重复开销）
# -----------------------------------------------------------------------------
RAW_LOG=$(${CRASH_CMD} --no_scroll <<'EOF'
log
EOF
)

# -----------------------------------------------------------------------------
# 来源1：Bad page / slab poison —— 内核直接打印 expected/actual
#   典型格式：
#     raw: expected:0000000000000000 actual:0000000000000080
#     flags: expected 0x17ffffc0000000, actual 0x17ffffc0000080
# -----------------------------------------------------------------------------
extract_from_bad_page() {
    # 格式一：raw: expected:HEX actual:HEX（无 0x 前缀）
    local line
    line=$(echo "$RAW_LOG" | grep -m1 -E 'expected:[0-9a-fA-F]+ actual:[0-9a-fA-F]+')
    if [[ -n "$line" ]]; then
        EXPECTED_STR="0x$(echo "$line" | grep -oP 'expected:\K[0-9a-fA-F]+')"
        ACTUAL_STR="0x$(echo "$line"   | grep -oP 'actual:\K[0-9a-fA-F]+')"
        EXTRACT_SOURCE="来源1-BadPage/SlabPoison（内核直接打印）"
        return 0
    fi
    # 格式二：expected 0xHEX, actual 0xHEX（带 0x 前缀，逗号分隔）
    line=$(echo "$RAW_LOG" | grep -m1 -E 'expected 0x[0-9a-fA-F]+.*actual 0x[0-9a-fA-F]+')
    if [[ -n "$line" ]]; then
        EXPECTED_STR=$(echo "$line" | grep -oP 'expected \K0x[0-9a-fA-F]+')
        ACTUAL_STR=$(echo "$line"   | grep -oP 'actual \K0x[0-9a-fA-F]+')
        EXTRACT_SOURCE="来源1-BadPage/SlabPoison（内核直接打印）"
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# 来源2：EDAC/ECC syndrome —— 硬件纠错记录
#   syndrome 本身就是 expected XOR actual 的结果（即翻转的 bit 位图）
#   此时我们把 syndrome 作为 XOR_DIFF 直接使用，actual=0 仅作占位
#   典型格式：
#     EDAC MC0: 1 CE ... syndrome: 0x0000000000000080
#     syndrome = 0x80
# -----------------------------------------------------------------------------
SYNDROME_STR=""
extract_from_edac() {
    local line
    line=$(echo "$RAW_LOG" | grep -m1 -iE 'syndrome[: =]+0x[0-9a-fA-F]+')
    if [[ -n "$line" ]]; then
        SYNDROME_STR=$(echo "$line" | grep -oP '(?i)syndrome[: =]+\K0x[0-9a-fA-F]+')
        EXTRACT_SOURCE="来源2-ECC/EDAC（硬件 syndrome，直接为翻转 bit 位图）"
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# 来源3：手动兜底 —— 从 pfn 读内存，对照 poison 常量
#   期望值 = poison 常量（POISON_FREE=0x6b / PAGE_POISON=0xaa）
#   实际值 = rd 读出的异常字节（已是翻转后）
# -----------------------------------------------------------------------------

# poison 常量表
declare -A POISON_MAP=(
    ["POISON_FREE"]="0x6b"
    ["POISON_INUSE"]="0x6a"
    ["PAGE_POISON"]="0xaa"
)

extract_from_memory() {
    # 1. 拿 pfn
    local pfn_line pfn phys_hex virt_hex mem_bytes poison_name poison_val
    pfn_line=$(echo "$RAW_LOG" | grep -m1 -oP 'pfn:?\s*\K(0x[0-9a-fA-F]+|[0-9]+)')
    [[ -z "$pfn_line" ]] && return 1

    info "手动兜底：找到 pfn = $pfn_line，开始读内存..."

    # 2. pfn → 物理地址 → 虚拟地址
    phys_hex=$(${CRASH_CMD} --no_scroll <<EOF | grep -oP '0x[0-9a-fA-F]+'| head -1
ptob $pfn_line
EOF
)
    [[ -z "$phys_hex" ]] && { warn "ptob 转换失败，手动兜底跳过"; return 1; }

    virt_hex=$(${CRASH_CMD} --no_scroll <<EOF | grep -oP '0x[0-9a-fA-F]+' | head -1
ptov $phys_hex
EOF
)
    [[ -z "$virt_hex" ]] && { warn "ptov 转换失败，手动兜底跳过"; return 1; }

    info "  pfn $pfn_line  →  物理地址 $phys_hex  →  虚拟地址 $virt_hex"

    # 3. 读出内存内容（字节模式，取前64字节）
    mem_bytes=$(${CRASH_CMD} --no_scroll <<EOF | grep -oP '[0-9a-fA-F]{2}' | head -64
rd -8 $virt_hex 64
EOF
)
    [[ -z "$mem_bytes" ]] && { warn "rd 读内存失败，手动兜底跳过"; return 1; }

    # 4. 逐种 poison 常量匹配：找到与期望值不同的第一个字节
    for poison_name in POISON_FREE PAGE_POISON POISON_INUSE; do
        poison_val="${POISON_MAP[$poison_name]}"
        local expected_byte="${poison_val:2}"  # 去掉 0x
        # 统计期望字节出现次数
        local match_count total_bytes anomaly_byte
        total_bytes=$(echo "$mem_bytes" | wc -w)
        match_count=$(echo "$mem_bytes" | tr ' ' '\n' | grep -ici "^${expected_byte}$")

        # 超过一半字节匹配 poison 值，说明这是该场景
        if (( match_count * 2 > total_bytes )); then
            # 找到第一个不匹配的字节作为 actual
            anomaly_byte=$(echo "$mem_bytes" | tr ' ' '\n' \
                | grep -iv "^${expected_byte}$" | head -1)
            if [[ -n "$anomaly_byte" ]]; then
                EXPECTED_STR="${poison_val}"
                ACTUAL_STR="0x${anomaly_byte}"
                EXTRACT_SOURCE="来源3-手动兜底（pfn=${pfn_line}, poison=${poison_name}=${poison_val}, 异常字节=0x${anomaly_byte}）"
                return 0
            fi
        fi
    done

    warn "内存内容与已知 poison 常量均不匹配，无法自动推算期望值"
    return 1
}

# -----------------------------------------------------------------------------
# 按优先级依次尝试三种来源
# -----------------------------------------------------------------------------
echo ""
info "开始自动提取期望值 / 实际值..."
echo ""

if extract_from_bad_page; then
    info "✅ 提取成功（${EXTRACT_SOURCE}）"
    info "   期望值: ${EXPECTED_STR}"
    info "   实际值: ${ACTUAL_STR}"
elif extract_from_edac; then
    info "✅ 提取成功（${EXTRACT_SOURCE}）"
    info "   syndrome（翻转 bit 位图）: ${SYNDROME_STR}"
elif extract_from_memory; then
    info "✅ 提取成功（${EXTRACT_SOURCE}）"
    info "   期望值: ${EXPECTED_STR}"
    info "   实际值: ${ACTUAL_STR}"
else
    echo ""
    warn "三种来源均未能自动提取到期望值/实际值。"
    warn "可能原因："
    warn "  • log 中无 Bad page / EDAC 输出（随机崩溃，bit flip 未触发校验路径）"
    warn "  • pfn 无法定位或内存已被覆盖"
    echo ""
    warn "建议手动操作（见【5】节），获取后使用以下命令在 crash 中验证："
    warn "  crash> eval <期望值> ^ <实际值>"
    echo ""
    exit 0
fi

# -----------------------------------------------------------------------------
# XOR 计算：syndrome 直通 or expected ^ actual
# -----------------------------------------------------------------------------
echo ""
if command -v python3 >/dev/null 2>&1; then
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

def classify_bit(pos):
    """翻转 bit 在 x86_64 虚拟地址中的语义"""
    if pos >= 63:
        return "符号扩展位（canonical address，翻转直接导致非法地址，必崩）"
    if pos >= 47:
        return f"bit{pos}：高位地址位，翻转可能破坏内核/用户态边界"
    if pos >= 12:
        return f"bit{pos}：页帧号区域（PFN），翻转导致指向错误物理页"
    return f"bit{pos}：页内偏移区域（低12位），翻转影响页内访问位置"

def print_result(xor, e=None, a=None, source=""):
    print()
    print("  ┌──────────────────────────────────────────────────────────────┐")
    print("  │                    Bit Flip 验证结果                         │")
    print("  └──────────────────────────────────────────────────────────────┘")
    print()
    print(f"  值来源  : {source}")
    print()

    if e is not None and a is not None:
        print(f"  期望值（expected）: 0x{e:016x}  ({e})")
        print(f"  实际值（actual）  : 0x{a:016x}  ({a})")
        print()
        print(f"  XOR 差异          : 0x{xor:016x}  ({xor})")
    else:
        print(f"  syndrome（翻转位图）: 0x{xor:016x}  ({xor})")
        print("  说明：syndrome 直接由 ECC 硬件计算，即 expected XOR actual 的结果")

    # 64位二进制对齐展示
    if xor.bit_length() <= 64:
        print()
        if e is not None and a is not None:
            print(f"  期望值二进制: {e:064b}")
            print(f"  实际值二进制: {a:064b}")
        xor_bin = f"{xor:064b}"
        markers  = ''.join('^' if c == '1' else ' ' for c in xor_bin)
        print(f"  差异位图    : {xor_bin}")
        print(f"  翻转标记    : {markers}")

    if xor == 0:
        print()
        print("  ⚠️  无差异，两值完全相同，请确认提取的值是否正确")
        return

    flipped = bit_positions(xor)
    bc = len(flipped)

    print()
    print(f"  翻转 bit 数量: {bc} 位")
    print(f"  翻转 bit 位置: {', '.join(f'bit{p}' for p in flipped)}")
    print()
    print("  翻转 bit 语义分析：")
    for p in flipped:
        if e is not None and a is not None:
            direction = "0→1" if (a >> p) & 1 else "1→0"
            print(f"    bit{p:2d} ({direction}): {classify_bit(p)}")
        else:
            print(f"    bit{p:2d}: {classify_bit(p)}")

    print()
    if bc == 1:
        p = flipped[0]
        print("  ✅ 检测到单 bit flip（硬件故障强特征）")
        print(f"     翻转位 : bit{p}  (差异值 = 2^{p} = {xor})")
        print()
        print("  【结论】硬件故障可能性极高")
        print("  根因推断：")
        print("    • 首选：内存 DIMM 颗粒缺陷（DRAM 老化 / 电压异常 / 宇宙射线）")
        print("    • 次选：CPU L1/L2/L3 Cache 一致性硬件 Bug")
        print()
        print("  处置建议：")
        print("    1. 立即隔离该物理宿主机，下线业务")
        print("    2. 查 BMC SEL / EDAC 日志确认是否有 CE/UE 历史告警")
        print("    3. 运行 memtest86+ 全内存压测（至少 2 轮）定位故障 DIMM")
        print("    4. 更换对应插槽 DIMM 内存条")
        print("    5. 复测通过后方可重新上线")
    else:
        print(f"  ❌ 多 bit 翻转（{bc} 位），不符合典型单 bit 硬件翻转特征")
        print()
        print("  【结论】需进一步软件分析")
        print("  可能原因：")
        print("    • 软件写坏（UAF / OOB / 并发写竞争）")
        print("    • 多次独立 bit flip（概率极低）")
        print("    • 自动提取的值有误，建议人工核对 log 原始输出")
        print()
        print("  建议继续排查：Use-after-free、内存越界、并发竞争等软件路径")

def main():
    exp_str, act_str, syn_str, source = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

    # syndrome 直通模式（来源2）
    if syn_str:
        try:
            xor = int(syn_str, 0)
        except ValueError:
            print(f"  错误：syndrome 解析失败（{syn_str}）")
            sys.exit(1)
        print_result(xor, source=source)
        return

    # expected ^ actual 模式（来源1 / 来源3）
    try:
        e = int(exp_str, 0)
        a = int(act_str, 0)
    except ValueError:
        print(f"  错误：数值解析失败（expected={exp_str}, actual={act_str}）")
        sys.exit(1)
    print_result(e ^ a, e=e, a=a, source=source)

if __name__ == "__main__":
    main()
PY

else
  # bash 回退（无 python3）
  warn "未检测到 python3，使用 bash 回退计算（不支持 64 位大整数）"
  echo ""

  if [[ -n "$SYNDROME_STR" ]]; then
    # syndrome 直通
    XOR=$(printf "%d" "$SYNDROME_STR" 2>/dev/null || echo "invalid")
    echo "  syndrome（翻转 bit 位图）: ${SYNDROME_STR}  (${XOR})"
    echo "  来源: ${EXTRACT_SOURCE}"
  else
    EXPECTED=$(printf "%d" "$EXPECTED_STR" 2>/dev/null || echo "invalid")
    ACTUAL=$(printf "%d"   "$ACTUAL_STR"   2>/dev/null || echo "invalid")
    if [[ "$EXPECTED" == "invalid" || "$ACTUAL" == "invalid" ]]; then
      echo "  错误：大整数转换失败，请安装 python3 后重试"
      exit 1
    fi
    XOR=$(( EXPECTED ^ ACTUAL ))
    echo "  期望值: $(printf '0x%016x' $EXPECTED)"
    echo "  实际值: $(printf '0x%016x' $ACTUAL)"
    echo "  XOR   : $(printf '0x%016x' $XOR)  ($XOR)"
    echo "  来源  : ${EXTRACT_SOURCE}"
  fi

  is_power_of_two() { (( $1 > 0 && ($1 & ($1 - 1)) == 0 )); }

  if [[ "$XOR" != "invalid" ]] && is_power_of_two "$XOR"; then
    BIT_POS=0; T=$XOR
    while (( T > 1 )); do T=$(( T/2 )); (( BIT_POS++ )); done
    echo ""
    echo "  ✅ 单 bit flip！翻转位: bit${BIT_POS}  (2^${BIT_POS} = ${XOR})"
    echo "  【结论】硬件故障，建议隔离宿主机 → memtest86+ 压测 → 更换 DIMM"
  else
    echo ""
    echo "  ❌ 多 bit 翻转，需软件分析（UAF / OOB / 并发竞争）"
  fi
fi