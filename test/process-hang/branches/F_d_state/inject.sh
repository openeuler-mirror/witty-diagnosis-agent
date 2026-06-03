#!/bin/bash
set -euo pipefail

IMAGE_NAME="fault-injection-base:latest"
SERVER="nfs-server-dstate"
CLIENT="process-hang-branch-f"

# 清理旧容器
docker rm -f "$SERVER" "$CLIENT" 2>/dev/null || true

echo "[INJECT] 启动 NFS 服务端 ..."
docker run -d --name "$SERVER" --rm --privileged \
    "$IMAGE_NAME" \
    sh -c '
        mkdir -p /exports
        echo "D-State Test File for NFS hard-mount" > /exports/test.txt
        echo "/exports *(rw,sync,no_subtree_check,no_root_squash,fsid=0)" > /etc/exports
        rpcbind -s
        /usr/sbin/rpc.statd
        exportfs -r
        rpc.nfsd 8
        echo "NFS server PID: $$"
        tail -f /dev/null
    '

sleep 3
NFS_IP=$(docker inspect --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$SERVER" 2>/dev/null || \
         docker inspect --format '{{.NetworkSettings.IPAddress}}' "$SERVER" 2>/dev/null)
echo "[INJECT] NFS Server IP: $NFS_IP"

echo "[INJECT] 启动 NFS 客户端 (hard mount) ..."
CLIENT_ID=$(docker run -d --name "$CLIENT" --rm --privileged --cap-add=SYS_PTRACE \
    "$IMAGE_NAME" \
    sh -c "
        mkdir -p /mnt/nfs
        echo 'Mounting NFS $NFS_IP:/exports ...'
        mount -t nfs4 -o hard,nointr,timeo=600,retrans=1 $NFS_IP:/ /mnt/nfs
        echo 'Mount exit code: \$?'
        ls -la /mnt/nfs/
        echo '=== NFS hard mount ready ==='
        echo 'Accessing file to trigger D state...'
        cat /mnt/nfs/test.txt &
        CAT_PID=\$!
        echo 'cat PID: \$CAT_PID'
        sleep 2
        echo 'Killing NFS server to trigger D state...'
        umount -l /mnt/nfs 2>/dev/null || true
        sleep 3
        echo '=== D state check ==='
        for p in /proc/[0-9]*/status; do
            grep -q 'State:D' \"\$p\" 2>/dev/null && echo \"D_PID=\$(basename \$(dirname \$p)) wchan=\$(cat /proc/\$(basename \$(dirname \$p))/wchan 2>/dev/null)\" >> /tmp/dstate_result
        done
        cat /tmp/dstate_result 2>/dev/null || echo 'No D state detected'
        tail -f /dev/null
    ")

sleep 10

echo ""
echo "=== D 状态检测 ==="
docker exec "$CLIENT" sh -c '
for p in /proc/[0-9]*/status; do
    grep -q "State:D" "$p" 2>/dev/null || continue
    pid=$(basename "$(dirname "$p")" 2>/dev/null)
    echo ">>> D状态进程: PID=$pid Name=$(grep Name $p | awk "{print \$2}") wchan=$(cat /proc/$pid/wchan 2>/dev/null)"
done
echo "---所有进程---"
for p in /proc/[0-9]*/status; do
    pid=$(basename "$(dirname "$p")" 2>/dev/null)
    echo "PID=$pid Name=$(grep Name $p | awk "{print \$2}") State=$(grep State $p | awk "{print \$2}") wchan=$(cat /proc/$pid/wchan 2>/dev/null)"
done
' 2>/dev/null|| echo "检查失败"

# 如果检测到 D 状态，收集诊断数据
D_PID=$(docker exec "$CLIENT" sh -c '
for p in /proc/[0-9]*/status; do
    grep -q "State:D" "$p" 2>/dev/null || continue
    basename "$(dirname "$p")"
done' 2>/dev/null | head -1)

DOCKER_EXEC="docker exec $CLIENT"
echo ""
echo "================================================"
echo "  故障注入完成: Branch F — D 状态阻塞"
echo "================================================"
echo "  NFS服务端:  $SERVER"
echo "  客户端容器: $CLIENT"
if [ -n "$D_PID" ]; then
echo "  D状态PID:   $D_PID (容器内)"
fi
echo "================================================"
echo "  诊断命令 (通过 docker exec):"
echo "  $DOCKER_EXEC cat /proc/1/wchan"
echo "  $DOCKER_EXEC cat /proc/1/status | grep State"
echo "================================================"

# 如果有 D 状态，自动收集诊断数据
if [ -n "$D_PID" ]; then
    DIAG_DIR="/tmp/opencode/test_branch_f"
    mkdir -p "$DIAG_DIR/proc"
    docker exec "$CLIENT" cat /proc/$D_PID/status > "$DIAG_DIR/proc/status" 2>/dev/null || true
    docker exec "$CLIENT" cat /proc/$D_PID/wchan > "$DIAG_DIR/proc/wchan" 2>/dev/null || true
    echo ""
    echo "=== 诊断数据已保存到 $DIAG_DIR ==="
    echo "State: $(grep State $DIAG_DIR/proc/status 2>/dev/null)"
    echo "wchan: $(cat $DIAG_DIR/proc/wchan 2>/dev/null)"
fi
