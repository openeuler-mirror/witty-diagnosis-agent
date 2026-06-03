#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FAULT_DIR="$(dirname "$SCRIPT_DIR")"
COMMON_DIR="$FAULT_DIR/common"
IMAGE_NAME="fault-injection-base:latest"
CONTAINER_NAME="process-hang-branch-b"

if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
    echo "[BUILD] 构建基础镜像 $IMAGE_NAME ..."
    docker build -t "$IMAGE_NAME" "$COMMON_DIR"
fi

echo "[BUILD] 编译 abba_deadlock.c ..."
docker run --rm \
    -v "$SCRIPT_DIR/src:/src" -w /src \
    "$IMAGE_NAME" gcc -O0 -g -pthread -o /src/abba_deadlock abba_deadlock.c -lpthread

echo "[INJECT] 启动 ABBA 死锁故障容器 ..."
CONTAINER_ID=$(docker run -d \
    --name "$CONTAINER_NAME" --rm \
    --cap-add=SYS_PTRACE \
    -v "$SCRIPT_DIR/src:/workspace" -w /workspace \
    "$IMAGE_NAME" ./abba_deadlock)

sleep 4
DOCKER_EXEC="docker exec $CONTAINER_NAME"

echo ""
echo "================================================"
echo "  故障注入完成: Branch B — ABBA 死锁"
echo "================================================"
echo "  容器名:    $CONTAINER_NAME"
echo "  容器ID:    $CONTAINER_ID"
echo "================================================"
echo "  诊断命令 (通过 docker exec):"
echo "  $DOCKER_EXEC cat /proc/1/wchan"
echo "  线程状态:"
echo "  $DOCKER_EXEC sh -c 'for t in /proc/1/task/*/; do echo TID $(basename $t) wchan=$(cat $t/wchan); done'"
echo "  gdb 死锁验证:"
echo "  $DOCKER_EXEC gdb -batch -nx -ex \"thread apply all bt full\" -p 1"
echo "================================================"
