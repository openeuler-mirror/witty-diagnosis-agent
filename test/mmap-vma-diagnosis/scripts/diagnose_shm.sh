#!/bin/bash
# ============================================================
# 路径D：共享内存映射 Permission denied 专项诊断脚本
#
# 用法:
#   bash diagnose_shm.sh -S <开始时间> [-E <结束时间>] [-p <PID> | -n <名称>]
#
# 示例:
#   bash diagnose_shm.sh -S "2024-01-15 14:00:00" -p 12345
#   bash diagnose_shm.sh -S "2024-01-15 14:00:00" -n myapp
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

OUTPUT_DIR="/tmp/mmap_shm_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"
exec > >(tee "$OUTPUT_DIR/diagnose_shm.log") 2>&1

HAS_JOURNAL=$(which journalctl 2>/dev/null)

section() { echo ""; echo "###############################################"; echo "# $1"; echo "###############################################"; }
banner()  { echo ""; echo "╔══════════════════════════════════════════════╗"; printf "║  %-44s║\n" "$1"; echo "╚══════════════════════════════════════════════╝"; }

# ================================================================
# [SUMMARY] 自动摘要
# ================================================================
banner "[SUMMARY] 路径D 共享内存映射诊断 — 模型优先阅读此节"
echo "分析时段: ${START_TIME:-全量} ~ ${END_TIME:-全量}"
echo ""

# ── S1: 共享内存内核参数 ───────────────────────────────────────
echo "━━━ S1. 共享内存内核参数 ━━━"
echo ""
echo "  kernel.shmall = $(cat /proc/sys/kernel/shmall 2>/dev/null || echo N/A)"
echo "  kernel.shmmax = $(cat /proc/sys/kernel/shmmax 2>/dev/null || echo N/A)"
echo "  kernel.shmmni = $(cat /proc/sys/kernel/shmmni 2>/dev/null || echo N/A)"
echo ""

# ── S2: 当前共享内存段列表 ────────────────────────────────────
echo "━━━ S2. 当前共享内存段列表 ━━━"
echo ""
ipcs -m -a 2>/dev/null | head -40
echo ""
echo "  共享内存资源使用:"
ipcs -u 2>/dev/null

# ── S3: 目标进程共享内存状态 ──────────────────────────────────
if [ -n "$TARGET_PID" ] && [ -d "/proc/$TARGET_PID" ]; then
    echo ""
    echo "━━━ S3. 目标进程共享内存检查 ━━━"
    echo ""
    echo "  进程 capabilities:"
    getpcaps "$TARGET_PID" 2>/dev/null || cat "/proc/$TARGET_PID/status" | grep CapEff 2>/dev/null
    echo ""
    echo "  进程 cgroup:"
    cat "/proc/$TARGET_PID/cgroup" 2>/dev/null
    echo ""
    echo "  /dev/shm 中该进程的文件:"
    lsof -p "$TARGET_PID" 2>/dev/null | grep "/dev/shm" | head -20
fi

# ── S4: /dev/shm 和容器 shm 检查 ──────────────────────────────
echo ""
echo "━━━ S4. /dev/shm 状态 ━━━"
echo ""
df -h /dev/shm 2>/dev/null
echo ""
mount | grep -i shm 2>/dev/null | head -10

# ── S5: 内核日志 ──────────────────────────────────────────────
echo ""
echo "━━━ S5. 内核日志 — 共享内存相关 ━━━"
echo ""

if [ -n "$HAS_JOURNAL" ] && [ -n "$START_TIME" ]; then
    END_ARG="${END_TIME:-$(date -d "@$(($(date -d "$START_TIME" +%s)+3600))" '+%Y-%m-%d %H:%M:%S')}"
    journalctl -k --since="$START_TIME" --until="$END_ARG" --no-pager 2>/dev/null \
        | grep -iE "shmget|shmat|shmctl|shared memory|shm|SYSV" > "$OUTPUT_DIR/kernel_shm.log"
elif [ -f /var/log/messages ]; then
    grep -iE "shmget|shmat|shared memory" /var/log/messages 2>/dev/null > "$OUTPUT_DIR/kernel_shm.log"
fi

if [ -s "$OUTPUT_DIR/kernel_shm.log" ]; then
    cat "$OUTPUT_DIR/kernel_shm.log"
else
    echo "  未找到共享内存相关内核日志"
fi

# ── S6: SELinux 检查 ──────────────────────────────────────────
echo ""
echo "━━━ S6. SELinux / AppArmor 状态 ━━━"
echo ""
if command -v getenforce &>/dev/null; then
    echo "  SELinux: $(getenforce 2>/dev/null)"
    ls -Z /dev/shm/ 2>/dev/null | head -10
fi
if command -v aa-status &>/dev/null; then
    aa-status 2>/dev/null | head -5
fi

echo ""
echo "============================================"
echo "完整日志已保存到: $OUTPUT_DIR"
echo "============================================"
