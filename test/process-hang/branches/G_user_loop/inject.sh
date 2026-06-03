#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FAULT_DIR="$(dirname "$SCRIPT_DIR")"
COMMON_DIR="$FAULT_DIR/common"
IMAGE_NAME="fault-injection-base:latest"
CONTAINER_NAME="process-hang-branch-g"
MODE="${1:-cpu}"

if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
    echo "[BUILD] 构建基础镜像 $IMAGE_NAME ..."
    docker build -t "$IMAGE_NAME" "$COMMON_DIR"
fi

if [ "$MODE" = "cpu" ]; then
    CONTAINER_ID=$(docker run -d \
        --name "$CONTAINER_NAME" --rm \
        --cap-add=SYS_PTRACE \
        "$IMAGE_NAME" \
        sh -c 'echo "PID: $$"; for i in $(seq 1 4); do while :; do :; done & done; while :; do :; done')
elif [ "$MODE" = "idle" ]; then
    CONTAINER_ID=$(docker run -d \
        --name "$CONTAINER_NAME" --rm \
        --cap-add=SYS_PTRACE \
        "$IMAGE_NAME" \
        sh -c 'echo "PID: $$"; while true; do for i in $(seq 1 100); do x=$((i*i)); done; sleep 2; done')
fi

sleep 2
DOCKER_EXEC="docker exec $CONTAINER_NAME"

echo ""
echo "================================================"
echo "  故障注入完成: Branch G — 用户态死循环 (模式: $MODE)"
echo "================================================"
echo "  容器名:     $CONTAINER_NAME"
echo "  容器ID:     $CONTAINER_ID"
echo "================================================"
echo "  诊断命令 (通过 docker exec):"
echo "  $DOCKER_EXEC cat /proc/1/status | grep State"
echo "  $DOCKER_EXEC cat /proc/1/wchan"
echo "  $DOCKER_EXEC top -b -n 1 -p 1"
echo "================================================"
