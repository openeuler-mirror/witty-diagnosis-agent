#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FAULT_DIR="$(dirname "$SCRIPT_DIR")"
COMMON_DIR="$FAULT_DIR/common"
IMAGE_NAME="fault-injection-base:latest"
CONTAINER_NAME="process-hang-branch-e"
MODE="${1:-stop}"

if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
    echo "[BUILD] 构建基础镜像 $IMAGE_NAME ..."
    docker build -t "$IMAGE_NAME" "$COMMON_DIR"
fi

if [ "$MODE" = "stop" ]; then
    echo "[INJECT] 启动信号停止故障 (SIGSTOP) ..."
    CONTAINER_ID=$(docker run -d \
        --name "$CONTAINER_NAME" --rm \
        --cap-add=SYS_PTRACE \
        "$IMAGE_NAME" \
        sh -c '
            # 启动一个子进程作为目标（非 PID 1）
            sleep 9999 &
            TARGET=$!
            echo "TARGET_PID=$TARGET"
            echo "State=T (stopped) - 向目标进程发送 SIGSTOP"
            kill -STOP $TARGET
            echo "信号已发送"
            # 保持容器运行
            wait $TARGET
        ')
    sleep 2

    DOCKER_EXEC="docker exec $CONTAINER_ID"
    # 获取被停止的子进程 PID
    STOPPED_PID=$($DOCKER_EXEC sh -c 'ps -o pid= --ppid 1 2>/dev/null | head -1 | tr -d " "' 2>/dev/null || echo "")

    echo ""
    echo "================================================"
    echo "  故障注入完成: Branch E — 信号停止 (SIGSTOP)"
    echo "================================================"
    echo "  容器名:     $CONTAINER_NAME"
    echo "  容器ID:     $CONTAINER_ID"
    echo "  被停止PID:  $STOPPED_PID (State=T, SIGSTOP)"
    echo "================================================"
    echo "  诊断命令 (通过 docker exec):"
    echo "  $DOCKER_EXEC cat /proc/$STOPPED_PID/status | grep State"
    echo "  $DOCKER_EXEC cat /proc/$STOPPED_PID/wchan"
    echo "  $DOCKER_EXEC kill -CONT $STOPPED_PID   # 恢复进程"
    echo "================================================"

elif [ "$MODE" = "trace" ]; then
    echo "[INJECT] 启动 ptrace 跟踪故障 ..."
    CONTAINER_ID=$(docker run -d \
        --name "$CONTAINER_NAME" --rm \
        --cap-add=SYS_PTRACE \
        "$IMAGE_NAME" \
        sh -c 'sleep 9999 & TARGET=$!; echo "Target PID: $TARGET"; exec strace -p $TARGET -q -o /dev/null')
    sleep 2
    DOCKER_EXEC="docker exec $CONTAINER_ID"
    echo ""
    echo "================================================"
    echo "  故障注入完成: Branch E — ptrace 跟踪"
    echo "================================================"
    echo "  容器名:    $CONTAINER_NAME"
    echo "  容器ID:    $CONTAINER_ID"
    echo "================================================"
    echo "  诊断命令 (通过 docker exec):"
    echo "  $DOCKER_EXEC sh -c '\''ps aux | grep -E \"sleep|strace\" | grep -v grep'\''"
    echo "================================================"
fi
