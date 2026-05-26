#!/bin/bash
# ============================================================
# 路径C：cgroup OOM 专项诊断脚本
#
# 用法:
#   bash cgroup_oom.sh -S <开始时间> [-E <结束时间>] [-g <cgroup路径片段或容器ID>]
#
# 示例:
#   bash cgroup_oom.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00"
#   bash cgroup_oom.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00" -g "abc123def456"
#
# 输出结构：
#   [SUMMARY]  自动摘要（模型优先阅读）
#   [DETAIL]   原始详细数据（摘要存疑时补充查阅）
# ============================================================

START_TIME=""; END_TIME=""; TARGET_CG=""

while getopts ":S:E:g:h" opt; do
    case $opt in
        S) START_TIME="$OPTARG" ;; E) END_TIME="$OPTARG" ;; g) TARGET_CG="$OPTARG" ;;
        h) sed -n '3,10p' "$0" | sed 's/^# \{0,2\}//'; exit 0 ;;
        :) echo "错误: -$OPTARG 需要参数值"; exit 1 ;;
    esac
done

if [ -n "$START_TIME" ] && [ -z "$END_TIME" ]; then
    START_TS=$(date -d "$START_TIME" +%s 2>/dev/null)
    END_TIME=$(date -d "@$((START_TS+3600))" '+%Y-%m-%d %H:%M:%S')
fi

OUTPUT_DIR="/tmp/oom_cg_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"
exec > >(tee "$OUTPUT_DIR/cgroup_oom.log") 2>&1

HAS_JOURNAL=$(which journalctl 2>/dev/null)
HAS_DOCKER=$(which docker 2>/dev/null)
HAS_KUBECTL=$(which kubectl 2>/dev/null)
CGROOT_V1="/sys/fs/cgroup/memory"
CGROOT_V2="/sys/fs/cgroup"
CG_VERSION="unknown"
[ -d "$CGROOT_V1" ] && CG_VERSION="v1"
[ -f "/sys/fs/cgroup/cgroup.controllers" ] && CG_VERSION="v2"

section() { echo ""; echo "###############################################"; echo "# $1"; echo "###############################################"; }
banner()  { echo ""; echo "╔══════════════════════════════════════════════╗"; printf "║  %-44s║\n" "$1"; echo "╚══════════════════════════════════════════════╝"; }
cmd_info() {
    echo ""
    echo "  ▶ 命令 : $1"
    echo "  ▶ 用途 : $2"
    echo "  ▶ 输出 : $3"
    echo ""
}

# ================================================================
# [SUMMARY] 自动摘要
# ================================================================
banner "[SUMMARY] 路径C cgroup OOM 自动摘要 — 模型优先阅读此节"
echo "分析时段:   ${START_TIME:-全量} ~ ${END_TIME:-全量}"
echo "目标cgroup: ${TARGET_CG:-全量扫描}"
echo "cgroup版本: $CG_VERSION"
echo ""

# ── S1: 有 OOM 事件的 cgroup 汇总表 ──────────────────────────
echo "━━━ S1. 存在 OOM 事件的 cgroup（自动过滤 failcnt/oom_events > 0）━━━"
cmd_info \
    "find /sys/fs/cgroup -name memory.failcnt（v1）或 memory.events（v2）" \
    "遍历所有 cgroup，过滤出 failcnt > 0（v1）或 oom_events > 0（v2）的 cgroup，即发生过 OOM 的容器/进程组" \
    "结构化表格：cgroup路径 / 内存限制(MB) / 当前使用(MB) / 使用率% / OOM次数；⚠️ 标记异常项"

if [ "$CG_VERSION" = "v1" ] && [ -d "$CGROOT_V1" ]; then
    printf "  %-55s %10s %10s %8s %8s\n" "cgroup路径" "limit(MB)" "usage(MB)" "使用率%" "failcnt"
    printf "  %-55s %10s %10s %8s %8s\n" "----------" "---------" "---------" "-------" "-------"
    find "$CGROOT_V1" -name "memory.failcnt" 2>/dev/null | while read f; do
        failcnt=$(cat "$f" 2>/dev/null || echo 0)
        [ "$failcnt" -eq 0 ] 2>/dev/null && continue
        dir=$(dirname "$f")
        limit=$(cat "$dir/memory.limit_in_bytes" 2>/dev/null || echo 0)
        usage=$(cat "$dir/memory.usage_in_bytes" 2>/dev/null || echo 0)
        [ "$limit" = "9223372036854771712" ] && limit_str="unlimited" || limit_str="$((limit/1024/1024))"
        pct=0; [ "$limit" -gt 0 ] 2>/dev/null && pct=$((usage*100/limit))
        printf "  %-55s %10s %10d %7d%% %8d  ⚠️\n" \
            "${dir#$CGROOT_V1}" "$limit_str" "$((usage/1024/1024))" "$pct" "$failcnt"
    done
elif [ "$CG_VERSION" = "v2" ]; then
    printf "  %-60s %10s %10s %8s\n" "cgroup路径" "usage(MB)" "max" "oom_cnt"
    printf "  %-60s %10s %10s %8s\n" "----------" "---------" "---" "-------"
    find "$CGROOT_V2" -name "memory.events" 2>/dev/null | while read f; do
        oom_cnt=$(awk '/^oom /{print $2}' "$f" 2>/dev/null || echo 0)
        [ "$oom_cnt" -eq 0 ] 2>/dev/null && continue
        dir=$(dirname "$f")
        usage=$(cat "$dir/memory.current" 2>/dev/null || echo 0)
        max=$(cat "$dir/memory.max" 2>/dev/null || echo "max")
        printf "  %-60s %10d %10s %8d  ⚠️\n" \
            "${dir#$CGROOT_V2}" "$((usage/1024/1024))" "$max" "$oom_cnt"
    done
fi

# ── S2: 所有有限制的 cgroup（按使用率排序）────────────────────
echo ""
echo "━━━ S2. 所有设置了内存限制的 cgroup（按使用率降序）━━━"
cmd_info \
    "find /sys/fs/cgroup -name memory.limit_in_bytes + usage_in_bytes（v1）" \
    "全量扫描所有设置了内存上限的 cgroup，计算当前使用率并排序" \
    "按使用率降序；使用率>80% 的 cgroup 有 OOM 风险；failcnt>0 是已发生 OOM 的直接证据"
{
if [ "$CG_VERSION" = "v1" ] && [ -d "$CGROOT_V1" ]; then
    find "$CGROOT_V1" -name "memory.limit_in_bytes" 2>/dev/null | while read f; do
        dir=$(dirname "$f"); limit=$(cat "$f" 2>/dev/null); usage=$(cat "$dir/memory.usage_in_bytes" 2>/dev/null||echo 0)
        failcnt=$(cat "$dir/memory.failcnt" 2>/dev/null||echo 0)
        [ "$limit" = "9223372036854771712" ] || [ -z "$limit" ] && continue
        pct=0; [ "$limit" -gt 0 ] 2>/dev/null && pct=$((usage*100/limit))
        warn=""; [ "$failcnt" -gt 0 ] && warn=" ⚠️failcnt=$failcnt"
        printf "%04d  %-55s %6dMB/%6dMB(%3d%%)%s\n" \
            "$pct" "${dir#$CGROOT_V1}" "$((usage/1024/1024))" "$((limit/1024/1024))" "$pct" "$warn"
    done
elif [ "$CG_VERSION" = "v2" ]; then
    find "$CGROOT_V2" -name "memory.max" 2>/dev/null | while read f; do
        max=$(cat "$f" 2>/dev/null); dir=$(dirname "$f")
        [ "$max" = "max" ] || [ -z "$max" ] && continue
        usage=$(cat "$dir/memory.current" 2>/dev/null||echo 0)
        oom_cnt=$(awk '/^oom /{print $2}' "$dir/memory.events" 2>/dev/null||echo 0)
        pct=0; [ "$max" -gt 0 ] 2>/dev/null && pct=$((usage*100/max))
        warn=""; [ "${oom_cnt:-0}" -gt 0 ] && warn=" ⚠️oom=$oom_cnt"
        printf "%04d  %-60s %6dMB/%6dMB(%3d%%)%s\n" \
            "$pct" "${dir#$CGROOT_V2}" "$((usage/1024/1024))" "$((max/1024/1024))" "$pct" "$warn"
    done
fi
} | sort -rn | sed 's/^[0-9]*  /  /' | head -30

# ── S3: 目标 cgroup 内进程内存分布 ───────────────────────────
echo ""
echo "━━━ S3. 目标 cgroup 内进程内存分布 ━━━"
cmd_info \
    "cat /sys/fs/cgroup/.../cgroup.procs + /proc/PID/status" \
    "枚举指定 cgroup 内所有进程，读取每个进程的 RSS 和 OOM score" \
    "cgroup 内各进程 RSS 排名；OOM score 最高的进程将被优先杀死；用于定位 cgroup 内哪个进程消耗了最多内存"
if [ -n "$TARGET_CG" ]; then
    # 定位 cgroup procs 文件
    if [ "$CG_VERSION" = "v1" ]; then
        PROCS_FILE=$(find "$CGROOT_V1" -path "*$TARGET_CG*" -name "cgroup.procs" 2>/dev/null | head -1)
    else
        PROCS_FILE=$(find "$CGROOT_V2" -path "*$TARGET_CG*" -name "cgroup.procs" 2>/dev/null | head -1)
    fi
    if [ -n "$PROCS_FILE" ]; then
        PIDS=$(cat "$PROCS_FILE" 2>/dev/null)
        echo "  cgroup: $TARGET_CG  进程数: $(echo "$PIDS" | wc -w)"
        printf "  %-8s %-20s %10s %10s\n" "PID" "COMM" "RSS(MB)" "OOM_SCORE"
        printf "  %-8s %-20s %10s %10s\n" "---" "----" "-------" "---------"
        for pid in $PIDS; do
            [ ! -d "/proc/$pid" ] && continue
            comm=$(cat /proc/$pid/comm 2>/dev/null)
            rss=$(awk '/^VmRSS/{printf "%.0f",$2/1024}' /proc/$pid/status 2>/dev/null)
            score=$(cat /proc/$pid/oom_score 2>/dev/null)
            printf "  %-8s %-20s %10s %10s\n" "$pid" "$comm" "${rss:-?}" "${score:-?}"
        done | sort -k3 -t' ' -rn
    else
        echo "  未找到 cgroup 路径匹配 '$TARGET_CG'，尝试全量输出..."
    fi
else
    echo "  未指定 -g 参数，显示使用率最高的 cgroup 进程概览（取前5个有限制的 cgroup）"
fi

# ── S4: 容器运行时元数据 ─────────────────────────────────────
echo ""
echo "━━━ S4. 容器运行时元数据 ━━━"
if [ -n "$HAS_DOCKER" ]; then
    cmd_info \
        "docker stats --no-stream" \
        "实时快照所有容器的内存使用量、使用率（相对于 memory limit）" \
        "MEM USAGE/LIMIT 列：当前使用量 / 设置的上限；MEM % 接近100% 时随时可能 OOM"
    docker stats --no-stream --format \
        "table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.PIDs}}" 2>/dev/null | head -20

    if [ -n "$TARGET_CG" ]; then
        echo ""
        cmd_info \
            "docker inspect <容器ID> | python3 解析 HostConfig.Memory + State.OOMKilled" \
            "获取容器的内存配置（limit/swap）和是否曾被 OOM kill" \
            "OOMKilled=true 是 docker 层面的 OOM 确认；ExitCode=137 = 128+9(SIGKILL) = OOM kill"
        docker inspect "$TARGET_CG" 2>/dev/null | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    if d:
        h=d[0].get('HostConfig',{}); s=d[0].get('State',{})
        print(f'  Memory Limit:  {h.get(\"Memory\",0)//1024//1024} MB')
        print(f'  MemorySwap:    {h.get(\"MemorySwap\",0)//1024//1024} MB')
        print(f'  OOMKilled:     {s.get(\"OOMKilled\",\"unknown\")}')
        print(f'  ExitCode:      {s.get(\"ExitCode\",\"unknown\")}')
except: pass
" 2>/dev/null
    fi
fi

if [ -n "$HAS_KUBECTL" ]; then
    echo ""
    cmd_info \
        "kubectl top pods --all-namespaces + kubectl get events --field-selector reason=OOMKilling" \
        "获取 K8s 集群中各 Pod 的内存使用，以及 OOMKilling 事件记录" \
        "top pods 显示当前内存使用量；events 显示历史 OOM kill 事件（时间/Pod名/原因）"
    kubectl top pods --all-namespaces 2>/dev/null | head -20
    echo ""
    kubectl get events --all-namespaces --field-selector reason=OOMKilling 2>/dev/null | head -20
fi

# ── S5: 时间段内 cgroup OOM 日志 ────────────────────────────
echo ""
echo "━━━ S5. 时间段内 cgroup OOM 内核日志 ━━━"
cmd_info \
    "journalctl --since/--until -k | grep 'memory cgroup|cgroup.*oom|Task in.*killed'" \
    "从内核日志中提取 cgroup 层面的 OOM 事件，区别于普通系统 OOM（有 cgroup 路径标识）" \
    "包含触发 OOM 的 cgroup 路径名；'Task in /xxx/yyy killed' 格式明确指出是哪个 cgroup 的 OOM"
if [ -n "$START_TIME" ] && [ -n "$HAS_JOURNAL" ]; then
    journalctl --since="$START_TIME" --until="$END_TIME" -k --no-pager 2>/dev/null \
        | grep -iE "memory cgroup|cgroup.*oom|oom.*cgroup|Task in.*killed|container.*oom|oom.*container" \
        | head -50
fi
dmesg -T 2>/dev/null | grep -iE "memory cgroup|cgroup.*oom|Task in.*killed" | tail -30

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[SUMMARY END] 以下为原始详细数据"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ================================================================
# [DETAIL] 原始详细数据
# ================================================================
section "[DETAIL-1] cgroup 内存统计（memory.stat）"
cmd_info \
    "cat /sys/fs/cgroup/.../memory.stat（v1）或 memory.stat（v2）" \
    "获取 cgroup 内存的精细分类统计（cache/rss/mapped_file/pgfault 等）" \
    "比 usage_in_bytes 更详细；cache 可回收，rss 不可回收；pgmajfault 高说明 cgroup 内有 swap 压力"
if [ "$CG_VERSION" = "v1" ]; then
    find "$CGROOT_V1" -name "memory.stat" 2>/dev/null | head -10 | while read f; do
        echo "=== ${f#$CGROOT_V1} ==="
        cat "$f" 2>/dev/null | grep -E "^(cache|rss|mapped_file|pgfault|pgmajfault|inactive_anon|active_anon|swap)"
    done
else
    find "$CGROOT_V2" -name "memory.stat" 2>/dev/null | head -10 | while read f; do
        echo "=== ${f#$CGROOT_V2} ==="
        cat "$f" 2>/dev/null | head -15
    done
fi

section "[DETAIL-2] memory.oom_control（v1）/ memory.events（v2）"
cmd_info \
    "cat memory.oom_control（v1）或 memory.events（v2）" \
    "获取 cgroup OOM 控制配置和历史 OOM 统计" \
    "v1: oom_kill_disable=1 表示禁止 kill（进程会被阻塞而非杀死，可能导致系统僵死）; v2: oom/oom_kill 字段为 OOM 触发次数"
if [ "$CG_VERSION" = "v1" ]; then
    find "$CGROOT_V1" -name "memory.oom_control" 2>/dev/null | head -20 | while read f; do
        echo "--- ${f#$CGROOT_V1} ---"; cat "$f" 2>/dev/null
    done
else
    find "$CGROOT_V2" -name "memory.events" 2>/dev/null | while read f; do
        oom=$(awk '/^oom /{print $2}' "$f" 2>/dev/null)
        [ "${oom:-0}" -gt 0 ] && echo "--- ${f#$CGROOT_V2} ---" && cat "$f"
    done | head -100
fi

section "收集完成"
tar czf "${OUTPUT_DIR}.tar.gz" -C /tmp "$(basename $OUTPUT_DIR)/" 2>/dev/null
echo "📦 打包文件: ${OUTPUT_DIR}.tar.gz"
