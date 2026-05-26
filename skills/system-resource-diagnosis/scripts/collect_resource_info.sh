#!/bin/bash
# ============================================================
# 系统资源故障全量信息收集脚本
#
# 用法:
#   bash collect_resource_info.sh -S <开始时间> [-E <结束时间>] [-u <用户>] [-p <PID>]
#
# 时间参数:
#   -S <时间>   故障时间段开始时间（建议填写），格式: "YYYY-MM-DD HH:MM:SS"
#   -E <时间>   故障时间段结束时间（可选），未填则默认 -S 后 +1 小时
#
# 过滤参数（可选）:
#   -u <用户>   指定用户名
#   -p <PID>    精确进程 ID
#
# 使用示例:
#   bash collect_resource_info.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00"
#   bash collect_resource_info.sh -S "2024-01-15 14:00:00" -u app
#   bash collect_resource_info.sh -S "2024-01-15 14:00:00" -p 12345
# ============================================================

START_TIME=""; END_TIME=""; TARGET_USER=""; TARGET_PID=""

while getopts ":S:E:u:p:h" opt; do
    case $opt in
        S) START_TIME="$OPTARG" ;; E) END_TIME="$OPTARG" ;;
        u) TARGET_USER="$OPTARG" ;; p) TARGET_PID="$OPTARG" ;;
        h) sed -n '3,20p' "$0" | sed 's/^# \{0,2\}//'; exit 0 ;;
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

OUTPUT_DIR="/tmp/resource_diag_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"
exec > >(tee "$OUTPUT_DIR/collect.log") 2>&1

if [ -n "$TARGET_USER" ]; then
    FILTER_DESC="指定用户: $TARGET_USER"
elif [ -n "$TARGET_PID" ]; then
    FILTER_DESC="精确PID: $TARGET_PID"
else
    FILTER_DESC="未指定（系统级全量分析）"
fi

HAS_JOURNAL=$(which journalctl 2>/dev/null)
LOG_FILES=""
for f in /var/log/messages /var/log/kern.log /var/log/syslog; do
    [ -f "$f" ] && LOG_FILES="$LOG_FILES $f"
done
RESOURCE_PATTERN="Resource temporarily unavailable|Cannot allocate memory|Segmentation fault|SIGSEGV|No space left on device|inotify.*failed|inotify.*limit|Could not insert module|Module already exists|modules_disabled|fork.*failed|out of memory|ulimit|max.*process|stack.*overflow|message queue|shared memory|semaphore|ENOSPC|EAGAIN|ENOMEM"

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
echo "  系统资源故障全量信息收集"
echo "  执行时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  故障时段: ${START_TIME:-未指定} ~ ${END_TIME:-未指定}"
echo "  过滤范围: $FILTER_DESC"
echo "  输出目录: $OUTPUT_DIR"
echo "================================================================"

# ================================================================
# PART 1: ulimit 配置
# ================================================================
section "1. ulimit 配置"

cmd_info "ulimit -a" \
    "获取当前用户的所有资源限制" \
    "max user processes (-u) 限制进程数；stack size (-s) 限制栈大小"
ulimit -a 2>/dev/null

echo ""
echo "--- ulimit 诊断 ---"
MAX_PROC=$(ulimit -u 2>/dev/null)
STACK_SIZE=$(ulimit -s 2>/dev/null)
printf "max user processes: %s\n" "$MAX_PROC"
printf "stack size (KB):    %s\n" "$STACK_SIZE"
if [ -n "$MAX_PROC" ] && [ "$MAX_PROC" != "unlimited" ] && [ "$MAX_PROC" -lt 4096 ] 2>/dev/null; then
    echo "⚠️  max user processes 限制较严（$MAX_PROC），可能导致 fork 失败"
else
    echo "✅ max user processes 限制正常"
fi
if [ -n "$STACK_SIZE" ] && [ "$STACK_SIZE" != "unlimited" ] && [ "$STACK_SIZE" -lt 8192 ] 2>/dev/null; then
    echo "⚠️  stack size 限制较小（${STACK_SIZE}KB），可能导致栈溢出"
else
    echo "✅ stack size 限制正常"
fi

echo ""
cmd_info "cat /etc/security/limits.conf" \
    "读取系统级资源限制持久化配置" \
    "检查是否有用户/组级别的限制覆盖"
cat /etc/security/limits.conf 2>/dev/null | grep -v "^#" | grep -v "^$" | head -30

if [ -d "/etc/security/limits.d" ]; then
    echo ""
    echo "--- limits.d 目录配置 ---"
    cat /etc/security/limits.d/*.conf 2>/dev/null | grep -v "^#" | grep -v "^$" | head -20
fi

# ================================================================
# PART 2: 进程数统计
# ================================================================
section "2. 进程数统计"

cmd_info "ps -eo user | sort | uniq -c | sort -rn" \
    "统计各用户的进程数量" \
    "找出进程数最多的用户，与 ulimit -u 对比"
ps -eo user | sort | uniq -c | sort -rn | head -20

echo ""
echo "--- 进程数诊断 ---"
CURRENT_USER=$(whoami)
CURRENT_USER_PROC=$(ps -u "$CURRENT_USER" -o pid 2>/dev/null | wc -l)
MAX_PROC=$(ulimit -u 2>/dev/null)
printf "当前用户: %s\n" "$CURRENT_USER"
printf "当前用户进程数: %d\n" "$CURRENT_USER_PROC"
printf "ulimit -u: %s\n" "$MAX_PROC"

if [ "$MAX_PROC" != "unlimited" ] && [ -n "$MAX_PROC" ] && [ -n "$CURRENT_USER_PROC" ]; then
    USAGE_RATIO=$(echo "scale=2; $CURRENT_USER_PROC * 100 / $MAX_PROC" | bc 2>/dev/null)
    printf "使用率: %.1f%%\n" "$USAGE_RATIO"
    if [ "$(echo "$USAGE_RATIO > 90" | bc 2>/dev/null)" = "1" ]; then
        echo "⚠️  进程数接近 ulimit 上限，可能导致 fork 失败"
    elif [ "$(echo "$USAGE_RATIO > 70" | bc 2>/dev/null)" = "1" ]; then
        echo "⚠️  进程数使用率较高，需关注"
    else
        echo "✅ 进程数使用正常"
    fi
fi

echo ""
cmd_info "ps -eo pid,nlwp,cmd --sort=-nlwp | head -20" \
    "列出线程数最多的进程" \
    "线程数过多可能导致资源耗尽"
ps -eo pid,nlwp,cmd --sort=-nlwp | head -20

# ================================================================
# PART 3: 栈限制与 core dump
# ================================================================
section "3. 栈限制与 core dump"

cmd_info "ulimit -s && cat /proc/sys/kernel/core_pattern" \
    "获取栈限制和 core dump 配置" \
    "栈限制过小可能导致 SIGSEGV；core_pattern 指定 core dump 存储位置"

STACK_LIMIT=$(ulimit -s 2>/dev/null)
CORE_LIMIT=$(ulimit -c 2>/dev/null)
CORE_PATTERN=$(cat /proc/sys/kernel/core_pattern 2>/dev/null)

echo "栈限制 (KB): $STACK_LIMIT"
echo "Core dump 限制: $CORE_LIMIT"
echo "Core pattern: $CORE_PATTERN"

echo ""
echo "--- 栈与 Core 诊断 ---"
# 诊断 1: Core 限制为 0
if [ "$CORE_LIMIT" = "0" ]; then
    echo "⚠️  风险: Core dump 限制为 0。即使程序因段错误崩溃，系统也不会生成调试文件！"
    echo "    >>> 建议执行: ulimit -c unlimited"
else
    echo "✅ Core dump 限制正常 ($CORE_LIMIT)"
fi

# 诊断 2: 栈空间配置过小
if [ -n "$STACK_LIMIT" ] && [ "$STACK_LIMIT" != "unlimited" ] && [ "$STACK_LIMIT" -lt 2048 ] 2>/dev/null; then
    echo "⚠️  警告: 栈限制极低 ($STACK_LIMIT KB)，极易触发深度递归导致的 Segmentation fault。"
else
    echo "✅ 栈限制配置正常"
fi

# 诊断 3: 解析 Core 存储路径
if [[ "$CORE_PATTERN" == "|"* ]]; then
    echo "ℹ️  注意: 系统配置了外部程序接管 Core Dump (如 apport 或 systemd-coredump)。"
    echo "    >>> 文件可能不会出现在当前目录，请检查 /var/crash/ 或 coredumpctl。"
fi

echo ""
echo "--- 进程栈使用情况（Top 10）---"
# 注意：VmStk 是进程当前已经实际分配的栈空间
for pid in $(ps -eo pid --no-headers | head -100); do
    if [ -f "/proc/$pid/status" ]; then
        stk=$(grep "^VmStk:" /proc/$pid/status 2>/dev/null | awk '{print $2}')
        if [ -n "$stk" ] && [ "$stk" -gt 50 ] 2>/dev/null; then
            comm=$(cat /proc/$pid/comm 2>/dev/null)
            echo "$pid $stk $comm"
        fi
    fi
done | sort -k2 -rn | head -10 | while read pid stk comm; do
    printf "PID %-8s 栈使用: %-8s KB  %s\n" "$pid" "$stk" "$comm"
done

echo ""
echo "--- 崩溃现场搜索 (/var/crash) ---"
if [ -d "/var/crash" ]; then
    # 搜索最近 7 天的崩溃日志或 core 文件
    CRASH_FILES=$(find /var/crash -name "*" -mtime -7 2>/dev/null | head -5)
    if [ -n "$CRASH_FILES" ]; then
        echo "$CRASH_FILES"
    else
        echo "无最近 7 天的崩溃记录"
    fi
else
    echo "/var/crash 目录不存在"
fi

# 尝试根据 core_pattern 寻找可能的自定义目录
CORE_DIR=$(echo "$CORE_PATTERN" | grep -oP '(?<=/).*(?=/)' | head -1)
if [ -n "$CORE_DIR" ] && [[ "$CORE_PATTERN" != "|"* ]]; then
    echo ""
    echo "--- 自定义 Core 目录检测 (/$CORE_DIR) ---"
    ls -la "/$CORE_DIR" 2>/dev/null | grep "core" | head -5 || echo "未发现 core 文件"
fi

# ================================================================
# PART 4: IPC 资源使用
# ================================================================
section "4. IPC 资源使用"

echo "=== [4.1] IPC 内核参数 ==="
cmd_info "sysctl msgmni shmmni semmni" \
    "获取 IPC 资源上限参数" \
    "msgmni=消息队列上限; shmmni=共享内存段上限; semmni=信号量数组上限"
echo "msgmni (消息队列上限): $(cat /proc/sys/kernel/msgmni 2>/dev/null)"
echo "shmmni (共享内存段上限): $(cat /proc/sys/kernel/shmmni 2>/dev/null)"
echo "semmni (信号量数组上限): $(cat /proc/sys/kernel/semmni 2>/dev/null)"

echo ""
echo "=== [4.2] 消息队列 ==="
MSG_COUNT=$(ipcs -q 2>/dev/null | wc -l)
MSG_MAX=$(cat /proc/sys/kernel/msgmni 2>/dev/null)
echo "当前消息队列数: $((MSG_COUNT - 3))"
echo "上限 (msgmni): $MSG_MAX"
if [ -n "$MSG_MAX" ] && [ "$MSG_MAX" -gt 0 ]; then
    MSG_USAGE=$(echo "scale=2; ($MSG_COUNT - 3) * 100 / $MSG_MAX" | bc 2>/dev/null)
    printf "使用率: %.1f%%\n" "$MSG_USAGE"
    if [ "$(echo "$MSG_USAGE > 90" | bc 2>/dev/null)" = "1" ]; then
        echo "⚠️  消息队列接近上限"
    else
        echo "✅ 消息队列使用正常"
    fi
fi

echo ""
echo "--- 消息队列详情 ---"
ipcs -q 2>/dev/null | head -20

echo ""
echo "=== [4.3] 共享内存 ==="
SHM_COUNT=$(ipcs -m 2>/dev/null | wc -l)
SHM_MAX=$(cat /proc/sys/kernel/shmmni 2>/dev/null)
echo "当前共享内存段数: $((SHM_COUNT - 3))"
echo "上限 (shmmni): $SHM_MAX"
if [ -n "$SHM_MAX" ] && [ "$SHM_MAX" -gt 0 ]; then
    SHM_USAGE=$(echo "scale=2; ($SHM_COUNT - 3) * 100 / $SHM_MAX" | bc 2>/dev/null)
    printf "使用率: %.1f%%\n" "$SHM_USAGE"
    if [ "$(echo "$SHM_USAGE > 90" | bc 2>/dev/null)" = "1" ]; then
        echo "⚠️  共享内存接近上限"
    else
        echo "✅ 共享内存使用正常"
    fi
fi

echo ""
echo "--- 共享内存详情 ---"
ipcs -m 2>/dev/null | head -20

echo ""
echo "=== [4.4] 信号量 ==="
SEM_COUNT=$(ipcs -s 2>/dev/null | wc -l)
SEM_MAX=$(cat /proc/sys/kernel/semmni 2>/dev/null)
echo "当前信号量数组数: $((SEM_COUNT - 3))"
echo "上限 (semmni): $SEM_MAX"
if [ -n "$SEM_MAX" ] && [ "$SEM_MAX" -gt 0 ]; then
    SEM_USAGE=$(echo "scale=2; ($SEM_COUNT - 3) * 100 / $SEM_MAX" | bc 2>/dev/null)
    printf "使用率: %.1f%%\n" "$SEM_USAGE"
    if [ "$(echo "$SEM_USAGE > 90" | bc 2>/dev/null)" = "1" ]; then
        echo "⚠️  信号量接近上限"
    else
        echo "✅ 信号量使用正常"
    fi
fi

echo ""
echo "--- 信号量详情 ---"
ipcs -s 2>/dev/null | head -20

echo ""
echo "=== [4.5] IPC 资源汇总（按用户）==="
ipcs -u 2>/dev/null || echo "ipcs -u 不可用"

ipcs -l 2>/dev/null > "$OUTPUT_DIR/ipc_limits.txt"
echo "IPC 限制详情已保存到: $OUTPUT_DIR/ipc_limits.txt"

# ================================================================
# PART 5: inotify 使用情况
# ================================================================
section "5. inotify 使用情况"

echo "=== [5.1] inotify 内核参数 ==="
cmd_info "sysctl fs.inotify" \
    "获取 inotify 资源限制" \
    "max_user_instances=实例上限; max_user_watches=监控点上限"
echo "max_user_instances: $(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null)"
echo "max_user_watches: $(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null)"
echo "max_queued_events: $(cat /proc/sys/fs/inotify/max_queued_events 2>/dev/null)"

echo ""
echo "=== [5.2] inotify 使用统计 ==="

# --- 1. 统计实例 (Instances) ---
INOTIFY_INSTANCES=$(find /proc/*/fd -lname "anon_inode:inotify" 2>/dev/null | wc -l)
INOTIFY_MAX_INST=$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null)
echo "当前 inotify 实例数: $INOTIFY_INSTANCES"
echo "上限 (max_user_instances): $INOTIFY_MAX_INST"

# --- 2. 统计监控点 (Watches) [新增核心逻辑] ---
# 原理：从每个进程的 fdinfo 中累计 inotify 条目数
echo "正在扫描系统监控点 (Watches)..."
TOTAL_WATCHES=$(find /proc/*/fdinfo/ -type f 2>/dev/null | xargs grep -s 'inotify' | wc -l)
INOTIFY_MAX_WATCH=$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null)
echo "当前总监控点数 (Watches): $TOTAL_WATCHES"
echo "上限 (max_user_watches): $INOTIFY_MAX_WATCH"

# --- 3. 综合诊断 ---
# 诊断实例使用率
if [ -n "$INOTIFY_MAX_INST" ] && [ "$INOTIFY_MAX_INST" -gt 0 ]; then
    INST_USAGE=$(echo "scale=2; $INOTIFY_INSTANCES * 100 / $INOTIFY_MAX_INST" | bc 2>/dev/null)
    printf "实例使用率: %.1f%%\n" "$INST_USAGE"
    [ "$(echo "$INST_USAGE > 90" | bc 2>/dev/null)" = "1" ] && echo "⚠️  inotify 实例即将耗尽！"
fi

# 诊断监控点使用率
if [ -n "$INOTIFY_MAX_WATCH" ] && [ "$INOTIFY_MAX_WATCH" -gt 0 ]; then
    WATCH_USAGE=$(echo "scale=2; $TOTAL_WATCHES * 100 / $INOTIFY_MAX_WATCH" | bc 2>/dev/null)
    printf "监控点使用率: %.1f%%\n" "$WATCH_USAGE"
    if [ "$(echo "$WATCH_USAGE > 90" | bc 2>/dev/null)" = "1" ]; then
        echo "⚠️  CRITICAL: inotify 监控点 (Watches) 已接近或达到上限！"
        echo "    >>> 这会导致 tail -f 失败、IDE 热重载失效或文件同步中断。"
    elif [ "$INOTIFY_MAX_WATCH" -lt 8192 ]; then
        echo "⚠️  警告: max_user_watches 设置过小 ($INOTIFY_MAX_WATCH)，建议调大至 524288。"
    else
        echo "✅ inotify 监控点使用正常"
    fi
fi

echo ""
echo "--- inotify 使用最多的进程（Top 10）---"
for pid in $(ps -eo pid --no-headers | head -200); do
    if [ -d "/proc/$pid/fd" ]; then
        inotify_cnt=$(ls -la /proc/$pid/fd 2>/dev/null | grep inotify | wc -l)
        if [ "$inotify_cnt" -gt 0 ]; then
            comm=$(cat /proc/$pid/comm 2>/dev/null)
            echo "$inotify_cnt $pid $comm"
        fi
    fi
done | sort -rn | head -10 | while read cnt pid comm; do
    printf "PID %-8s 实例数: %-5s  %s\n" "$pid" "$cnt" "$comm"
done

echo ""
echo "=== [5.3] 受影响服务状态 ==="
echo "--- udev 服务 ---"
systemctl status udev 2>/dev/null | head -5 || echo "udev 服务不可用或 systemd 未启用"

echo ""
echo "--- rsyslog 服务 ---"
systemctl status rsyslog 2>/dev/null | head -5 || echo "rsyslog 服务不可用或 systemd 未启用"

# ================================================================
# PART 6: 内核模块状态
# ================================================================
section "6. 内核模块状态"

echo "=== [6.1] 模块加载配置 ==="
cmd_info "cat /proc/sys/kernel/modules_disabled" \
    "检查模块加载是否被禁用" \
    "0=允许加载模块; 1=禁止加载模块（需重启恢复）"
MODULES_DISABLED=$(cat /proc/sys/kernel/modules_disabled 2>/dev/null)
printf "modules_disabled: %s\n" "$MODULES_DISABLED"
if [ "$MODULES_DISABLED" = "1" ]; then
    echo "⚠️  模块加载已被禁用，无法 insmod/modprobe"
else
    echo "✅ 模块加载未禁用"
fi

echo ""
echo "=== [6.2] 已加载模块统计 ==="
MODULE_COUNT=$(lsmod 2>/dev/null | wc -l)
echo "已加载模块数: $((MODULE_COUNT - 1))"
lsmod 2>/dev/null | head -20

echo ""
echo "=== [6.3] 模块目录信息 ==="
KERNEL_VER=$(uname -r)
echo "内核版本: $KERNEL_VER"
echo "模块目录: /lib/modules/$KERNEL_VER"
ls -la "/lib/modules/$KERNEL_VER" 2>/dev/null | head -10 || echo "模块目录不存在"

echo ""
echo "=== [6.4] 黑名单模块 ==="
if [ -d "/etc/modprobe.d" ]; then
    grep -rh "blacklist" /etc/modprobe.d/*.conf 2>/dev/null | grep -v "^#" | head -20 || echo "无黑名单模块"
else
    echo "/etc/modprobe.d 目录不存在"
fi

lsmod 2>/dev/null > "$OUTPUT_DIR/lsmod_full.txt"
echo "完整模块列表已保存到: $OUTPUT_DIR/lsmod_full.txt"

# ================================================================
# PART 7: 内核日志分析
# ================================================================
section "7. 内核日志分析（时间段: ${START_TIME:-全量} ~ ${END_TIME:-全量}）"

if [ -n "$START_TIME" ] && [ -n "$END_TIME" ]; then
    echo "=== [7.1] 时间段内系统资源相关日志 ==="

    if [ -n "$HAS_JOURNAL" ]; then
        cmd_info "journalctl --since='$START_TIME' --until='$END_TIME' -k | grep 资源关键字" \
            "从 systemd journal 提取故障时间段内资源相关日志" \
            "包含 fork 失败、内存不足、IPC 错误等"
        journalctl --since="$START_TIME" --until="$END_TIME" \
            -k --no-pager 2>/dev/null | grep -iE "$RESOURCE_PATTERN" | head -300
    fi

    for LOG_FILE in $LOG_FILES; do
        cmd_info "awk 时间段过滤 $LOG_FILE" \
            "从传统 syslog 文件中按时间段提取资源相关日志" \
            "适用于未使用 systemd 的系统"
        awk -v s="$START_TIME" -v e="$END_TIME" -v pat="$RESOURCE_PATTERN" '
        {
            if (match($0,/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}/)) {
                ts=substr($0,RSTART,19); gsub("T"," ",ts)
                if(ts>=s && ts<=e && $0~pat) print
            }
        }' "$LOG_FILE" 2>/dev/null | head -300
    done
fi

echo ""
echo "=== [7.2] 全量资源相关日志（最近 100 条）==="
cmd_info "journalctl -k | grep 资源关键字 | tail -100" \
    "不限时间范围，获取历史上所有资源相关事件" \
    "用于发现历史问题和模式"
[ -n "$HAS_JOURNAL" ] && journalctl -k --no-pager 2>/dev/null | grep -iE "$RESOURCE_PATTERN" | tail -100

echo ""
cmd_info "dmesg -T | grep 资源关键字" \
    "从内核环形缓冲区读取资源相关日志" \
    "注意：ring buffer 有大小限制，早期日志可能被覆盖"
dmesg -T 2>/dev/null | grep -iE "$RESOURCE_PATTERN" | tail -100
dmesg -T 2>/dev/null > "$OUTPUT_DIR/dmesg_full.txt"

echo ""
echo "=== [7.3] fork 失败日志 ==="
dmesg -T 2>/dev/null | grep -iE "fork.*failed|Resource temporarily unavailable|EAGAIN" | tail -20

echo ""
echo "=== [7.4] 内存相关错误 ==="
dmesg -T 2>/dev/null | grep -iE "Cannot allocate memory|out of memory|ENOMEM" | tail -20

echo ""
echo "=== [7.5] SIGSEGV/Core Dump 日志 ==="
dmesg -T 2>/dev/null | grep -iE "Segmentation fault|SIGSEGV|coredump" | tail -20

echo ""
echo "=== [7.6] 模块加载失败日志 ==="
dmesg -T 2>/dev/null | grep -iE "Could not insert module|Module already exists|modules_disabled|unknown symbol" | tail -20

echo "完整内核日志已保存到: $OUTPUT_DIR/dmesg_full.txt"

# ================================================================
# PART 8: 目标用户/进程详细信息
# ================================================================
if [ -n "$TARGET_USER" ] || [ -n "$TARGET_PID" ]; then
    section "8. 目标详细信息（$FILTER_DESC）"

    if [ -n "$TARGET_PID" ]; then
        if [ -d "/proc/$TARGET_PID" ]; then
            echo "=== PID: $TARGET_PID 详情 ==="
            COMM=$(cat /proc/$TARGET_PID/comm 2>/dev/null)
            echo "进程名: $COMM"
            echo ""
            echo "--- 进程状态 ---"
            grep -E "^(Name|State|Pid|PPid|Threads|Uid|Gid|voluntary|nonvoluntary|VmStk|VmSize)" /proc/$TARGET_PID/status 2>/dev/null
            echo ""
            echo "--- 进程限制 ---"
            cat /proc/$TARGET_PID/limits 2>/dev/null | head -20
            echo ""
            echo "--- 进程树 ---"
            pstree -p -s "$TARGET_PID" 2>/dev/null || echo "pstree 不可用"
            echo ""
            echo "--- 打开文件数 ---"
            FD_CNT=$(ls /proc/$TARGET_PID/fd 2>/dev/null | wc -l)
            printf "fd 数量: %-6d  %s\n" "$FD_CNT" \
                "$([ "$FD_CNT" -gt 1000 ] && echo '⚠️ 偏多，疑似 fd 泄漏' || echo '✅ 正常')"
        else
            echo "⚠️  PID $TARGET_PID 不存在，可能已退出"
            echo ""
            echo "--- 从日志搜索历史记录 ---"
            dmesg -T 2>/dev/null | grep -i "$TARGET_PID" | tail -30
        fi
    fi

    if [ -n "$TARGET_USER" ]; then
        echo ""
        echo "=== 用户: $TARGET_USER 详情 ==="
        echo "--- 用户进程列表 ---"
        ps -u "$TARGET_USER" -o pid,ppid,stat,%cpu,%mem,cmd --sort=-%cpu 2>/dev/null | head -30
        echo ""
        echo "--- 用户进程数 ---"
        ps -u "$TARGET_USER" -o pid 2>/dev/null | wc -l
        echo ""
        echo "--- 用户资源限制 ---"
        if [ "$TARGET_USER" = "$(whoami)" ]; then
            ulimit -a 2>/dev/null
        else
            echo "需切换到用户 $TARGET_USER 查看 ulimit"
        fi
    fi
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
echo "  - ulimit 配置与诊断"
echo "  - 进程数统计与使用率"
echo "  - 栈限制与 core dump"
echo "  - IPC 资源使用（消息队列/共享内存/信号量）"
echo "  - inotify 使用情况"
echo "  - 内核模块状态"
echo "  - 内核日志分析"
echo ""
echo "文件输出详情："
echo "  - $OUTPUT_DIR/dmesg_full.txt      (完整内核日志)"
echo "  - $OUTPUT_DIR/ipc_limits.txt      (IPC 限制详情)"
echo "  - $OUTPUT_DIR/lsmod_full.txt      (完整模块列表)"
echo "  - $OUTPUT_DIR/collect.log         (本次收集完整日志)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
