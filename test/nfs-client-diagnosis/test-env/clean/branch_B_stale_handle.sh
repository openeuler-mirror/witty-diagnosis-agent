#!/bin/bash
# ============================================================
# 清理: Stale File Handle
# ============================================================
set -euo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SELF_DIR/../lib/common.sh"

check_env 2>/dev/null || { warn "环境未运行，无需清理"; exit 0; }

header
echo "  清理: Branch B — 重置 Stale File Handle 测试环境"
header

info "Step 1/3: 终止 fd holder 进程并清理文件描述符..."
exec_cli 'pkill -f "sleep 60" 2>/dev/null; true'
exec_cli 'rm -f /tmp/stale_holder_pid 2>/dev/null; true'
exec_cli 'for fd in 200 201 202; do exec '"\$fd"'<&- 2>/dev/null; done; true'
ok "文件描述符已清理"

info "Step 2/3: 卸载 NFS 挂载..."
nfs_umount

info "Step 3/3: 重置服务端测试目录..."
exec_srv "rm -rf /exports/stale-test && mkdir -p /exports/stale-test"
ok "服务端目录已重置"

echo ""
ok "✅ 环境已恢复"
echo ""
