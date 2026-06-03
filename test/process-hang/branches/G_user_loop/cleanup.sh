#!/bin/bash
#
# cleanup.sh — Branch G: 清理用户态死循环故障容器
#
set -euo pipefail

CONTAINER_NAME="process-hang-branch-g"

if docker ps --filter "name=$CONTAINER_NAME" --format '{{.Names}}' | grep -q "$CONTAINER_NAME"; then
    echo "[CLEANUP] 停止并删除容器 $CONTAINER_NAME ..."
    docker kill "$CONTAINER_NAME" 2>/dev/null || true
    echo "[CLEANUP] 完成"
else
    echo "[CLEANUP] 容器 $CONTAINER_NAME 未在运行"
fi
