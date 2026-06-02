#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FAULT_DIR="$(dirname "$SCRIPT_DIR")"
COMMON_DIR="$FAULT_DIR/common"
IMAGE_NAME="fault-injection-base:latest"
CONTAINER_NAME="process-hang-branch-d"
MODE="${1:-read}"

if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
    echo "[BUILD] 构建基础镜像 $IMAGE_NAME ..."
    docker build -t "$IMAGE_NAME" "$COMMON_DIR"
fi

echo "[BUILD] 编译 pipe_block.c ..."
docker run --rm \
    -v "$SCRIPT_DIR/src:/src" -w /src \
    "$IMAGE_NAME" gcc -O0 -g -o /src/pipe_block pipe_block.c

echo "[INJECT] 启动管道阻塞故障容器 (模式: $MODE) ..."
CONTAINER_ID=$(docker run -d \
    --name "$CONTAINER_NAME" --rm \
    --cap-add=SYS_PTRACE \
    -v "$SCRIPT_DIR/src:/workspace" -w /workspace \
    "$IMAGE_NAME" ./pipe_block "$MODE")

sleep 3
DOCKER_EXEC="docker exec $CONTAINER_NAME"
CHILD_PID=""
if [ "$MODE" = "read" ]; then
    CHILD_PID=$($DOCKER_EXEC sh -c 'ps -o pid= --ppid 1 2>/dev/null | head -1 | tr -d " "' 2>/dev/null || echo "")
fi

echo ""
echo "================================================"
echo "  故障注入完成: Branch D — 管道阻塞 (模式: $MODE)"
echo "================================================"
echo "  容器名:     $CONTAINER_NAME"
echo "  容器ID:     $CONTAINER_ID"
echo "  入口进程:   PID 1（容器入口）"
if [ -n "$CHILD_PID" ]; then
echo "  阻塞子进程: PID $CHILD_PID (pipe_read 阻塞)"
fi
echo "================================================"
echo "  诊断命令 (通过 docker exec):"
echo "  $DOCKER_EXEC cat /proc/1/wchan"
echo "  $DOCKER_EXEC ls -la /proc/1/fd/ | grep pipe"
echo "  $DOCKER_EXEC sh -c 'find /proc/*/fd -lname \"pipe:*\" 2>/dev/null'"
if [ -n "$CHILD_PID" ]; then
echo "  $DOCKER_EXEC cat /proc/$CHILD_PID/wchan"
fi
echo "================================================"
