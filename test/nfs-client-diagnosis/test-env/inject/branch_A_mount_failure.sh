#!/bin/bash
# ============================================================
# 故障注入: NFS mount 挂载失败
# 方式: 用 iptables 在 server 侧阻断 NFS 端口 (2049)
# 工具: iptables（内核内置，无需额外安装）
# ============================================================
set -euo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SELF_DIR/../lib/common.sh"

check_env

print_scenario_header "Branch A" "NFS mount 挂载失败 — 屏蔽 server 2049 端口"

# 确认当前没有 NFS 挂载
if exec_cli "mountpoint -q ${MOUNT_DIR}" 2>/dev/null; then
    warn "NFS 已挂载，先卸载..."
    nfs_umount
fi

# Step 1: 在 server 侧阻断 2049 端口
info "Step 1/2: 在 NFS Server 侧阻断端口 2049..."
exec_srv "iptables -A INPUT -p tcp --dport 2049 -j DROP"
# 也阻断 111 (rpcbind) 以模拟更彻底的不可达
exec_srv "iptables -A INPUT -p tcp --dport 111 -j DROP"
exec_srv "iptables -A INPUT -p udp --dport 2049 -j DROP"
exec_srv "iptables -A INPUT -p udp --dport 111 -j DROP"
ok "端口 2049/111 (TCP/UDP) 已屏蔽"

# Step 2: 验证屏蔽生效
info "Step 2/2: 验证阻断..."
SERVER_IP=$(get_server_ip)
info "Server IP: ${SERVER_IP}"

# 从客户端测试连通性
echo ""
echo "  ┌─ 测试报告 ─────────────────────────────────┐"
echo "  │  以下连接应全部失败：                        │"
echo "  ├─────────────────────────────────────────────┤"

if exec_cli "timeout 3 nc -zv ${SERVER_HOST} 2049 2>&1" 2>/dev/null; then
    echo "  │  ⚠️  port 2049: 可达 (阻断可能未生效)       │"
else
    echo "  │  ✅ port 2049: 不可达 (已阻断)              │"
fi

if exec_cli "timeout 3 nc -zv ${SERVER_HOST} 111 2>&1" 2>/dev/null; then
    echo "  │  ⚠️  port 111: 可达 (阻断可能未生效)        │"
else
    echo "  │  ✅ port 111: 不可达 (已阻断)               │"
fi

echo "  └─────────────────────────────────────────────┘"

print_injection_result "NFS Server 端口 2049/111 (TCP/UDP) 被 iptables 屏蔽，客户端 mount 将超时/失败"

echo "预期诊断脚本:"
echo "  bash /diagnosis-scripts/branch_A_mount_failure.sh ${SERVER_HOST} /exports"
echo ""
