#!/bin/bash
# ============================================================
# teardown.sh — 停止并清理 NFS 故障注入测试环境
# 用法: bash teardown.sh [--volumes]
#   --volumes: 同时删除数据卷
# ============================================================
set -euo pipefail

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "═══════════════════════════════════════════"
echo "  NFS 故障注入测试环境 — 停止"
echo "═══════════════════════════════════════════"

cd "$SELF_DIR"

# 检查容器是否存在再执行清理
if docker ps --format '{{.Names}}' | grep -q "nfs-fault-client" 2>/dev/null; then
    echo "卸载客户端挂载..."
    docker exec nfs-fault-client bash -c 'umount -f /mnt/nfs-test 2>/dev/null; umount -l /mnt/nfs-test 2>/dev/null; true'
fi

# 停止容器
echo "停止容器..."
docker compose down --timeout 30

# 删除数据卷
if [ "${1:-}" = "--volumes" ]; then
    echo "删除数据卷..."
    docker compose down -v
fi

echo ""
echo "✅ 环境已清理"
echo ""
