#!/bin/bash
# ============================================================
# 路径E：地址空间碎片化专项诊断脚本
#
# 用法:
#   bash diagnose_fragmentation.sh -S <开始时间> [-E <结束时间>] [-p <PID> | -n <名称>]
#
# 示例:
#   bash diagnose_fragmentation.sh -S "2024-01-15 14:00:00" -p 12345
#
# 输出结构：
#   [SUMMARY]  自动摘要（模型优先阅读）
#   [DETAIL]   原始详细数据
# ============================================================

START_TIME=""; END_TIME=""; TARGET_PID=""; TARGET_NAME=""

while getopts ":S:E:p:n:h" opt; do
    case $opt in
        S) START_TIME="$OPTARG" ;; E) END_TIME="$OPTARG" ;;
        p) TARGET_PID="$OPTARG" ;; n) TARGET_NAME="$OPTARG" ;;
        h) sed -n '3,15p' "$0" | sed 's/^# \{0,2\}//'; exit 0 ;;
        :) echo "错误: -$OPTARG 需要参数值"; exit 1 ;;
    esac
done

if [ -n "$TARGET_NAME" ] && [ -z "$TARGET_PID" ]; then
    TARGET_PID=$(pgrep -f "$TARGET_NAME" 2>/dev/null | head -1)
fi

OUTPUT_DIR="/tmp/mmap_frag_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"
exec > >(tee "$OUTPUT_DIR/diagnose_fragmentation.log") 2>&1

section() { echo ""; echo "###############################################"; echo "# $1"; echo "###############################################"; }
banner()  { echo ""; echo "╔══════════════════════════════════════════════╗"; printf "║  %-44s║\n" "$1"; echo "╚══════════════════════════════════════════════╝"; }

# ================================================================
# [SUMMARY] 自动摘要
# ================================================================
banner "[SUMMARY] 路径E 地址空间碎片化诊断 — 模型优先阅读此节"
echo "分析时段: ${START_TIME:-全量} ~ ${END_TIME:-全量}"
echo "目标PID:  ${TARGET_PID:-未指定}"
echo ""

# ── S1: VMA 总数与分布 ────────────────────────────────────────
if [ -n "$TARGET_PID" ] && [ -d "/proc/$TARGET_PID" ]; then
    MAPS_FILE="/proc/$TARGET_PID/maps"
    VMA_COUNT=$(wc -l < "$MAPS_FILE" 2>/dev/null)
    MAX_MAP=$(cat /proc/sys/vm/max_map_count 2>/dev/null || echo 65530)

    echo "━━━ S1. VMA 数量与地址空间概要 ━━━"
    echo ""
    echo "  VMA 数量: $VMA_COUNT (max_map_count=$MAX_MAP, 使用率=$((VMA_COUNT*100/MAX_MAP))%)"
    echo ""

    # 分析地址空间空洞
    echo "  [地址空间空洞分析]"
    python3 /dev/stdin << 'PYEOF' 2>/dev/null
import re, sys
try:
    pid = int('$TARGET_PID')
    with open(f'/proc/{pid}/maps') as f:
        regions = []
        for line in f:
            m = re.match(r'([0-9a-f]+)-([0-9a-f]+)', line)
            if m:
                start, end = int(m.group(1), 16), int(m.group(2), 16)
                regions.append((start, end))
    regions.sort()
    total_mapped = sum(e - s for s, e in regions)
    total_addr_space = 1 << 48  # x86_64 用户空间上限
    gaps = []
    for i in range(len(regions)-1):
        gap = regions[i+1][0] - regions[i][1]
        if gap > 0:
            gaps.append(gap)
    if gaps:
        gaps.sort(reverse=True)
        print(f"  总映射大小: {total_mapped/1024/1024:.0f} MB")
        print(f"  地址空间使用率: {total_mapped*100/total_addr_space:.2f}%")
        print(f"  空洞数量: {len(gaps)}")
        print(f"  最大连续空洞: {max(gaps)/1024/1024:.1f} MB")
        print(f"  平均空洞: {sum(gaps)/len(gaps)/1024/1024:.1f} MB")
        print(f"  中位空洞: {sorted(sorted(gaps)[len(gaps)//2], reverse=True)[0]/1024/1024:.1f} MB")
        top5 = sorted([g for g in gaps if g > 0], reverse=True)[:5]
        print(f"  Top 5 空洞:")
        for i, g in enumerate(top5):
            print(f"    {i+1}. {g/1024/1024:.1f} MB")
    else:
        print("  (无法计算空洞 - 可能无数据)")
except Exception as e:
    print(f"  分析失败: {e}")
PYEOF

    echo ""
    echo "  [VMA 大小分布]"
    awk '{
        split($1, addr, "-")
        start=strtonum("0x" addr[1]); end=strtonum("0x" addr[2])
        size=end-start
        if (size < 4096) cat="<4KB"
        else if (size < 65536) cat="4KB-64KB"
        else if (size < 1048576) cat="64KB-1MB"
        else if (size < 10485760) cat="1MB-10MB"
        else if (size < 104857600) cat="10MB-100MB"
        else cat=">100MB"
        count[cat]++
    } END {
        for (c in count) printf "  %-15s %d\n", c, count[c]
    }' "$MAPS_FILE" 2>/dev/null | sort -t- -k1 -n

    echo ""
    echo "  [进程内存概要]"
    grep -E "VmPeak|VmSize|VmRSS|VmData|VmStk" "/proc/$TARGET_PID/status" 2>/dev/null

    # 保存 maps 文件用于详细分析
    cp "$MAPS_FILE" "$OUTPUT_DIR/maps.txt"
fi

# ── S2: 物理页面碎片 ──────────────────────────────────────────
echo ""
echo "━━━ S2. 物理页面碎片状态 (buddyinfo) ━━━"
echo ""
cat /proc/buddyinfo 2>/dev/null

echo ""
echo "  [诊断: 最大连续物理块]"
cat /proc/buddyinfo 2>/dev/null | awk '{
    max_order=0
    for (i=4; i<=NF; i++) if ($i+0 > 0) max_order=i-4
    printf "  %s %s: order=%d (%d KB)\n", $1, $2, max_order, (2^max_order)*4
}'

# ── S3: THP 和大页 ────────────────────────────────────────────
echo ""
echo "━━━ S3. 透明大页 / HugePages ━━━"
echo ""
echo "  THP 策略: $(cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null | grep -oP '\[\K[^\]]+' || echo N/A)"
echo ""
grep -E "HugePages_Total|HugePages_Free|Hugepagesize|HugePages_Rsvd|HugePages_Surp" /proc/meminfo 2>/dev/null

# ── S4: ASLR ──────────────────────────────────────────────────
echo ""
echo "━━━ S4. ASLR 与地址空间布局 ━━━"
echo ""
echo "  randomize_va_space = $(cat /proc/sys/kernel/randomize_va_space 2>/dev/null || echo N/A)"
echo "  legacy_va_layout   = $(cat /proc/sys/vm/legacy_va_layout 2>/dev/null || echo N/A)"

echo ""
echo "============================================"
echo "完整日志已保存到: $OUTPUT_DIR"
echo "============================================"
