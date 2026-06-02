#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FAULT_DIR="$(dirname "$SCRIPT_DIR")"
COMMON_DIR="$FAULT_DIR/common"
IMAGE_NAME="fault-injection-base:latest"
CONTAINER_NAME="process-hang-branch-c"

if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
    echo "[BUILD] 构建基础镜像 $IMAGE_NAME ..."
    docker build -t "$IMAGE_NAME" "$COMMON_DIR"
fi

echo "[BUILD] 编译 filelock_contention.c ..."
docker run --rm \
    -v "$SCRIPT_DIR/src:/src" -w /src \
    "$IMAGE_NAME" gcc -O0 -g -o /src/filelock_contention filelock_contention.c

echo "[INJECT] 启动文件锁竞争故障容器 ..."
CONTAINER_ID=$(docker run -d \
    --name "$CONTAINER_NAME" --rm \
    --cap-add=SYS_PTRACE \
    -v "$SCRIPT_DIR/src:/workspace" -w /workspace \
    "$IMAGE_NAME" ./filelock_contention)

sleep 2
DOCKER_EXEC="docker exec $CONTAINER_NAME"
CHILD_PID=$($DOCKER_EXEC sh -c 'ps -o pid= --ppid 1 2>/dev/null | head -1 | tr -d " "' 2>/dev/null || echo "")

echo ""
echo "================================================"
echo "  故障注入完成: Branch C — 文件锁竞争"
echo "================================================"
echo "  容器名:     $CONTAINER_NAME"
echo "  容器ID:     $CONTAINER_ID"
echo "  父进程PID:  1（容器入口，持有写锁）"
echo "  子进程PID:  $CHILD_PID（阻塞等待读锁）"
echo "================================================"
echo "  诊断命令 (通过 docker exec):"
echo "  $DOCKER_EXEC cat /proc/locks"
echo "  $DOCKER_EXEC cat /proc/$CHILD_PID/wchan"
echo "  $DOCKER_EXEC cat /proc/$CHILD_PID/status | grep State"
echo "  $DOCKER_EXEC lslocks"
echo "================================================"
