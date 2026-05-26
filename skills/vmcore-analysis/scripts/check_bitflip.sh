#!/bin/bash
#
# Bit Flip 检查工具：验证两整数是否为「仅 1 个 bit 不同」（含完整 64 位内核指针）。
# 优先使用 python3 做无符号大整数 XOR /  popcount；无 python3 时回退 bash（适合较小整数）。
#
# 使用方法：
#     ./check_bitflip.sh <expected_value> <actual_value>
#

set -e

usage() {
    cat << EOF
Bit Flip 检查工具 - 验证两值 XOR 是否为 2 的幂（即是否仅 1-bit 不同）

使用方法:
    $0 <expected_value> <actual_value>
    $0 --help | -h

参数:
    expected_value    预期值（十进制或十六进制，如 100、0xDEADBEEF、0xfffffffbb3a01000）
    actual_value      实际值（同上；支持完整 64 位指针，需本机有 python3）

示例:
    $0 100 134217828
    $0 0xDEADBEEF 0xDEACBEEF
    $0 0xffffffffb3a01000 0xfffffffbb3a01000

EOF
    exit 0
}

if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    usage
fi

if [ $# -ne 2 ]; then
    echo "错误: 需要两个参数"
    echo ""
    usage
fi

EXPECTED_STR="$1"
ACTUAL_STR="$2"

is_valid_number() {
    local str="$1"
    if [[ "$str" =~ ^[0-9]+$ ]] || [[ "$str" =~ ^0x[0-9a-fA-F]+$ ]]; then
        return 0
    fi
    return 1
}

if ! is_valid_number "$EXPECTED_STR" || ! is_valid_number "$ACTUAL_STR"; then
    echo "错误: 无效的数值输入（须为十进制数字或 0x 开头的十六进制）"
    echo "预期值: $EXPECTED_STR"
    echo "实际值: $ACTUAL_STR"
    exit 1
fi

# ---------- python3：完整多字长 / 64 位指针 ----------
if command -v python3 >/dev/null 2>&1; then
    exec python3 - "$EXPECTED_STR" "$ACTUAL_STR" <<'PY'
import sys

def main():
    a0, a1 = sys.argv[1], sys.argv[2]
    try:
        e = int(a0, 0)
        a = int(a1, 0)
    except ValueError:
        print("错误: 数值解析失败")
        print(f"预期值: {a0}")
        print(f"实际值: {a1}")
        sys.exit(1)

    xor = e ^ a

    print("=" * 70)
    print("Bit Flip 检查（python3 / 大整数）")
    print("=" * 70)
    print()
    print(f"预期值: {e} (0x{e:x})")
    print(f"实际值: {a} (0x{a:x})")
    print()
    print(f"XOR 结果: 0x{xor:x} ({xor})")

    def xor_binary_bits(x: int) -> str:
        if x == 0:
            return "0"
        return bin(x)[2:]

    bin_str = xor_binary_bits(xor)
    if len(bin_str) > 128:
        bin_str = bin_str[:128] + "…(已截断)"
    print()
    print("二进制差异(XOR): " + bin_str)

    if xor == 0:
        print()
        print("⚠️  值完全相同，无需分析")
        sys.exit(0)

    bc = bin(xor).count("1")

    if xor > 0 and (xor & (xor - 1)) == 0:
        bit_pos = xor.bit_length() - 1
        print()
        print("✅ 检测到 1-bit flip!")
        print(f"   翻转位: bit {bit_pos}")
        print(f"   差异值: 2^{bit_pos} = {xor}")
        print()
        print("【结论】硬件故障可能性极高")
        print("   根因: 内存条缺陷或 CPU 高速缓存一致性硬件 Bug")
        print("   建议: 必须在线下隔离该物理宿主机，整体下线并进行 DIMM 内存条硬件更换")
        sys.exit(0)

    print()
    print("❌ 不是 1-bit flip")
    print(f"   翻转位数: {bc} 位")
    print()
    print("【结论】需要软件分析")
    print("   继续进行死锁、Use-after-free 等软件常规排查")
    sys.exit(1)

if __name__ == "__main__":
    main()
PY
fi

# ---------- bash 回退（较小整数）----------
EXPECTED=$(printf "%d" "$EXPECTED_STR" 2>/dev/null || echo "invalid")
ACTUAL=$(printf "%d" "$ACTUAL_STR" 2>/dev/null || echo "invalid")

if [ "$EXPECTED" = "invalid" ] || [ "$ACTUAL" = "invalid" ]; then
    echo "错误: 数值转换失败（大整数或 64 位指针请安装 python3 后重试）"
    echo "预期值: $EXPECTED_STR"
    echo "实际值: $ACTUAL_STR"
    exit 1
fi

echo "======================================================================"
echo "Bit Flip 检查（bash 回退；大指针请使用 python3）"
echo "======================================================================"
echo ""
echo "预期值: $EXPECTED (0x$(printf '%x' $EXPECTED))"
echo "实际值: $ACTUAL (0x$(printf '%x' $ACTUAL))"

XOR=$((EXPECTED ^ ACTUAL))
echo ""
echo "XOR 结果: 0x$(printf '%x' $XOR) ($XOR)"

to_binary() {
    local n=$1
    local binary=""
    while [ $n -gt 0 ]; do
        binary=$((n % 2))$binary
        n=$((n / 2))
    done
    [ -z "$binary" ] && binary="0"
    echo "$binary"
}

echo -n "二进制差异: "
to_binary $XOR

if [ $XOR -eq 0 ]; then
    echo ""
    echo "⚠️  值完全相同，无需分析"
    exit 0
fi

is_power_of_two() {
    local n=$1
    if [ $((n & (n - 1))) -eq 0 ] && [ $n -gt 0 ]; then
        return 0
    else
        return 1
    fi
}

if is_power_of_two $XOR; then
    BIT_POS=0
    TEMP=$XOR
    while [ $TEMP -gt 1 ]; do
        TEMP=$((TEMP / 2))
        BIT_POS=$((BIT_POS + 1))
    done

    echo ""
    echo "✅ 检测到 1-bit flip!"
    echo "   翻转位: bit $BIT_POS"
    echo "   差异值: 2^$BIT_POS = $XOR"
    echo ""
    echo "【结论】硬件故障可能性极高"
    echo "   根因: 内存条缺陷或 CPU 高速缓存一致性硬件 Bug"
    echo "   建议: 必须在线下隔离该物理宿主机，整体下线并进行 DIMM 内存条硬件更换"
    exit 0
else
    count_bits() {
        local n=$1
        local count=0
        while [ $n -gt 0 ]; do
            if [ $((n % 2)) -eq 1 ]; then
                count=$((count + 1))
            fi
            n=$((n / 2))
        done
        echo $count
    }

    bit_count=$(count_bits $XOR)

    echo ""
    echo "❌ 不是 1-bit flip"
    echo "   翻转位数: $bit_count 位"
    echo ""
    echo "【结论】需要软件分析"
    echo "   继续进行死锁、Use-after-free 等软件常规排查"
    exit 1
fi
