#!/bin/bash
#
# Bit Flip 检查工具 (Bash 版本)
#
# 核心原理：Bit Flip 通常发生在数据本身，而不是计算的地址。
#
# 使用方法：
#     ./check_bitflip.sh <expected_value> <actual_value>
#
# 示例：
#     # 检查 CPU ID 是否发生 bit flip
#     ./check_bitflip.sh 69 134217797
#     
#     # 使用十六进制
#     ./check_bitflip.sh 0x45 0x08000045
#
# 真实案例：
#     预期值: 69 (CPU ID)
#     实际值: 134217797 (第 27 位翻转)
#     结果: 1-bit flip detected!
#

set -e

usage() {
    cat << EOF
Bit Flip 检查工具 - 验证数据值是否存在硬件 1-bit 翻转

使用方法:
    $0 <expected_value> <actual_value>
    $0 --help | -h

参数:
    expected_value    预期值（十进制或十六进制，如 69 或 0x45）
    actual_value      实际值（十进制或十六进制，如 134217797 或 0x08000045）

示例:
    # 检查 CPU ID 是否发生 bit flip
    $0 69 134217797
    
    # 使用十六进制
    $0 0x45 0x08000045
    
    # 真实案例：struct rq->cpu 字段翻转
    预期值: 69 (CPU ID)
    实际值: 134217797 (第 27 位翻转)
    结果: 1-bit flip detected!

EOF
    exit 0
}

# 检查是否请求帮助
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

# 更严格的数值验证
is_valid_number() {
    local str="$1"
    # 检查是否是十进制或十六进制
    if [[ "$str" =~ ^[0-9]+$ ]] || [[ "$str" =~ ^0x[0-9a-fA-F]+$ ]]; then
        return 0
    else
        return 1
    fi
}

if ! is_valid_number "$EXPECTED_STR" || ! is_valid_number "$ACTUAL_STR"; then
    echo "错误: 无效的数值输入"
    echo "预期值: $EXPECTED_STR (必须是十进制如 69 或十六进制如 0x45)"
    echo "实际值: $ACTUAL_STR (必须是十进制如 134217797 或十六进制如 0x8000045)"
    exit 1
fi

EXPECTED=$(printf "%d" "$EXPECTED_STR" 2>/dev/null || echo "invalid")
ACTUAL=$(printf "%d" "$ACTUAL_STR" 2>/dev/null || echo "invalid")

if [ "$EXPECTED" = "invalid" ] || [ "$ACTUAL" = "invalid" ]; then
    echo "错误: 数值转换失败"
    echo "预期值: $EXPECTED_STR"
    echo "实际值: $ACTUAL_STR"
    exit 1
fi

echo "======================================================================"
echo "Bit Flip 检查"
echo "======================================================================"
echo ""
echo "预期值: $EXPECTED (0x$(printf '%x' $EXPECTED))"
echo "实际值: $ACTUAL (0x$(printf '%x' $ACTUAL))"

XOR=$((EXPECTED ^ ACTUAL))
echo ""
echo "XOR 结果: 0x$(printf '%x' $XOR) ($XOR)"

# 二进制转换函数
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
    # 计算翻转位数函数
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