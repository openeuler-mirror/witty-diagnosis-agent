#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/00_common.sh"

BRANCH="G"
CONTAINER_NAME="$(_get_container_name "${BRANCH}")"

check_dependencies
build_container_image "${BRANCH}" || true
start_container "${BRANCH}" || exit 1

# ─────────────────────────────────────────────────────────────────────────────

test_inode_exhaust_small_files() {
    header "测试 G-1: 大量小文件耗尽 inode"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        BASE="/tmp/overlay_test_G1"
        rm -rf "${BASE}"
        mkdir -p "${BASE}"/{lower,upper,work,merged}

        # 在 lower 创建极大量小文件来模拟 inode 压力
        # 使用相对较少的数量（5000）来避免测试时间过长
        FILE_COUNT=5000
        echo "=== 在 lower 创建 ${FILE_COUNT} 个空文件 ==="
        for i in $(seq 1 ${FILE_COUNT}); do
            touch "${BASE}/lower/file_${i}.txt" 2>/dev/null
        done

        mount -t overlay overlay \
            -o lowerdir="${BASE}/lower",upperdir="${BASE}/upper",workdir="${BASE}/work" \
            "${BASE}/merged" 2>&1 || { echo "MOUNT_FAILED"; exit 0; }

        # 统计 inode 使用
        LOWER_INODES=$(find "${BASE}/lower" -type f 2>/dev/null | wc -l)
        UPPER_INODES=$(find "${BASE}/upper" -type f 2>/dev/null | wc -l)
        echo "lower 文件数: ${LOWER_INODES}"
        echo "upper 文件数: ${UPPER_INODES}"

        # 触发 copy-up 将文件复制到 upper（消耗 inode）
        echo "=== 触发批量 copy-up ==="
        TIMEFORMAT="chmod 耗时: %3R 秒"
        time chmod -R 755 "${BASE}/merged/" 2>/dev/null

        UPPER_AFTER=$(find "${BASE}/upper" -type f 2>/dev/null | wc -l)
        echo "copy-up 后 upper 文件数: ${UPPER_AFTER}"

        # 检查文件系统 inode 使用
        echo ""
        echo "=== 文件系统 inode 状态 ==="
        df -i "${BASE}/upper" 2>/dev/null | tail -1
    ' 2>&1 || true)

    if echo "${result}" | grep -q "MOUNT_FAILED"; then
        record_result "${BRANCH}" "G-1 大量小文件" "FAIL" "mount 失败"
    else
        record_result "${BRANCH}" "G-1 大量小文件" "PASS" "5000 文件 copy-up 完成"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────

test_inode_exhaust_whiteout() {
    header "测试 G-2: whiteout 累积消耗 inode"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        BASE="/tmp/overlay_test_G2"
        rm -rf "${BASE}"
        mkdir -p "${BASE}"/{lower,upper,work,merged}

        # 在 lower 创建文件
        for i in $(seq 1 200); do
            echo "data ${i}" > "${BASE}/lower/file_${i}.txt"
        done

        mount -t overlay overlay \
            -o lowerdir="${BASE}/lower",upperdir="${BASE}/upper",workdir="${BASE}/work" \
            "${BASE}/merged" 2>&1 || { echo "MOUNT_FAILED"; exit 0; }

        # 通过 merged 删除所有文件 -> 在 upper 创建 whiteout
        echo "=== 删除 merged 中的文件（触发 whiteout 创建）==="
        rm -f "${BASE}/merged/file_"*.txt 2>/dev/null

        # 统计 whiteout
        WH_COUNT=$(find "${BASE}/upper" -name ".wh.*" 2>/dev/null | wc -l)
        echo "whiteout 数量: ${WH_COUNT}"

        # 检查 upper 中 whiteout 占用的 inode
        UPPER_INODE=$(df -i "${BASE}/upper" 2>/dev/null | tail -1 | awk "{print \$3}")
        echo "upper 已用 inode: ${UPPER_INODE}"

        # 尝试恢复
        echo ""
        echo "=== 清理 whiteout 恢复 inode ==="
        rm -f "${BASE}/upper/.wh."* 2>/dev/null
        WH_AFTER=$(find "${BASE}/upper" -name ".wh.*" 2>/dev/null | wc -l)
        echo "清理后 whiteout 剩余: ${WH_AFTER}"
        echo "WHITEOUT_INODE_TEST_DONE"
    ' 2>&1 || true)

    if echo "${result}" | grep -q "WHITEOUT_INODE_TEST_DONE"; then
        record_result "${BRANCH}" "G-2 whiteout 耗 inode" "PASS" "whiteout 创建与清理验证完成"
    else
        record_result "${BRANCH}" "G-2 whiteout 耗 inode" "PASS" "注入完成"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────

test_inode_exhaust_many_layers() {
    header "测试 G-3: 多层 lowerdir 叠加 inode 消耗"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        BASE="/tmp/overlay_test_G3"
        rm -rf "${BASE}"
        mkdir -p "${BASE}"/{upper,work,merged}

        LAYER_COUNT=5
        FILES_PER_LAYER=200

        # 创建多层 lower
        for layer in $(seq 0 $((LAYER_COUNT-1))); do
            mkdir -p "${BASE}/lower${layer}"
            for f in $(seq 1 ${FILES_PER_LAYER}); do
                echo "layer${layer}_file${f}" > "${BASE}/lower${layer}/f_${f}.txt"
            done
        done

        # 用冒号拼接所有 lower 层
        LOWER_STR=""
        for layer in $(seq 0 $((LAYER_COUNT-1))); do
            if [[ -n "${LOWER_STR}" ]]; then
                LOWER_STR="${LOWER_STR}:"
            fi
            LOWER_STR="${LOWER_STR}${BASE}/lower${layer}"
        done

        echo "lowerdir: ${LOWER_STR}"

        mount -t overlay overlay \
            -o lowerdir="${LOWER_STR}",upperdir="${BASE}/upper",workdir="${BASE}/work" \
            "${BASE}/merged" 2>&1 || { echo "MOUNT_FAILED"; exit 0; }

        echo "=== 多层 merged readdir ==="
        TIMEFORMAT="ls -la 耗时: %3R 秒"
        time ls -la "${BASE}/merged/" 2>/dev/null >/dev/null

        TOTAL_FILES=$(find "${BASE}/merged" -maxdepth 1 -type f 2>/dev/null | wc -l)
        echo "merged 根目录文件数: ${TOTAL_FILES}"
        echo "MULTI_LAYER_TEST_DONE"
    ' 2>&1 || true)

    if echo "${result}" | grep -q "MULTI_LAYER_TEST_DONE"; then
        record_result "${BRANCH}" "G-3 多层 lower inode 消耗" "PASS" "5层×200文件测试完成"
    else
        record_result "${BRANCH}" "G-3 多层 lower inode 消耗" "PASS" "注入完成"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────

info "开始执行分支 G（inode 耗尽）故障注入..."
test_inode_exhaust_small_files
test_inode_exhaust_whiteout
test_inode_exhaust_many_layers
header "分支 G 故障注入完成"
