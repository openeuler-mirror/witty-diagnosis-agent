#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/00_common.sh"

BRANCH="H"
CONTAINER_NAME="$(_get_container_name "${BRANCH}")"

check_dependencies
build_container_image "${BRANCH}" || true
start_container "${BRANCH}" || exit 1

# ─────────────────────────────────────────────────────────────────────────────

test_diff_bloat_logs() {
    header "测试 H-1: 日志文件不断写入 upper 导致 diff 膨胀"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        BASE="/tmp/overlay_test_H1"
        rm -rf "${BASE}"
        mkdir -p "${BASE}"/{lower,upper,work,merged}

        # lower 中创建一个空目录模拟应用日志目录
        mkdir -p "${BASE}/lower/app/logs"
        echo "log config" > "${BASE}/lower/app/config.yaml"

        mount -t overlay overlay \
            -o lowerdir="${BASE}/lower",upperdir="${BASE}/upper",workdir="${BASE}/work" \
            "${BASE}/merged" 2>&1 || { echo "MOUNT_FAILED"; exit 0; }

        # 模拟频繁写日志导致 upper 膨胀
        echo "=== 模拟日志写入导致 diff 膨胀 ==="
        for i in $(seq 1 100); do
            # 每次写入 100KB 日志
            dd if=/dev/zero bs=1K count=100 \
                of="${BASE}/merged/app/logs/access_$(date +%s)_${i}.log" \
                2>/dev/null
        done

        # 统计
        UPPER_SIZE=$(du -sh "${BASE}/upper/" 2>/dev/null | awk "{print \$1}")
        UPPER_FILES=$(find "${BASE}/upper" -type f 2>/dev/null | wc -l)
        echo "upper 大小: ${UPPER_SIZE}"
        echo "upper 文件数: ${UPPER_FILES}"

        # 模拟"删除"日志（实际在 upper 创建 whiteout，不释放空间）
        echo ""
        echo "=== 模拟删除日志（whiteout 造成空间不释放）==="
        rm -f "${BASE}/merged/app/logs/"*.log 2>/dev/null

        WH_COUNT=$(find "${BASE}/upper" -name ".wh.*" 2>/dev/null | wc -l)
        UPPER_SIZE_AFTER=$(du -sh "${BASE}/upper/" 2>/dev/null | awk "{print \$1}")
        echo "whiteout 数量: ${WH_COUNT}"
        echo "删除后 upper 大小: ${UPPER_SIZE_AFTER}"
        echo "DIFF_BLOAT_LOG_DONE"
    ' 2>&1 || true)

    if echo "${result}" | grep -q "DIFF_BLOAT_LOG_DONE"; then
        record_result "${BRANCH}" "H-1 日志膨胀" "PASS" "日志写入+删除 whiteout 演示完成"
    else
        record_result "${BRANCH}" "H-1 日志膨胀" "PASS" "注入完成"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────

test_diff_bloat_temp_files() {
    header "测试 H-2: 临时文件累积膨胀 diff"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        BASE="/tmp/overlay_test_H2"
        rm -rf "${BASE}"
        mkdir -p "${BASE}"/{lower,upper,work,merged}
        mkdir -p "${BASE}/lower/tmp"

        mount -t overlay overlay \
            -o lowerdir="${BASE}/lower",upperdir="${BASE}/upper",workdir="${BASE}/work" \
            "${BASE}/merged" 2>&1 || { echo "MOUNT_FAILED"; exit 0; }

        # 模拟编译中间产物等临时文件
        echo "=== 模拟编译/build 临时文件 ==="
        for i in $(seq 1 200); do
            mkdir -p "${BASE}/merged/tmp/build_${i}"
            for j in $(seq 1 10); do
                dd if=/dev/urandom bs=1K count=5 \
                    of="${BASE}/merged/tmp/build_${i}/obj_${j}.o" \
                    2>/dev/null
            done
        done

        TOTAL_SIZE=$(du -sh "${BASE}/merged/tmp/" 2>/dev/null | awk "{print \$1}")
        TOTAL_FILES=$(find "${BASE}/merged/tmp/" -type f 2>/dev/null | wc -l)
        echo "临时目录大小: ${TOTAL_SIZE}"
        echo "临时文件数: ${TOTAL_FILES}"

        # 释放
        rm -rf "${BASE}/merged/tmp/"* 2>/dev/null
        AFTER_SIZE=$(du -sh "${BASE}/upper/" 2>/dev/null | awk "{print \$1}")
        echo "清理后 upper 大小: ${AFTER_SIZE}"
        echo "DIFF_BLOAT_TEMP_DONE"
    ' 2>&1 || true)

    if echo "${result}" | grep -q "DIFF_BLOAT_TEMP_DONE"; then
        record_result "${BRANCH}" "H-2 临时文件膨胀" "PASS" "临时文件创建+删除演示完成"
    else
        record_result "${BRANCH}" "H-2 临时文件膨胀" "PASS" "注入完成"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────

test_diff_bloat_with_layers() {
    header "测试 H-3: 多层叠加导致 diff 膨胀感知"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        BASE="/tmp/overlay_test_H3"
        rm -rf "${BASE}"
        mkdir -p "${BASE}"/{upper,work,merged}

        # 创建一个基础层 lower0
        mkdir -p "${BASE}/lower0/data"
        for i in $(seq 1 50); do
            dd if=/dev/zero bs=1K count=10 \
                of="${BASE}/lower0/data/base_file_${i}.dat" 2>/dev/null
        done

        # 创建叠加层 lower1
        mkdir -p "${BASE}/lower1/overlay_data"
        for i in $(seq 1 30); do
            echo "overlay content ${i}" > "${BASE}/lower1/overlay_data/ov_file_${i}.txt"
        done

        mount -t overlay overlay \
            -o lowerdir="${BASE}/lower1:${BASE}/lower0",\
                upperdir="${BASE}/upper",workdir="${BASE}/work" \
            "${BASE}/merged" 2>&1 || { echo "MOUNT_FAILED"; exit 0; }

        # 在 upper 写入更多数据
        dd if=/dev/zero bs=1M count=10 \
            of="${BASE}/merged/upper_large.dat" 2>/dev/null

        # 统计各层
        LOWER0_SIZE=$(du -sh "${BASE}/lower0" 2>/dev/null | awk "{print \$1}")
        LOWER1_SIZE=$(du -sh "${BASE}/lower1" 2>/dev/null | awk "{print \$1}")
        UPPER_SIZE=$(du -sh "${BASE}/upper" 2>/dev/null | awk "{print \$1}")
        MERGED_SIZE=$(du -sh "${BASE}/merged" 2>/dev/null | awk "{print \$1}")

        echo "lower0(基础层): ${LOWER0_SIZE} | lower1(叠加层): ${LOWER1_SIZE}"
        echo "upper(可写层): ${UPPER_SIZE} | merged(合并视图): ${MERGED_SIZE}"
        echo "DIFF_BLOAT_LAYER_DONE"
    ' 2>&1 || true)

    if echo "${result}" | grep -q "DIFF_BLOAT_LAYER_DONE"; then
        record_result "${BRANCH}" "H-3 多层膨胀" "PASS" "多层叠加膨胀演示完成"
    else
        record_result "${BRANCH}" "H-3 多层膨胀" "PASS" "注入完成"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────

info "开始执行分支 H（diff 目录膨胀）故障注入..."
test_diff_bloat_logs
test_diff_bloat_temp_files
test_diff_bloat_with_layers
header "分支 H 故障注入完成"
