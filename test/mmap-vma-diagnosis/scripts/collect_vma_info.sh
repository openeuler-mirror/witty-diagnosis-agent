#!/bin/bash
# ============================================================
# VMA 综合信息收集脚本
#
# 用法:
#   bash collect_vma_info.sh -S <开始时间> [-E <结束时间>] [-p <PID>] [-n <进程名>]
#
# 时间参数:
#   -S <时间>   故障时间段开始时间，格式: "YYYY-MM-DD HH:MM:SS"
#   -E <时间>   故障时间段结束时间（可选），未填则默认 -S 后 +1 小时
#
# 过滤参数（可选）:
#   -p <PID>    精确进程 ID
#   -n <名称>   模糊进程名
#
# 输出结构:
#   终端直接输出 — 诊断摘要
#   /tmp/vma_diag_*/ — 完整详细数据
# ============================================================

START_TIME=""; END_TIME=""; TARGET_PID=""; TARGET_NAME=""

while getopts ":S:E:p:n:h" opt; do
    case $opt in
        S) START_TIME="$OPTARG" ;; E) END_TIME="$OPTARG" ;;
        p) TARGET_PID="$OPTARG" ;; n) TARGET_NAME="$OPTARG" ;;
        h) sed -n '3,18p' "$0" | sed 's/^# \{0,2\}//'; exit 0 ;;
        :) echo "错误: -$OPTARG 需要参数值"; exit 1 ;;
    esac
done

if [ -n "$START_TIME" ] && [ -z "$END_TIME" ]; then
    START_TS=$(date -d "$START_TIME" +%s 2>/dev/null)
    [ -z "$START_TS" ] && echo "错误: -S 时间格式解析失败" && exit 1
    END_TIME=$(date -d "@$((START_TS+3600))" '+%Y-%m-%d %H:%M:%S')
fi

# 解析目标 PID
if [ -n "$TARGET_NAME" ] && [ -z "$TARGET_PID" ]; then
    TARGET_PID=$(pgrep -f "$TARGET_NAME" 2>/dev/null | head -1)
fi

OUTPUT_DIR="/tmp/vma_diag_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"
exec > >(tee "$OUTPUT_DIR/collect.log") 2>&1

HAS_JOURNAL=$(which journalctl 2>/dev/null)

section() { echo ""; echo "###############################################"; echo "# $1"; echo "###############################################"; }
banner()  { echo ""; echo "╔══════════════════════════════════════════════╗"; printf "║  %-44s║\n" "$1"; echo "╚══════════════════════════════════════════════╝"; }

# ================================================================
# [SUMMARY] 自动摘要
# ================================================================
banner "[SUMMARY] VMA 综合信息摘要 — 模型优先阅读此节"
echo "分析时段: ${START_TIME:-全量} ~ ${END_TIME:-全量}"
echo "目标PID:  ${TARGET_PID:-未指定}"
echo ""

# ── S1: 系统 VMA 参数 ──────────────────────────────────────────
section "S1. 系统 VMA 参数"
echo ""
echo "  vm.max_map_count  = $(cat /proc/sys/vm/max_map_count 2>/dev/null || echo N/A)"
echo "  vm.overcommit_memory = $(cat /proc/sys/vm/overcommit_memory 2>/dev/null || echo N/A)"
echo "  vm.overcommit_ratio  = $(cat /proc/sys/vm/overcommit_ratio 2>/dev/null || echo N/A)"
echo "  vm.mmap_min_addr     = $(cat /proc/sys/vm/mmap_min_addr 2>/dev/null || echo N/A)"
echo ""
echo "  共享内存限制:"
echo "  kernel.shmall = $(cat /proc/sys/kernel/shmall 2>/dev/null || echo N/A)"
echo "  kernel.shmmax = $(cat /proc/sys/kernel/shmmax 2>/dev/null || echo N/A)"
echo "  kernel.shmmni = $(cat /proc/sys/kernel/shmmni 2>/dev/null || echo N/A)"
echo ""
echo "  ASLR: randomize_va_space = $(cat /proc/sys/kernel/randomize_va_space 2>/dev/null || echo N/A)"

# ── S2: 系统资源限制 ────────────────────────────────────────────
section "S2. 系统资源限制"
echo ""
echo "  RLIMIT_MEMLOCK (当前 shell):"
echo "    soft = $(ulimit -l 2>/dev/null || echo N/A)"
echo "    hard = $(ulimit -H -l 2>/dev/null || echo N/A)"
echo ""

# ── S3: 目标进程 VMA 统计 ──────────────────────────────────────
section "S3. 目标进程 VMA 统计"
if [ -n "$TARGET_PID" ] && [ -d "/proc/$TARGET_PID" ]; then
    MAPS_FILE="$OUTPUT_DIR/pid_${TARGET_PID}_maps.txt"
    SMAPS_FILE="$OUTPUT_DIR/pid_${TARGET_PID}_smaps_rollup.txt"
    STATUS_FILE="$OUTPUT_DIR/pid_${TARGET_PID}_status.txt"
    LIMITS_FILE="$OUTPUT_DIR/pid_${TARGET_PID}_limits.txt"

    cat "/proc/$TARGET_PID/maps" > "$MAPS_FILE" 2>/dev/null
    cat "/proc/$TARGET_PID/status" > "$STATUS_FILE" 2>/dev/null
    cat "/proc/$TARGET_PID/limits" > "$LIMITS_FILE" 2>/dev/null
    [ -f "/proc/$TARGET_PID/smaps_rollup" ] && cat "/proc/$TARGET_PID/smaps_rollup" > "$SMAPS_FILE" 2>/dev/null

    VMA_COUNT=$(wc -l < "$MAPS_FILE" 2>/dev/null)
    MAX_MAP_COUNT=$(cat /proc/sys/vm/max_map_count 2>/dev/null || echo 65530)
    VMA_USAGE=$((VMA_COUNT * 100 / MAX_MAP_COUNT))

    echo "  VMA 数量:  $VMA_COUNT  (max_map_count=$MAX_MAP_COUNT, 使用率=${VMA_USAGE}%)"
    [ "$VMA_USAGE" -gt 80 ] && echo "  ⚠️  VMA 使用率超过 80%！"
    echo ""
    echo "  进程内存状态 (来自 /proc/$TARGET_PID/status):"
    grep -E "VmPeak|VmSize|VmLck|VmRSS|VmData|VmStk|VmExe" "$STATUS_FILE" 2>/dev/null
    echo ""
    echo "  进程 limits (locked memory):"
    grep "max locked memory" "$LIMITS_FILE" 2>/dev/null
    echo ""
    echo "  VMA 类型分布:"
    awk '{
        if ($7 ~ /^\[heap\]$/)       type="[heap]"
        else if ($7 ~ /^\[stack\]$/) type="[stack]"
        else if ($7 ~ /^\[vdso\]$/)  type="[vdso]"
        else if ($7 ~ /^\[/)         type="[anon]"
        else if ($NF != "")          type="file:"$NF
        else                         type="anon"
        count[type]++
    } END {
        for (t in count) printf "  %-30s %d\n", t, count[t]
    }' "$MAPS_FILE" 2>/dev/null | sort -rn -k2

    cat "/proc/$TARGET_PID/fd/"* 2>/dev/null > "$OUTPUT_DIR/pid_${TARGET_PID}_fd.txt"
    FD_COUNT=$(ls -la "/proc/$TARGET_PID/fd/" 2>/dev/null | wc -l)
    echo "  fd 数量:  $FD_COUNT"
else
    echo "  目标 PID $TARGET_PID 未指定或进程已退出"
fi

# ── S4: 共享内存状态 ──────────────────────────────────────────
section "S4. 共享内存状态"
echo ""
ipcs -m -a 2>/dev/null | head -30
echo ""
echo "共享内存资源使用:"
ipcs -u 2>/dev/null

# ── S5: 内存碎片状态 ──────────────────────────────────────────
section "S5. 内存碎片状态"
echo ""
echo "Buddyinfo (高阶页可用性):"
BUDDY_FILE="$OUTPUT_DIR/buddyinfo.txt"
cat /proc/buddyinfo > "$BUDDY_FILE" 2>/dev/null
cat "$BUDDY_FILE" 2>/dev/null | awk '{
    printf "  %s %s: ", $1, $2
    min_order=0; for (i=4; i<=NF; i++) {
        if ($i+0 > 0) min_order = i-4
    }
    printf "max contiguous order=%d (%d pages, %d KB)\n", min_order, 2^min_order, (2^min_order)*4
}'

echo ""
echo "HugePage 状态:"
grep -E "HugePages_Total|HugePages_Free|Hugepagesize" /proc/meminfo 2>/dev/null

# ── S6: 内核日志 — mmap/mlock/sigbus/shm 相关错误 ──────────────
section "S6. 内核日志关键字搜索"
echo ""
LOG_FILE="$OUTPUT_DIR/kernel_errors.log"

if [ -n "$HAS_JOURNAL" ] && [ -n "$START_TIME" ]; then
    journalctl -k --since="$START_TIME" --until="$END_TIME" --no-pager 2>/dev/null \
        | grep -iE "max_map_count|mmap.*fail|SIGBUS|bus error|mlock|locked memory|shmget|shmat|page allocation failure" \
        > "$LOG_FILE"
elif [ -f /var/log/messages ]; then
    awk -v s="${START_TIME:-2000-01-01}" -v e="${END_TIME:-2099-12-31}" '
        match($0,/[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}/) {
            ts=substr($0,RSTART,19); if(ts>=s && ts<=e) print
        }
    ' /var/log/messages 2>/dev/null | grep -iE "max_map_count|mmap.*fail|SIGBUS|bus error|mlock" > "$LOG_FILE"
fi

if [ -s "$LOG_FILE" ]; then
    cat "$LOG_FILE"
else
    echo "  未找到相关内核错误日志"
fi

# ── S7: 内存信息 ─────────────────────────────────────────────
section "S7. 系统内存关键指标"
echo ""
grep -E "MemTotal|MemFree|MemAvailable|Mlocked|Shmem|Unevictable" /proc/meminfo 2>/dev/null

echo ""
echo "============================================"
echo "完整日志已保存到: $OUTPUT_DIR"
echo "============================================"
