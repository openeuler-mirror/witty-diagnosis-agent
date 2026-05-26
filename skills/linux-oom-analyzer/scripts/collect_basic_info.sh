#!/bin/bash
# ============================================================
# Linux OOM 故障全量信息收集脚本（基础信息 + 日志一体化）
#
# 用法:
#   bash collect_basic_info.sh -S <开始时间> [-E <结束时间>] [-p|-n|-s <进程标识>]
#
# 时间参数:
#   -S <时间>   故障时间段开始时间（强烈建议填写），格式: "YYYY-MM-DD HH:MM:SS"
#   -E <时间>   故障时间段结束时间（可选），未填则默认 -S 后 +1 小时
#
# 进程参数（三选一，不填则为系统级全量分析）:
#   -p <PID>    精确进程 ID                      示例: -p 12345
#   -n <名称>   模糊进程名，匹配命令行含该字符串  示例: -n java
#   -s <服务>   systemd 服务名                   示例: -s nginx
#
# 使用示例:
#   bash collect_basic_info.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00"
#   bash collect_basic_info.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00" -p 12345
#   bash collect_basic_info.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00" -n java
#   bash collect_basic_info.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00" -s nginx
# ============================================================

START_TIME=""; END_TIME=""; TARGET_PID=""; TARGET_NAME=""; TARGET_SVC=""

while getopts ":S:E:p:n:s:h" opt; do
    case $opt in
        S) START_TIME="$OPTARG" ;; E) END_TIME="$OPTARG" ;;
        p) TARGET_PID="$OPTARG" ;; n) TARGET_NAME="$OPTARG" ;; s) TARGET_SVC="$OPTARG" ;;
        h) sed -n '3,22p' "$0" | sed 's/^# \{0,2\}//'; exit 0 ;;
        :) echo "错误: -$OPTARG 需要参数值"; exit 1 ;;
    esac
done

[ -z "$START_TIME" ] && echo "⚠️  未指定 -S 开始时间，将进行全量日志扫描（速度较慢）"

if [ -n "$START_TIME" ] && [ -z "$END_TIME" ]; then
    START_TS=$(date -d "$START_TIME" +%s 2>/dev/null)
    [ -z "$START_TS" ] && echo "⚠️  -S 时间格式解析失败，请使用: YYYY-MM-DD HH:MM:SS" && exit 1
    END_TIME=$(date -d "@$((START_TS+3600))" '+%Y-%m-%d %H:%M:%S')
    echo "ℹ️  未指定 -E，自动设为 +1h: $END_TIME"
fi

PROC_OPT_COUNT=0
[ -n "$TARGET_PID" ]  && PROC_OPT_COUNT=$((PROC_OPT_COUNT+1))
[ -n "$TARGET_NAME" ] && PROC_OPT_COUNT=$((PROC_OPT_COUNT+1))
[ -n "$TARGET_SVC" ]  && PROC_OPT_COUNT=$((PROC_OPT_COUNT+1))
[ "$PROC_OPT_COUNT" -gt 1 ] && echo "错误: -p / -n / -s 互斥，只能指定一个" && exit 1

OUTPUT_DIR="/tmp/oom_diag_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"
exec > >(tee "$OUTPUT_DIR/collect.log") 2>&1

if   [ -n "$TARGET_PID" ];  then PROC_DESC="精确PID: $TARGET_PID"
elif [ -n "$TARGET_NAME" ]; then PROC_DESC="模糊进程名: $TARGET_NAME"
elif [ -n "$TARGET_SVC" ];  then PROC_DESC="服务名: $TARGET_SVC"
else                              PROC_DESC="未指定（系统级全量分析）"
fi

HAS_JOURNAL=$(which journalctl 2>/dev/null)
LOG_FILES=""
for f in /var/log/messages /var/log/kern.log /var/log/syslog; do
    [ -f "$f" ] && LOG_FILES="$LOG_FILES $f"
done
OOM_PATTERN="Out of memory|oom.kill|oom-kill|Killed process|page allocation failure|kswapd|memory pressure|lowmem|SLUB: Unable|vmalloc: allocation failure|BUG: unable to handle kernel"

# ── 辅助函数 ──────────────────────────────────────────────────
section() {
    echo ""
    echo "###############################################"
    echo "# $1"
    echo "###############################################"
}
# 命令说明块：每条重要命令前打印用途和预期输出说明
cmd_info() {
    echo ""
    echo "  ▶ 命令 : $1"
    echo "  ▶ 用途 : $2"
    echo "  ▶ 输出 : $3"
    echo ""
}

echo "================================================================"
echo "  Linux OOM 故障全量信息收集"
echo "  执行时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  故障时段: ${START_TIME:-未指定} ~ ${END_TIME:-未指定}"
echo "  进程范围: $PROC_DESC"
echo "  输出目录: $OUTPUT_DIR"
echo "================================================================"

# ================================================================
# PART 1: 系统基础信息
# ================================================================
section "1. 系统基础信息"

cmd_info "uname -a" \
    "获取内核版本、硬件架构、编译时间" \
    "内核版本字符串，用于匹配源码分析和判断内核 bug 已知版本"
uname -a

cmd_info "hostname" \
    "获取主机名" \
    "标识采集来源，多机环境下避免混淆"
hostname

cmd_info "uptime" \
    "获取系统运行时长和平均负载" \
    "load average 三个值分别为 1/5/15 分钟均值；若 >CPU核数 说明 CPU 也存在压力"
uptime

cmd_info "cat /etc/os-release 或 /etc/redhat-release" \
    "获取 Linux 发行版名称和版本号" \
    "用于判断默认内核参数、日志路径、systemd 版本等发行版差异"
cat /etc/os-release 2>/dev/null || cat /etc/redhat-release 2>/dev/null

# ================================================================
# PART 2: 内存使用情况
# ================================================================
section "2. 内存使用情况"

cmd_info "free -m" \
    "以 MB 为单位展示内存和 swap 的 总量/已用/空闲/缓存" \
    "快速判断整体内存压力；available 列比 free 更准确反映可分配内存"
free -m

cmd_info "cat /proc/meminfo" \
    "获取内核内存子系统全量字段（60+ 项）" \
    "包含 AnonPages/Slab/Shmem/VmallocUsed 等精细分类，是内存归因分析的原始数据源"
cat /proc/meminfo
cp /proc/meminfo "$OUTPUT_DIR/meminfo.txt"

echo ""
echo "--- 内存关键指标汇总 & 诊断（基于 /proc/meminfo 计算）---"
echo "  ▶ 命令 : awk 对 /proc/meminfo 进行多字段提取和计算"
echo "  ▶ 用途 : 汇总各内存分类占比，自动标注异常项（未归因>512MB/Slab>15%/Shmem>10%）"
echo "  ▶ 输出 : 各类型 MB 数值 + 使用率 + 自动诊断标记"
echo ""
awk '
/MemTotal/        {total=$2} /MemFree/         {free=$2}  /MemAvailable/    {avail=$2}
/^Buffers/        {buf=$2}   /^Cached/         {cache=$2} /^Slab:/          {slab=$2}
/SReclaimable/    {srec=$2}  /SUnreclaim/      {sunrec=$2}/^Shmem:/         {shmem=$2}
/AnonPages/       {anon=$2}  /^Mapped/         {mapped=$2}/PageTables/      {pt=$2}
/VmallocUsed/     {vmalloc=$2} /KernelStack/   {kstack=$2}
/HugePages_Total/ {hptotal=$2} /Hugepagesize/  {hpsize=$2}
END {
    printf "%-22s %8d MB\n","MemTotal:",       total/1024
    printf "%-22s %8d MB\n","MemFree:",        free/1024
    printf "%-22s %8d MB\n","MemAvailable:",   avail/1024
    printf "%-22s %8d MB\n","Buffers:",        buf/1024
    printf "%-22s %8d MB\n","Cached:",         cache/1024
    printf "%-22s %8d MB\n","Shmem:",          shmem/1024
    printf "%-22s %8d MB\n","Slab(total):",    slab/1024
    printf "%-22s %8d MB\n","  Reclaimable:",  srec/1024
    printf "%-22s %8d MB\n","  Unreclaimable:",sunrec/1024
    printf "%-22s %8d MB\n","AnonPages:",      anon/1024
    printf "%-22s %8d MB\n","PageTables:",     pt/1024
    printf "%-22s %8d MB\n","VmallocUsed:",    vmalloc/1024
    printf "%-22s %8d MB\n","KernelStack:",    kstack/1024
    printf "%-22s %8d x %d kB\n","HugePages:",hptotal,hpsize
    printf "\n=== 自动诊断 ===\n"
    printf "%-30s %6.1f%%\n","内存使用率:",(total-avail)*100/total
    acc = anon+cache+slab+shmem+buf+pt+kstack+vmalloc
    unacc = total-free-acc
    printf "%-30s %6d MB  %s\n","未归因内存(>512MB告警):",unacc/1024, \
        (unacc>512*1024)?"⚠️  疑似内核模块泄漏":"✅ 正常"
    printf "%-30s %6.1f%%  %s\n","Slab占比(>15%告警):",slab*100/total, \
        (slab>total*0.15)?"⚠️  Slab偏高，检查dentry/inode":"✅ 正常"
    printf "%-30s %6.1f%%  %s\n","Shmem占比(>10%告警):",shmem*100/total, \
        (shmem>total*0.10)?"⚠️  Shmem偏高，检查tmpfs":"✅ 正常"
}' /proc/meminfo

cmd_info "swapon --show 或 cat /proc/swaps" \
    "显示当前 swap 分区/文件的挂载情况和使用量" \
    "若 Used 列持续增大，说明系统在用 swap 缓解内存压力，I/O 延迟会显著上升"
swapon --show 2>/dev/null || cat /proc/swaps

# ================================================================
# PART 3: CPU & 内存压力指标
# ================================================================
section "3. CPU & 内存压力指标"

cmd_info "nproc" \
    "获取逻辑 CPU 核数" \
    "用于对比 load average；load/nproc > 2 时说明 CPU 也存在严重排队"
nproc

cmd_info "vmstat 1 5" \
    "每秒采样一次，共 5 次，展示 CPU/内存/IO/swap 综合指标" \
    "关键列：si/so=swap换入换出(>0说明内存压力大) bi=块读取(>0说明page回收中) b=阻塞进程数"
vmstat 1 5

cmd_info "cat /proc/vmstat | grep -E '^(pgfault|oom_kill|allocstall|kswapd|pswpin|compact)'" \
    "从内核内存统计中提取 OOM/回收/碎片整理相关累计计数器" \
    "oom_kill=OOM触发总次数; allocstall_normal=直接内存回收次数(高=严重压力); compact_fail=内存规整失败(高=碎片化)"
cat /proc/vmstat | grep -E \
    "^(pgfault|pgmajfault|pswpin|pswpout|oom_kill|pgalloc_normal|pgfree|pgsteal|pgscan|kswapd_steal|allocstall|compact_fail|compact_success)"
cp /proc/vmstat "$OUTPUT_DIR/vmstat.txt"

cmd_info "sar -u 1 3" \
    "通过 sysstat 获取 3 秒内 CPU 使用率历史（需安装 sysstat）" \
    "%iowait 列高说明 I/O 等待（可能因 swap 或 page 回收导致）；若不可用则跳过"
sar -u 1 3 2>/dev/null || echo "sar 不可用，跳过"

# ================================================================
# PART 4: OOM 内核参数
# ================================================================
section "4. OOM 相关内核参数"

cmd_info "sysctl -a | grep vm.*oom / overcommit / watermark 等" \
    "读取内核内存管理策略参数" \
    "panic_on_oom=0 时触发 OOM kill 而非 panic；overcommit_memory=2 时按比例限制提交；min_free_kbytes 影响回收触发水位"
sysctl -a 2>/dev/null | grep -E \
    "vm\.(panic_on_oom|oom_kill_allocating_task|oom_dump_tasks|\
overcommit_memory|overcommit_ratio|min_free_kbytes|\
swappiness|zone_reclaim_mode|vfs_cache_pressure|\
dirty_ratio|dirty_background_ratio|watermark_scale_factor)"

# ================================================================
# PART 5: 日志分析（时间段优先）
# ================================================================
section "5. OOM 日志分析（时间段: ${START_TIME:-全量} ~ ${END_TIME:-全量}）"

if [ -n "$START_TIME" ] && [ -n "$END_TIME" ]; then
    echo "=== [5.1] 时间段内 OOM 日志（优先级最高）==="

    if [ -n "$HAS_JOURNAL" ]; then
        cmd_info "journalctl --since='$START_TIME' --until='$END_TIME' -k | grep OOM关键字" \
            "从 systemd journal 提取故障时间段内内核 OOM 相关日志" \
            "包含 Out of memory / Killed process / page allocation failure 等事件，是时间线分析的主要来源"
        journalctl --since="$START_TIME" --until="$END_TIME" \
            -k --no-pager 2>/dev/null | grep -E "$OOM_PATTERN" | head -300

        echo ""
        cmd_info "journalctl --since='$START_TIME' --until='$END_TIME' -k（全量）" \
            "提取时间段内完整内核日志，用于还原故障前后的完整时间线" \
            "包含所有内核事件，可看到 kswapd 唤醒、内存分配失败、驱动报错等上下文"
        journalctl --since="$START_TIME" --until="$END_TIME" \
            -k --no-pager 2>/dev/null | head -2000
    fi

    for LOG_FILE in $LOG_FILES; do
        cmd_info "awk 时间段过滤 $LOG_FILE" \
            "从传统 syslog 文件中按时间段提取 OOM 关键字" \
            "适用于未使用 systemd 的系统；时间戳格式支持 ISO 8601"
        awk -v s="$START_TIME" -v e="$END_TIME" -v pat="$OOM_PATTERN" '
        {
            if (match($0,/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}/)) {
                ts=substr($0,RSTART,19); gsub("T"," ",ts)
                if(ts>=s && ts<=e && $0~pat) print
            }
        }' "$LOG_FILE" 2>/dev/null | head -300
    done
fi

echo ""
echo "=== [5.2] 全量 OOM 日志（最近100条，兜底）==="
cmd_info "journalctl -k | grep OOM关键字 | tail -100" \
    "不限时间范围，获取历史上所有 OOM 事件（防止时间段漏掉早期触发）" \
    "100条 OOM 相关内核日志；若与时间段内日志重复说明时间段覆盖完整"
[ -n "$HAS_JOURNAL" ] && journalctl -k --no-pager 2>/dev/null | grep -E "$OOM_PATTERN" | tail -100
for LOG_FILE in $LOG_FILES; do grep -E "$OOM_PATTERN" "$LOG_FILE" 2>/dev/null | tail -50; done

echo ""
cmd_info "dmesg -T | grep OOM关键字" \
    "从内核环形缓冲区（ring buffer）读取 OOM 日志，-T 参数将时间戳转换为可读格式" \
    "注意：ring buffer 有大小限制（通常 512KB），系统繁忙时早期日志可能被覆盖"
dmesg -T 2>/dev/null | grep -E "$OOM_PATTERN" | tail -100
dmesg -T 2>/dev/null > "$OUTPUT_DIR/dmesg_full.txt"

echo ""
echo "=== [5.3] OOM kill 事件完整上下文（含进程快照列表）==="
cmd_info "dmesg -T + 行号定位，提取每次 OOM 事件前后 40 行" \
    "OOM killer 触发时内核会打印所有进程的内存占用列表（task list），这是判断被选中进程和内存分布的关键" \
    "包含：触发进程、各进程 PID/RSS/swap/oom_score、最终被杀进程及原因"
dmesg -T 2>/dev/null | grep -n "Out of memory\|oom_kill_process\|Killed process" \
    | head -10 \
    | while IFS=: read lineno rest; do
        echo ""; echo ">>> OOM 事件（dmesg 行 $lineno）<<<"
        dmesg -T 2>/dev/null | sed -n "$((lineno>5?lineno-5:1)),$((lineno+40))p"
    done

[ -n "$TARGET_SVC" ] && [ -n "$HAS_JOURNAL" ] && {
    echo ""
    echo "=== [5.4] 服务 [$TARGET_SVC] 专项日志 ==="
    cmd_info "journalctl -u $TARGET_SVC --since/--until" \
        "提取指定 systemd 服务在故障时间段内的全部日志（应用层 + 系统层）" \
        "可看到服务的启动/停止/OOM kill 事件及应用自身的报错输出"
    if [ -n "$START_TIME" ]; then
        journalctl -u "$TARGET_SVC" --since="$START_TIME" --until="$END_TIME" --no-pager 2>/dev/null | head -500
    else
        journalctl -u "$TARGET_SVC" --no-pager 2>/dev/null | tail -300
    fi
}

# ================================================================
# PART 6: 进程内存排名
# ================================================================
section "6. 进程内存排名（当前快照 Top 30）"

cmd_info "ps aux --sort=-%mem | head -31" \
    "按实际物理内存（RSS）降序列出当前进程，快速找出内存大户" \
    "RSS 列（第6列，KB）= 进程当前驻留物理内存；注意多线程进程共享内存段会被重复计算"
ps aux --sort=-%mem | head -31
ps aux --sort=-%mem > "$OUTPUT_DIR/ps_by_mem.txt"

echo ""
cmd_info "ps aux --sort=-%vsz | head -21" \
    "按虚拟内存（VSZ）降序排列，补充展示申请但未必驻留的内存" \
    "VSZ 远大于 RSS 说明进程有大量 mmap 或延迟分配的虚拟内存（不一定是问题）"
ps aux --sort=-%vsz | head -21

echo ""
cmd_info "遍历 /proc/PID/oom_score 和 /proc/PID/oom_score_adj" \
    "读取每个进程的 OOM 评分和调整值，OOM killer 会选择评分最高的进程杀死" \
    "score = (RSS/总内存)*1000 + adj；adj=-1000 表示永不被杀；adj=1000 表示最优先被杀"
printf "%-8s %-10s %-8s %s\n" "PID" "OOM_SCORE" "OOM_ADJ" "COMM"
printf "%-8s %-10s %-8s %s\n" "---" "---------" "-------" "----"
for pid in $(ls /proc | grep '^[0-9]*$'); do
    score=$(cat /proc/$pid/oom_score 2>/dev/null)
    [ -z "$score" ] && continue
    [ "$score" -eq 0 ] 2>/dev/null && continue
    adj=$(cat /proc/$pid/oom_score_adj 2>/dev/null)
    comm=$(cat /proc/$pid/comm 2>/dev/null)
    printf "%-8s %-10s %-8s %s\n" "$pid" "$score" "$adj" "$comm"
done 2>/dev/null | sort -k2 -rn | head -30

# ================================================================
# PART 7: 目标进程详细信息
# ================================================================
RESOLVED_PIDS=""
if [ -n "$TARGET_PID" ]; then
    [ -d "/proc/$TARGET_PID" ] && RESOLVED_PIDS="$TARGET_PID" || \
        echo "⚠️  PID $TARGET_PID 不存在，可能已退出"
elif [ -n "$TARGET_NAME" ]; then
    RESOLVED_PIDS=$(pgrep -f "$TARGET_NAME" 2>/dev/null | head -10 | tr '\n' ' ')
    [ -z "$RESOLVED_PIDS" ] && echo "⚠️  模糊进程名 [$TARGET_NAME] 无匹配运行中进程"
elif [ -n "$TARGET_SVC" ]; then
    MAIN_PID=$(systemctl show "$TARGET_SVC" --property=MainPID --value 2>/dev/null)
    if [ -n "$MAIN_PID" ] && [ "$MAIN_PID" != "0" ]; then
        CGROUP=$(systemctl show "$TARGET_SVC" --property=ControlGroup --value 2>/dev/null)
        if [ -n "$CGROUP" ]; then
            PROCS=$(find /sys/fs/cgroup -path "*${CGROUP}*/cgroup.procs" 2>/dev/null | head -1)
            [ -n "$PROCS" ] && RESOLVED_PIDS=$(cat "$PROCS" 2>/dev/null | tr '\n' ' ')
        fi
        RESOLVED_PIDS="${RESOLVED_PIDS:-$MAIN_PID}"
    else
        RESOLVED_PIDS=$(pgrep -f "$TARGET_SVC" 2>/dev/null | head -10 | tr '\n' ' ')
    fi
fi

if [ -n "$RESOLVED_PIDS" ]; then
    section "7. 目标进程详细信息（$PROC_DESC）"
    for PID in $RESOLVED_PIDS; do
        [ ! -d "/proc/$PID" ] && echo "PID $PID 已退出，跳过" && continue
        COMM=$(cat /proc/$PID/comm 2>/dev/null)
        echo ""; echo "══════ PID: $PID  COMM: $COMM ══════"

        cmd_info "grep 内存字段 /proc/$PID/status" \
            "读取进程内存相关 status 字段，包含虚拟/物理/峰值/swap 内存" \
            "VmHWM = 历史最高 RSS 峰值（High Water Mark），与当前 VmRSS 对比可判断内存是否在增长"
        grep -E "^(Name|Pid|PPid|Threads|VmPeak|VmSize|VmRSS|VmHWM|VmData|VmStk|VmExe|VmLib|VmSwap)" \
            /proc/$PID/status 2>/dev/null

        echo ""
        cmd_info "cat /proc/$PID/smaps_rollup 或 awk 汇总 smaps" \
            "按内存段类型（heap/stack/共享库/匿名mmap）汇总 RSS/PSS/PrivateDirty" \
            "PrivateDirty = 进程独占且已修改的物理页，是进程真实内存开销的最准确指标"
        if [ -f "/proc/$PID/smaps_rollup" ]; then
            cat /proc/$PID/smaps_rollup
        else
            awk '
            /^[0-9a-f]/{n=$NF; if(n=="")t="anonymous"; else if(n~/\.so/)t="shared_lib";
                else if(n=="[heap]")t="heap"; else if(n~/\[stack/)t="stack"; else t="file_mmap"}
            /^Rss:/{rss[t]+=$2;trss+=$2} /^Private_Dirty:/{pd[t]+=$2}
            END{printf "%-18s %10s %12s\n","Type","RSS(KB)","PrivDirty(KB)";
                printf "%-18s %10s %12s\n","----","-------","------------";
                for(t in rss)printf "%-18s %10d %12d\n",t,rss[t],pd[t];
                printf "%-18s %10d\n","TOTAL",trss}' /proc/$PID/smaps 2>/dev/null
        fi

        echo ""
        cmd_info "grep 匿名mmap段 /proc/$PID/maps | wc -l" \
            "统计进程匿名 mmap 段（无文件名的可读写映射）的数量，是 mmap 泄漏的关键指标" \
            "正常进程通常 < 100 段；> 500 段且持续增长强烈暗示 mmap 泄漏"
        anon_segs=$(grep -c "^[0-9a-f].*rw-p 00000000 00:00 0 *$" /proc/$PID/maps 2>/dev/null || echo 0)
        fd_cnt=$(ls /proc/$PID/fd 2>/dev/null | wc -l)
        printf "    匿名mmap段数量: %-6s  %s\n" "$anon_segs" \
            "$([ "$anon_segs" -gt 500 ] 2>/dev/null && echo '⚠️ 偏多，疑似mmap泄漏' || echo '正常')"
        printf "    fd 数量:        %-6s  %s\n" "$fd_cnt" \
            "$([ "$fd_cnt" -gt 1000 ] 2>/dev/null && echo '⚠️ 偏多，疑似fd泄漏' || echo '正常')"
    done

elif [ "$PROC_OPT_COUNT" -gt 0 ]; then
    section "7. 目标进程历史记录（进程已退出，从日志搜索）"
    SEARCH_TERM="${TARGET_PID:-${TARGET_NAME:-$TARGET_SVC}}"
    cmd_info "grep -i '$SEARCH_TERM' dmesg + journalctl + syslog" \
        "在所有日志来源中搜索目标进程的历史记录，还原进程被杀前后的状态" \
        "重点关注 Killed / OOM / exit 相关行，可看到被杀时的内存占用"
    dmesg -T 2>/dev/null | grep -i "$SEARCH_TERM" | tail -30
    [ -n "$HAS_JOURNAL" ] && [ -n "$START_TIME" ] && \
        journalctl --since="$START_TIME" --until="$END_TIME" --no-pager 2>/dev/null \
            | grep -i "$SEARCH_TERM" | head -100
    for LOG_FILE in $LOG_FILES; do
        grep -i "$SEARCH_TERM" "$LOG_FILE" 2>/dev/null | grep -E "kill|OOM|memory|error" | tail -30
    done
fi

# ================================================================
# PART 8: Slab 内存详情
# ================================================================
section "8. Slab 内存详情"

cmd_info "slabtop -o" \
    "以快照模式输出内核 slab 分配器的对象统计，按内存占用降序排列" \
    "显示各 slab 对象的数量、单个大小、总内存占用；dentry/inode 偏高说明目录缓存异常"
slabtop -o 2>/dev/null | head -40

echo ""
cmd_info "awk 解析 /proc/slabinfo（Top 20）" \
    "逐行解析 slab 信息文件，计算各对象类型的总内存占用（对象数 × 对象大小）" \
    "比 slabtop 更稳定，不依赖终端；输出包含对象名/数量/单个大小/总MB"
awk 'NR>2{printf "%-32s objs=%-8d obj_size=%-6dB total=%8.1fMB\n",
    $1,$3,$4,$3*$4/1024/1024}' /proc/slabinfo 2>/dev/null | sort -k5 -rn | head -20
cp /proc/slabinfo "$OUTPUT_DIR/slabinfo.txt" 2>/dev/null

echo ""
cmd_info "grep dentry|inode|sock|task_struct /proc/slabinfo" \
    "重点关注最常见的内核 slab 泄漏对象" \
    "dentry偏高=大量目录遍历; proc_inode偏高=大量进程创建; sock偏高=网络连接未关闭"
awk 'NR>2 && /dentry|inode|sock|task_struct|mm_struct|vm_area|signal_cache/{
    printf "%-32s objs=%-8d obj_size=%-6dB total=%8.1fMB\n",$1,$3,$4,$3*$4/1024/1024
}' /proc/slabinfo 2>/dev/null | sort -k5 -rn

# ================================================================
# PART 9: cgroup 内存
# ================================================================
section "9. cgroup 内存使用情况"

cmd_info "find /sys/fs/cgroup/memory -name memory.limit_in_bytes（v1）" \
    "遍历所有 cgroup v1 的内存限制文件，过滤掉无限制（max int）的 cgroup" \
    "同时读取 usage_in_bytes 和 failcnt；failcnt>0 是 cgroup OOM 的直接证据"
find /sys/fs/cgroup/memory -name "memory.limit_in_bytes" 2>/dev/null \
    | while read f; do
        dir=$(dirname "$f"); limit=$(cat "$f" 2>/dev/null); usage=$(cat "$dir/memory.usage_in_bytes" 2>/dev/null||echo 0)
        failcnt=$(cat "$dir/memory.failcnt" 2>/dev/null||echo 0)
        [ "$limit" = "9223372036854771712" ] || [ -z "$limit" ] && continue
        pct=0; [ "$limit" -gt 0 ] 2>/dev/null && pct=$((usage*100/limit))
        warn=""; [ "$failcnt" -gt 0 ] && warn=" ⚠️ failcnt=$failcnt"
        [ "$pct" -gt 80 ] 2>/dev/null && warn="$warn ⚠️ 使用率${pct}%"
        name=${dir#/sys/fs/cgroup/memory}
        printf "%-55s limit=%6dMB usage=%6dMB(%3d%%)%s\n" \
            "${name:-/}" "$((limit/1024/1024))" "$((usage/1024/1024))" "$pct" "$warn"
    done

echo ""
cmd_info "find /sys/fs/cgroup -name memory.current（v2）" \
    "遍历所有 cgroup v2 的当前内存使用，读取 memory.max 和 memory.events" \
    "memory.events 中 oom 字段 > 0 是 cgroup OOM 的直接证据"
find /sys/fs/cgroup -name "memory.current" 2>/dev/null \
    | while read f; do
        dir=$(dirname "$f"); usage=$(cat "$f" 2>/dev/null||echo 0); max=$(cat "$dir/memory.max" 2>/dev/null||echo "max")
        oom_cnt=$(awk '/^oom /{print $2}' "$dir/memory.events" 2>/dev/null); warn=""
        [ "${oom_cnt:-0}" -gt 0 ] && warn=" ⚠️ oom_events=$oom_cnt"
        name=${dir#/sys/fs/cgroup}
        printf "%-55s usage=%6dMB max=%-10s%s\n" "${name:-/}" "$((usage/1024/1024))" "$max" "$warn"
    done

# ================================================================
# PART 10: 内核模块
# ================================================================
section "10. 内核模块列表"

cmd_info "lsmod | sort -k2 -rn" \
    "列出所有已加载的内核模块，按模块大小降序排列" \
    "第2列为模块占用内存（字节）；大模块需重点关注，异常大的第三方模块可能存在内存泄漏"
lsmod | sort -k2 -rn
lsmod > "$OUTPUT_DIR/lsmod.txt"

echo ""
cmd_info "modinfo 过滤非标准路径模块" \
    "识别路径不在标准内核目录下的第三方/自定义模块" \
    "非原生模块（如监控 agent、自研驱动）是内核态内存泄漏的高危来源"
lsmod | awk 'NR>1{print $1}' | while read mod; do
    fname=$(modinfo "$mod" 2>/dev/null | awk '/^filename/{print $2}')
    [ -z "$fname" ] && continue
    echo "$fname" | grep -qE "/kernel/(drivers|net|fs|crypto|sound|block|lib|arch|mm|security)" && continue
    desc=$(modinfo "$mod" 2>/dev/null | awk '/^description/{$1="";print}')
    printf "%-25s %s\n  路径: %s\n" "$mod" "$desc" "$fname"
done | head -40

# ================================================================
# PART 11: NUMA & 内存碎片
# ================================================================
section "11. NUMA 内存分布 & 内存碎片"

cmd_info "numactl --hardware" \
    "显示 NUMA 节点数量、每节点内存大小和节点间距离" \
    "多 NUMA 系统中，某个节点内存耗尽但其他节点有空闲时，也会触发 OOM"
numactl --hardware 2>/dev/null || echo "numactl 不可用"

echo ""
cmd_info "cat /proc/buddyinfo" \
    "显示每个 NUMA 节点/zone 中各 order（2^N 个连续页）的空闲块数量" \
    "高阶（order>=8）数量为0说明内存碎片严重，大块连续内存分配将失败触发 OOM，即使总空闲内存不少"
cat /proc/buddyinfo 2>/dev/null
cat /proc/buddyinfo > "$OUTPUT_DIR/buddyinfo.txt" 2>/dev/null

cmd_info "cat /proc/pagetypeinfo" \
    "详细显示每种页面类型（Unmovable/Movable/Reclaimable）在各 order 的分布" \
    "Unmovable 类型高阶页不足说明不可移动内存碎片化，是内核态大内存分配失败的根因"
cat /proc/pagetypeinfo 2>/dev/null | head -60
cat /proc/pagetypeinfo > "$OUTPUT_DIR/pagetypeinfo.txt" 2>/dev/null

# ================================================================
# PART 12: 历史监控数据
# ================================================================
section "12. 历史监控数据（atop / sar）"

if [ -n "$START_TIME" ]; then
    DATE_STR=$(date -d "$START_TIME" +%Y%m%d 2>/dev/null)
    START_HM=$(date -d "$START_TIME" '+%H:%M' 2>/dev/null)
    END_HM=$(date -d "$END_TIME"   '+%H:%M' 2>/dev/null)

    cmd_info "atop -r /var/log/atop/atop_$DATE_STR -b $START_HM -e $END_HM -PMEM" \
        "从 atop 历史记录文件中回放故障时间段内的内存使用情况" \
        "按采集间隔（通常1分钟）展示系统内存总量/使用量/进程内存变化，是分析内存增长趋势的最佳工具"
    ATOP_FILE="/var/log/atop/atop_$DATE_STR"
    if [ -f "$ATOP_FILE" ]; then
        atop -r "$ATOP_FILE" -b "$START_HM" -e "$END_HM" -PMEM 2>/dev/null | head -200
    else
        echo "atop 历史文件 $ATOP_FILE 不存在（未安装 atop 或未到达记录时间）"
    fi

    echo ""
    cmd_info "sar -r -f /var/log/sa/saDD -s HH:MM:SS -e HH:MM:SS" \
        "从 sysstat sar 历史文件中读取故障时间段的内存统计" \
        "%memused/%commit = 内存使用率/提交率；kbavail 持续下降到0时说明内存即将耗尽"
    SAR_FILE="/var/log/sa/sa$(date -d "$START_TIME" +%d 2>/dev/null)"
    sar -r -f "$SAR_FILE" \
        -s "$(date -d "$START_TIME" '+%H:%M:%S' 2>/dev/null)" \
        -e "$(date -d "$END_TIME"   '+%H:%M:%S' 2>/dev/null)" 2>/dev/null \
        | head -80 || echo "sar 历史数据不可用（未安装 sysstat 或无对应日期文件）"
fi

# ================================================================
# 打包 & 完成
# ================================================================
section "收集完成"
tar czf "${OUTPUT_DIR}.tar.gz" -C /tmp "$(basename $OUTPUT_DIR)/" 2>/dev/null
echo ""
echo "✅ 全量信息收集完成！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📁 输出目录 : $OUTPUT_DIR"
echo "📦 打包文件 : ${OUTPUT_DIR}.tar.gz"
echo "请将打包文件或本脚本完整输出提供给分析 Agent。"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
