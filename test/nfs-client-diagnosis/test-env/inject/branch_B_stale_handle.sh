#!/bin/bash
# ============================================================
# 故障注入: Stale File Handle (ESTALE) — v2 改进版
# 方式: 
#   1. 客户端后台进程持有文件 fd
#   2. 服务端删除文件并重启 NFS 服务，彻底释放 inode
#   3. 通过 /proc/PID/fd/ 跨进程访问旧句柄 → ESTALE
# 工具: exec, rm, rpc.nfsd, exportfs
# ============================================================
set -euo pipefail
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SELF_DIR/../lib/common.sh"

check_env

print_scenario_header "Branch B" "Stale File Handle (ESTALE) — 服务端删除文件+重启NFSD 触发句柄过期"

# 清理可能残留的旧测试数据
exec_srv "rm -rf /exports/stale-test && mkdir -p /exports/stale-test"

# Step 1: 挂载 NFS (v3 避免 v4 lease 干扰)
info "Step 1/4: 挂载 NFS (vers=3)..."
nfs_mount "vers=3,hard,timeo=600,retrans=2" || {
    err "NFS 挂载失败"
    exit 1
}

# Step 2: 在服务端创建测试文件
info "Step 2/4: 创建测试文件并启动 fd holder 进程..."
TEST_FILE="persist.txt"
exec_srv "echo 'STALE_TEST_DATA_$(date +%s)' > /exports/stale-test/${TEST_FILE}"

# 在客户端启动后台进程：打开并持有 fd，记录 PID
HOLDER_SCRIPT="
exec 200>${MOUNT_DIR}/stale-test/${TEST_FILE}
echo 'held-data-\$(date +%s)' >&200
echo \$BASHPID > /tmp/stale_holder_pid
sleep 60
"
exec_cli_detach() {
    docker exec -d "$CLIENT_CONTAINER" bash -c "$1" 2>/dev/null
}
exec_cli_detach "$HOLDER_SCRIPT"
sleep 2

# 读取 holder PID
HOLDER_PID=$(exec_cli "cat /tmp/stale_holder_pid 2>/dev/null" 2>/dev/null) || {
    err "无法获取 holder PID"
    exit 1
}
info "Holder 进程 PID: ${HOLDER_PID}"

# 验证 fd 已打开
if exec_cli "ls -la /proc/${HOLDER_PID}/fd/200 2>/dev/null" | grep -q "$TEST_FILE"; then
    ok "文件描述符 fd 200 已打开并持有可能 ✅"
else
    warn "fd 200 可能未正确打开，继续尝试..."
fi

# Step 3: 服务端删除文件并重启 NFS 服务（彻底释放 inode）
info "Step 3/4: 服务端删除文件并重启 NFS 服务（释放 inode）..."
exec_srv "rm -f /exports/stale-test/${TEST_FILE}"
exec_srv "sync"
sleep 1
exec_srv "rpc.nfsd 0 2>/dev/null; sleep 1"
exec_srv "rpc.nfsd 8 2>/dev/null; sleep 1"
exec_srv "rpc.mountd -F & 2>/dev/null; sleep 2"
exec_srv "exportfs -ra 2>/dev/null"
ok "NFS Server 已重启，旧 inode 已释放"

# Step 4: 通过 /proc/PID/fd/ 触发 ESTALE
info "Step 4/4: 通过 /proc/PID/fd/ 访问旧句柄触发 ESTALE..."
echo ""
echo "  ┌─ ESTALE 触发结果 ─────────────────────────┐"
ESTALE_RESULT=$(exec_cli "timeout 3 cat /proc/${HOLDER_PID}/fd/200" 2>&1) || true
if echo "$ESTALE_RESULT" | grep -qi "stale"; then
    echo "  │  ❌ cat: /proc/${HOLDER_PID}/fd/200:        │"
    echo "  │     Stale file handle                       │"
    echo "  │                                             │"
    echo "  │  ✅ ESTALE 错误成功触发！                    │"
elif [ -z "$ESTALE_RESULT" ]; then
    echo "  │  ⚠️  无错误输出（可能 fd 已关闭或未被持有）  │"
else
    echo "  │  输出: ${ESTALE_RESULT:0:50}│"
fi
echo "  └─────────────────────────────────────────────┘"

# 清理 holder 进程
exec_cli "kill ${HOLDER_PID} 2>/dev/null; true" 2>/dev/null || true

print_injection_result "NFS 服务端删除文件+重启NFSD → 旧文件句柄过期 → 跨进程 /proc/PID/fd/ 访问触发 ESTALE"

echo "预期诊断脚本:"
echo "  bash /diagnosis-scripts/branch_B_stale_handle.sh ${MOUNT_DIR} ${MOUNT_DIR}/stale-test/${TEST_FILE}"
echo ""
