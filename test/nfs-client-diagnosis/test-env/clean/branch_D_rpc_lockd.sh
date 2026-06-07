#!/bin/bash
# ============================================================
# 清理: rpc.statd / lockd 异常
# ============================================================
set -euo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SELF_DIR/../lib/common.sh"

check_env 2>/dev/null || { warn "环境未运行，无需清理"; exit 0; }

header
echo "  清理: Branch D — 恢复 rpc.statd"
header

info "Step 1/2: 重启 rpcbind 和 rpc.statd..."
exec_cli 'pkill -9 rpcbind 2>/dev/null; true'
exec_cli 'service rpcbind start 2>/dev/null || rpcbind -f &'
sleep 2
ok "rpcbind 已重新启动"

# statd 通常由 rpcbind 按需启动，尝试显式启动
exec_cli 'service rpc-statd start 2>/dev/null || /sbin/rpc.statd 2>/dev/null || true'
sleep 1
ok "rpc.statd 已尝试启动"

info "Step 2/2: 卸载 NFS..."
nfs_umount

echo ""
ok "✅ 环境已恢复"
echo ""
