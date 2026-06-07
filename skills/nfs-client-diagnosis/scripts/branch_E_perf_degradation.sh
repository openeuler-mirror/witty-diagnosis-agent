#!/bin/bash
# ============================================================
# 脚本：branch_E_perf_degradation.sh
# 用途：NFS 性能退化（RTT 飙升/吞吐下降）诊断
# 使用：bash branch_E_perf_degradation.sh [mount_point] [nfs_server]
# ============================================================

set -euo pipefail

TARGET_MOUNT="${1:-}"
TARGET_SERVER="${2:-}"

echo "================================================================"
echo " 分支E: NFS 性能退化诊断"
echo " 挂载点: ${TARGET_MOUNT:-未指定}"
echo " 服务器: ${TARGET_SERVER:-未指定}"
echo "================================================================"

echo ""
echo "=== E1: RPC 延迟和重传统计 ==="
echo "--- nfsstat -r (RPC 统计) ---"
nfsstat -r 2>/dev/null || echo "nfsstat -r 不可用"
echo ""

echo "--- nfsstat -c (客户端统计, 关注 retrans) ---"
nfsstat -c 2>/dev/null || echo "nfsstat -c 不可用"
echo ""

echo "--- retrans 分析 ---"
if ! command -v nfsstat &>/dev/null; then
    echo "⚠️  nfsstat 命令不可用，跳过 RPC 统计"
    RPC_LINE=""
else
    RPC_LINE=$(nfsstat -r | tail -1)
fi
RPC_CALLS=$(echo "$RPC_LINE" | awk '{print $1}' | grep -oE '^[0-9]+' || echo 0)
RPC_RETRANS=$(echo "$RPC_LINE" | awk '{print $2}' | grep -oE '^[0-9]+' || echo 0)
if [ "$RPC_CALLS" -gt 0 ] 2>/dev/null; then
    RETRANS_RATIO=$(echo "scale=2; $RPC_RETRANS * 100 / $RPC_CALLS" | bc 2>/dev/null || echo "N/A")
    echo "RPC calls: $RPC_CALLS, retrans: $RPC_RETRANS, ratio: ${RETRANS_RATIO:-N/A}%"
    if [ -n "$RETRANS_RATIO" ] && [ "$(echo "$RETRANS_RATIO > 1" | bc 2>/dev/null)" = "1" ]; then
        echo "⚠️  retrans 率 ${RETRANS_RATIO}% > 1%，网络可能存在丢包"
    fi
else
    echo "⚠️  无法计算 retrans 率"
fi
echo ""

echo "=== E2: mountstats 逐操作延迟分析 ==="
echo "--- /proc/self/mountstats ---"
MOUNTSTATS=$(cat /proc/self/mountstats 2>/dev/null) || {
    echo "⚠️  /proc/self/mountstats 不可读"
    MOUNTSTATS=""
}

if [ -n "$MOUNTSTATS" ]; then
    if [ -n "$TARGET_MOUNT" ]; then
        echo "（聚焦挂载点: $TARGET_MOUNT）"
        echo "$MOUNTSTATS" | grep -A 100 "device $TARGET_MOUNT" | head -80
    else
        echo "$MOUNTSTATS" | head -150
    fi
    echo ""
    echo "--- RPC 平均 RTT 提取 ---"
    echo "$MOUNTSTATS" | grep -E "RPC|rtt" | head -10 || echo "  (无 NFS 相关 RPC 统计)"
fi
echo ""

echo "=== E3: 网络路径质量 ==="
if [ -n "$TARGET_SERVER" ]; then
    echo "--- ping 延迟统计 (10 次) ---"
    if ! timeout 15 ping -c 10 "$TARGET_SERVER" 2>&1 | tail -5; then
        echo "    ⚠️  到 ${TARGET_SERVER} 的 ping 测试未通过"
    fi
    echo ""

    echo "--- mtr 路径质量 ---"
    timeout 30 mtr --report -c 5 "$TARGET_SERVER" 2>&1 | tail -15 || echo "mtr 不可用"
    echo ""

    echo "--- MTU 探测 ---"
    tracepath "$TARGET_SERVER" 2>&1 | head -10 || echo "tracepath 不可用"
else
    echo "未指定服务器，提取 NFS 挂载中的服务器地址..."
    nfs_servers=$(mount 2>/dev/null | grep nfs | awk '{print $1}' | sed 's/:[^:]*$//' | sort -u)
    for svr in $nfs_servers; do
        echo "--- ping ${svr} (5 次) ---"
        if ! timeout 10 ping -c 5 "$svr" 2>&1 | tail -3; then
            echo "    ⚠️  到 ${svr} 的 ping 未通过"
        fi
        echo ""
    done
fi
echo ""

echo "=== E4: 操作级别性能基准（只读）==="
if [ -n "$TARGET_MOUNT" ] && mountpoint -q "$TARGET_MOUNT" 2>/dev/null; then
    echo "--- ls -la (目录列表) ---"
    TIMEFORMAT='ls 耗时: %R 秒'
    time (timeout 10 ls -la "$TARGET_MOUNT" 2>/dev/null) || echo "ls 超时"
    echo ""

    echo "--- stat (属性查询) ---"
    TIMEFORMAT='stat 耗时: %R 秒'
    time (timeout 5 stat "$TARGET_MOUNT" 2>/dev/null) || echo "stat 超时"
    echo ""

    echo "--- read 性能 (小文件) ---"
    testfile=$(find "$TARGET_MOUNT" -type f -size -1M 2>/dev/null | head -1)
    if [ -n "$testfile" ]; then
        TIMEFORMAT='read 耗时: %R 秒'
        time (timeout 10 dd if="$testfile" of=/dev/null bs=1M count=10 2>/dev/null) || echo "read 超时"
    else
        echo "未找到适合读测试的小文件"
    fi
else
    echo "未指定有效挂载点或挂载点不可达，跳过操作性能基准。"
fi
echo ""

echo "=== E5: 系统资源 ---"
echo "--- CPU 负载 ---"
uptime
echo ""
echo "--- top CPU 进程 ---"
ps -eo pid,%cpu,%mem,cmd --sort=-%cpu 2>/dev/null | head -10 || true
echo ""
echo "--- 内存 ---"
free -h 2>/dev/null
echo ""
echo "--- 网络统计 ---"
if command -v netstat &>/dev/null; then
    netstat -s 2>/dev/null | grep -iE "drop|error|retrans|loss|retransmit|segment" | head -20 || echo "netstat 无错误计数"
else
    echo "netstat 不可用。使用 ss -s 查看 socket 统计摘要："
    ss -s 2>/dev/null
fi

echo ""
echo "=== E6: NFS 挂载参数优化检查 ==="
mount | grep nfs | while read line; do
    echo "挂载: $line"
    if echo "$line" | grep -q "rsize="; then
        rsize=$(echo "$line" | grep -oP 'rsize=\K\d+')
        if [ -n "$rsize" ] && [ "$rsize" -lt 1048576 ]; then
            echo "  ⚠️  rsize=${rsize} < 1M，大文件传输可能未优化"
        fi
    fi
    if echo "$line" | grep -q "wsize="; then
        wsize=$(echo "$line" | grep -oP 'wsize=\K\d+')
        if [ -n "$wsize" ] && [ "$wsize" -lt 1048576 ]; then
            echo "  ⚠️  wsize=${wsize} < 1M，大文件传输可能未优化"
        fi
    fi
    if echo "$line" | grep -q "soft"; then
        echo "  ⚠️  soft mount: 超时返回 EIO，应用需妥善处理错误"
    fi
done

echo ""
echo "================================================================"
echo " 分支E 诊断结论模板"
echo "================================================================"
echo ""
echo "RPC retrans: [正常/偏高] (ratio: X%)"
echo "RPC RTT: [正常/偏高] (avg: Xms)"
echo "网络延迟: [正常/高] (ping avg: Xms)"
echo "网络丢包: [有/无]"
echo "操作延迟: [GETATTR/READ/WRITE 的 RTT 分布]"
echo "挂载参数优化: [合理/可优化（rsize/wsize/timeo）]"
echo "系统资源: [充足/瓶颈: CPU/内存/网络]"
echo ""
echo "根因分类:"
echo "  □ 网络延迟高/丢包"
echo "  □ NFS 服务器过载"
echo "  □ rsize/wsize 参数过小"
echo "  □ MTU 不匹配导致分片"
echo "  □ 客户端资源瓶颈（CPU/内存/IO）"
echo "  □ RPC slot 限制"
echo "================================================================"
