#!/bin/bash
# ============================================================
# 清理: NFSv4 Lease 过期
# ============================================================
set -euo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SELF_DIR/../lib/common.sh"

check_env 2>/dev/null || { warn "环境未运行，无需清理"; exit 0; }

header
echo "  清理: Branch C — 重置 NFSv4 Lease 测试环境"
header

info "Step 1/3: 确保 NFS Server 运行正常..."
exec_srv "rpc.nfsd 8 2>/dev/null; true"
exec_srv "rpc.mountd -F &" 2>/dev/null
exec_srv "exportfs -ra 2>/dev/null; true"
sleep 2
ok "NFS Server 已恢复"

info "Step 2/3: 卸载客户端挂载..."
nfs_umount

info "Step 3/3: 清除残留的 NFSv4 state..."
exec_cli 'cat /dev/null 2>/dev/null > /proc/net/rpc/nfs4.0/* 2>/dev/null; true'

echo ""
ok "✅ 环境已恢复"
echo ""
