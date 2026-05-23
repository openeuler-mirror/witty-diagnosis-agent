#!/bin/bash
# ============================================================
# 路径B：SIGBUS 文件截断专项诊断脚本
#
# 用法:
#   bash diagnose_sigbus.sh -S <开始时间> [-E <结束时间>] [-p <PID> | -n <名称>]
#
# 示例:
#   bash diagnose_sigbus.sh -S "2024-01-15 14:00:00" -p 12345
#   bash diagnose_sigbus.sh -S "2024-01-15 14:00:00" -n "myapp"
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

OUTPUT_DIR="/tmp/mmap_sigbus_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"
exec > >(tee "$OUTPUT_DIR/diagnose_sigbus.log") 2>&1

HAS_JOURNAL=$(which journalctl 2>/dev/null)
HAS_COREDUMPCTL=$(which coredumpctl 2>/dev/null)

section() { echo ""; echo "###############################################"; echo "# $1"; echo "###############################################"; }
banner()  { echo ""; echo "╔══════════════════════════════════════════════╗"; printf "║  %-44s║\n" "$1"; echo "╚══════════════════════════════════════════════╝"; }

# ================================================================
# [SUMMARY] 自动摘要
# ================================================================
banner "[SUMMARY] 路径B SIGBUS 文件截断诊断 — 模型优先阅读此节"
echo "分析时段: ${START_TIME:-全量} ~ ${END_TIME:-全量}"
echo ""

# ── S1: 内核日志 — SIGBUS 相关 ─────────────────────────────────
echo "━━━ S1. 内核日志 — SIGBUS / bus error ━━━"
echo ""

LOG_FILE="$OUTPUT_DIR/kernel_sigbus.log"
if [ -n "$HAS_JOURNAL" ] && [ -n "$START_TIME" ]; then
    journalctl -k --since="$START_TIME" --until="${END_TIME:-$START_TIME + 1 hour}" --no-pager 2>/dev/null \
        | grep -iE "SIGBUS|bus error|segfault at.*ip.*sp" > "$LOG_FILE"
elif [ -f /var/log/messages ]; then
    grep -iE "SIGBUS|bus error" /var/log/messages 2>/dev/null > "$LOG_FILE"
fi

if [ -s "$LOG_FILE" ]; then
    cat "$LOG_FILE"
else
    echo "  未找到 SIGBUS 相关内核日志"
fi

# ── S2: Core dump 检查 ─────────────────────────────────────────
echo ""
echo "━━━ S2. Core dump 检查 ━━━"
echo ""

if [ -n "$HAS_COREDUMPCTL" ]; then
    coredumpctl list 2>/dev/null | head -20
    echo ""
    # 检查最近的 SIGBUS core dump
    coredumpctl list 2>/dev/null | grep "SIGBUS" | head -5
else
    # 检查 /var/lib/systemd/coredump 或其他常见位置
    ls -lt /var/lib/systemd/coredump/ 2>/dev/null | head -5
    ls -lt /var/crash/ 2>/dev/null | head -5
    ls -lt core* 2>/dev/null | head -5
fi

# ── S3: 日志轮转配置检查 ───────────────────────────────────────
echo ""
echo "━━━ S3. 日志轮转配置检查 ━━━"
echo ""
for f in /etc/logrotate.conf /etc/logrotate.d/*; do
    if [ -f "$f" ] && grep -q "copytruncate\|create" "$f" 2>/dev/null; then
        echo "  可能触发 SIGBUS 的轮转配置: $f"
        grep -A5 "copytruncate\|create" "$f" 2>/dev/null
    fi
done

# ── S4: 当前 mmap 文件映射状态 ─────────────────────────────────
if [ -n "$TARGET_PID" ] && [ -d "/proc/$TARGET_PID" ]; then
    echo ""
    echo "━━━ S4. 进程文件映射状态 ━━━"
    echo ""
    awk '{if ($NF != "") print $1, $2, $3, $NF}' "/proc/$TARGET_PID/maps" 2>/dev/null | head -30
    echo ""

    # 检查映射的文件是否还存在、大小是否有变化
    echo "  [映射文件大小检查]"
    awk '{if ($NF != "" && $NF !~ /^\[|^\/SYSV|^\/dev\/|^\/memfd:/) print $NF}' \
        "/proc/$TARGET_PID/maps" 2>/dev/null | sort -u | while read f; do
        [ -f "$f" ] && echo "  $f ($(stat -c%s "$f" 2>/dev/null) bytes)" \
                   || echo "  $f (已删除或被替换)"
    done | head -20
fi

echo ""
echo "============================================"
echo "完整日志已保存到: $OUTPUT_DIR"
echo "============================================"
