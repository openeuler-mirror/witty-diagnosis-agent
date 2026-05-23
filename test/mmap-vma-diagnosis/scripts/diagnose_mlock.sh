#!/bin/bash
# ============================================================
# 路径C：mlock 超限专项诊断脚本
#
# 用法:
#   bash diagnose_mlock.sh -S <开始时间> [-E <结束时间>] [-p <PID> | -n <名称>]
#
# 示例:
#   bash diagnose_mlock.sh -S "2024-01-15 14:00:00" -p 12345
#   bash diagnose_mlock.sh -S "2024-01-15 14:00:00" -n elasticsearch
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

OUTPUT_DIR="/tmp/mmap_mlock_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"
exec > >(tee "$OUTPUT_DIR/diagnose_mlock.log") 2>&1

HAS_JOURNAL=$(which journalctl 2>/dev/null)

section() { echo ""; echo "###############################################"; echo "# $1"; echo "###############################################"; }
banner()  { echo ""; echo "╔══════════════════════════════════════════════╗"; printf "║  %-44s║\n" "$1"; echo "╚══════════════════════════════════════════════╝"; }

# ================================================================
# [SUMMARY] 自动摘要
# ================================================================
banner "[SUMMARY] 路径C mlock 超限诊断 — 模型优先阅读此节"
echo "分析时段: ${START_TIME:-全量} ~ ${END_TIME:-全量}"
echo "目标PID:  ${TARGET_PID:-未指定}"
echo ""

# ── S1: memlock 限制检查 ───────────────────────────────────────
echo "━━━ S1. memlock 限制检查 ━━━"
echo ""
echo "  当前 shell RLIMIT_MEMLOCK:"
echo "    soft = $(ulimit -l 2>/dev/null || echo 'N/A')"
echo "    hard = $(ulimit -H -l 2>/dev/null || echo 'N/A')"
echo ""

if [ -n "$TARGET_PID" ] && [ -d "/proc/$TARGET_PID" ]; then
    echo "  进程 $TARGET_PID limits:"
    grep "max locked memory" "/proc/$TARGET_PID/limits" 2>/dev/null

    echo ""
    echo "  进程锁定内存:"
    grep VmLck "/proc/$TARGET_PID/status" 2>/dev/null

    echo ""
    echo "  进程 capabilities:"
    CAP_EFF=$(grep "CapEff:" "/proc/$TARGET_PID/status" 2>/dev/null | awk '{print $2}')
    if [ -n "$CAP_EFF" ]; then
        # 检查 cap_sys_resource (bit 22 in effective set)
        CAP_INT=$((16#$CAP_EFF))
        HAS_SYS_RESOURCE=$(( (CAP_INT >> 22) & 1 ))
        if [ "$HAS_SYS_RESOURCE" = "1" ]; then
            echo "  ⚠️  进程持有 CAP_SYS_RESOURCE — 可绕过 RLIMIT_MEMLOCK"
        fi
        capsh --decode=$CAP_EFF 2>/dev/null | grep -i "sys_resource" || true
    fi

    echo ""
    echo "  进程 cgroup:"
    cat "/proc/$TARGET_PID/cgroup" 2>/dev/null
fi

echo ""
echo "  systemd 全局 DefaultLimitMEMLOCK:"
systemctl show --property=DefaultLimitMEMLOCK 2>/dev/null || echo "    N/A"

echo ""
echo "  /etc/security/limits.conf memlock 配置:"
grep -v "^#\|^$" /etc/security/limits.conf 2>/dev/null | grep -i memlock | head -10

echo ""
echo "  limits.d memlock 配置:"
cat /etc/security/limits.d/*.conf 2>/dev/null | grep -v "^#\|^$" | grep -i memlock | head -10

# ── S2: 系统锁定内存总量 ───────────────────────────────────────
echo ""
echo "━━━ S2. 系统锁定内存状态 ━━━"
echo ""
grep -E "Unevictable|Mlocked" /proc/meminfo 2>/dev/null

# ── S3: 内核日志 — mlock 相关 ──────────────────────────────────
echo ""
echo "━━━ S3. 内核日志 — mlock 相关 ━━━"
echo ""

if [ -n "$HAS_JOURNAL" ] && [ -n "$START_TIME" ]; then
    END_ARG="${END_TIME:-$(date -d "@$(($(date -d "$START_TIME" +%s)+3600))" '+%Y-%m-%d %H:%M:%S')}"
    journalctl -k --since="$START_TIME" --until="$END_ARG" --no-pager 2>/dev/null \
        | grep -iE "mlock|locked memory|RLIMIT_MEMLOCK|memlock" > "$OUTPUT_DIR/kernel_mlock.log"
elif [ -f /var/log/messages ]; then
    grep -iE "mlock|locked memory" /var/log/messages 2>/dev/null > "$OUTPUT_DIR/kernel_mlock.log"
fi

if [ -s "$OUTPUT_DIR/kernel_mlock.log" ]; then
    cat "$OUTPUT_DIR/kernel_mlock.log"
else
    echo "  未找到 mlock 相关内核日志"
fi

# ── S4: ES 配置检查 ────────────────────────────────────────────
echo ""
echo "━━━ S4. Elasticsearch bootstrap.memory_lock 检查 ━━━"
echo ""
ES_CONFIG=""
for f in /etc/elasticsearch/elasticsearch.yml /usr/share/elasticsearch/config/elasticsearch.yml; do
    [ -f "$f" ] && ES_CONFIG="$f" && break
done
if [ -n "$ES_CONFIG" ]; then
    MLOCK=$(grep "bootstrap.memory_lock" "$ES_CONFIG" 2>/dev/null | awk '{print $2}')
    echo "  ES 配置: $ES_CONFIG"
    echo "  bootstrap.memory_lock = $MLOCK"
    if [ "$MLOCK" = "true" ]; then
        echo "  ⚠️  ES 请求内存锁定，但 memlock 限制可能不足"
    fi
else
    echo "  未发现 ES 配置"
fi

echo ""
echo "============================================"
echo "完整日志已保存到: $OUTPUT_DIR"
echo "============================================"
