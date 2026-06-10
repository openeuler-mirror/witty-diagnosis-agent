#!/bin/bash
# ============================================================
# 脚本：branch_D_rpc_lockd.sh
# 用途：rpc.statd / lockd 异常诊断
# 使用：bash branch_D_rpc_lockd.sh [nfs_server]
# ============================================================

set -euo pipefail

TARGET_SERVER="${1:-}"

echo "================================================================"
echo " 分支D: rpc.statd / lockd 异常诊断"
echo " 服务器: ${TARGET_SERVER:-未指定}"
echo "================================================================"

echo ""
echo "=== D1: rpc.statd 服务状态 ==="
echo "--- systemctl ---"
systemctl status rpc-statd 2>/dev/null | head -15 || echo "⚠️  rpc-statd 服务不存在或不可查"
echo ""
echo "--- ps 进程 ---"
ps aux 2>/dev/null | grep -E "rpc.statd|rpcbind" | grep -v grep || echo "⚠️  rpc.statd 或 rpcbind 未运行"
echo ""

echo "=== D2: 内核 NFS 锁模块 ==="
lsmod 2>/dev/null | grep -E "nfsv4|lockd|nfsd" || echo "⚠️  lockd/nfsv4 模块未加载"
echo ""

echo "=== D3: rpcinfo - 锁服务注册 ==="
echo "--- localhost ---"
rpcinfo -p localhost 2>/dev/null | grep -E "statd|nlockmgr" || echo "⚠️  本地未注册 statd 或 nlockmgr"
echo ""

if [ -n "$TARGET_SERVER" ]; then
    echo "--- server: ${TARGET_SERVER} ---"
    timeout 10 rpcinfo -p "$TARGET_SERVER" 2>/dev/null | grep -E "statd|nlockmgr" || echo "⚠️  服务端未注册 statd 或 nlockmgr"
fi
echo ""

echo "=== D4: /proc/locks 中的 NFS 锁 ==="
echo "--- NFS 锁列表 ---"
cat /proc/locks 2>/dev/null | grep -i NFS || echo "无 NFS 锁条目"
echo ""
echo "--- 全部锁统计 ---"
LOCKS_TOTAL=$(cat /proc/locks 2>/dev/null | wc -l)
LOCKS_NFS=$(grep -ci NFS /proc/locks 2>/dev/null || true)
echo "总锁条目: $LOCKS_TOTAL, NFS 锁: $LOCKS_NFS"
echo ""

echo "=== D5: statd 状态目录 ==="
if [ -d "/var/lib/nfs/sm" ]; then
    echo "--- /var/lib/nfs/sm/ (monitored hosts) ---"
    ls -la /var/lib/nfs/sm/ 2>/dev/null
    echo ""
    echo "--- /var/lib/nfs/sm.bak/ (backup) ---"
    ls -la /var/lib/nfs/sm.bak/ 2>/dev/null
    echo ""
    echo "--- 异常检测 ---"
    sm_count=$(ls /var/lib/nfs/sm/ 2>/dev/null | wc -l)
    sm_bak_count=$(ls /var/lib/nfs/sm.bak/ 2>/dev/null | wc -l)
    echo "sm/ 条目数: $sm_count, sm.bak/ 条目数: $sm_bak_count"
    if [ "$sm_count" -gt "$sm_bak_count" ]; then
        echo "⚠️  sm/ 比 sm.bak/ 多 $((sm_count - sm_bak_count)) 条目，可能存在残留监控条目"
    fi
else
    echo "/var/lib/nfs/ 不存在或不可读"
fi

echo ""
echo "=== D6: NFS 锁统计 ==="
nfsstat -l 2>/dev/null || echo "nfsstat -l 不可用"
echo ""

echo "=== D7: 锁相关 dmesg 日志 ==="
dmesg -T 2>/dev/null | grep -iE "lockd|statd|nfslock|NLM|blocked.*lock" | tail -30 || echo "无锁相关内核日志"
echo ""

echo "=== D8: 当前 D 状态进程（可能与锁相关）==="
ps -eo pid,stat,wchan:40,cmd 2>/dev/null | grep " D " | grep -v grep || echo "无 D 状态进程"
echo ""

echo "--- D 状态进程内核栈（过滤 lock/nfs）---"
for pid in $(ps -eo pid,stat 2>/dev/null | awk '$2 ~ /^D/ {print $1}'); do
    stack=$(cat /proc/$pid/stack 2>/dev/null || echo "")
    if echo "$stack" | grep -qiE "nfs|lock|rpc"; then
        echo "PID $pid:"
        echo "$stack"
        cmd=$(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ' || echo "")
        echo "CMD: $cmd"
        echo "---"
    fi
done

echo ""
echo "=== D9: 文件锁命令可用性检查 ==="
for cmd in lslocks flock; do
    if command -v "$cmd" &>/dev/null; then
        echo "✅ $cmd 可用"
    else
        echo "⚠️  $cmd 不可用"
    fi
done

echo ""
echo "================================================================"
echo " 分支D 诊断结论模板"
echo "================================================================"
echo ""
echo "rpc.statd 状态: [运行中/未运行/crashed]"
echo "内核 lockd: [已加载/未加载]"
echo "rpcinfo statd: [已注册/未注册]"
echo "rpcinfo nlockmgr: [已注册/未注册]"
echo "/proc/locks NFS: [正常/异常（泄漏）]"
echo "statd 目录: [正常/残留条目]"
echo ""
echo "根因分类:"
echo "  □ rpc.statd 未运行或 crashed"
echo "  □ 内核 lockd 模块未加载"
echo "  □ statd 防火墙拦截（NLM 通知走丢）"
echo "  □ 进程崩溃未释放锁（锁泄漏）"
echo "  □ server 端 statd 不可达"
echo "================================================================"
