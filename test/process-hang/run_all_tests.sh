#!/bin/bash
# process-hang 故障注入全分支批量测试脚本
# 用法: bash run_all_tests.sh [分支名]  # 不指定则测试全部
set -euo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
BUILD_IMAGE=true
SINGLE="${1:-}"

# 构建基础镜像（首次运行需要）
if [ "$BUILD_IMAGE" = true ]; then
    echo "[SETUP] 构建基础镜像 fault-injection-base:latest ..."
    docker build -t fault-injection-base:latest "$BASE/common/" 2>&1 | tail -3
fi

test_branch() {
    local name="$1" dir="$2" extra="${3:-}"

    if [ -n "$SINGLE" ] && [ "$SINGLE" != "$name" ]; then
        return
    fi

    echo ""
    echo "================================================"
    echo "  测试: $name"
    echo "================================================"

    # 清理旧容器
    if [ "$name" = "F_d_state" ]; then
        docker kill nfs-server-dstate 2>/dev/null || true
        docker kill process-hang-branch-f 2>/dev/null || true
    else
        local cname=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')
        docker kill "process-hang-${cname}" 2>/dev/null || true
    fi

    # 注入故障
    echo "[TEST] 注入 $name ..."
    bash "$dir/inject.sh" $extra 2>&1 | tail -5

    # 等待故障生效
    sleep 3

    # 验证故障容器在运行
    if [ "$name" = "F_d_state" ]; then
        local running=$(docker ps --filter "name=process-hang-branch-f" --format '{{.Names}}' 2>/dev/null)
    else
        local cname_lower=$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g')
        local running=$(docker ps --filter "name=process-hang-${cname_lower}" --format '{{.Names}}' 2>/dev/null)
    fi

    if [ -n "$running" ]; then
        echo "[PASS] 容器 $running 运行中"
    else
        echo "[FAIL] 容器未运行"
        return 1
    fi

    # 清理
    echo "[CLEAN] 清理 $name ..."
    bash "$dir/cleanup.sh" 2>&1
    echo "[DONE] $name 测试完成"
}

# 逐一测试
test_branch "G_user_loop"    "$BASE/branches/G_user_loop"
test_branch "E_signal_stop"  "$BASE/branches/E_signal_stop" "stop"
test_branch "A_futex_wait"   "$BASE/branches/A_futex_wait"
test_branch "B_deadlock"     "$BASE/branches/B_deadlock"
test_branch "C_filelock"     "$BASE/branches/C_filelock"
test_branch "D_pipe_socket"  "$BASE/branches/D_pipe_socket" "read"
test_branch "F_d_state"      "$BASE/branches/F_d_state"

echo ""
echo "================================================"
echo "  全部测试完成"
echo "================================================"
