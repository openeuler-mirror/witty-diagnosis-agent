#!/bin/bash
# ============================================================
# 故障注入: Soft/Hard Mount 超时行为差异
# 方式: hard mount 后，用 iptables 阻断客户端到服务端的
#        NFS 连接（port 2049），模拟 server 不可达
# 工具: iptables, mount
# ============================================================
set -euo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SELF_DIR/../lib/common.sh"

check_env

print_scenario_header "Branch F" "Hard Mount 超时 — 挂载后阻断 NFS 连接"

# Step 1: 挂载 NFS (hard mode)
info "Step 1/3: 挂载 NFS (hard mode)..."
nfs_mount "vers=4.2,hard,timeo=70,retrans=1" || {
    warn "NFSv4.2 挂载失败，尝试 v4.0..."
    nfs_mount "vers=4.0,hard,timeo=70,retrans=1" || {
        err "NFS 挂载失败"
        exit 1
    }
}
ok "NFS 已挂载 (hard, timeo=7s, retrans=1)"

# 在 mount 上做一些操作确认正常
exec_cli "touch ${MOUNT_DIR}/timeout-test.txt && echo 'ok' > ${MOUNT_DIR}/timeout-test.txt"
ok "挂载读写正常"

# Step 2: 阻断 NFS 连接
info "Step 2/3: 在客户端侧阻断到 NFS Server 2049 端口的出站流量..."
exec_cli "iptables -A OUTPUT -p tcp --dport 2049 -j DROP"
exec_cli "iptables -A OUTPUT -p udp --dport 2049 -j DROP"
sleep 1
ok "出站 NFS 流量已阻断"

# Step 3: 触发超时 — 在后台发起 IO 操作
info "Step 3/3: 触发 NFS 超时操作..."
echo ""
echo "  执行挂载点操作（将触发超时）："

# 在后台执行读写操作（会卡住进入 D 状态）
exec_cli 'timeout 15 ls ${MOUNT_DIR} 2>&1 || true' &
LS_PID=$!
echo "  等待 RPC 超时触发 (timeo=7s, retrans=1)..."
sleep 12
kill $LS_PID 2>/dev/null || true
wait $LS_PID 2>/dev/null || true

echo ""
echo "  ┌─ 超时行为观察 ─────────────────────────────┐"
D_PROCS=$(exec_cli "ps -eo pid,stat,wchan:30,cmd 2>/dev/null | grep ' D ' | head -5" 2>/dev/null || echo "(无)")
if [ -n "$D_PROCS" ]; then
    echo "  │  D 状态进程 (NFS 相关):                    │"
    while IFS= read -r line; do
        echo "  │  ${line:0:56}│"
    done <<< "$D_PROCS"
else
    echo "  │  当前无 D 状态进程                         │"
    echo "  │  (超时可能已返回 EIO 或操作尚在进行中)     │"
fi
echo "  └─────────────────────────────────────────────┘"
echo ""
echo "  如果使用 hard mount: 进程将进入 D 状态不可杀"
echo "  如果使用 soft mount: 操作返回 EIO 给应用层"

print_injection_result "NFS hard mount 后阻断网络，触发 RPC 超时 → D 状态进程或 EIO 返回"

echo "预期诊断脚本:"
echo "  bash /diagnosis-scripts/branch_F_mount_timeout.sh ${MOUNT_DIR}"
echo ""
