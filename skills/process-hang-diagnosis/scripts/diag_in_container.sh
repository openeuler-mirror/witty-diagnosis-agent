#!/bin/bash
#
# diag_in_container.sh — 在 Docker 容器内执行诊断脚本的包装器
#
# 解决: 嵌套容器环境中 /proc/<pid> 不可见的问题
# 原理: 将诊断脚本复制到容器内执行，直接访问容器内的 /proc
#
# 用法:
#   # 基线信息采集
#   bash diag_in_container.sh <容器名> 01_baseline_info.sh <容器内PID> [work_dir]
#
#   # 分支诊断
#   bash diag_in_container.sh <容器名> branch_X_xxx.sh <容器内PID> [work_dir]
#
# 示例:
#   bash diag_in_container.sh process-hang-branch-g \
#     /home/win11/.config/opencode/skills/process-hang-diagnosis/scripts/01_baseline_info.sh \
#     1
#
set -euo pipefail

if [ $# -lt 3 ]; then
    echo "用法: $0 <容器名> <诊断脚本路径> <容器内PID> [work_dir]"
    echo "示例: $0 process-hang-branch-g ./01_baseline_info.sh 1"
    exit 1
fi

CONTAINER="$1"
SCRIPT="$2"
PID="$3"
WORK_DIR="${4:-/tmp/hang_diag_${PID}}"

# 验证容器存在
if ! docker inspect "$CONTAINER" &>/dev/null; then
    echo "[ERROR] 容器 $CONTAINER 不存在或未运行"
    exit 1
fi

# 验证脚本存在
if [ ! -f "$SCRIPT" ]; then
    echo "[ERROR] 脚本 $SCRIPT 不存在"
    exit 1
fi

# 在容器内创建工作目录
docker exec "$CONTAINER" mkdir -p "$WORK_DIR"

# 复制脚本到容器内
SCRIPT_NAME=$(basename "$SCRIPT")
docker cp "$SCRIPT" "$CONTAINER:/tmp/$SCRIPT_NAME"
docker exec "$CONTAINER" chmod +x "/tmp/$SCRIPT_NAME"

echo "================================================"
echo " 在容器 $CONTAINER 中执行诊断脚本"
echo " 脚本: $SCRIPT_NAME"
echo " PID:  $PID"
echo " 目录: $WORK_DIR"
echo "================================================"

# 在容器内执行诊断脚本
docker exec "$CONTAINER" \
    bash "/tmp/$SCRIPT_NAME" "$PID" "$WORK_DIR"

EXIT_CODE=$?

# 将诊断结果复制回主机
HOST_OUTPUT_DIR="/tmp/container_diag_${CONTAINER}_$(date +%Y%m%d%H%M%S)"
mkdir -p "$HOST_OUTPUT_DIR"
docker cp "$CONTAINER:$WORK_DIR/." "$HOST_OUTPUT_DIR/" 2>/dev/null || true

echo ""
echo "================================================"
echo " 诊断完成 (exit=$EXIT_CODE)"
echo " 容器内结果: $WORK_DIR"
echo " 主机副本:   $HOST_OUTPUT_DIR"
echo "================================================"
