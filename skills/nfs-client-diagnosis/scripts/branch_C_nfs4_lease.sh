#!/bin/bash
# ============================================================
# 脚本：branch_C_nfs4_lease.sh
# 用途：NFSv4 Lease 过期/State 恢复故障诊断
# 使用：bash branch_C_nfs4_lease.sh [mount_point] [nfs_server]
# ============================================================

set -euo pipefail

TARGET_MOUNT="${1:-}"
TARGET_SERVER="${2:-}"

echo "================================================================"
echo " 分支C: NFSv4 Lease 过期 / State 恢复诊断"
echo " 挂载点: ${TARGET_MOUNT:-未指定}"
echo " 服务器: ${TARGET_SERVER:-未指定}"
echo "================================================================"

echo ""
echo "=== C1: NFSv4 客户端 state 概览 ==="
if [ -d "/proc/net/rpc/nfs4.0" ]; then
    for f in /proc/net/rpc/nfs4.0/*; do
        fname=$(basename "$f")
        echo "--- $fname ---"
        cat "$f" 2>/dev/null || echo "(空)"
        echo ""
    done
else
    echo "⚠️  /proc/net/rpc/nfs4.0 不存在（无活跃 NFSv4 会话）"
fi

echo "=== C2: NFSv4 操作统计 ==="
echo "--- nfsstat -4 -c (NFSv4 错误类统计) ---"
nfsstat -4 -c 2>/dev/null || echo "nfsstat -4 不可用"
echo ""

echo "--- 关键 NFSv4 错误计数 ---"
nfsstat -4 -c 2>/dev/null | grep -iE "expired|stale|bad|denied|delay|fault|error" || echo "无显著 NFSv4 错误"
echo ""

echo "=== C3: lease 时间信息 ==="
if [ -f "/proc/net/rpc/nfs4.0/clientid" ]; then
    echo "--- lease 信息 ---"
    cat /proc/net/rpc/nfs4.0/clientid
    echo ""
    echo "--- 解释 ---"
    echo "字段: clientid boot verify lease_expires [flags]"
    echo "  lease_expires: 从启动到 lease 到期的 jiffies"
    echo "  当前 jiffies: $(cat /proc/timer_list 2>/dev/null | grep -m1 "jiffies" || echo "不可读")"
fi

echo ""
echo "=== C4: slot table 状态 ==="
if [ -f "/proc/net/rpc/nfs4.0/slot_table" ]; then
    echo "--- slot_table ---"
    cat /proc/net/rpc/nfs4.0/slot_table
    echo ""
    echo "--- 解释 ---"
    echo "字段: slot_nr seqid [rpc_status]"
    echo "  大量 slot 处于非空闲状态 → 请求堆积"
    echo "  backlog 队列 → server 处理不过来"
fi

echo ""
echo "=== C5: callback (回拨) 通道检查 ==="
echo "--- /proc/net/rpc/nfs4.0/callback ---"
if [ -f "/proc/net/rpc/nfs4.0/callback" ]; then
    cat /proc/net/rpc/nfs4.0/callback
else
    echo "/proc/net/rpc/nfs4.0/callback 不存在"
fi

if [ -n "$TARGET_SERVER" ]; then
    echo ""
    echo "--- 检查 server 的 callback 端口注册 ---"
    timeout 10 rpcinfo -p "$TARGET_SERVER" 2>/dev/null | grep nfs || echo "rpcinfo 失败或无 NFS 注册"
fi

echo ""
echo "=== C6: 内核日志 NFSv4 恢复记录 ==="
dmesg -T 2>/dev/null | grep -iE "nfs4|reclaim|state.*recover|lease|clientid|BADSESSION|NFS4ERR" | tail -40 || echo "无 NFSv4 相关内核日志"
echo ""

echo "=== C7: 当前 NFSv4 挂载状态 ==="
mount | grep " nfs4 " 2>/dev/null || echo "无活跃 NFSv4 挂载"
echo ""

echo "=== C8: D 状态进程检查（NFS 相关）==="
ps -eo pid,stat,wchan:30,cmd 2>/dev/null | grep " D " | grep -iE "nfs|rpc" || echo "无 NFS 相关 D 状态进程"
echo ""

if [ -n "$TARGET_MOUNT" ] && mountpoint -q "$TARGET_MOUNT" 2>/dev/null; then
    echo "=== C9: 指定挂载点状态 ==="
    echo "--- statfs ---"
    timeout 5 stat -f "$TARGET_MOUNT" 2>&1 || echo "statfs 超时或失败"
    echo ""
    echo "--- 简单文件操作测试（ls）---"
    timeout 5 ls "$TARGET_MOUNT" 2>&1 | head -10 || echo "ls 超时或失败"
fi

echo ""
echo "================================================================"
echo " 分支C 诊断结论模板"
echo "================================================================"
echo ""
echo "NFSv4 state: [正常/异常]"
echo "  clientid: [有效/过期]"
echo "  lease: [有效/过期]"
echo "  slot_table: [正常/耗尽/backlog]"
echo "  callback: [正常/异常]"
echo "NFSv4 错误计数: [NFS4ERR_EXPIRED/BADSESSION/其他]"
echo "内核日志: [有重新声明失败/无]"
echo ""
echo "根因分类:"
echo "  □ Server 重启导致 lease 中断"
echo "  □ 网络长时间断开超 lease_time"
echo "   □ callback 通道被防火墙拦截"
echo "   □ slot table 耗尽（请求堆积）"
echo "   □ session 被 server 销毁"
echo "================================================================"
