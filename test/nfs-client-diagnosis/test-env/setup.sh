#!/bin/bash
# ============================================================
# setup.sh — 启动 NFS 故障注入测试环境
# 用法: bash setup.sh [build]
#   build: 强制重新构建镜像
# ============================================================
set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SELF_DIR/lib/common.sh"

REBUILD="${1:-}"

echo ""
header
echo "  NFS 故障注入测试环境 — 启动"
header

# 检查 Docker
if ! command -v docker &>/dev/null; then
    err "Docker 未安装"
    exit 1
fi

# 构建并启动
cd "$SELF_DIR"
if [ "$REBUILD" = "build" ]; then
    info "强制重新构建镜像..."
    docker compose build --no-cache
fi

info "启动容器..."
docker compose up -d

# 等待容器运行
sleep 3
check_env 2>/dev/null || { err "容器启动失败"; exit 1; }

info "Server IP: $(get_server_ip)"
info "Client IP: $(get_client_ip)"

# 等待 NFS 服务就绪
wait_nfs_server 30 || {
    warn "NFS 服务可能未完全就绪，尝试查看日志..."
    docker compose logs nfs-server --tail 10
    exit 1
}

# 清理可能残留的 iptables 规则
iptables_clear_all

echo ""
header
echo "  NFS 故障注入测试环境就绪！"
header
echo ""
echo "可用场景:"
echo "  bash inject/branch_A_mount_failure.sh    — NFS mount 挂载失败"
echo "  bash inject/branch_B_stale_handle.sh     — Stale File Handle"
echo "  bash inject/branch_C_nfs4_lease.sh       — NFSv4 Lease 过期"
echo "  bash inject/branch_D_rpc_lockd.sh        — rpc.statd/lockd 异常"
echo "  bash inject/branch_E_perf_degradation.sh — 性能退化"
echo "  bash inject/branch_F_mount_timeout.sh    — Soft/Hard 超时"
echo ""
echo "清理环境:"
echo "  bash teardown.sh"
echo ""
