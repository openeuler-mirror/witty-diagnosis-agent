#!/bin/bash
set -e

echo "=== NFS Client 容器启动 ==="
echo "时间: $(date -Iseconds)"

# 启动 rpcbind
echo "[1/3] 启动 rpcbind..."
if ! service rpcbind start 2>/dev/null; then
    rpcbind -f &
    sleep 1
fi

# 创建挂载点
echo "[2/3] 创建挂载点 /mnt/nfs-test..."
mkdir -p /mnt/nfs-test

# 检查可用工具
echo "[3/3] 工具检查..."
for cmd in mount.nfs nfsstat rpcinfo showmount ip iptables tc bc; do
    if command -v $cmd &>/dev/null; then
        echo "  ✅ $cmd 可用"
    else
        echo "  ⚠️  $cmd 不可用"
    fi
done

echo ""
echo "=== NFS Client 就绪 ==="
echo "诊断脚本目录: /diagnosis-scripts (只读挂载)"
echo "挂载点: /mnt/nfs-test"
echo ""

# 保持容器运行
trap "exit 0" SIGTERM SIGINT
while true; do sleep 3600 & wait; done
