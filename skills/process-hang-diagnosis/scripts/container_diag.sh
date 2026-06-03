#!/bin/bash
# container_diag.sh — 将诊断脚本复制到容器内执行，复制结果回宿主机
# 用法: container_diag.sh <容器名> <脚本路径> <PID> [工作目录]
set -euo pipefail
[ $# -lt 3 ] && { echo "用法: $0 <容器名> <脚本路径> <PID> [工作目录]"; exit 1; }
CONTAINER="$1"; SCRIPT="$2"; PID="$3"
WORK_DIR="${4:-/tmp/hang_diag_${PID}}"
docker inspect "$CONTAINER" &>/dev/null || { echo "[ERROR] 容器 $CONTAINER 不可用"; exit 1; }
[ -f "$SCRIPT" ] || { echo "[ERROR] 脚本 $SCRIPT 不存在"; exit 1; }
docker exec "$CONTAINER" mkdir -p "$WORK_DIR" 2>/dev/null || true
SNAME=$(basename "$SCRIPT")
docker cp "$SCRIPT" "$CONTAINER:/tmp/$SNAME"
docker exec "$CONTAINER" chmod +x "/tmp/$SNAME"
echo "[container_diag] 容器=$CONTAINER 脚本=$SNAME PID=$PID"
docker exec "$CONTAINER" bash "/tmp/$SNAME" "$PID" "$WORK_DIR"
RC=$?
HOST_OUT="/tmp/cdiag_${CONTAINER}_$(date +%Y%m%d%H%M%S)"
mkdir -p "$HOST_OUT"
docker cp "$CONTAINER:$WORK_DIR/." "$HOST_OUT/" 2>/dev/null || true
echo "[container_diag] 完成 exit=$RC 结果=$HOST_OUT"
exit $RC
