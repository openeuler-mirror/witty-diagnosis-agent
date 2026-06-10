#!/bin/bash
# 不使用 set -e，手动处理错误

echo "=== NFS Server 容器启动 ==="
echo "时间: $(date -Iseconds)"

# 创建测试目录
mkdir -p /exports/{stale-test,perf-test,mount-test}

# /etc/exports 由 Dockerfile 中的 COPY 提供, 确保存在
exportfs -ra 2>/dev/null || true

# ── 1. 启动 rpcbind ──
echo "[1/4] 启动 rpcbind..."
# 在 Docker 中 service 命令可能不起作用, 直接运行 rpcbind
/sbin/rpcbind 2>/dev/null || /usr/sbin/rpcbind 2>/dev/null || true
if ! rpcinfo -p localhost 2>/dev/null | grep -q rpcbind; then
    echo "  直接启动 rpcbind..."
    rpcbind -f &
    sleep 2
fi

# ── 2. 启动 nfsd ──
echo "[2/4] 启动 NFS 内核守护进程 (rpc.nfsd)..."
# 先检查是否已有 nfsd 内核线程
if rpcinfo -p localhost 2>/dev/null | grep -q nfs; then
    echo "  nfsd 已运行"
else
    rpc.nfsd 8 2>/dev/null || echo "⚠️  rpc.nfsd 启动失败 (宿主机可能不支持 NFS 内核模块)"
    sleep 1
fi

# ── 3. 启动 mountd ──
echo "[3/4] 启动 mountd (rpc.mountd)..."
if rpcinfo -p localhost 2>/dev/null | grep -q mountd; then
    echo "  mountd 已运行"
else
    rpc.mountd -F &
    sleep 2
fi

# ── 4. 重新导出 ──
echo "[4/4] 重新导出 NFS 目录..."
exportfs -ra 2>&1
exportfs -v 2>&1 | head -5
echo ""

# ── 验证状态 ──
echo "=== NFS Server 状态 ==="
rpcinfo -p localhost 2>/dev/null || echo "⚠️  rpcinfo 查询失败"

echo ""
if rpcinfo -p localhost 2>/dev/null | grep -qE 'nfs|mountd'; then
    echo "✅ NFS Server 就绪"
else
    echo "⚠️  NFS 服务未完全注册，请检查宿主机是否支持 NFS"
fi
echo ""

# 保持容器运行
trap "echo '关闭 NFS 服务...'; rpc.nfsd 0 2>/dev/null; exit 0" SIGTERM SIGINT
while true; do sleep 3600 & wait; done
