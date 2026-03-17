#!/bin/bash
# usage: ./strace_analyze.sh /tmp/log 16
LOG_FILE="$1"
TARGET_MB="$2"

# 将 MB 转换为 Bytes，并计算上下限
# 这里的逻辑是：只关注看起来像大小的参数（通常是第2个参数）
BYTES=$((TARGET_MB * 1024 * 1024))
HEX_VAL=$(printf "0x%x" $BYTES)
MIN=$((BYTES - 1024 * 1024))  # 减 1MB
MAX=$((BYTES + 1024 * 1024))  # 加 1MB

echo "正在分析日志: $LOG_FILE"
echo "目标大小: ${TARGET_MB}MB ($BYTES bytes / $HEX_VAL)"

# === 策略 A: 精确匹配 (带上下文) ===
# 使用双引号 "$BYTES"，并加上 -C 5 打印前后5行
# 这是最直观的，直接看这里
echo ">>> [A] 精确匹配 (Exact Match) <<<"
# 搜索 十进制 OR 十六进制
grep -n -E "${BYTES}|${HEX_VAL}" "$LOG_FILE" -C 5

# === 策略 B: 范围模糊匹配 (Awk + Grep) ===
echo -e "\n>>> [B] 范围搜索 ($MIN - $MAX bytes) <<<"

# 1. 用 Awk 找出范围内出现过的“特殊数值”，去重
FOUND_SIZES=$(awk -v min="$MIN" -v max="$MAX" '
{
    for (i=1; i<=NF; i++) {
        val = $i
        gsub(/[,()]/, "", val)
        if (val ~ /^0x[0-9a-fA-F]+$/) val = strtonum(val)
        
        # 必须是数字，且在范围内，且不是类似 0.000 的浮点数
        if (val ~ /^[0-9]+$/ && val >= min && val <= max) {
            print val
        }
    }
}' "$LOG_FILE" | sort -u)

# 2. 如果找到了模糊数值，用 Grep 把它们的上下文打出来
if [ -n "$FOUND_SIZES" ]; then
    for size in $FOUND_SIZES; do
        # 排除掉精确值（因为策略A已经展示过了）
        if [ "$size" != "$BYTES" ]; then
            echo "发现非标准大小: $size bytes"
            grep -n "$size" "$LOG_FILE" -C 2 | head -n 20
        fi
    done
else
    echo "未发现范围内的其他数值。"
fi