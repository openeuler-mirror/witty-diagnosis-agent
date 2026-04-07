#!/bin/bash
# ============================================================
# 文件系统在线故障全量信息收集脚本
#
# 用法:
#   bash collect_filesystem_info.sh -S <开始时间> [-E <结束时间>] [-m <挂载点>] [-p <进程PID>]
#
# 时间参数:
#   -S <时间>   故障时间段开始时间（建议填写），格式: "YYYY-MM-DD HH:MM:SS"
#   -E <时间>   故障时间段结束时间（可选），未填则默认 -S 后 +1 小时
#
# 过滤参数（可选）:
#   -m <挂载点> 指定挂载点路径（如 /data、/home）
#   -p <PID>    指定进程 ID（用于分析进程 IO 行为）
#
# 输出模式（自动回退）:
#   - 优先尝试 /tmp 目录
#   - 若 /tmp 不可写，扫描所有挂载点找可写磁盘
#   - 若所有磁盘均不可写（空间不足/只读/inode耗尽），则仅输出到标准输出
#
# 使用示例:
#   bash collect_filesystem_info.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00"
#   bash collect_filesystem_info.sh -S "2024-01-15 14:00:00" -m /data
#   bash collect_filesystem_info.sh -S "2024-01-15 14:00:00" -p 12345
# ============================================================

START_TIME=""; END_TIME=""; TARGET_MOUNT=""; TARGET_PID=""

while getopts ":S:E:m:p:h" opt; do
    case $opt in
        S) START_TIME="$OPTARG" ;; 
        E) END_TIME="$OPTARG" ;;
        m) TARGET_MOUNT="$OPTARG" ;; 
        p) TARGET_PID="$OPTARG" ;;
        h) sed -n '3,21p' "$0" | sed 's/^# \{0,2\}//'; exit 0 ;;
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

OUTPUT_DIR=""

try_write_dir() {
    local dir="$1"
    local base_dir
    base_dir=$(dirname "$dir")
    
    if [ -d "$base_dir" ] && [ -w "$base_dir" ]; then
        if mkdir -p "$dir" 2>/dev/null; then
            if touch "$dir/.write_test" 2>/dev/null && rm -f "$dir/.write_test" 2>/dev/null; then
                OUTPUT_DIR="$dir"
                return 0
            else
                rmdir "$dir" 2>/dev/null
            fi
        fi
    fi
    return 1
}

try_write_dir "/tmp/fs_diag_$(date +%Y%m%d_%H%M%S)"

if [ -z "$OUTPUT_DIR" ]; then
    for mount_point in $(df -t ext2,ext3,ext4,xfs,btrfs,tmpfs --output=target 2>/dev/null | tail -n +2 | sort -u); do
        [ "$mount_point" = "/" ] && continue
        [ "$mount_point" = "/boot" ] && continue
        [ "$mount_point" = "/boot/efi" ] && continue
        [ "$mount_point" = "/tmp" ] && continue
        
        usage=$(df "$mount_point" 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5+0}')
        [ -z "$usage" ] && continue
        [ "$usage" -ge 98 ] && continue
        
        test_dir="$mount_point/.fs_diag_$(date +%Y%m%d_%H%M%S)"
        if try_write_dir "$test_dir"; then
            break
        fi
    done
fi

if [ -n "$OUTPUT_DIR" ]; then
    LOG_FILE_MODE="file"
    fs_type=$(df -T "$OUTPUT_DIR" 2>/dev/null | awk 'NR==2 {print $2}')
    mount_point=$(df "$OUTPUT_DIR" 2>/dev/null | awk 'NR==2 {print $NF}')
    echo "ℹ️  日志输出目录: $OUTPUT_DIR (${fs_type:-未知}, 挂载点: ${mount_point:-未知})"
    exec > >(tee "$OUTPUT_DIR/collect.log" 2>/dev/null || cat) 2>&1
else
    LOG_FILE_MODE="stdout_only"
    echo "⚠️  所有磁盘均不可写（空间不足/只读/inode耗尽），仅输出到标准输出"
fi

if [ -n "$TARGET_MOUNT" ]; then
    FILTER_DESC="指定挂载点: $TARGET_MOUNT"
elif [ -n "$TARGET_PID" ]; then
    FILTER_DESC="指定PID: $TARGET_PID"
else
    FILTER_DESC="未指定（系统级全量分析）"
fi

HAS_JOURNAL=$(which journalctl 2>/dev/null)
LOG_FILES=""
for f in /var/log/messages /var/log/kern.log /var/log/syslog; do
    [ -f "$f" ] && LOG_FILES="$LOG_FILES $f"
done
FS_PATTERN="ENOSPC|No space left on device|inode.*full|disk.*full|I/O error|Buffer I/O error|EXT4-fs|XFS|BTRFS|read-only|remounting|IO.*wait|D state|uninterruptible|critical|permission denied|cannot stat|cannot open|segmentation fault|core dumped|ld.so|cannot execute|shared object|cannot open shared object file|lib.*so"

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
echo "  文件系统在线故障全量信息收集"
echo "  执行时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  故障时段: ${START_TIME:-未指定} ~ ${END_TIME:-未指定}"
echo "  过滤范围: $FILTER_DESC"
echo "  输出目录: $OUTPUT_DIR"
echo "================================================================"

# ================================================================
# PART 1: 磁盘空间使用情况
# ================================================================
section "1. 磁盘空间使用情况"

cmd_info "df -hT" \
    "查看所有文件系统空间使用情况" \
    "识别空间使用率超过阈值的分区"
df -hT 2>/dev/null

echo ""
echo "--- 空间使用诊断 ---"
df -h 2>/dev/null | awk 'NR>1 {
    usage=$5; gsub("%","",usage); usage=usage+0;
    mount=$NF;
    if (usage >= 95) {
        print "⚠️  CRITICAL: " $1 " 挂载点 " mount " 使用率 " usage "%，空间即将耗尽！"
    } else if (usage >= 85) {
        print "⚠️  WARNING: " $1 " 挂载点 " mount " 使用率 " usage "%，需关注"
    } else if (usage >= 70) {
        print "ℹ️  INFO: " $1 " 挂载点 " mount " 使用率 " usage "%"
    }
}'

echo ""
echo "--- 各分区大文件/目录分析（Top 10）---"
for mount in $(df -h 2>/dev/null | awk 'NR>1 && $5 ~ /[0-9]+/ {gsub("%","",$5); if($5+0>70) print $NF}'); do
    echo ""
    echo "挂载点: $mount"
    du -h --max-depth=2 "$mount" 2>/dev/null | sort -rh | head -10 || echo "无法访问"
done

# ================================================================
# PART 2: inode 使用情况
# ================================================================
section "2. inode 使用情况"

cmd_info "df -i" \
    "查看所有文件系统 inode 使用情况" \
    "识别 inode 使用率超过阈值的分区"
df -i 2>/dev/null

echo ""
echo "--- inode 使用诊断 ---"
df -i 2>/dev/null | awk 'NR>1 {
    usage=$5; gsub("%","",usage); usage=usage+0;
    mount=$NF;
    if (usage >= 95) {
        print "⚠️  CRITICAL: " $1 " 挂载点 " mount " inode 使用率 " usage "%，无法创建新文件！"
    } else if (usage >= 85) {
        print "⚠️  WARNING: " $1 " 挂载点 " mount " inode 使用率 " usage "%，需关注"
    } else if (usage >= 70) {
        print "ℹ️  INFO: " $1 " 挂载点 " mount " inode 使用率 " usage "%"
    }
}'

echo ""
echo "--- inode 耗尽分区的小文件分布分析 ---"
for mount in $(df -i 2>/dev/null | awk 'NR>1 && $5 ~ /[0-9]+/ {gsub("%","",$5); if($5+0>70) print $NF}'); do
    echo ""
    echo "挂载点: $mount"
    echo "目录文件数量统计（Top 10）："
    find "$mount" -maxdepth 3 -type d 2>/dev/null | while read dir; do
        count=$(find "$dir" -maxdepth 1 -type f 2>/dev/null | wc -l)
        [ "$count" -gt 100 ] && echo "$count $dir"
    done | sort -rn | head -10
done

# ================================================================
# PART 3: 磁盘 IO 性能分析
# ================================================================
section "3. 磁盘 IO 性能分析"

echo "=== [3.1] 磁盘统计信息 ==="
cmd_info "iostat -x 1 3" \
    "获取磁盘 IO 统计信息" \
    "关注 %util（利用率）、await（平均等待时间）、svctm（服务时间）"
if command -v iostat &>/dev/null; then
    iostat -x 1 3 2>/dev/null
else
    echo "⚠️  iostat 不可用，尝试读取 /proc/diskstats"
    cat /proc/diskstats 2>/dev/null | head -20
fi

echo ""
echo "--- IO 性能诊断 ---"
if command -v iostat &>/dev/null; then
    iostat -x 2>/dev/null | awk 'NR>3 && $1 ~ /^(sd|vd|nvme|hd|dm)[a-z]*[0-9]*$/ {
        util=$NF; gsub("%","",util); util=util+0;
        if (util >= 90) {
            print "⚠️  CRITICAL: 磁盘 " $1 " 利用率 " util "%，IO 瓶颈！"
        } else if (util >= 70) {
            print "⚠️  WARNING: 磁盘 " $1 " 利用率 " util "%，IO 压力较高"
        }
    }'
fi

echo ""
echo "=== [3.2] 当前 IO 等待进程 ==="
cmd_info "ps -eo pid,stat,cmd | grep -E '^[[:space:]]*[0-9]+[[:space:]]+D'" \
    "查找处于不可中断睡眠（D 状态）的进程" \
    "D 状态进程通常表示正在等待 IO"
ps -eo pid,stat,cmd 2>/dev/null | grep -E '^[[:space:]]*[0-9]+[[:space:]]+D' || echo "无 D 状态进程"

echo ""
echo "--- D 状态进程详情 ---"
for pid in $(ps -eo pid,stat 2>/dev/null | awk '$2 ~ /^D/ {print $1}'); do
    echo ""
    echo "PID: $pid"
    [ -f "/proc/$pid/cmdline" ] && echo "命令: $(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ')"
    [ -f "/proc/$pid/stack" ] && echo "内核栈:" && cat /proc/$pid/stack 2>/dev/null
    [ -f "/proc/$pid/wchan" ] && echo "等待通道: $(cat /proc/$pid/wchan 2>/dev/null)"
done

echo ""
echo "=== [3.3] 磁盘队列深度 ==="
if [ -d "/sys/block" ]; then
    for disk in /sys/block/sd* /sys/block/vd* /sys/block/nvme*; do
        [ -d "$disk" ] || continue
        disk_name=$(basename "$disk")
        queue_depth=$(cat "$disk/queue/nr_requests" 2>/dev/null)
        scheduler=$(cat "$disk/queue/scheduler" 2>/dev/null)
        echo "磁盘: $disk_name | 队列深度: $queue_depth | 调度器: $scheduler"
    done
else
    echo "/sys/block 目录不存在"
fi

echo ""
echo "=== [3.4] IO 调度器配置 ==="
for disk in /sys/block/sd* /sys/block/vd* /sys/block/nvme*; do
    [ -d "$disk" ] || continue
    disk_name=$(basename "$disk")
    echo "磁盘: $disk_name"
    cat "$disk/queue/scheduler" 2>/dev/null
done

# ================================================================
# PART 4: 关键文件完整性检查
# ================================================================
section "4. 关键文件完整性检查"

echo "=== [4.1] 系统关键配置文件 ==="
CRITICAL_FILES=(
    "/etc/passwd"
    "/etc/shadow"
    "/etc/group"
    "/etc/gshadow"
    "/etc/fstab"
    "/etc/hosts"
    "/etc/resolv.conf"
    "/etc/sysctl.conf"
    "/etc/security/limits.conf"
    "/etc/systemd/system.conf"
)

echo "文件权限和状态检查："
for file in "${CRITICAL_FILES[@]}"; do
    if [ -f "$file" ]; then
        perms=$(stat -c "%a" "$file" 2>/dev/null)
        owner=$(stat -c "%U:%G" "$file" 2>/dev/null)
        size=$(stat -c "%s" "$file" 2>/dev/null)
        echo "$file | 权限: $perms | 所有者: $owner | 大小: $size bytes"
        
        case "$file" in
            /etc/passwd)
                [ "$perms" != "644" ] && echo "  ⚠️  权限异常，应为 644"
                ;;
            /etc/shadow)
                if [ "$perms" != "000" ] && [ "$perms" != "0" ] && [ "$perms" != "640" ]; then
                    echo "  ⚠️  权限异常，应为 000 或 640"
                fi
                ;;
        esac
    else
        echo "⚠️  $file 不存在"
    fi
done

echo ""
echo "=== [4.2] 核心动态库检查 ==="
echo "动态链接库缓存："
ldconfig -p 2>/dev/null | head -20

echo ""
echo "--- 核心库文件检查 ---"
CORE_LIB_NAMES=(
    "libc.so.6"
    "libm.so.6"
    "libpthread.so.0"
    "libdl.so.2"
    "librt.so.1"
)

for lib_name in "${CORE_LIB_NAMES[@]}"; do
    lib_path=$(ldconfig -p 2>/dev/null | grep -m1 "$lib_name" | awk '{print $NF}')
    if [ -n "$lib_path" ] && [ -f "$lib_path" ]; then
        perms=$(stat -c "%a" "$lib_path" 2>/dev/null)
        size=$(stat -c "%s" "$lib_path" 2>/dev/null)
        echo "$lib_name -> $lib_path | 权限: $perms | 大小: $size bytes"
        
        if [ "$perms" != "755" ] && [ "$perms" != "555" ]; then
            echo "  ⚠️  权限异常，应为 755 或 555"
        fi
        
        if ! file "$lib_path" 2>/dev/null | grep -q "shared object"; then
            echo "  ⚠️  文件类型异常"
        fi
    else
        echo "⚠️  $lib_name 未在 ldconfig 缓存中找到"
    fi
done

echo ""
echo "--- 动态链接器检查 ---"
LD_SO=""
for path in /lib64/ld-linux*.so* /lib/ld-linux*.so* /lib/aarch64-linux-gnu/ld-linux*.so* /lib64/ld-linux-aarch64*.so*; do
    if [ -f "$path" ]; then
        LD_SO="$path"
        break
    fi
done
if [ -z "$LD_SO" ]; then
    LD_SO=$(find /lib /lib64 -name "ld-linux*.so*" -type f 2>/dev/null | head -1)
fi
if [ -n "$LD_SO" ] && [ -f "$LD_SO" ]; then
    perms=$(stat -c "%a" "$LD_SO" 2>/dev/null)
    size=$(stat -c "%s" "$LD_SO" 2>/dev/null)
    echo "动态链接器: $LD_SO | 权限: $perms | 大小: $size bytes"
    
    if [ "$perms" != "755" ] && [ "$perms" != "555" ]; then
        echo "  ⚠️  权限异常，应为 755 或 555"
    fi
else
    echo "⚠️  未找到动态链接器"
fi

echo ""
echo "=== [4.3] 二进制文件执行测试 ==="
TEST_BINS=(
    "/bin/ls"
    "/bin/cat"
    "/bin/echo"
    "/usr/bin/id"
)

for bin in "${TEST_BINS[@]}"; do
    if [ -x "$bin" ]; then
        echo -n "测试 $bin: "
        if "$bin" --version &>/dev/null || "$bin" &>/dev/null; then
            echo "✅ 正常"
        else
            echo "⚠️  执行异常"
        fi
    else
        echo "⚠️  $bin 不可执行或不存在"
    fi
done

echo ""
echo "=== [4.4] 文件系统挂载选项 ==="
cmd_info "mount | grep -E 'ext|xfs|btrfs|nfs'" \
    "查看文件系统挂载选项" \
    "检查是否有 ro（只读）异常挂载"
mount 2>/dev/null | grep -E 'ext|xfs|btrfs|nfs'

echo ""
echo "--- 只读挂载检测 ---"
mount 2>/dev/null | grep " ro," | while read line; do
    echo "⚠️  检测到只读挂载: $line"
done

# ================================================================
# PART 5: 文件系统错误日志
# ================================================================
section "5. 文件系统错误日志"

echo "=== [5.1] 磁盘空间相关错误 ==="
dmesg -T 2>/dev/null | grep -iE "No space left on device|ENOSPC|disk.*full|inode.*full" | tail -30

echo ""
echo "=== [5.2] IO 错误日志 ==="
dmesg -T 2>/dev/null | grep -iE "I/O error|Buffer I/O error|read error|write error|timeout" | tail -30

echo ""
echo "=== [5.3] 文件系统错误 ==="
dmesg -T 2>/dev/null | grep -iE "EXT4-fs error|XFS error|BTRFS error|filesystem.*error|corrupt|remounting.*ro" | tail -30

echo ""
echo "=== [5.4] 关键文件损坏日志 ==="
dmesg -T 2>/dev/null | grep -iE "segmentation fault|core dumped|cannot execute|cannot open shared object|lib.*error" | tail -30

# ================================================================
# PART 6: 时间段日志分析
# ================================================================
if [ -n "$START_TIME" ] && [ -n "$END_TIME" ]; then
    section "6. 时间段日志分析（${START_TIME} ~ ${END_TIME}）"

    echo "=== [6.1] journalctl 时间段日志 ==="
    if [ -n "$HAS_JOURNAL" ]; then
        journalctl --since="$START_TIME" --until="$END_TIME" \
            -k --no-pager 2>/dev/null | grep -iE "$FS_PATTERN" | head -300
    fi

    echo ""
    echo "=== [6.2] syslog 时间段日志 ==="
    for LOG_FILE in $LOG_FILES; do
        echo "--- $LOG_FILE ---"
        awk -v s="$START_TIME" -v e="$END_TIME" -v pat="$FS_PATTERN" '
        {
            if (match($0,/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}/)) {
                ts=substr($0,RSTART,19); gsub("T"," ",ts)
                if(ts>=s && ts<=e && $0~pat) print
            }
        }' "$LOG_FILE" 2>/dev/null | head -300
    done
fi

# ================================================================
# PART 7: 指定挂载点详细信息
# ================================================================
if [ -n "$TARGET_MOUNT" ]; then
    section "7. 指定挂载点详细信息"

    echo "=== 挂载点: $TARGET_MOUNT ==="
    
    if mountpoint -q "$TARGET_MOUNT" 2>/dev/null; then
        echo "--- 挂载信息 ---"
        mount | grep "$TARGET_MOUNT"
        
        echo ""
        echo "--- 空间使用 ---"
        df -h "$TARGET_MOUNT" 2>/dev/null
        
        echo ""
        echo "--- inode 使用 ---"
        df -i "$TARGET_MOUNT" 2>/dev/null
        
        echo ""
        echo "--- 大文件 Top 20 ---"
        du -h --max-depth=1 "$TARGET_MOUNT" 2>/dev/null | sort -rh | head -20
        
        echo ""
        echo "--- 最近修改的文件 ---"
        find "$TARGET_MOUNT" -type f -mtime -1 2>/dev/null | head -20
        
        echo ""
        echo "--- 打开此挂载点的进程 ---"
        lsof +D "$TARGET_MOUNT" 2>/dev/null | head -30 || echo "lsof 不可用"
    else
        echo "⚠️  $TARGET_MOUNT 不是有效的挂载点"
    fi
fi

# ================================================================
# PART 8: 指定进程 IO 分析
# ================================================================
if [ -n "$TARGET_PID" ]; then
    section "8. 指定进程 IO 分析"

    if [ -d "/proc/$TARGET_PID" ]; then
        echo "=== PID: $TARGET_PID 详情 ==="
        COMM=$(cat /proc/$TARGET_PID/comm 2>/dev/null)
        echo "进程名: $COMM"
        
        echo ""
        echo "--- 进程状态 ---"
        cat /proc/$TARGET_PID/status 2>/dev/null | grep -E "^(Name|State|Pid|PPid|Threads|Uid|Gid)"
        
        echo ""
        echo "--- IO 统计 ---"
        if [ -f "/proc/$TARGET_PID/io" ]; then
            cat /proc/$TARGET_PID/io
        else
            echo "IO 统计不可用"
        fi
        
        echo ""
        echo "--- 打开的文件 ---"
        ls -la /proc/$TARGET_PID/fd 2>/dev/null | head -30
        
        echo ""
        echo "--- 文件描述符数量 ---"
        fd_count=$(ls /proc/$TARGET_PID/fd 2>/dev/null | wc -l)
        echo "打开的 fd 数量: $fd_count"
        [ "$fd_count" -gt 1000 ] && echo "⚠️  fd 数量过多，可能存在泄漏"
        
        echo ""
        echo "--- 进程打开的文件（lsof）---"
        lsof -p "$TARGET_PID" 2>/dev/null | head -30 || echo "lsof 不可用"
    else
        echo "⚠️  PID $TARGET_PID 不存在，可能已退出"
    fi
fi

# ================================================================
# PART 9: 系统整体 IO 状态
# ================================================================
section "9. 系统整体 IO 状态"

echo "=== [9.1] 系统负载 ==="
uptime

echo ""
echo "=== [9.2] 内存与交换空间 ==="
free -h

echo ""
echo "=== [9.3] 进程 IO 排行（Top 10）---"
if command -v iotop &>/dev/null; then
    iotop -b -n 1 -o 2>/dev/null | head -20
else
    echo "iotop 不可用，使用 /proc/[pid]/io 统计"
    for pid in $(ps -eo pid --no-headers | head -100); do
        if [ -f "/proc/$pid/io" ]; then
            read_bytes=$(grep "^read_bytes:" /proc/$pid/io 2>/dev/null | awk '{print $2}')
            write_bytes=$(grep "^write_bytes:" /proc/$pid/io 2>/dev/null | awk '{print $2}')
            comm=$(cat /proc/$pid/comm 2>/dev/null)
            [ -n "$read_bytes" ] && [ "$read_bytes" -gt 0 ] && echo "$read_bytes $write_bytes $pid $comm"
        fi
    done | sort -rn | head -10 | while read rb wb pid comm; do
        printf "PID %-8s 读: %-12s 写: %-12s %s\n" "$pid" "$rb" "$wb" "$comm"
    done
fi

echo ""
echo "=== [9.4] NFS 挂载状态（如有）==="
mount 2>/dev/null | grep nfs

# ================================================================
# 保存完整日志（仅文件模式）
# ================================================================
if [ -n "$OUTPUT_DIR" ] && [ "$LOG_FILE_MODE" = "file" ]; then
    dmesg -T 2>/dev/null > "$OUTPUT_DIR/dmesg_full.txt"
    echo ""
    echo "完整内核日志已保存到: $OUTPUT_DIR/dmesg_full.txt"

    if [ -n "$HAS_JOURNAL" ]; then
        journalctl -k --no-pager 2>/dev/null > "$OUTPUT_DIR/journal_kernel.txt"
        echo "完整 journal 内核日志已保存到: $OUTPUT_DIR/journal_kernel.txt"
    fi
fi

# ================================================================
# 打包 & 完成
# ================================================================
section "收集完成"
echo ""
echo "✅ 全量信息收集完成！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$LOG_FILE_MODE" = "stdout_only" ]; then
    echo "📤 输出模式: 仅标准输出（文件系统不可写回退）"
    echo ""
    echo "提示: 日志已直接输出到终端，可通过 Ansible/SSH 捕获保存"
else
    echo "📁 输出目录 : ${OUTPUT_DIR:-无（仅终端输出）}"
    echo ""
    if [ -n "$OUTPUT_DIR" ] && [ "$LOG_FILE_MODE" = "file" ]; then
        echo "文件输出详情："
        echo "  - $OUTPUT_DIR/dmesg_full.txt       (完整内核日志)"
        echo "  - $OUTPUT_DIR/journal_kernel.txt   (journal 内核日志)"
        echo "  - $OUTPUT_DIR/collect.log          (本次收集完整日志)"
    fi
fi

echo ""
echo "收集内容摘要："
echo "  - 磁盘空间使用情况与诊断"
echo "  - inode 使用情况与诊断"
echo "  - 磁盘 IO 性能分析"
echo "  - 关键文件完整性检查"
echo "  - 文件系统错误日志"
echo "  - 时间段日志分析"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
