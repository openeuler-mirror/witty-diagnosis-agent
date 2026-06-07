#!/bin/bash
# ============================================================
# 清理: NFS 性能退化
# ============================================================
set -euo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SELF_DIR/../lib/common.sh"

check_env 2>/dev/null || { warn "环境未运行，无需清理"; exit 0; }

header
echo "  清理: Branch E — 移除网络延迟注入"
header

info "Step 1/2: 删除 tc 规则..."
tc_del "eth0"
ok "tc 规则已清除"

info "Step 2/2: 卸载 NFS..."
nfs_umount

echo ""
ok "✅ 环境已恢复"
echo ""
