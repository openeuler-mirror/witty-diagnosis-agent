#!/bin/bash
# ============================================================
# 脚本：branch_A_mount_failure.sh
# 用途：NFS mount 挂载失败/hung 诊断
# 使用：bash branch_A_mount_failure.sh <NFS_server> <export_path> [mount_point]
# ============================================================

set -euo pipefail

NFS_SERVER="${1:-}"
EXPORT_PATH="${2:-}"
MOUNT_POINT="${3:-/tmp/nfs_diag_test_mount}"

if [ -z "$NFS_SERVER" ] || [ -z "$EXPORT_PATH" ]; then
    echo "用法: bash $0 <NFS_server> <export_path> [mount_point]"
    echo "示例: bash $0 192.168.1.100 /data/shared"
    echo "      bash $0 nfs-server.local /srv/exports /mnt/test"
    exit 1
fi

echo "================================================================"
echo " 分支A: NFS mount 挂载失败/hung 诊断"
echo " 服务器: ${NFS_SERVER}"
echo " Export: ${EXPORT_PATH}"
echo " 测试挂载点: ${MOUNT_POINT}"
echo "================================================================"

echo ""
echo "=== A1: 网络连通性检查 ==="
echo "--- ping (4 次) ---"
timeout 10 ping -c 4 "$NFS_SERVER" 2>&1 || echo "⚠️  ping 失败"
echo ""

echo "--- NFS 端口 (2049) ---"
timeout 5 nc -zv "$NFS_SERVER" 2049 2>&1 || echo "⚠️  port 2049 不可达"
echo ""

echo "--- portmapper 端口 (111) ---"
timeout 5 nc -zv "$NFS_SERVER" 111 2>&1 || echo "⚠️  port 111 不可达"
echo ""

echo "=== A2: RPC 服务可达性 ==="
timeout 10 rpcinfo -p "$NFS_SERVER" 2>&1 || echo "⚠️  rpcinfo 查询失败"
echo ""

echo "--- rpcinfo 过滤 NFS/mountd ---"
timeout 10 rpcinfo -p "$NFS_SERVER" 2>/dev/null | grep -E "nfs|mountd" || echo "⚠️  未找到 NFS 或 mountd 注册"
echo ""

echo "=== A3: showmount - export 列表 ==="
timeout 10 showmount -e "$NFS_SERVER" 2>&1 || echo "⚠️  showmount 失败（可能需要服务端 nfs-server 或 rpcbind 放行）"
echo ""

echo "=== A4: 内核模块状态 ==="
lsmod 2>/dev/null | grep -E "nfs|rpc|lockd" || echo "⚠️  内核 NFS 模块未加载"
echo ""

echo "=== A5: 当前 NFS 挂载状态 ==="
mount | grep nfs 2>/dev/null || echo "无当前 NFS 挂载"
echo ""

echo "=== A6: 尝试测试挂载（只测试连通性，不做实际 mount）==="
echo "--- Mount option probing ---"
echo "NFSv4.2 (default): mount -t nfs -o vers=4.2,proto=tcp,timeo=600,hard,noexec,nosuid"
echo "NFSv4.0:           mount -t nfs -o vers=4.0,proto=tcp,timeo=600,hard,noexec,nosuid"
echo "NFSv3:             mount -t nfs -o vers=3,proto=tcp,timeo=600,hard,noexec,nosuid"
echo ""
echo "⚠️  本脚本不执行 mount 操作（只读诊断）。如需测试 mount，请用户手动执行。"
echo ""

echo "=== A7: dmesg 中 mount 相关错误 ==="
dmesg -T 2>/dev/null | grep -iE "nfs.*mount|mount.*nfs|RPC.*Unable|NFS:.*error" | tail -20 || echo "无相关日志"
echo ""

echo "=== A8: 连接跟踪状态 (conntrack) ==="
conntrack -L 2>/dev/null | grep "$NFS_SERVER" | head -10 || echo "conntrack 不可用或对 ${NFS_SERVER} 无条目"
echo ""

echo "================================================================"
echo " 分支A 诊断结论模板"
echo "================================================================"
echo ""
echo "网络层: [可达/不可达]"
echo "  ping: [成功/失败]"
echo "  port 2049: [可达/不可达]"
echo "  port 111: [可达/不可达]"
echo "RPC 层: [正常/异常]"
echo "  rpcinfo: [成功/失败]"
echo "  NFS 注册: [存在/缺失]"
echo "  mountd 注册: [存在/缺失]"
echo "Export 可见性: [可见/不可见] (showmount)"
echo "内核模块: [已加载/未加载]"
echo "诊断结论: <一句话根因>"
echo "================================================================"
