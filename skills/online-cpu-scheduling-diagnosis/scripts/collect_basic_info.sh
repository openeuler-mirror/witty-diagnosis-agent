#!/bin/bash
# ============================================================
# CPU 调度故障全量信息收集脚本
#
# 用法:
#   bash collect_basic_info.sh -S <开始时间> [-E <结束时间>] [-p|-n|-s <进程标识>]
#
# 时间参数:
#   -S <时间>   故障时间段开始时间（建议填写），格式: "YYYY-MM-DD HH:MM:SS"
#   -E <时间>   故障时间段结束时间（可选），未填则默认 -S 后 +1 小时
#
# 进程参数（三选一，不填则为系统级全量分析）:
#   -p <PID>    精确进程 ID                      示例: -p 12345
#   -n <名称>   模糊进程名，匹配命令行含该字符串  示例: -n java
#   -s <服务>   systemd 服务名                   示例: -s nginx
#
# 使用示例:
#   bash collect_basic_info.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00"
#   bash collect_basic_info.sh -S "2024-01-15 14:00:00" -p 12345
#   bash collect_basic_info.sh -S "2024-01-15 14:00:00" -n java
#   bash collect_basic_info.sh -S "2024-01-15 14:00:00" -s nginx
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

OUTPUT_DIR="/tmp/cpu_diag_$(date +%Y%m%d_%H%M%S)"
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
CPU_PATTERN="blocked for more than|hung_task|soft lockup|hard lockup|rcu.*stall|sched.*delay|I/O error|blk_update_request|NFS server not responding|printk: messages suppressed|BUG:|Call Trace|RIP:|Kernel panic"

section() {
    echo ""
    echo "###############################################"
    echo "# $1"
    echo "###############################################"
}

cmd_info() {
    echo ""
    echo "  ▶ 命令 : $1"
    echo "  ▶ 用途 : $2"
    echo "  ▶ 输出 : $3"
    echo ""
}

echo "================================================================"
echo "  CPU 调度故障全量信息收集"
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
    "内核版本字符串，用于判断已知 bug 和调度器版本"
uname -a

cmd_info "hostname" \
    "获取主机名" \
    "标识采集来源，多机环境下避免混淆"
hostname

cmd_info "uptime" \
    "获取系统运行时长和平均负载" \
    "load average 三个值分别为 1/5/15 分钟均值；Load/Cores > 2 说明存在压力"
uptime

cmd_info "cat /etc/os-release 或 /etc/redhat-release" \
    "获取 Linux 发行版名称和版本号" \
    "用于判断默认内核参数、systemd 版本等发行版差异"
cat /etc/os-release 2>/dev/null || cat /etc/redhat-release 2>/dev/null

# ================================================================
# PART 2: 负载与 CPU 使用率
# ================================================================
section "2. 负载与 CPU 使用率"

cmd_info "cat /proc/loadavg" \
    "获取系统负载和最近创建的进程信息" \
    "前三个值为 1/5/15 分钟负载；第四个值为当前运行进程数/总进程数"
cat /proc/loadavg

cmd_info "nproc" \
    "获取逻辑 CPU 核数" \
    "用于计算 Load/Cores 比值；Load/Cores > 2 时说明存在排队"
nproc

echo ""
echo "--- 负载诊断（基于 /proc/loadavg 计算）---"
echo "  ▶ 命令 : awk 对 /proc/loadavg 进行计算"
echo "  ▶ 用途 : 计算 Load/Cores 比值，自动标注异常"
echo "  ▶ 输出 : 负载比值 + 自动诊断标记"
echo ""
CORES=$(nproc 2>/dev/null || echo 1)
awk -v cores="$CORES" '{
    load1=$1; load5=$2; load15=$3
    ratio1=load1/cores; ratio5=load5/cores; ratio15=load15/cores
    printf "%-20s %8.2f\n", "Load 1min:", load1
    printf "%-20s %8.2f\n", "Load 5min:", load5
    printf "%-20s %8.2f\n", "Load 15min:", load15
    printf "%-20s %8d\n", "CPU Cores:", cores
    printf "\n=== 自动诊断 ===\n"
    printf "%-25s %6.2f  %s\n", "Load/Cores (1min):", ratio1, \
        (ratio1>4)?"⚠️  严重过载":(ratio1>2)?"⚠️  存在压力":"✅ 正常"
    printf "%-25s %6.2f  %s\n", "Load/Cores (5min):", ratio5, \
        (ratio5>4)?"⚠️  严重过载":(ratio5>2)?"⚠️  存在压力":"✅ 正常"
    printf "%-25s %6.2f  %s\n", "Load/Cores (15min):", ratio15, \
        (ratio15>4)?"⚠️  持续过载":(ratio15>2)?"⚠️  持续压力":"✅ 正常"
}' /proc/loadavg

cmd_info "cat /proc/stat | head -n $((CORES+1))" \
    "获取 CPU 使用率原始计数器" \
    "user/nice/system/idle/iowait/irq/softirq 列；用于计算各类型 CPU 占比"
cat /proc/stat | head -n $((CORES+1))

echo ""
echo "--- CPU 使用率快照（mpstat）---"
cmd_info "mpstat -P ALL 1 1" \
    "通过 sysstat 获取各 CPU 核的使用率快照" \
    "%usr=用户态 %sys=内核态 %iowait=I/O等待 %irq=硬中断 %soft=软中断；若不可用则跳过"
mpstat -P ALL 1 1 2>/dev/null || echo "mpstat 不可用，跳过"

cmd_info "vmstat 1 5" \
    "每秒采样一次，共 5 次，展示 CPU/内存/IO/swap 综合指标" \
    "r=运行队列进程数 b=阻塞进程数 wa=I/O等待 si/so=swap换入换出"
vmstat 1 5

# ================================================================
# PART 3: 进程状态统计
# ================================================================
section "3. 进程状态统计"

cmd_info "ps 状态统计" \
    "统计各状态进程数量" \
    "R=运行中 D=不可中断睡眠 Z=僵尸 S=睡眠 T=停止"
echo ""
ps -eo stat | awk '{
    if (NR > 1) {
        state = substr($1, 1, 1)
        count[state]++
    }
} END {
    printf "%-10s %8s\n", "状态", "数量"
    printf "%-10s %8s\n", "----", "----"
    for (s in count) printf "%-10s %8d\n", s, count[s]
}' | sort

echo ""
echo "--- 进程状态诊断 ---"
D_COUNT=$(ps -eo stat | awk 'NR>1 && /^D/ {count++} END {print count+0}')
Z_COUNT=$(ps -eo stat | awk 'NR>1 && /^Z/ {count++} END {print count+0}')
R_COUNT=$(ps -eo stat | awk 'NR>1 && /^R/ {count++} END {print count+0}')
printf "D 状态进程数: %-6d  %s\n" "$D_COUNT" \
    "$([ "$D_COUNT" -gt 10 ] && echo '⚠️  偏多，可能存在 I/O 阻塞' || echo '✅ 正常')"
printf "Z 状态进程数: %-6d  %s\n" "$Z_COUNT" \
    "$([ "$Z_COUNT" -gt 10 ] && echo '⚠️  偏多，检查父进程回收逻辑' || echo '✅ 正常')"
printf "R 状态进程数: %-6d  %s\n" "$R_COUNT" \
    "$([ "$R_COUNT" -gt "$CORES" ] && echo '⚠️  超过 CPU 核数，存在排队' || echo '✅ 正常')"

cmd_info "ps aux --sort=-%cpu | head -21" \
    "按 CPU 使用率降序列出进程" \
    "快速找出 CPU 消耗大户；%CPU 列（第3列）= 进程 CPU 使用率"
ps aux --sort=-%cpu | head -21

# ================================================================
# PART 4: 关键配置参数
# ================================================================
section "4. 关键配置参数"

cmd_info "sysctl -a | grep sched / printk / rt" \
    "读取 CPU 调度相关内核参数" \
    "sched_rt_runtime_us=-1 表示 RT 无限制；printk 级别过高可能导致日志洪泛"
sysctl -a 2>/dev/null | grep -E \
    "kernel\.(sched|printk|softlockup|hung_task)|kernel\.rt"

echo ""
echo "--- RT 配置诊断 ---"
RT_RUNTIME=$(cat /proc/sys/kernel/sched_rt_runtime_us 2>/dev/null)
printf "sched_rt_runtime_us: %s\n" "$RT_RUNTIME"
if [ "$RT_RUNTIME" = "-1" ]; then
    echo "⚠️  RT 进程无时间限制，可能导致饿死其他进程"
elif [ -n "$RT_RUNTIME" ] && [ "$RT_RUNTIME" -gt 0 ]; then
    echo "✅ RT 进程有时间限制（${RT_RUNTIME}us/1s）"
fi

echo ""
cmd_info "cat /proc/sys/kernel/hung_task_timeout_secs" \
    "获取 D 状态进程超时检测时间" \
    "默认 120 秒；超时会打印 'blocked for more than X seconds' 日志"
cat /proc/sys/kernel/hung_task_timeout_secs 2>/dev/null || echo "未配置"

echo ""
cmd_info "cat /proc/sys/kernel/softlockup_panic" \
    "获取软锁死是否触发 panic" \
    "1 表示软锁死时触发内核 panic；0 表示仅打印日志"
cat /proc/sys/kernel/softlockup_panic 2>/dev/null || echo "未配置"

# ================================================================
# PART 5: 中断统计
# ================================================================
section "5. 中断统计"

echo "=== [5.1] 硬中断诊断 ==="
cp /proc/interrupts "$OUTPUT_DIR/interrupts.txt"
echo "完整硬中断统计已保存到: $OUTPUT_DIR/interrupts.txt"
echo ""
echo "--- Top 10 中断源（按计数排序）---"
awk 'NR>1 {
    name=$1; sub(/:$/,"",name)
    total=0
    for(i=2;i<=NF-1;i++) total+=$i
    if(total>0) print total, name, $NF
}' /proc/interrupts 2>/dev/null | sort -rn | head -10 | \
    awk '{printf "%-15s %-15s %s\n", $1, $2, $3}'

echo ""
echo "--- 中断分布诊断 ---"
INTERRUPTS=$(awk 'NR>1 {
    name=$1; sub(/:$/,"",name)
    total=0
    for(i=2;i<=NF-1;i++) total+=$i
    if(total>0) print name, total, $NF
}' /proc/interrupts 2>/dev/null | sort -k2 -rn | head -5)
if [ -n "$INTERRUPTS" ]; then
    echo "$INTERRUPTS" | while read name total desc; do
        printf "%-15s 计数: %-12s %s\n" "$name" "$total" "$desc"
    done
else
    echo "无显著中断活动"
fi

echo ""
echo "=== [5.2] 软中断诊断 ==="
cp /proc/softirqs "$OUTPUT_DIR/softirqs.txt"
echo "完整软中断统计已保存到: $OUTPUT_DIR/softirqs.txt"
echo ""
echo "--- 软中断汇总（按计数排序）---"
awk 'NR>1 {
    name=$1; sub(/:$/,"",name)
    total=0
    for(i=2;i<=NF;i++) total+=$i
    if(total>0) print total, name
}' /proc/softirqs 2>/dev/null | sort -rn | \
    awk '{printf "%-15s %s\n", $1, $2}'

echo ""
echo "--- 软中断分布诊断 ---"
SOFTIRQ_HIGH=""
NET_RX=$(awk '/NET_RX:/{total=0; for(i=2;i<=NF;i++) total+=$i; print total}' /proc/softirqs 2>/dev/null)
TIMER=$(awk '/TIMER:/{total=0; for(i=2;i<=NF;i++) total+=$i; print total}' /proc/softirqs 2>/dev/null)
RCU=$(awk '/RCU:/{total=0; for(i=2;i<=NF;i++) total+=$i; print total}' /proc/softirqs 2>/dev/null)
[ -n "$NET_RX" ] && [ "$NET_RX" -gt 1000000 ] 2>/dev/null && SOFTIRQ_HIGH="$SOFTIRQ_HIGH NET_RX(${NET_RX})"
[ -n "$TIMER" ] && [ "$TIMER" -gt 1000000 ] 2>/dev/null && SOFTIRQ_HIGH="$SOFTIRQ_HIGH TIMER(${TIMER})"
[ -n "$RCU" ] && [ "$RCU" -gt 1000000 ] 2>/dev/null && SOFTIRQ_HIGH="$SOFTIRQ_HIGH RCU(${RCU})"
if [ -n "$SOFTIRQ_HIGH" ]; then
    echo "⚠️  高计数软中断类型:$SOFTIRQ_HIGH"
else
    echo "✅ 软中断计数正常"
fi

# ================================================================
# PART 6: 进程详情（D/Z/R 状态 + 目标进程）
# ================================================================
section "6. 进程详情"

echo "=== [6.1] D 状态进程（不可中断睡眠）==="
D_PIDS=$(ps -eo pid,stat | awk '$2 ~ /^D/ {print $1}')
if [ -z "$D_PIDS" ]; then
    echo "✅ 当前无 D 状态进程"
else
    echo "⚠️  发现 D 状态进程，详情如下："
    for pid in $D_PIDS; do
        [ ! -d "/proc/$pid" ] && continue
        COMM=$(cat /proc/$pid/comm 2>/dev/null)
        CMDLINE=$(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ')
        echo ""
        echo "--- PID: $pid  COMM: $COMM ---"
        echo "命令行: $CMDLINE"
        echo "内核堆栈:"
        cat /proc/$pid/stack 2>/dev/null || echo "  无法读取堆栈"
    done
fi

echo ""
echo "=== [6.2] Z 状态进程（僵尸进程）==="
Z_PIDS=$(ps -eo pid,stat | awk '$2 ~ /^Z/ {print $1}')
if [ -z "$Z_PIDS" ]; then
    echo "✅ 当前无 Z 状态进程"
else
    echo "⚠️  发现 Z 状态进程，详情如下："
    ps -eo pid,ppid,stat,cmd | awk '$3 ~ /^Z/ {print}'
    echo ""
    echo "--- 按父进程统计 ---"
    ps -eo pid,ppid,stat | awk '$3 ~ /^Z/ {count[$2]++} END {for (p in count) print "PPID " p ": " count[p] " zombies"}' | sort -t: -k2 -rn
fi

echo ""
echo "=== [6.3] R 状态进程（运行中）==="
R_PIDS=$(ps -eo pid,stat | awk '$2 ~ /^R/ {print $1}')
if [ -z "$R_PIDS" ]; then
    echo "✅ 当前无 R 状态进程"
else
    echo "R 状态进程列表："
    ps -eo pid,ppid,stat,%cpu,cmd | awk '$3 ~ /^R/ {print}'
fi

echo ""
echo "=== [6.4] 高 CPU 进程详情 ==="
cmd_info "ps aux --sort=-%cpu | head -11" \
    "列出 CPU 使用率最高的进程" \
    "用于快速定位 CPU 消耗大户"
ps aux --sort=-%cpu | head -11

# ================================================================
# PART 7: RT 进程
# ================================================================
section "7. RT 进程（实时调度）"

cmd_info "ps -eo pid,rtprio,stat,%cpu,cmd | grep -v '-'" \
    "列出所有 RT 调度进程" \
    "RTPRIO 列不为 '-' 的进程为 RT 进程；RR=FIFO 轮转 FIFO=先进先出"
ps -eo pid,rtprio,stat,%cpu,cmd | grep -v "RTPRIO" | awk '$2 != "-" {print}' || echo "无 RT 进程"

RT_PIDS=$(ps -eo pid,rtprio | grep -v "RTPRIO" | awk '$2 != "-" {print $1}')
if [ -n "$RT_PIDS" ]; then
    echo ""
    echo "--- RT 进程诊断 ---"
    RT_COUNT=0
    RT_HIGH_CPU=""
    for pid in $RT_PIDS; do
        [ ! -d "/proc/$pid" ] && continue
        RT_COUNT=$((RT_COUNT+1))
        COMM=$(cat /proc/$pid/comm 2>/dev/null)
        CPU=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ')
        RTPRIO=$(ps -p "$pid" -o rtprio= 2>/dev/null | tr -d ' ')
        if [ -n "$CPU" ] && [ "$(echo "$CPU > 80" | bc 2>/dev/null)" = "1" ]; then
            RT_HIGH_CPU="$RT_HIGH_CPU PID:$pid($COMM) CPU:${CPU}%"
        fi
        {
            echo "=== PID: $pid ==="
            echo "COMM: $COMM"
            echo "CMDLINE: $(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ')"
            if command -v chrt &> /dev/null; then
                chrt -p "$pid" 2>/dev/null
            fi
            echo ""
        } >> "$OUTPUT_DIR/rt_processes_detail.txt"
    done
    printf "RT 进程数量: %d\n" "$RT_COUNT"
    if [ -n "$RT_HIGH_CPU" ]; then
        echo "⚠️  高 CPU RT 进程:$RT_HIGH_CPU"
    else
        echo "✅ 无高 CPU 占用的 RT 进程"
    fi
    echo "详细信息已保存到: $OUTPUT_DIR/rt_processes_detail.txt"
fi

# ================================================================
# PART 8: cgroup CPU 统计
# ================================================================
section "8. cgroup CPU 统计"

echo "=== [8.1] cgroup v1 CPU 统计 ==="
if [ -d "/sys/fs/cgroup/cpu,cpuacct" ]; then
    find /sys/fs/cgroup/cpu,cpuacct -name "cpu.stat" 2>/dev/null | while read stat_file; do
        dir=$(dirname "$stat_file")
        throttled=$(grep "throttled_time" "$stat_file" 2>/dev/null | awk '{print $2}')
        if [ -n "$throttled" ] && [ "$throttled" -gt 0 ]; then
            name=${dir#/sys/fs/cgroup/cpu,cpuacct}
            echo ""
            echo "⚠️  cgroup: ${name:-/}"
            echo "throttled_time: $throttled"
            cat "$stat_file"
        fi
    done
    echo ""
    echo "完整 cgroup CPU 统计已保存到: $OUTPUT_DIR/cgroup_cpu_v1.txt"
    find /sys/fs/cgroup/cpu,cpuacct -name "cpu.stat" 2>/dev/null | while read stat_file; do
        echo "=== $stat_file ===" >> "$OUTPUT_DIR/cgroup_cpu_v1.txt"
        cat "$stat_file" >> "$OUTPUT_DIR/cgroup_cpu_v1.txt"
        echo "" >> "$OUTPUT_DIR/cgroup_cpu_v1.txt"
    done
else
    echo "cgroup v1 cpu 控制器未找到"
fi

echo ""
echo "=== [8.2] cgroup v2 CPU 统计 ==="
if [ -f "/sys/fs/cgroup/cgroup.controllers" ]; then
    find /sys/fs/cgroup -name "cpu.stat" 2>/dev/null | while read stat_file; do
        dir=$(dirname "$stat_file")
        throttled=$(grep "throttled_usec" "$stat_file" 2>/dev/null | awk '{print $2}')
        if [ -n "$throttled" ] && [ "$throttled" -gt 0 ]; then
            name=${dir#/sys/fs/cgroup}
            echo ""
            echo "⚠️  cgroup: ${name:-/}"
            echo "throttled_usec: $throttled"
            cat "$stat_file"
        fi
    done
    echo ""
    echo "完整 cgroup v2 CPU 统计已保存到: $OUTPUT_DIR/cgroup_cpu_v2.txt"
    find /sys/fs/cgroup -name "cpu.stat" 2>/dev/null | while read stat_file; do
        echo "=== $stat_file ===" >> "$OUTPUT_DIR/cgroup_cpu_v2.txt"
        cat "$stat_file" >> "$OUTPUT_DIR/cgroup_cpu_v2.txt"
        echo "" >> "$OUTPUT_DIR/cgroup_cpu_v2.txt"
    done
else
    echo "cgroup v2 未启用"
fi

# ================================================================
# PART 9: 内核日志分析
# ================================================================
section "9. 内核日志分析（时间段: ${START_TIME:-全量} ~ ${END_TIME:-全量}）"

if [ -n "$START_TIME" ] && [ -n "$END_TIME" ]; then
    echo "=== [9.1] 时间段内 CPU 相关日志 ==="

    if [ -n "$HAS_JOURNAL" ]; then
        cmd_info "journalctl --since='$START_TIME' --until='$END_TIME' -k | grep CPU关键字" \
            "从 systemd journal 提取故障时间段内 CPU 调度相关日志" \
            "包含 blocked/hung/lockup/stall 等事件"
        journalctl --since="$START_TIME" --until="$END_TIME" \
            -k --no-pager 2>/dev/null | grep -E "$CPU_PATTERN" | head -300
    fi

    for LOG_FILE in $LOG_FILES; do
        cmd_info "awk 时间段过滤 $LOG_FILE" \
            "从传统 syslog 文件中按时间段提取 CPU 相关日志" \
            "适用于未使用 systemd 的系统"
        awk -v s="$START_TIME" -v e="$END_TIME" -v pat="$CPU_PATTERN" '
        {
            if (match($0,/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}/)) {
                ts=substr($0,RSTART,19); gsub("T"," ",ts)
                if(ts>=s && ts<=e && $0~pat) print
            }
        }' "$LOG_FILE" 2>/dev/null | head -300
    done
fi

echo ""
echo "=== [9.2] 全量 CPU 相关日志（最近 100 条）==="
cmd_info "journalctl -k | grep CPU关键字 | tail -100" \
    "不限时间范围，获取历史上所有 CPU 调度相关事件" \
    "用于发现历史问题和模式"
[ -n "$HAS_JOURNAL" ] && journalctl -k --no-pager 2>/dev/null | grep -E "$CPU_PATTERN" | tail -100

echo ""
cmd_info "dmesg -T | grep CPU关键字" \
    "从内核环形缓冲区读取 CPU 相关日志" \
    "注意：ring buffer 有大小限制，早期日志可能被覆盖"
dmesg -T 2>/dev/null | grep -E "$CPU_PATTERN" | tail -100
dmesg -T 2>/dev/null > "$OUTPUT_DIR/dmesg_full.txt"

echo ""
echo "=== [9.3] hung_task / blocked 进程详情 ==="
cmd_info "dmesg -T + 行号定位，提取 blocked 事件上下文" \
    "提取 'blocked for more than X seconds' 日志及其上下文" \
    "包含阻塞进程的 PID、命令行、堆栈信息"
dmesg -T 2>/dev/null | grep -n "blocked for more than" | head -10 | while IFS=: read lineno rest; do
    echo ""
    echo ">>> blocked 事件（dmesg 行 $lineno）<<<"
    dmesg -T 2>/dev/null | sed -n "$((lineno>5?lineno-5:1)),$((lineno+30))p"
done

echo ""
echo "=== [9.4] soft lockup 详情 ==="
cmd_info "dmesg -T | grep 'soft lockup'" \
    "提取软锁死事件" \
    "软锁死表示某个 CPU 长时间未调度，可能由死循环或关抢占导致"
dmesg -T 2>/dev/null | grep -i "soft lockup" | tail -20

[ -n "$TARGET_SVC" ] && [ -n "$HAS_JOURNAL" ] && {
    echo ""
    echo "=== [9.5] 服务 [$TARGET_SVC] 专项日志 ==="
    cmd_info "journalctl -u $TARGET_SVC --since/--until" \
        "提取指定 systemd 服务在故障时间段内的全部日志" \
        "可看到服务的启动/停止/错误事件"
    if [ -n "$START_TIME" ]; then
        journalctl -u "$TARGET_SVC" --since="$START_TIME" --until="$END_TIME" --no-pager 2>/dev/null | head -500
    else
        journalctl -u "$TARGET_SVC" --no-pager 2>/dev/null | tail -300
    fi
}

# ================================================================
# PART 10: 目标进程详细信息
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
    section "10. 目标进程详细信息（$PROC_DESC）"
    for PID in $RESOLVED_PIDS; do
        [ ! -d "/proc/$PID" ] && echo "PID $PID 已退出，跳过" && continue
        COMM=$(cat /proc/$PID/comm 2>/dev/null)
        echo ""; echo "══════ PID: $PID  COMM: $COMM ══════"

        cmd_info "cat /proc/$PID/status" \
            "读取进程状态信息" \
            "包含 State/Voluntary/Nonvoluntary 上下文切换次数"
        grep -E "^(Name|State|Pid|PPid|Threads|voluntary|nonvoluntary)" /proc/$PID/status 2>/dev/null

        echo ""
        cmd_info "cat /proc/$PID/sched" \
            "读取进程调度器统计" \
            "包含 nr_voluntary_switches/nr_involuntary_switches/se.sum_exec_runtime"
        head -30 /proc/$PID/sched 2>/dev/null

        echo ""
        cmd_info "cat /proc/$PID/stack" \
            "读取进程内核堆栈" \
            "显示进程当前在内核中的调用链，用于分析阻塞原因"
        cat /proc/$PID/stack 2>/dev/null || echo "无法读取堆栈"

        echo ""
        cmd_info "ls -la /proc/$PID/fd | wc -l" \
            "统计进程打开的文件描述符数量" \
            "fd 数量过多可能导致资源泄漏"
        FD_CNT=$(ls /proc/$PID/fd 2>/dev/null | wc -l)
        printf "fd 数量: %-6d  %s\n" "$FD_CNT" \
            "$([ "$FD_CNT" -gt 1000 ] && echo '⚠️ 偏多，疑似 fd 泄漏' || echo '✅ 正常')"

        if command -v chrt &> /dev/null; then
            echo ""
            cmd_info "chrt -p $PID" \
                "读取进程调度策略和优先级" \
                "显示调度策略（OTHER/RR/FIFO）和优先级"
            chrt -p "$PID" 2>/dev/null
        fi
    done

elif [ "$PROC_OPT_COUNT" -gt 0 ]; then
    section "10. 目标进程历史记录（进程已退出，从日志搜索）"
    SEARCH_TERM="${TARGET_PID:-${TARGET_NAME:-$TARGET_SVC}}"
    cmd_info "grep -i '$SEARCH_TERM' dmesg + journalctl" \
        "在所有日志来源中搜索目标进程的历史记录" \
        "重点关注 blocked/lockup/kill 相关行"
    dmesg -T 2>/dev/null | grep -i "$SEARCH_TERM" | tail -30
    [ -n "$HAS_JOURNAL" ] && [ -n "$START_TIME" ] && \
        journalctl --since="$START_TIME" --until="$END_TIME" --no-pager 2>/dev/null \
            | grep -i "$SEARCH_TERM" | head -100
fi

# ================================================================
# PART 11: 历史监控数据
# ================================================================
section "11. 历史监控数据（atop / sar）"

if [ -n "$START_TIME" ]; then
    DATE_STR=$(date -d "$START_TIME" +%Y%m%d 2>/dev/null)
    START_HM=$(date -d "$START_TIME" '+%H:%M' 2>/dev/null)
    END_HM=$(date -d "$END_TIME"   '+%H:%M' 2>/dev/null)

    cmd_info "atop -r /var/log/atop/atop_$DATE_STR -b $START_HM -e $END_HM -PCPU" \
        "从 atop 历史记录文件中回放故障时间段内的 CPU 使用情况" \
        "按采集间隔展示系统 CPU 使用率/进程 CPU 变化"
    ATOP_FILE="/var/log/atop/atop_$DATE_STR"
    if [ -f "$ATOP_FILE" ]; then
        atop -r "$ATOP_FILE" -b "$START_HM" -e "$END_HM" -PCPU 2>/dev/null | head -200
    else
        echo "atop 历史文件 $ATOP_FILE 不存在"
    fi

    echo ""
    cmd_info "sar -u -f /var/log/sa/saDD -s HH:MM:SS -e HH:MM:SS" \
        "从 sysstat sar 历史文件中读取故障时间段的 CPU 统计" \
        "%user/%system/%iowait/%idle 变化趋势"
    SAR_FILE="/var/log/sa/sa$(date -d "$START_TIME" +%d 2>/dev/null)"
    sar -u -f "$SAR_FILE" \
        -s "$(date -d "$START_TIME" '+%H:%M:%S' 2>/dev/null)" \
        -e "$(date -d "$END_TIME"   '+%H:%M:%S' 2>/dev/null)" 2>/dev/null \
        | head -80 || echo "sar 历史数据不可用"
fi

# ================================================================
# 打包 & 完成
# ================================================================
section "收集完成"
echo ""
echo "✅ 全量信息收集完成！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📁 输出目录 : $OUTPUT_DIR"
echo ""
echo "终端输出摘要："
echo "  - 系统基础信息、负载、CPU 使用率"
echo "  - 进程状态统计（D/Z/R 状态）"
echo "  - 中断统计、RT 进程、cgroup CPU"
echo "  - 关键配置参数"
echo ""
echo "文件输出详情："
echo "  - $OUTPUT_DIR/dmesg_full.txt     (完整内核日志)"
echo "  - $OUTPUT_DIR/interrupts.txt     (硬中断统计)"
echo "  - $OUTPUT_DIR/softirqs.txt       (软中断统计)"
echo "  - $OUTPUT_DIR/cgroup_cpu_*.txt   (cgroup CPU 详情)"
echo "  - $OUTPUT_DIR/collect.log        (本次收集完整日志)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
