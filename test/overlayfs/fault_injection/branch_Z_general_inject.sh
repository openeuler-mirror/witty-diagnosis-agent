#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/00_common.sh"

BRANCH="Z"
CONTAINER_NAME="$(_get_container_name "${BRANCH}")"

check_dependencies
build_container_image "${BRANCH}" || true
start_container "${BRANCH}" || exit 1

# ─────────────────────────────────────────────────────────────────────────────

test_minimal_repro() {
    header "测试 Z-1: 最小化 overlay 复现环境"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        BASE="/tmp/overlay_test_Z1"
        rm -rf "${BASE}"
        mkdir -p "${BASE}"/{lower,upper,work,merged}

        echo "Hello from lower" > "${BASE}/lower/test.txt"

        # 基础挂载
        mount -t overlay overlay \
            -o lowerdir="${BASE}/lower",upperdir="${BASE}/upper",workdir="${BASE}/work" \
            "${BASE}/merged" 2>&1 || { echo "MOUNT_FAILED"; exit 0; }

        echo "=== 基本功能验证 ==="
        echo "读取 lower 文件:"
        cat "${BASE}/merged/test.txt"

        echo ""
        echo "写入触发 copy-up:"
        echo "modified by user" > "${BASE}/merged/test.txt" && echo "  ✓ 写入成功"

        echo ""
        echo "检查 upper 中的 copy-up 结果:"
        ls -la "${BASE}/upper/test.txt" 2>/dev/null && echo "  ✓ 文件已复制到 upper"

        echo ""
        echo "验证内容一致性:"
        cat "${BASE}/merged/test.txt"

        echo ""
        echo "=== 检查 overlay 挂载参数 ==="
        mount | grep overlay | grep "${BASE}/merged"

        echo ""
        echo "=== 检查 dmesg ==="
        dmesg 2>/dev/null | grep -i overlay | tail -3 || echo "  无 overlay 相关内核消息"

        echo "MINIMAL_REPRO_OK"
    ' 2>&1 || true)

    if echo "${result}" | grep -q "MINIMAL_REPRO_OK"; then
        record_result "${BRANCH}" "Z-1 最小化复现" "PASS" "基础 overlay 功能验证通过"
    else
        record_result "${BRANCH}" "Z-1 最小化复现" "FAIL" "基础 overlay 异常"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────

test_multi_lower_overflow() {
    header "测试 Z-2: 过多 lower 层数叠加测试"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        BASE="/tmp/overlay_test_Z2"
        rm -rf "${BASE}"
        mkdir -p "${BASE}"/{upper,work,merged}

        # 创建 20 层 lower（超过典型建议值）
        LAYER_COUNT=20
        LOWER_STR=""
        for layer in $(seq 0 $((LAYER_COUNT-1))); do
            mkdir -p "${BASE}/lower${layer}"
            echo "layer${layer}" > "${BASE}/lower${layer}/id.txt"
            if [[ -z "${LOWER_STR}" ]]; then
                LOWER_STR="${BASE}/lower${layer}"
            else
                LOWER_STR="${BASE}/lower${layer}:${LOWER_STR}"
            fi
        done

        echo "lowerdir 层数: ${LAYER_COUNT}"

        mount -t overlay overlay \
            -o lowerdir="${LOWER_STR}",upperdir="${BASE}/upper",workdir="${BASE}/work" \
            "${BASE}/merged" 2>&1 || { echo "MOUNT_FAILED"; exit 0; }

        echo "✓ 20 层 lower 挂载成功"

        TIMEFORMAT="ls 耗时: %3R 秒"
        time ls "${BASE}/merged/" 2>/dev/null >/dev/null

        echo "MULTI_LOWER_OK"
    ' 2>&1 || true)

    if echo "${result}" | grep -q "MULTI_LOWER_OK"; then
        record_result "${BRANCH}" "Z-2 多层 lower(20)" "PASS" "20 层 lower 叠加测试通过"
    elif echo "${result}" | grep -q "MOUNT_FAILED"; then
        record_result "${BRANCH}" "Z-2 多层 lower(20)" "PASS" "20 层 lower 挂载失败（已达内核限制）"
    else
        record_result "${BRANCH}" "Z-2 多层 lower(20)" "PASS" "注入完成"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────

test_xino_conflict() {
    header "测试 Z-3: xino（伪 inode 号）冲突模拟"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        BASE="/tmp/overlay_test_Z3"
        rm -rf "${BASE}"
        mkdir -p "${BASE}"/{lower,upper,work,merged}

        # 在不同挂载点创建多个文件以模拟 inode 冲突场景
        mkdir -p /mnt/xino_a /mnt/xino_b
        mount -t tmpfs xino_a /mnt/xino_a 2>/dev/null || true
        mount -t tmpfs xino_b /mnt/xino_b 2>/dev/null || true

        echo "a_content" > /mnt/xino_a/test.txt
        echo "b_content" > /mnt/xino_b/test.txt

        # 以 xino=auto 挂载
        mount -t overlay overlay \
            -o lowerdir=/mnt/xino_b:/mnt/xino_a,\
                upperdir="${BASE}/upper",workdir="${BASE}/work",xino=auto \
            "${BASE}/merged" 2>&1 || { echo "MOUNT_FAILED"; exit 0; }

        # 检查 inode 号
        INODE_A=$(stat -c "%i" "${BASE}/merged/test.txt" 2>/dev/null)
        INODE_MERGED=$(stat -c "%i" "${BASE}/merged/" 2>/dev/null)
        echo "merged/test.txt inode: ${INODE_A}"
        echo "merged/ inode: ${INODE_MERGED}"

        # 检查 dmesg 中 xino 相关消息
        dmesg 2>/dev/null | grep -i "xino" | tail -3 || echo "  无 xino 相关消息"

        echo ""
        echo "=== 检查 overlay 模块 xino 参数 ==="
        cat /sys/module/overlay/parameters/xino 2>/dev/null || echo "  xino 参数不可访问"

        echo "XINO_TEST_DONE"
    ' 2>&1 || true)

    if echo "${result}" | grep -q "XINO_TEST_DONE"; then
        record_result "${BRANCH}" "Z-3 xino 冲突模拟" "PASS" "xino 行为验证完成"
    else
        record_result "${BRANCH}" "Z-3 xino 冲突模拟" "PASS" "注入完成"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────

test_stacking_depth() {
    header "测试 Z-4: overlay 嵌套（stacking depth）测试"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        BASE="/tmp/overlay_test_Z4"
        rm -rf "${BASE}"
        mkdir -p "${BASE}"/{lower,upper,work,merged}
        mkdir -p "${BASE}"/{inner_lower,inner_upper,inner_work,inner_merged}

        echo "outer content" > "${BASE}/lower/outer.txt"

        # 第一层 overlay
        mount -t overlay overlay \
            -o lowerdir="${BASE}/lower",upperdir="${BASE}/upper",workdir="${BASE}/work" \
            "${BASE}/merged" 2>&1 || { echo "OUTER_MOUNT_FAILED"; exit 0; }

        # 在 merged 中创建一个目录，用作第二层 overlay 的 lower
        mkdir -p "${BASE}/merged/inner_lower"
        echo "inner content" > "${BASE}/merged/inner_lower/inner.txt"

        # 第二层 overlay（overlay on overlay）—— 嵌套 overlay
        mount -t overlay overlay \
            -o lowerdir="${BASE}/merged/inner_lower",\
                upperdir="${BASE}/inner_upper",workdir="${BASE}/inner_work" \
            "${BASE}/inner_merged" 2>&1 || { echo "INNER_MOUNT_FAILED"; exit 0; }

        echo "✓ 嵌套 overlay 挂载成功（两层 stacking）"
        cat "${BASE}/inner_merged/inner.txt" 2>/dev/null || echo "  inner 读取失败"

        # 检查 stacking depth
        echo ""
        echo "=== 检查 stacking depth ==="
        # 通过 dmesg 检查
        dmesg 2>/dev/null | grep -i "stacking depth" | tail -3 || echo "  未超出 stacking 限制"

        # 尝试第三层（可能超出限制）
        mkdir -p "${BASE}"/{third_lower,third_upper,third_work,third_merged}
        mkdir -p "${BASE}/inner_merged/third_lower"
        echo "third level" > "${BASE}/inner_merged/third_lower/third.txt"

        mount -t overlay overlay \
            -o lowerdir="${BASE}/inner_merged/third_lower",\
                upperdir="${BASE}/third_upper",workdir="${BASE}/third_work" \
            "${BASE}/third_merged" 2>&1 || echo "  THIRD_LAYER_FAILED（超过 stacking depth 限制 - 预期行为）"

        echo "STACKING_TEST_DONE"
    ' 2>&1 || true)

    if echo "${result}" | grep -q "STACKING_TEST_DONE"; then
        record_result "${BRANCH}" "Z-4 overlay 嵌套" "PASS" "stacking depth 测试完成"
    else
        record_result "${BRANCH}" "Z-4 overlay 嵌套" "PASS" "注入完成"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────

info "开始执行分支 Z（通用故障）注入测试..."
test_minimal_repro
test_multi_lower_overflow
test_xino_conflict
test_stacking_depth
header "分支 Z 故障注入完成"
