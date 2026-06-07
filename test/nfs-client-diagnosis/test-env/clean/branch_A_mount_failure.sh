#!/bin/bash
# ============================================================
# 清理: NFS mount 挂载失败
# ============================================================
set -euo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SELF_DIR/../lib/common.sh"

check_env 2>/dev/null || { warn "环境未运行，无需清理"; exit 0; }

header
echo "  清理: Branch A — 恢复 NFS 端口"
header

info "Step 1/2: 解除 iptables 端口屏蔽..."
for port in 2049 111; do
    for proto in tcp udp; do
        exec_srv "iptables -D INPUT -p ${proto} --dport ${port} -j DROP 2>/dev/null; true"
    done
done
ok "iptables 规则已清除"

info "Step 2/2: 验证端口恢复..."
SERVER_HOST="nfs-server"
if exec_cli "timeout 3 nc -zv ${SERVER_HOST} 2049 2>&1" 2>/dev/null; then
    ok "port 2049 已恢复"
else
    warn "port 2049 仍未恢复，可能需要重启容器或检查 iptables"
fi

echo ""
ok "✅ 环境已恢复，可进行下一场景测试"
echo ""
