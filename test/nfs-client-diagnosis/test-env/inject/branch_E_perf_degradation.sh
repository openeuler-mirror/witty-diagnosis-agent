#!/bin/bash
# ============================================================
# 故障注入: NFS 性能退化 (RTT 飙升/重传)
# 方式: 用 tc (traffic control) 在客户端添加网络延迟+抖动+丢包
# 工具: tc (iproute2)
# ============================================================
set -euo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SELF_DIR/../lib/common.sh"

check_env

print_scenario_header "Branch E" "NFS 性能退化 — tc 注入网络延迟/抖动/丢包"

# Step 1: 先清理可能残留的 tc 规则
tc_del "eth0"

# Step 2: 挂载 NFS
info "Step 1/3: 挂载 NFS..."
nfs_mount "vers=4.2,hard,timeo=600,retrans=3" || {
    warn "NFSv4.2 挂载失败，尝试 v4.0..."
    nfs_mount "vers=4.0,hard,timeo=600,retrans=3" || {
        err "NFS 挂载失败"
        exit 1
    }
}

# 先建立正常基线
info "  记录正常延迟基线..."
exec_cli "timeout 5 ping -c 3 ${SERVER_HOST} 2>&1 | tail -3"

# Step 3: 注入 tc 延迟
info "Step 2/3: 用 tc 注入网络延迟 + 抖动..."
# 添加 400ms 延迟 + 100ms 抖动 + 2% 丢包
tc_add_latency "eth0" "400ms" "100ms" "2"
sleep 1
ok "tc 规则已生效: eth0 delay=400ms jitter=100ms loss=2%"

# Step 4: 验证延迟效果
info "Step 3/3: 验证延迟效果..."
echo ""
echo "  ┌─ 网络质量 ──────────────────────────────────┐"
PING_RESULT=$(exec_cli "timeout 5 ping -c 3 ${SERVER_HOST} 2>&1" 2>/dev/null || echo "(ping 超时)")
echo "  │  ${PING_RESULT//$'\n'/$'\n  │  '}"
echo "  └─────────────────────────────────────────────┘"
echo ""
echo "  NFS 操作延迟将显著增高 (RTT 飙升)"
echo "  nfsstat -r 中将出现 retrans 增长"
echo "  mountstats 中的 RPC RTT 将反映高延迟"

print_injection_result "tc netem 注入 400ms 延迟 + 100ms 抖动 + 2% 丢包，NFS 操作 RTT 飙升/重传"

echo "预期诊断脚本:"
echo "  bash /diagnosis-scripts/branch_E_perf_degradation.sh ${MOUNT_DIR} ${SERVER_HOST}"
echo ""
