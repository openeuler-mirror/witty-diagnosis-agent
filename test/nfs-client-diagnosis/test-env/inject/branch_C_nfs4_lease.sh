#!/bin/bash
# ============================================================
# 故障注入: NFSv4 Lease 过期 / State 恢复
# 方式: 重启 NFS Server 使客户端 lease/state 失效
# 工具: rpc.nfsd (nfs-kernel-server 自带)
# ============================================================
set -euo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SELF_DIR/../lib/common.sh"

check_env

print_scenario_header "Branch C" "NFSv4 Lease 过期 — 重启 NFS Server 使 state 失效"

# Step 1: 挂载 NFSv4
info "Step 1/3: 挂载 NFSv4..."
nfs_mount "vers=4.2,hard,timeo=600,retrans=2" || {
    # 降级到 v4.0 尝试
    warn "NFSv4.2 挂载失败，尝试 NFSv4.0..."
    nfs_mount "vers=4.0,hard,timeo=600,retrans=2" || {
        err "NFSv4 挂载失败"
        exit 1
    }
}

# 在挂载上做一些操作产生 state
info "  产生 NFSv4 state..."
exec_cli "touch ${MOUNT_DIR}/lease-test-1.txt && cat ${MOUNT_DIR}/lease-test-1.txt > /dev/null && rm -f ${MOUNT_DIR}/lease-test-1.txt"
sleep 2

# Step 2: 重启 NFS Server
info "Step 2/3: 在 Server 侧重启 NFS 服务..."
# 先记录当前的 nfsd 进程/线程数
exec_srv "NFSD_COUNT_BEFORE=\$(ps aux | grep nfsd | grep -v grep | wc -l); echo \"重启前 nfsd 线程数: \$NFSD_COUNT_BEFORE\""

# 停止 NFS 服务
exec_srv "rpc.nfsd 0 2>/dev/null; true"
sleep 1
# 关闭 mountd
exec_srv "pkill -9 rpc.mountd 2>/dev/null; true"
sleep 1

# 重启 NFS 服务
exec_srv "rpc.nfsd 8 2>/dev/null || warn 'rpc.nfsd 重启失败'"
exec_srv "rpc.mountd -F &"
sleep 2

# 重新导出
exec_srv "exportfs -ra 2>/dev/null; true"
ok "NFS Server 已重启"

# Step 3: 验证客户端 state 受影响
info "Step 3/3: 验证客户端 NFSv4 state 状态..."
echo ""

# 尝试访问以触发 state 恢复
exec_cli "timeout 5 ls ${MOUNT_DIR} 2>&1 || true"

echo "  ┌─ NFSv4 状态 ──────────────────────────────┐"
if exec_cli 'cat /proc/net/rpc/nfs4.0/clientid 2>/dev/null' 2>/dev/null | grep -q .; then
    echo "  │  clientid: 存在（可能有恢复尝试）          │"
else
    echo "  │  clientid: 已过期或不存在                  │"
fi
echo "  │  (详情见诊断脚本输出)                        │"
echo "  └─────────────────────────────────────────────┘"

print_injection_result "NFS Server 重启导致客户端 NFSv4 lease/state 过期，触发状态恢复流程"

echo "预期诊断脚本:"
echo "  bash /diagnosis-scripts/branch_C_nfs4_lease.sh ${MOUNT_DIR} ${SERVER_HOST}"
echo ""
