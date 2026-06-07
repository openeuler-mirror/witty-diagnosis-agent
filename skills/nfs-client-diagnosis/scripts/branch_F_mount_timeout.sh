#!/bin/bash
# ============================================================
# 脚本：branch_F_mount_timeout.sh
# 用途：Soft/Hard Mount 超时行为差异诊断
# 使用：bash branch_F_mount_timeout.sh [mount_point]
# ============================================================

set -euo pipefail

TARGET_MOUNT="${1:-}"

echo "================================================================"
echo " 分支F: Soft/Hard Mount 超时行为差异诊断"
echo " 挂载点: ${TARGET_MOUNT:-未指定}"
echo "================================================================"

echo ""
echo "=== F1: 当前 NFS 挂载参数 ==="
echo "--- mount ---"
mount | grep nfs 2>/dev/null || echo "无 NFS 挂载"
echo ""
echo "--- findmnt 详细参数 ---"
findmnt -t nfs,nfs4 -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null || echo "findmnt 不可用"
echo ""

echo "=== F2: soft/hard 参数识别 ==="
nfs_lines=$(mount 2>/dev/null | grep nfs || true)
if [ -n "$nfs_lines" ]; then
    echo "$nfs_lines" | while IFS= read -r line; do
    echo "挂载点: $(echo "$line" | awk '{print $3}')"
    opts=$(echo "$line" | grep -oP '\((.*?)\)' | tr -d '()' || echo "")
    if echo "$opts" | grep -q "soft"; then
        echo "  类型: soft mount"
        echo "  行为: RPC 超时 × retrans 次后返回 EIO 给应用"
        echo "  风险: 应用未检查错误 → 静默数据损坏"
        echo "  timeo=$(echo "$opts" | grep -oP 'timeo=\K\d+' || echo '默认(600=60s)') (1/10 秒)"
        echo "  retrans=$(echo "$opts" | grep -oP 'retrans=\K\d+' || echo '默认(3)')"
    elif echo "$opts" | grep -q "hard"; then
        echo "  类型: hard mount"
        echo "  行为: RPC 无限重试直到 server 恢复"
        echo "  风险: 进程进入 D 状态不可杀，umount -f 也可能失败"
        echo "  timeo=$(echo "$opts" | grep -oP 'timeo=\K\d+' || echo '默认(600=60s)') (1/10 秒)"
        echo "  retrans=$(echo "$opts" | grep -oP 'retrans=\K\d+' || echo '默认(3)')"
    else
        echo "  类型: 未知（默认 hard）"
    fi
    echo "  actimeo=$(echo "$opts" | grep -oP 'actimeo=\K\d+' || echo '未设置(默认使用acregmin/acregmax)')"
    echo ""
    done
else
    echo "  (当前无活跃 NFS 挂载)"
fi

echo "=== F3: RPC 超时统计 ==="
echo "--- nfsstat -c (关注 timed out) ---"
nfsstat -c 2>/dev/null | grep -iE "timed out|timeout|error" || echo "无超时统计"
echo ""
echo "--- RPC retrans 统计 ---"
nfsstat -r 2>/dev/null || echo "nfsstat -r 不可用"
echo ""

echo "=== F4: 超时日志 ==="
echo "--- dmesg NFS 超时日志 ---"
dmesg -T 2>/dev/null | grep -iE "NFS:.*timed out|NFS:.*timeout|RPC:.*timed out|server.*not responding" | tail -30 || echo "无 NFS 超时日志"
echo ""

echo "=== F5: D 状态进程检查（hard mount 场景）==="
echo "--- D 状态 NFS 进程 ---"
D_PROCS=$(ps -eo pid,stat,cmd 2>/dev/null | grep " D " | grep -iE "nfs|rpc" || echo "无")
echo "$D_PROCS"
echo ""

echo "--- D 状态进程的内核栈 ---"
for pid in $(ps -eo pid,stat 2>/dev/null | awk '$2 == "D" {print $1}'); do
    cmd=$(cat /proc/$pid/comm 2>/dev/null || "")
    if [ -n "$cmd" ]; then
        echo "PID: $pid ($cmd)"
        cat /proc/$pid/stack 2>/dev/null | head -5 || echo "  stack 不可读"
        echo "---"
    fi
done

echo ""
echo "=== F6: 软 mount 静默数据丢失风险 ==="
echo "检查哪些应用使用了 soft mount..."
nfs_lines=$(mount 2>/dev/null | grep nfs || true)
if [ -n "$nfs_lines" ]; then
    echo "$nfs_lines" | while IFS= read -r line; do
    if echo "$line" | grep -q "soft"; then
        mp=$(echo "$line" | awk '{print $3}')
        echo "⚠️  以下挂载点使用 soft mount: $mp"
        echo "   检查该挂载点上运行的应用是否处理 EIO 错误..."
        fuser -v "$mp" 2>/dev/null | head -10 || true
    fi
    done
else
    echo "  (当前无活跃 NFS 挂载)"
fi

echo ""
echo "=== F7: 故障模拟（只读检查，不触发实际 IO）==="
echo "--- 当前 NFS 连接的 TCP 状态 ---"
ss -tnp "src :2049 or dst :2049" 2>/dev/null | head -20 || netstat -tnp 2>/dev/null | grep 2049 | head -10
echo ""

echo "--- 时间基线: 当前 RPC 超时估算 ---"
nfs_lines=$(mount 2>/dev/null | grep nfs || true)
if [ -n "$nfs_lines" ]; then
    echo "$nfs_lines" | while IFS= read -r line; do
    mp=$(echo "$line" | awk '{print $3}')
    opts=$(echo "$line" | grep -oP '\((.*?)\)' | tr -d '()' || "")
    timeo=$(echo "$opts" | grep -oP 'timeo=\K\d+' || echo "600")
    retrans=$(echo "$opts" | grep -oP 'retrans=\K\d+' || echo "3")
    total_timeout_ms=$((timeo * retrans * 100))
    if echo "$opts" | grep -q "soft"; then
        echo "  $mp: soft mount, 单次 RPC 超时=${timeo}00ms, retrans=${retrans}次, 应用可见超时=${total_timeout_ms}ms"
    elif echo "$opts" | grep -q "hard"; then
        echo "  $mp: hard mount, 单次 RPC 超时=${timeo}00ms, retrans=${retrans}次, 无限重试直到 server 恢复"
    fi
    done
else
    echo "  (当前无活跃 NFS 挂载)"
fi

echo ""
echo "================================================================"
echo " 分支F 诊断结论模板"
echo "================================================================"
echo ""
echo "挂载类型: [soft/hard/混合]"
echo "timeo: [X00ms]"
echo "retrans: [X次]"
echo "应用可见超时(soft): [Xms]"
echo "RPC 超时统计: [有超时/无超时]"
echo "D 状态进程: [有(NFS相关)/无]"
echo "soft mount 应用风险: [存在(应用可能不处理EIO)/无风险]"
echo ""
echo "根因分类:"
echo "  □ soft mount + 应用不处理 EIO → 静默数据丢失"
echo "  □ hard mount + server 不可达 → 进程 D 状态 hang"
echo "  □ timeo/retrans 参数过小 → 正常网络抖动也触发超时"
echo "  □ timeo/retrans 参数过大 → 故障恢复时间过长"
echo "  □ actimeo 参数不当 → 缓存一致性导致的问题"
echo "================================================================"
