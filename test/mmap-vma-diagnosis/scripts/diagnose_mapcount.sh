#!/bin/bash
# ============================================================
# 路径A：vm.max_map_count 耗尽专项诊断脚本
#
# 用法:
#   bash diagnose_mapcount.sh -S <开始时间> [-E <结束时间>] [-p <PID> | -n <名称>]
#
# 示例:
#   bash diagnose_mapcount.sh -S "2024-01-15 14:00:00" -p 12345
#   bash diagnose_mapcount.sh -S "2024-01-15 14:00:00" -n elasticsearch
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

OUTPUT_DIR="/tmp/mmap_mapcount_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"
exec > >(tee "$OUTPUT_DIR/diagnose_mapcount.log") 2>&1

HAS_JOURNAL=$(which journalctl 2>/dev/null)

section() { echo ""; echo "###############################################"; echo "# $1"; echo "###############################################"; }
banner()  { echo ""; echo "╔══════════════════════════════════════════════╗"; printf "║  %-44s║\n" "$1"; echo "╚══════════════════════════════════════════════╝"; }

# ================================================================
# [SUMMARY] 自动摘要
# ================================================================
banner "[SUMMARY] 路径A vm.max_map_count 耗尽诊断 — 模型优先阅读此节"
echo "分析时段: ${START_TIME:-全量} ~ ${END_TIME:-全量}"
echo "目标PID:  ${TARGET_PID:-未指定}"
echo ""

# ── S1: 确认 VMA 状态 ─────────────────────────────────────────
echo "━━━ S1. VMA 状态确认 ━━━"
echo ""

MAX_MAP=$(cat /proc/sys/vm/max_map_count 2>/dev/null || echo 65530)
echo "  系统 vm.max_map_count = $MAX_MAP"

if [ -n "$TARGET_PID" ] && [ -d "/proc/$TARGET_PID" ]; then
    VMA_COUNT=$(cat "/proc/$TARGET_PID/maps" 2>/dev/null | wc -l)
    VMA_USAGE=$((VMA_COUNT * 100 / MAX_MAP))
    echo "  进程 $TARGET_PID VMA 数量 = $VMA_COUNT (使用率 ${VMA_USAGE}%)"

    if [ "$VMA_USAGE" -ge 90 ]; then
        echo "  🔴 严重: VMA 使用率 >= 90%，极可能耗尽"
    elif [ "$VMA_USAGE" -ge 70 ]; then
        echo "  🟡 警告: VMA 使用率 >= 70%，需关注"
    else
        echo "  🟢 正常: VMA 使用率 < 70%"
    fi
    echo ""

    # VMA 类型分布
    echo "  [VMA 类型分布]"
    awk '{
        if ($7 ~ /^\[heap\]$/)       type="[heap]"
        else if ($7 ~ /^\[stack\]$/) type="[stack]"
        else if ($7 ~ /^\[vdso\]$/)  type="[vdso]"
        else if ($7 ~ /^\[/)         type="[anon-sys]"
        else if ($NF != "")          type="file:"$NF
        else                         type="anon"
        count[type]++
    } END {
        for (t in count) printf "  %-35s %d\n", t, count[t]
    }' "/proc/$TARGET_PID/maps" 2>/dev/null | sort -rn -k2 | head -15

    echo ""
    echo "  [文件映射 TOP 15]"
    awk '{if ($NF != "") print $NF}' "/proc/$TARGET_PID/maps" 2>/dev/null \
        | sort | uniq -c | sort -rn | head -15

    echo ""
    echo "  [进程内存概览]"
    grep -E "VmPeak|VmSize|VmLck|VmRSS|VmData" "/proc/$TARGET_PID/status" 2>/dev/null

    echo ""
    echo "  [进程限制]"
    grep "max locked memory\|max processes\|open files" "/proc/$TARGET_PID/limits" 2>/dev/null

else
    echo "  （进程可能已退出，以下从内核日志检索证据）"

    echo "  [检索 dmesg — max_map_count / mmap 失败 / ENOMEM]"
    dmesg -T 2>/dev/null | grep -iE "max_map_count|mmap.*fail|ENOMEM|Cannot allocate memory" | tail -20

    echo ""
    echo "  [检索 dmesg — overcommit]"
    dmesg -T 2>/dev/null | grep -iE "overcommit|page allocation failure" | tail -10

    if [ -n "$HAS_JOURNAL" ] && [ -n "$START_TIME" ]; then
        END_ARG="${END_TIME:-$(date -d "@$(($(date -d "$START_TIME" +%s)+3600))" '+%Y-%m-%d %H:%M:%S')}"
        echo ""
        echo "  [检索 journalctl — 目标进程 mmap 错误]"
        journalctl --since="$START_TIME" --until="$END_ARG" --no-pager 2>/dev/null \
            | grep -iE "mmap.*fail|ENOMEM|max_map_count" | head -10
    fi
fi

# ── S2: 内核日志 — max_map_count 相关 ──────────────────────────
echo ""
echo "━━━ S2. 内核日志 — max_map_count / mmap 失败 ━━━"
echo ""

LOG_FILE="$OUTPUT_DIR/kernel_mmap_errors.log"
if [ -n "$HAS_JOURNAL" ] && [ -n "$START_TIME" ]; then
    END_ARG="${END_TIME:-$(date -d "@$(($(date -d "$START_TIME" +%s)+3600))" '+%Y-%m-%d %H:%M:%S')}"
    journalctl -k --since="$START_TIME" --until="$END_ARG" --no-pager 2>/dev/null \
        | grep -iE "max_map_count|mmap.*fail|ENOMEM|Cannot allocate memory" > "$LOG_FILE"
elif [ -f /var/log/messages ]; then
    grep -iE "max_map_count|mmap.*fail|ENOMEM" /var/log/messages 2>/dev/null > "$LOG_FILE"
fi

if [ -s "$LOG_FILE" ]; then
    cat "$LOG_FILE"
else
    echo "  未找到相关内核日志"
fi

# ── S3: 应用日志 — 检查 ES/Java 相关 ───────────────────────────
echo ""
echo "━━━ S3. Elasticsearch 专项检查 ━━━"
echo ""

ES_PATHS="/etc/elasticsearch/elasticsearch.yml /usr/share/elasticsearch/config/elasticsearch.yml"
for f in $ES_PATHS; do
    if [ -f "$f" ]; then
        echo "  发现 ES 配置: $f"
        grep -E "bootstrap.memory_lock|indices.fielddata|index.store" "$f" 2>/dev/null
        break
    fi
done

echo ""
echo "============================================"
echo "完整日志已保存到: $OUTPUT_DIR"
echo "============================================"
