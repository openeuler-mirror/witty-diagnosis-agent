#!/bin/bash
#
# inject.sh — Branch A: futex 锁等待故障注入
#
# 注入方式: Docker 容器内运行多线程 mutex 竞争程序
# 故障特征: wchan=futex_wait_queue_me, State=S, 多线程排队
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FAULT_DIR="$(dirname "$SCRIPT_DIR")"
COMMON_DIR="$FAULT_DIR/common"
CONTAINER_NAME="process-hang-branch-a"
IMAGE_NAME="fault-injection-base:latest"

if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
    echo "[BUILD] 构建基础镜像 $IMAGE_NAME ..."
    docker build -t "$IMAGE_NAME" "$COMMON_DIR"
    echo "[BUILD] 镜像构建完成"
fi

echo "[BUILD] 编译 futex_contention.c ..."
docker run --rm \
    -v "$SCRIPT_DIR/src:/src" -w /src \
    "$IMAGE_NAME" gcc -O0 -g -pthread -o /src/futex_contention futex_contention.c -lpthread

echo "[INJECT] 启动 futex 锁等待故障容器 ..."
CONTAINER_ID=$(docker run -d \
    --name "$CONTAINER_NAME" --rm \
    --cap-add=SYS_PTRACE \
    -v "$SCRIPT_DIR/src:/workspace" -w /workspace \
    "$IMAGE_NAME" ./futex_contention)

sleep 2

DOCKER_EXEC="docker exec $CONTAINER_NAME"

echo ""
echo "================================================"
echo "  故障注入完成: Branch A — futex 锁等待"
echo "================================================"
echo "  容器名:    $CONTAINER_NAME"
echo "  容器ID:    $CONTAINER_ID"
echo "================================================"
echo "  诊断命令 (通过 docker exec):"
echo "  $DOCKER_EXEC cat /proc/1/wchan"
echo "  $DOCKER_EXEC cat /proc/1/status | grep State"
echo "  $DOCKER_EXEC ls /proc/1/task/ | wc -l"
echo "  $DOCKER_EXEC sh -c 'for t in /proc/1/task/*/status; do echo \"TID \$(basename \$(dirname \$t)) State=\$(grep ^State \$t 2>/dev/null)\"; done'"
echo "================================================"
