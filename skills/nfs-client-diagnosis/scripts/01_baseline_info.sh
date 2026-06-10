#!/bin/bash
# ============================================================
# 脚本：01_baseline_info.sh
# 用途：NFS 客户端故障全量信息收集基线脚本
# 使用：bash 01_baseline_info.sh [-S <开始时间>] [-E <结束时间>] [-m <挂载点>] [-s <NFS服务器>]
#
# 时间参数:
#   -S <时间>   故障时间段开始时间（推荐填写），格式: "YYYY-MM-DD HH:MM:SS"
#   -E <时间>   故障时间段结束时间（可选），未填则默认 -S 后 +1 小时
#
# 过滤参数（可选）:
#   -m <挂载点> 指定 NFS 挂载点路径（如 /mnt/nfs_data）
#   -s <服务器> 指定 NFS 服务器地址（如 192.168.1.100）
#
# 设计原则:
#   本脚本一次性收集所有 NFS 客户端诊断所需的基线数据。
#   所有采集均为只读操作，不修改系统状态。
#   日志输出目录自动回退（优先 /tmp，降级到 stdout）。
# ============================================================

START_TIME=""; END_TIME=""; TARGET_MOUNT=""; TARGET_SERVER=""

while getopts ":S:E:m:s:h" opt; do
    case $opt in
        S) START_TIME="$OPTARG" ;;
        E) END_TIME="$OPTARG" ;;
        m) TARGET_MOUNT="$OPTARG" ;;
        s) TARGET_SERVER="$OPTARG" ;;
        h) sed -n '3,21p' "$0" | sed 's/^# \{0,2\}//'; exit 0 ;;
        :) echo "错误: -$OPTARG 需要参数值"; exit 1 ;;
    esac
done

if [ -z "$START_TIME" ]; then
    echo "⚠️  未指定 -S 开始时间，将进行全量日志扫描（可能包含历史告警噪声）"
fi

if [ -n "$START_TIME" ] && [ -z "$END_TIME" ]; then
    START_TS=$(date -d "$START_TIME" +%s 2>/dev/null)
    [ -z "$START_TS" ] && echo "⚠️  -S 时间格式解析失败，请使用: YYYY-MM-DD HH:MM:SS" && exit 1
    END_TIME=$(date -d "@$((START_TS+3600))" '+%Y-%m-%d %H:%M:%S')
    echo "ℹ️  未指定 -E，自动设为 +1h: $END_TIME"
fi

# ── 输出目录自动回退 ────────────────────────────────────────
OUTPUT_DIR=""
try_write_dir() {
    local dir="$1"
    local base_dir=$(dirname "$dir")
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

try_write_dir "/tmp/nfs_diag_$(date +%Y%m%d_%H%M%S)"

if [ -z "$OUTPUT_DIR" ]; then
    for mount_point in $(df -t ext2,ext3,ext4,xfs,btrfs,tmpfs,nfs,nfs4 --output=target 2>/dev/null | tail -n +2 | sort -u); do
        [ "$mount_point" = "/" ] && continue; [ "$mount_point" = "/boot" ] && continue
        usage=$(df "$mount_point" 2>/dev/null | awk 'NR==2 {gsub("%","",$5); print $5+0}')
        [ -z "$usage" ] && continue; [ "$usage" -ge 98 ] && continue
        test_dir="$mount_point/.nfs_diag_$(date +%Y%m%d_%H%M%S)"
        if try_write_dir "$test_dir"; then break; fi
    done
fi

if [ -n "$OUTPUT_DIR" ]; then
    LOG_FILE_MODE="file"
    fs_type=$(df -T "$OUTPUT_DIR" 2>/dev/null | awk 'NR==2 {print $2}')
    echo "ℹ️  日志输出目录: $OUTPUT_DIR (${fs_type:-未知})"
    exec > >(tee "$OUTPUT_DIR/collect.log" 2>/dev/null || cat) 2>&1
else
    LOG_FILE_MODE="stdout_only"
    echo "⚠️  所有磁盘均不可写，仅输出到标准输出"
fi

# ── 辅助函数 ────────────────────────────────────────────────
section() {
    echo ""
    echo "================================================================"
    echo " [NFS DIAG] $1"
    echo "================================================================"
}

cmd_info() {
    echo ""
    echo "  ▶ CMD: $1"
    echo "  ▶ 用途: $2"
    echo ""
}

HAS_JOURNAL=$(which journalctl 2>/dev/null)
NFS_LOG_PATTERN="nfs|NFS|rpc|RPC|statd|lockd|idmapd|ESTALE|stale|nfs4|mountd|exportfs"

echo "================================================================"
echo "  NFS Client 全量信息收集"
echo "  执行时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  故障时段: ${START_TIME:-未指定} ~ ${END_TIME:-未指定}"
echo "  目标挂载点: ${TARGET_MOUNT:-未指定}"
echo "  目标服务器: ${TARGET_SERVER:-未指定}"
echo "  输出目录: ${OUTPUT_DIR:-仅 stdout}"
echo "================================================================"

# ================================================================
# PART 1: NFS 挂载信息
# ================================================================
section "1. NFS 挂载信息"

cmd_info "mount | grep nfs" "当前 NFS 挂载列表及参数"
mount 2>/dev/null | grep -E " type nfs" 
echo ""

cmd_info "findmnt -t nfs,nfs4 -o TARGET,SOURCE,FSTYPE,OPTIONS" "结构化 NFS 挂载信息"
findmnt -t nfs,nfs4 -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null || echo "findmnt 不可用"
echo ""

cmd_info "nfsstat -m" "NFS 挂载参数详情（含 timeo/retrans/soft/hard）"
nfsstat -m 2>/dev/null || echo "nfsstat 不可用"
echo ""

cmd_info "mountstats: /proc/self/mountstats" "逐挂载点详细操作统计"
cat /proc/self/mountstats 2>/dev/null | head -200 || echo "/proc/self/mountstats 不可读"
echo ""

# ================================================================
# PART 2: NFS 客户端统计
# ================================================================
section "2. NFS 客户端统计"

cmd_info "nfsstat -c" "NFS 客户端操作统计（含错误计数）"
nfsstat -c 2>/dev/null || echo "nfsstat 不可用"
echo ""

cmd_info "nfsstat -4 -c" "NFSv4 客户端统计（独立查看）"
nfsstat -4 -c 2>/dev/null || echo "nfsstat -4 不可用"
echo ""

cmd_info "nfsstat -r" "RPC 客户端统计（retrans/时间）"
nfsstat -r 2>/dev/null || echo "nfsstat -r 不可用"
echo ""

cmd_info "nfsstat -l" "NFS 锁统计"
nfsstat -l 2>/dev/null || echo "nfsstat -l 不可用"
echo ""

# ================================================================
# PART 3: RPC 与辅助服务状态
# ================================================================
section "3. RPC 辅助服务状态"

cmd_info "ps aux | grep rpc" "rpc 相关进程运行状态"
ps aux 2>/dev/null | grep -E "rpc\." | grep -v grep || echo "无 rpc 相关进程运行"
echo ""

cmd_info "systemctl status rpcbind rpc-statd nfs-client" "rpcbind/statd/nfs-client 服务状态"
for svc in rpcbind rpc-statd nfs-client nfs-idmapd rpc-gssd; do
    systemctl status "$svc" 2>/dev/null | head -10 || true
    echo "---"
done
echo ""

cmd_info "lsmod | grep nfs" "内核 NFS 模块加载状态"
lsmod 2>/dev/null | grep -E "nfs|rpc|lockd" || echo "内核 NFS 模块未加载或 lsmod 不可用"
echo ""

# ================================================================
# PART 4: NFSv4 状态（/proc/net/rpc/nfs4.0/*）
# ================================================================
section "4. NFSv4 状态"

if [ -d "/proc/net/rpc/nfs4.0" ]; then
    for f in /proc/net/rpc/nfs4.0/*; do
        fname=$(basename "$f")
        echo "=== $fname ==="
        cat "$f" 2>/dev/null || echo "(空)"
        echo ""
    done
else
    echo "⚠️  /proc/net/rpc/nfs4.0 不存在（当前无活跃 NFSv4 会话或非 NFSv4 挂载）"
fi

# ================================================================
# PART 5: NFS 锁状态
# ================================================================
section "5. NFS 锁状态"

cmd_info "cat /proc/locks | grep NFS" "NFS 相关文件锁"
cat /proc/locks 2>/dev/null | grep -i NFS || echo "无 NFS 锁条目"
echo ""

cmd_info "lslocks (if available)" "锁统计（含 NFS 锁）"
lslocks 2>/dev/null || echo "lslocks 不可用"
echo ""

cmd_info "statd 状态目录" "statd 监控的主机和备份列表"
if [ -d "/var/lib/nfs/sm" ]; then
    echo "/var/lib/nfs/sm/ (monitored hosts):"
    ls -la /var/lib/nfs/sm/ 2>/dev/null
    echo ""
    echo "/var/lib/nfs/sm.bak/ (backup):"
    ls -la /var/lib/nfs/sm.bak/ 2>/dev/null
else
    echo "/var/lib/nfs/ 不存在或不可读"
fi

# ================================================================
# PART 6: 网络层诊断
# ================================================================
section "6. 网络层诊断"

if [ -n "$TARGET_SERVER" ]; then
    echo "=== 到 NFS 服务器 ${TARGET_SERVER} 的连通性 ==="
    timeout 5 ping -c 4 "$TARGET_SERVER" 2>&1 || echo "ping 失败"
    echo ""

    echo "=== NFS 端口 (2049) 可达性 ==="
    timeout 5 nc -zv "$TARGET_SERVER" 2049 2>&1 || echo "⚠️  port 2049 不可达"
    echo ""

    echo "=== portmapper 端口 (111) 可达性 ==="
    timeout 5 nc -zv "$TARGET_SERVER" 111 2>&1 || echo "⚠️  port 111 不可达"
    echo ""

    echo "=== rpcinfo ==="
    timeout 10 rpcinfo -p "$TARGET_SERVER" 2>&1 || echo "⚠️  rpcinfo 查询失败"
    echo ""

    echo "=== mtr 路径质量 ==="
    mtr --report -c 10 "$TARGET_SERVER" 2>&1 | tail -10 || echo "mtr 不可用或失败"
    echo ""

    echo "=== route get ==="
    ip route get "$TARGET_SERVER" 2>/dev/null || echo "ip route get 失败"
    echo ""

    echo "=== MTU 探测 ==="
    tracepath "$TARGET_SERVER" 2>&1 | head -10 || echo "tracepath 不可用"
else
    echo "未指定 NFS 服务器（-s），跳过网络层诊断。"
    echo "如有 NFS 挂载，提取服务器地址："
    mount 2>/dev/null | grep nfs | awk '{print $1}' | sed 's/:[^:]*$//'
fi

echo ""
echo "=== 本机网络接口 ==="
ip -brief addr show 2>/dev/null || ip addr show 2>/dev/null | grep -E "^[0-9]"

# ================================================================
# PART 7: 内核日志 - NFS 相关
# ================================================================
section "7. 内核日志（NFS 相关）"

echo "=== dmesg NFS 日志 ==="
dmesg -T 2>/dev/null | grep -iE "$NFS_LOG_PATTERN" | tail -60
echo ""

if [ -n "$HAS_JOURNAL" ] && [ -n "$START_TIME" ]; then
    echo "=== journalctl kernel 日志（时间窗口内）==="
    journalctl --since="$START_TIME" --until="$END_TIME" -k --no-pager 2>/dev/null | grep -iE "$NFS_LOG_PATTERN" | tail -60
elif [ -n "$HAS_JOURNAL" ]; then
    echo "=== journalctl kernel 日志（最近 200 行）==="
    journalctl -k --no-pager 2>/dev/null | grep -iE "$NFS_LOG_PATTERN" | tail -60
fi

# ================================================================
# PART 8: 系统日志 - NFS 相关
# ================================================================
section "8. 系统日志（NFS 相关）"

for logfile in /var/log/messages /var/log/syslog; do
    if [ -f "$logfile" ]; then
        if [ -n "$START_TIME" ] && [ -n "$END_TIME" ]; then
            echo "=== $logfile (时间窗口内) ==="
            awk -v s="$START_TIME" -v e="$END_TIME" -v pat="$NFS_LOG_PATTERN" '
            {
                if (match($0,/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}/)) {
                    ts=substr($0,RSTART,19); gsub("T"," ",ts)
                    if(ts>=s && ts<=e && tolower($0)~pat) print
                }
            }' "$logfile" 2>/dev/null | tail -60
        else
            echo "=== $logfile (grep NFS, 最近 60 行) ==="
            grep -iE "$NFS_LOG_PATTERN" "$logfile" 2>/dev/null | tail -60
        fi
        echo ""
    fi
done

# ================================================================
# PART 9: 系统资源概览
# ================================================================
section "9. 系统资源概览"

echo "=== 系统负载 ==="
uptime
echo ""

echo "=== CPU 使用 ==="
head -5 /proc/loadavg 2>/dev/null
echo ""

echo "=== 内存使用 ==="
free -h 2>/dev/null
echo ""

echo "=== 磁盘 IO（NFS 客户端本地）==="
iostat -x 1 2 2>/dev/null || echo "iostat 不可用"
echo ""

echo "=== 网络统计 ==="
netstat -s 2>/dev/null | head -20 || ss -s 2>/dev/null

# ================================================================
# PART 10: 指定挂载点/服务器的详细信息
# ================================================================
if [ -n "$TARGET_MOUNT" ]; then
    section "10. 指定挂载点详细信息: $TARGET_MOUNT"

    if mountpoint -q "$TARGET_MOUNT" 2>/dev/null; then
        echo "=== 挂载信息 ==="
        mount | grep "$TARGET_MOUNT"
        echo ""
        echo "=== mountstats（该挂载点）==="
        cat /proc/self/mountstats 2>/dev/null | grep -A 200 "$TARGET_MOUNT" | head -100
        echo ""
        echo "=== 该挂载点上打开的句柄 ==="
        lsof +D "$TARGET_MOUNT" 2>/dev/null | head -30 || echo "lsof 不可用"
    else
        echo "⚠️  $TARGET_MOUNT 不是有效挂载点"
    fi
fi

if [ -n "$TARGET_SERVER" ]; then
    section "11. 服务器连接详情: $TARGET_SERVER"

    echo "=== 到 ${TARGET_SERVER} 的连接 ==="
    ss -tnp "dst ${TARGET_SERVER}" 2>/dev/null || netstat -tnp 2>/dev/null | grep "$TARGET_SERVER"
    echo ""

    echo "=== NFS 到 ${TARGET_SERVER} 的连接统计 ==="
    ss -tn "dst ${TARGET_SERVER}" 2>/dev/null | grep -E "2049|:nfs" || echo "无活跃 NFS 连接"
fi

# ================================================================
# 文件保存 & 完成
# ================================================================

if [ "$LOG_FILE_MODE" = "file" ] && [ -n "$OUTPUT_DIR" ]; then
    dmesg -T 2>/dev/null > "$OUTPUT_DIR/dmesg_nfs.txt"
    echo "✅ 完整 dmesg 已保存到: $OUTPUT_DIR/dmesg_nfs.txt"

    if [ -n "$HAS_JOURNAL" ]; then
        if [ -n "$START_TIME" ] && [ -n "$END_TIME" ]; then
            journalctl --since="$START_TIME" --until="$END_TIME" -k --no-pager 2>/dev/null > "$OUTPUT_DIR/journal_nfs.txt"
        else
            journalctl -k --no-pager 2>/dev/null > "$OUTPUT_DIR/journal_nfs.txt"
        fi
        echo "✅ journalctl 日志已保存到: $OUTPUT_DIR/journal_nfs.txt"
    fi

    # 保存核心数据到独立文件（便于 Agent 读取）
    mount 2>/dev/null | grep nfs > "$OUTPUT_DIR/nfs_mount_info.txt" 2>/dev/null
    nfsstat -c > "$OUTPUT_DIR/nfsstat_client.txt" 2>/dev/null
    nfsstat -m > "$OUTPUT_DIR/nfs_mountstats.txt" 2>/dev/null
    cat /proc/net/rpc/nfs4.0/* > "$OUTPUT_DIR/nfsv4_state.txt" 2>/dev/null || echo "(无 NFSv4 状态)" > "$OUTPUT_DIR/nfsv4_state.txt"
    cat /proc/locks 2>/dev/null | grep -i nfs > "$OUTPUT_DIR/nfs_locks.txt" 2>/dev/null; [ -s "$OUTPUT_DIR/nfs_locks.txt" ] || echo "(无 NFS 锁条目)" > "$OUTPUT_DIR/nfs_locks.txt"
    rpcinfo -p localhost 2>/dev/null > "$OUTPUT_DIR/rpc_services.txt" 2>/dev/null
    echo "✅ 核心数据已分离保存到各独立文件"
fi

# ================================================================
section "收集完成"

echo ""
echo "✅ NFS 客户端全量信息收集完成！"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$LOG_FILE_MODE" = "stdout_only" ]; then
    echo "📤 输出模式: 仅标准输出（文件系统不可写回退）"
else
    echo "📁 输出目录: ${OUTPUT_DIR:-无}"
    echo ""
    echo "生成文件:"
    echo "  - nfs_mount_info.txt     (NFS 挂载列表)"
    echo "  - nfsstat_client.txt     (NFS 客户端统计)"
    echo "  - nfs_mountstats.txt     (挂载参数详情)"
    echo "  - nfsv4_state.txt        (NFSv4 状态)"
    echo "  - nfs_locks.txt          (NFS 锁状态)"
    echo "  - rpc_services.txt       (RPC 服务状态)"
    echo "  - dmesg_nfs.txt          (内核日志)"
    echo "  - journal_nfs.txt        (journal 日志)"
fi
echo ""
echo "收集内容:"
echo "  - NFS 挂载状态与参数"
echo "  - 客户端操作统计与错误计数"
echo "  - RPC/辅助服务运行状态"
echo "  - NFSv4 会话/lease/slot 状态"
echo "  - 文件锁状态"
echo "  - 网络连通性与路径质量"
echo "  - 内核与系统日志（NFS 相关）"
echo "  - 系统资源概览"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit 0
