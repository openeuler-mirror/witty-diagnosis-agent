#!/bin/bash
# ============================================================
# 故障注入: rpc.statd / lockd 异常
# 方式: 杀掉客户端 rpc.statd 进程
# 工具: pkill/kill (procps)
# ============================================================
set -euo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SELF_DIR/../lib/common.sh"

check_env

print_scenario_header "Branch D" "rpc.statd / lockd 异常 — 杀掉客户端 rpc.statd 进程"

# Step 1: 挂载 NFS
info "Step 1/3: 挂载 NFS..."
nfs_mount "vers=3,hard,timeo=600,retrans=2" || {
    err "NFS 挂载失败"
    exit 1
}

# 确认 statd 当前状态
info "Step 2/3: 记录当前 statd 状态..."
EXISTING_PIDS=$(exec_cli "pgrep -x rpc.statd 2>/dev/null || true" 2>/dev/null)
if [ -n "$EXISTING_PIDS" ]; then
    info "当前 rpc.statd PID: ${EXISTING_PIDS}"
else
    warn "当前 rpc.statd 未运行（在某些环境中 statd 由 rpcbind 按需启动）"
fi

# 杀掉 statd
info "Step 3/3: 终止 rpc.statd..."
exec_cli 'pkill -9 rpc.statd 2>/dev/null; pkill -9 rpcbind 2>/dev/null; true'
sleep 1

# 验证
echo ""
echo "  ┌─ 验证 ──────────────────────────────────────┐"
REMAINING=$(exec_cli "pgrep rpc.statd 2>/dev/null || echo '(无运行中)'" 2>/dev/null)
echo "  │  rpc.statd 进程: ${REMAINING}            │"
echo "  │  NLM 锁服务注册将丢失                       │"
echo "  └─────────────────────────────────────────────┘"

print_injection_result "客户端 rpc.statd 进程被 kill，锁服务(NLM)不可用，文件锁操作将受影响"

echo "预期诊断脚本:"
echo "  bash /diagnosis-scripts/branch_D_rpc_lockd.sh ${SERVER_HOST}"
echo ""
