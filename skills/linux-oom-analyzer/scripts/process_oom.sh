#!/bin/bash
# ============================================================
# 路径B：进程级 OOM 专项诊断脚本
#
# 用法:
#   bash process_oom.sh -S <开始时间> [-E <结束时间>] (-p <PID> | -n <名称> | -s <服务>)
#
# 示例:
#   bash process_oom.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00" -p 12345
#   bash process_oom.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00" -n java
#   bash process_oom.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00" -s nginx
#
# 输出结构：
#   [SUMMARY]  自动摘要（模型优先阅读）
#   [DETAIL]   原始详细数据（摘要存疑时补充查阅）
# ============================================================

START_TIME=""; END_TIME=""; TARGET_PID=""; TARGET_NAME=""; TARGET_SVC=""

while getopts ":S:E:p:n:s:h" opt; do
    case $opt in
        S) START_TIME="$OPTARG" ;; E) END_TIME="$OPTARG" ;;
        p) TARGET_PID="$OPTARG" ;; n) TARGET_NAME="$OPTARG" ;; s) TARGET_SVC="$OPTARG" ;;
        h) sed -n '3,12p' "$0" | sed 's/^# \{0,2\}//'; exit 0 ;;
        :) echo "错误: -$OPTARG 需要参数值"; exit 1 ;;
    esac
done

if [ -n "$START_TIME" ] && [ -z "$END_TIME" ]; then
    START_TS=$(date -d "$START_TIME" +%s 2>/dev/null)
    END_TIME=$(date -d "@$((START_TS+3600))" '+%Y-%m-%d %H:%M:%S')
fi

# 解析目标 PID
RESOLVED_PIDS=""; SEARCH_TERM=""
if   [ -n "$TARGET_PID" ];  then
    [ -d "/proc/$TARGET_PID" ] && RESOLVED_PIDS="$TARGET_PID"; SEARCH_TERM="$TARGET_PID"
elif [ -n "$TARGET_NAME" ]; then
    RESOLVED_PIDS=$(pgrep -f "$TARGET_NAME" 2>/dev/null | head -5 | tr '\n' ' '); SEARCH_TERM="$TARGET_NAME"
elif [ -n "$TARGET_SVC" ];  then
    MAIN_PID=$(systemctl show "$TARGET_SVC" --property=MainPID --value 2>/dev/null)
    [ -n "$MAIN_PID" ] && [ "$MAIN_PID" != "0" ] && RESOLVED_PIDS="$MAIN_PID"
    SEARCH_TERM="$TARGET_SVC"
fi

OUTPUT_DIR="/tmp/oom_proc_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"
exec > >(tee "$OUTPUT_DIR/process_oom.log") 2>&1

HAS_JOURNAL=$(which journalctl 2>/dev/null)

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
banner "[SUMMARY] 路径B 进程级OOM 自动摘要 — 模型优先阅读此节"
echo "分析时段: ${START_TIME:-全量} ~ ${END_TIME:-全量}"
echo "目标进程: ${TARGET_PID:+精确PID=$TARGET_PID} ${TARGET_NAME:+模糊名称=$TARGET_NAME} ${TARGET_SVC:+服务=$TARGET_SVC}"
echo "解析PID:  ${RESOLVED_PIDS:-未找到（进程可能已退出）}"
echo ""

# ── S1: 进程退出方式确认 ──────────────────────────────────────
echo "━━━ S1. 进程退出方式确认 ━━━"
cmd_info \
    "dmesg -T | grep 'Killed process' + journalctl | grep 'exit code|signal=KILL'" \
    "确认进程是否被 OOM killer 杀死（区别于正常退出/segment fault/用户主动 kill）" \
    "OOM kill 特征：dmesg 中出现 'Killed process <PID>'；systemd 服务日志中 exit-code=killed, signal=KILL"
echo "  [dmesg 中的 OOM kill 记录]"
dmesg -T 2>/dev/null | grep -E "Killed process|Kill process|oom.kill" \
    | grep -i "${SEARCH_TERM:-}" | tail -10

echo ""
echo "  [journalctl 进程退出记录]"
if [ -n "$HAS_JOURNAL" ] && [ -n "$SEARCH_TERM" ] && [ -n "$START_TIME" ]; then
    journalctl --since="$START_TIME" --until="$END_TIME" --no-pager 2>/dev/null \
        | grep -iE "${SEARCH_TERM}.*(kill|exit|OOM|signal|137)" | tail -15
fi
[ -n "$TARGET_SVC" ] && [ -n "$HAS_JOURNAL" ] && \
    journalctl -u "$TARGET_SVC" --no-pager 2>/dev/null | grep -E "exit|kill|OOM|signal" | tail -10

echo ""
echo "  [当前进程状态（VmRSS vs VmHWM 对比）]"
cmd_info \
    "cat /proc/PID/status | grep Vm" \
    "读取进程当前内存使用和历史峰值，VmHWM=有史以来最高 RSS" \
    "若 VmRSS 接近 VmHWM 且两者都在持续增大，说明内存仍在增长；若 VmRSS << VmHWM 说明内存已部分释放"
for PID in $RESOLVED_PIDS; do
    [ ! -d "/proc/$PID" ] && echo "  PID $PID: 已退出" && continue
    state=$(awk '/^State/{print $2,$3}' /proc/$PID/status 2>/dev/null)
    vmrss=$(awk '/^VmRSS/{printf "%d MB",$2/1024}' /proc/$PID/status 2>/dev/null)
    vmhwm=$(awk '/^VmHWM/{printf "%d MB",$2/1024}' /proc/$PID/status 2>/dev/null)
    printf "  PID %-8s 状态=%-12s 当前RSS=%-12s 历史峰值(HWM)=%-12s\n" \
        "$PID" "$state" "$vmrss" "$vmhwm"
done

# ── S2: 进程内存分布汇总 ─────────────────────────────────────
echo ""
echo "━━━ S2. 进程内存分布汇总 ━━━"
for PID in $RESOLVED_PIDS; do
    [ ! -d "/proc/$PID" ] && continue
    COMM=$(cat /proc/$PID/comm 2>/dev/null)
    echo "  ── PID $PID ($COMM) ──"

    cmd_info \
        "cat /proc/$PID/smaps_rollup 或 awk 汇总 /proc/$PID/smaps" \
        "按内存段类型汇总 RSS/PSS/PrivateDirty；PrivateDirty 是进程独占的已修改页，是最准确的内存消耗指标" \
        "heap=堆内存(malloc区); stack=栈; anonymous=匿名mmap; shared_lib=动态库; PrivateDirty=实际占用物理内存"
    if [ -f "/proc/$PID/smaps_rollup" ]; then
        cat /proc/$PID/smaps_rollup
    else
        awk '
        /^[0-9a-f]/{n=$NF; if(n=="")t="anonymous_mmap"; else if(n~/\.so/)t="shared_lib";
            else if(n=="[heap]")t="heap"; else if(n~/\[stack/)t="stack"; else t="file_mmap"}
        /^Rss:/{rss[t]+=$2;trss+=$2} /^Pss:/{pss[t]+=$2}
        /^Private_Dirty:/{pd[t]+=$2;tpd+=$2} /^Swap:/{swap[t]+=$2}
        END{
            printf "    %-20s %10s %12s %12s\n","Type","RSS(KB)","PrivDirty(KB)","Swap(KB)"
            printf "    %-20s %10s %12s %12s\n","----","-------","-------------","--------"
            for(t in rss)printf "    %-20s %10d %12d %12d\n",t,rss[t],pd[t],swap[t]
            printf "    %-20s %10d %12d\n","TOTAL",trss,tpd
        }' /proc/$PID/smaps 2>/dev/null
    fi

    echo ""
    cmd_info \
        "grep 匿名mmap段 /proc/$PID/maps | wc -l  +  ls /proc/$PID/fd | wc -l" \
        "统计三大泄漏指标：①匿名mmap段数量（mmap泄漏）②fd数量（fd泄漏）③heap虚拟大小（heap泄漏）" \
        "匿名mmap段>500=mmap泄漏; fd>1000=fd泄漏; heap虚拟大小持续增大=heap泄漏（需结合时间趋势判断）"
    anon_segs=$(grep -c "^[0-9a-f].*rw-p 00000000 00:00 0 *$" /proc/$PID/maps 2>/dev/null || echo 0)
    fd_cnt=$(ls /proc/$PID/fd 2>/dev/null | wc -l)
    heap_range=$(grep "\[heap\]" /proc/$PID/maps 2>/dev/null | head -1 | awk -F'[ -]' '{
        if(NF>=2){start=strtonum("0x"$1); end=strtonum("0x"$2); printf "%d MB",(end-start)/1024/1024}}')
    printf "    匿名mmap段数量: %-6s  %s\n" "$anon_segs" \
        "$([ "$anon_segs" -gt 500 ] 2>/dev/null && echo '⚠️ 偏多，疑似mmap内存泄漏' || echo '✅ 正常')"
    printf "    fd 数量:        %-6s  %s\n" "$fd_cnt" \
        "$([ "$fd_cnt" -gt 1000 ] 2>/dev/null && echo '⚠️ 偏多，疑似fd泄漏' || echo '✅ 正常')"
    printf "    Heap 虚拟大小:  %s\n" "${heap_range:-未找到heap段}"
    echo ""
done

# ── S3: 历史内存趋势 ─────────────────────────────────────────
echo "━━━ S3. 历史内存趋势 ━━━"
cmd_info \
    "atop -r <历史文件> -PPRG | grep <进程名>  或  sar -r" \
    "从历史监控数据中回放进程内存的逐分钟变化趋势，判断是单调递增（泄漏）还是随负载波动（正常）" \
    "atop PPRG 格式包含每分钟进程的 VSIZE/RSIZE；单调递增且不随负载下降是内存泄漏的核心特征"
if [ -n "$START_TIME" ] && [ -n "$SEARCH_TERM" ]; then
    DATE_STR=$(date -d "$START_TIME" +%Y%m%d 2>/dev/null)
    ATOP_FILE="/var/log/atop/atop_$DATE_STR"
    if [ -f "$ATOP_FILE" ]; then
        atop -r "$ATOP_FILE" \
            -b "$(date -d "$START_TIME" '+%H:%M' 2>/dev/null)" \
            -e "$(date -d "$END_TIME"   '+%H:%M' 2>/dev/null)" \
            -PPRG 2>/dev/null | grep -i "$SEARCH_TERM" | head -60
    else
        echo "  atop 历史文件 $ATOP_FILE 不存在"
    fi
    SAR_FILE="/var/log/sa/sa$(date -d "$START_TIME" +%d 2>/dev/null)"
    echo ""
    echo "  [sar 系统内存趋势（时间段内，反映整体走向）]"
    sar -r -f "$SAR_FILE" \
        -s "$(date -d "$START_TIME" '+%H:%M:%S' 2>/dev/null)" \
        -e "$(date -d "$END_TIME"   '+%H:%M:%S' 2>/dev/null)" 2>/dev/null \
        | head -40 || echo "  sar 历史不可用"
else
    echo "  未指定时间段或进程标识，跳过历史趋势"
fi

# ── S4: 同类进程对比 ─────────────────────────────────────────
echo ""
echo "━━━ S4. 同类进程内存对比 ━━━"
cmd_info \
    "ps aux | grep <进程名> | 按 RSS 排序" \
    "横向对比同名/同类进程的内存使用，判断是单进程异常还是所有实例都偏高" \
    "若只有特定 PID 内存异常高而其他同名进程正常，说明是该实例的个别问题（如特定请求触发泄漏）"
[ -n "$SEARCH_TERM" ] && \
    ps aux | grep -i "$SEARCH_TERM" | grep -v grep | \
    awk '{printf "  PID=%-8s RSS=%-8skB VSZ=%-10skB CMD=%s\n",$2,$6,$5,$11}' | \
    sort -k3 -t= -rn | head -20

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[SUMMARY END] 以下为原始详细数据"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ================================================================
# [DETAIL] 原始详细数据
# ================================================================
section "[DETAIL-1] 进程完整 /proc/PID/status"
cmd_info "cat /proc/PID/status" \
    "完整进程状态文件，包含所有内存字段、线程数、信号掩码等" \
    "60+ 字段；重点关注 Vm* 内存字段和 Threads 数量"
for PID in $RESOLVED_PIDS; do
    [ ! -d "/proc/$PID" ] && continue
    echo "=== PID $PID ==="
    cat /proc/$PID/status 2>/dev/null
done

section "[DETAIL-2] 进程 maps 前200行（内存段列表）"
cmd_info "cat /proc/PID/maps" \
    "列出进程所有虚拟内存段（地址范围/权限/文件名）" \
    "每行一个内存段：起止地址 权限(rwxp) 偏移 设备 inode 文件名；[heap]=[堆] [stack]=[主线程栈] 空文件名=匿名mmap"
for PID in $RESOLVED_PIDS; do
    [ ! -d "/proc/$PID" ] && continue
    echo "=== PID $PID maps ==="
    cat /proc/$PID/maps 2>/dev/null | head -200
done

section "[DETAIL-3] fd 分类统计（fd数量>200时输出）"
cmd_info "ls -la /proc/PID/fd | 分类统计" \
    "枚举进程所有文件描述符并按目标类型分组，识别 fd 泄漏的资源类型" \
    "按 socket/pipe/file/anon 分类计数；某类 fd 数量异常多（如 socket 数千个）指向具体泄漏点"
for PID in $RESOLVED_PIDS; do
    [ ! -d "/proc/$PID" ] && continue
    fd_cnt=$(ls /proc/$PID/fd 2>/dev/null | wc -l)
    echo "=== PID $PID fd 共 $fd_cnt 个 ==="
    [ "$fd_cnt" -gt 200 ] 2>/dev/null && \
        ls -la /proc/$PID/fd 2>/dev/null \
            | awk 'NF>0{print $NF}' | sed 's/[0-9]\{4,\}/N/g' \
            | sort | uniq -c | sort -rn | head -20
done

section "[DETAIL-4] OOM kill 日志中的进程相关记录"
cmd_info "dmesg -T | grep -B2 -A50 <进程名>" \
    "从内核日志中提取目标进程被 OOM kill 时的完整上下文" \
    "包含被杀时刻的 anon-rss/total-vm，以及内核打印的所有进程内存快照列表"
dmesg -T 2>/dev/null | grep -B2 -A50 \
    "$([ -n "$SEARCH_TERM" ] && echo "$SEARCH_TERM" || echo 'Out of memory')" | head -200

section "收集完成"
tar czf "${OUTPUT_DIR}.tar.gz" -C /tmp "$(basename $OUTPUT_DIR)/" 2>/dev/null
echo "📦 打包文件: ${OUTPUT_DIR}.tar.gz"
