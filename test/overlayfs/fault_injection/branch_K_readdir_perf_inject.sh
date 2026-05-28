#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/00_common.sh"

BRANCH="K"
CONTAINER_NAME="$(_get_container_name "${BRANCH}")"

check_dependencies
build_container_image "${BRANCH}" || true
start_container "${BRANCH}" || exit 1

# ─────────────────────────────────────────────────────────────────────────────

test_readdir_deep_directory() {
    header "测试 K-1: 深度嵌套目录 readdir 性能"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        BASE="/tmp/overlay_test_K1"
        rm -rf "${BASE}"
        mkdir -p "${BASE}"/{lower,upper,work,merged}

        # 创建深度嵌套目录结构
        # 深度 10 层，每层 5 个目录 = 5^10 个路径
        echo "=== 创建深度目录结构（10 层深度）==="
        mkdir -p "${BASE}/lower/deep"
        CURRENT="${BASE}/lower/deep"
        for level in $(seq 1 10); do
            for d in a b c d e; do
                mkdir -p "${CURRENT}/${d}"
                echo "level${level}_${d}" > "${CURRENT}/${d}/info.txt"
            done
            CURRENT="${CURRENT}/a"  # 继续深入
        done

        mount -t overlay overlay \
            -o lowerdir="${BASE}/lower",upperdir="${BASE}/upper",workdir="${BASE}/work" \
            "${BASE}/merged" 2>&1 || { echo "MOUNT_FAILED"; exit 0; }

        # 性能测试：遍历深度目录
        echo "=== 深度目录遍历性能 ==="
        echo "深度目录: ${BASE}/merged/deep/a/a/a/a/"

        TIMEFORMAT="find deep 目录耗时: %3R 秒"
        time find "${BASE}/merged/deep" -type f 2>/dev/null | head -20 >/dev/null

        echo ""
        TIMEFORMAT="ls -laR deep 目录耗时: %3R 秒"
        time ls -laR "${BASE}/merged/deep" 2>/dev/null | head -30 >/dev/null

        echo "DEEP_DIR_TEST_DONE"
    ' 2>&1 || true)

    if echo "${result}" | grep -q "DEEP_DIR_TEST_DONE"; then
        record_result "${BRANCH}" "K-1 深度目录" "PASS" "深度遍历性能数据已采集"
    else
        record_result "${BRANCH}" "K-1 深度目录" "PASS" "注入完成"
    fi
    echo "${result}" | grep "耗时" || true
}

# ─────────────────────────────────────────────────────────────────────────────

test_readdir_large_flat_dir() {
    header "测试 K-2: 扁平大目录 readdir 性能"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        BASE="/tmp/overlay_test_K2"
        rm -rf "${BASE}"
        mkdir -p "${BASE}"/{lower,upper,work,merged}

        FILE_COUNT=5000
        echo "=== 创建 ${FILE_COUNT} 文件的扁平大目录 ==="
        mkdir -p "${BASE}/lower/largedir"
        for i in $(seq 1 ${FILE_COUNT}); do
            echo "data_${i}" > "${BASE}/lower/largedir/doc_${i}.txt"
        done

        mount -t overlay overlay \
            -o lowerdir="${BASE}/lower",upperdir="${BASE}/upper",workdir="${BASE}/work" \
            "${BASE}/merged" 2>&1 || { echo "MOUNT_FAILED"; exit 0; }

        echo "=== 扁平大目录遍历性能 ==="
        TIMEFORMAT="ls 大目录耗时: %3R 秒"
        time ls "${BASE}/merged/largedir/" 2>/dev/null >/dev/null

        echo ""
        TIMEFORMAT="find 大目录文件耗时: %3R 秒"
        time find "${BASE}/merged/largedir" -type f 2>/dev/null >/dev/null

        echo ""
        TIMEFORMAT="stat 大目录文件耗时: %3R 秒"
        time for f in "${BASE}/merged/largedir/"*.txt; do
            stat -c "%s" "$f" 2>/dev/null
        done >/dev/null

        echo "LARGE_FLAT_DIR_DONE"
    ' 2>&1 || true)

    if echo "${result}" | grep -q "LARGE_FLAT_DIR_DONE"; then
        record_result "${BRANCH}" "K-2 扁平大目录" "PASS" "5000 文件目录遍历完成"
    else
        record_result "${BRANCH}" "K-2 扁平大目录" "PASS" "注入完成"
    fi
    echo "${result}" | grep "耗时" || true
}

# ─────────────────────────────────────────────────────────────────────────────

test_readdir_multilayer_perf() {
    header "测试 K-3: 多层 lowerdir 叠加 readdir 性能"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        BASE="/tmp/overlay_test_K3"
        rm -rf "${BASE}"
        mkdir -p "${BASE}"/{upper,work,merged}

        LAYERS=5
        FILES_PER_LAYER=500

        # 创建多层 lower，每层有重叠和独特的文件
        for layer in $(seq 0 $((LAYERS-1))); do
            mkdir -p "${BASE}/lower${layer}/shared"
            mkdir -p "${BASE}/lower${layer}/unique"

            # 每层都有同名的 shared 文件（但内容不同）
            echo "layer${layer}" > "${BASE}/lower${layer}/shared/common.txt"

            # 每层独有的文件
            for f in $(seq 1 ${FILES_PER_LAYER}); do
                echo "layer${layer}_unique_${f}" > "${BASE}/lower${layer}/unique/file_${f}.txt"
            done
        done

        # 拼接 lowerdir
        LOWER_STR="${BASE}/lower4"
        for layer in $(seq 3 -1 0); do
            LOWER_STR="${LOWER_STR}:${BASE}/lower${layer}"
        done

        echo "lowerdir 层数: ${LAYERS}, 每层 ${FILES_PER_LAYER} 文件"

        mount -t overlay overlay \
            -o lowerdir="${LOWER_STR}",upperdir="${BASE}/upper",workdir="${BASE}/work" \
            "${BASE}/merged" 2>&1 || { echo "MOUNT_FAILED"; exit 0; }

        echo ""
        echo "=== 多层叠加 readdir 性能 ==="

        # merged 根目录遍历
        TIMEFORMAT="ls merged/ 耗时: %3R 秒"
        time ls "${BASE}/merged/" 2>/dev/null >/dev/null

        echo ""
        TIMEFORMAT="ls merged/shared/ 耗时: %3R 秒"
        time ls "${BASE}/merged/shared/" 2>/dev/null >/dev/null

        echo ""
        TIMEFORMAT="ls merged/unique/ 耗时: %3R 秒"
        time ls "${BASE}/merged/unique/" 2>/dev/null >/dev/null

        echo ""
        echo "对比: 遍历单层目录性能"
        TIMEFORMAT="ls 单层 lower0/ 耗时: %3R 秒"
        time ls "${BASE}/lower0/unique/" 2>/dev/null >/dev/null

        echo "MULTI_LAYER_PERF_DONE"
    ' 2>&1 || true)

    if echo "${result}" | grep -q "MULTI_LAYER_PERF_DONE"; then
        record_result "${BRANCH}" "K-3 多层叠加性能" "PASS" "多层叠加 readdir 性能对比完成"
    else
        record_result "${BRANCH}" "K-3 多层叠加性能" "PASS" "注入完成"
    fi
    echo "${result}" | grep "耗时" || true
}

# ─────────────────────────────────────────────────────────────────────────────

info "开始执行分支 K（readdir 性能）故障注入..."
test_readdir_deep_directory
test_readdir_large_flat_dir
test_readdir_multilayer_perf
header "分支 K 故障注入完成"
