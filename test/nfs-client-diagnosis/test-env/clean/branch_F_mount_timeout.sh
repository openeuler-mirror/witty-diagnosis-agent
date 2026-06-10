#!/bin/bash
# ============================================================
# 清理: Soft/Hard Mount 超时
# ============================================================
set -euo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SELF_DIR/../lib/common.sh"

check_env 2>/dev/null || { warn "环境未运行，无需清理"; exit 0; }

header
echo "  清理: Branch F — 恢复网络连接并卸载挂载"
header

info "Step 1/3: 清除 iptables 阻断规则..."
exec_cli "iptables -D OUTPUT -p tcp --dport 2049 -j DROP 2>/dev/null; true"
exec_cli "iptables -D OUTPUT -p udp --dport 2049 -j DROP 2>/dev/null; true"
ok "iptables 规则已清除"

info "Step 2/3: 等待并卸载 NFS（可能需要强制卸载）..."
sleep 2
nfs_umount
exec_cli "umount -l ${MOUNT_DIR} 2>/dev/null; true"
ok "NFS 已卸载"

info "Step 3/3: 清理残留 D 状态影响..."
exec_cli "kill -9 \$(ps -eo pid,stat | awk '\$2 ~ /D/ {print \$1}') 2>/dev/null; true" || true

echo ""
ok "✅ 环境已恢复"
echo ""
