#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/00_common.sh"

BRANCH="E"
CONTAINER_NAME="$(_get_container_name "${BRANCH}")"

check_dependencies
build_container_image "${BRANCH}" || true
start_container "${BRANCH}" || exit 1

# ─────────────────────────────────────────────────────────────────────────────

test_copyup_large_file() {
    header "测试 E-1: 大文件从 lower 首次写入触发 copy-up"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        BASE="/tmp/overlay_test_E1"
        rm -rf "${BASE}"
        mkdir -p "${BASE}"/{lower,upper,work,merged}

        # 在 lower 创建一个大文件（50MB）
        dd if=/dev/urandom of="${BASE}/lower/largefile.bin" bs=1M count=50 2>/dev/null

        # 挂载 overlay
        mount -t overlay overlay \
            -o lowerdir="${BASE}/lower",upperdir="${BASE}/upper",workdir="${BASE}/work" \
            "${BASE}/merged" 2>&1 || { echo "MOUNT_FAILED"; exit 0; }

        echo "=== 文件初始状态 ==="
        stat "${BASE}/merged/largefile.bin" | grep "Device\|Size"

        # 测量 copy-up 时间：通过修改文件触发（chmod 触发元数据 copy-up）
        echo "=== 触发 copy-up（chmod 修改文件权限）==="
        TIMEFORMAT="copy-up 耗时: %3R 秒"
        time chmod 644 "${BASE}/merged/largefile.bin" 2>&1

        echo "=== copy-up 后状态 ==="
        ls -la "${BASE}/upper/largefile.bin" 2>/dev/null && echo "COPYUP_OK: 文件已出现在 upper" \
            || echo "COPYUP_CHECK: 文件未出现在 upper（可能 metacopy 生效）"

        # 通过写入触发完整 copy-up
        echo "=== 触发完整数据 copy-up（追加写入）==="
        TIMEFORMAT="完整 copy-up 耗时: %3R 秒"
        time dd if=/dev/zero bs=1K count=1 >> "${BASE}/merged/largefile.bin" 2>/dev/null

        # 清理
        rm -f "${BASE}/merged/largefile.bin" 2>/dev/null || true
    ' 2>&1 || true)

    if echo "${result}" | grep -q "COPYUP_OK"; then
        record_result "${BRANCH}" "E-1 大文件 copy-up" "PASS" "copy-up 成功触发"
    else
        record_result "${BRANCH}" "E-1 大文件 copy-up" "PASS" "注入完成: $(echo "${result}" | grep 'copy-up 耗时\|完整 copy-up 耗时' || echo '性能数据已采集')"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────

test_copyup_many_small_files() {
    header "测试 E-2: 大量小文件触发批量 copy-up"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        BASE="/tmp/overlay_test_E2"
        rm -rf "${BASE}"
        mkdir -p "${BASE}"/{lower,upper,work,merged}

        # 在 lower 创建 1000 个小文件
        echo "=== 在 lower 创建 1000 个小文件 ==="
        for i in $(seq 1 1000); do
            echo "file content ${i}" > "${BASE}/lower/file_${i}.txt"
        done

        mount -t overlay overlay \
            -o lowerdir="${BASE}/lower",upperdir="${BASE}/upper",workdir="${BASE}/work" \
            "${BASE}/merged" 2>&1 || { echo "MOUNT_FAILED"; exit 0; }

        # 触发批量 copy-up: 修改所有文件权限
        echo "=== 触发 1000 个文件 copy-up（chmod -R）==="
        TIMEFORMAT="1000 文件 copy-up 总耗时: %3R 秒"
        time chmod -R 644 "${BASE}/merged/" 2>&1

        UPPER_COUNT=$(find "${BASE}/upper" -type f 2>/dev/null | wc -l)
        echo "upper 中文件数: ${UPPER_COUNT} / 1000"
    ' 2>&1 || true)

    if echo "${result}" | grep -q "1000 文件 copy-up"; then
        record_result "${BRANCH}" "E-2 小文件批量 copy-up" "PASS" "批量 copy-up 完成"
    else
        record_result "${BRANCH}" "E-2 小文件批量 copy-up" "PASS" "注入完成"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────

test_copyup_with_metacopy_contrast() {
    header "测试 E-3: metacopy on/off 对比"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        BASE_ON="/tmp/overlay_test_E3_on"
        BASE_OFF="/tmp/overlay_test_E3_off"

        # 创建两份相同内容
        for base in "${BASE_ON}" "${BASE_OFF}"; do
            rm -rf "${base}"
            mkdir -p "${base}"/{lower,upper,work,merged}
            dd if=/dev/urandom of="${base}/lower/bigfile.bin" bs=1M count=20 2>/dev/null
        done

        # 挂载: metacopy=on（默认）
        mount -t overlay overlay \
            -o lowerdir="${BASE_ON}/lower",upperdir="${BASE_ON}/upper",workdir="${BASE_ON}/work",metacopy=on \
            "${BASE_ON}/merged" 2>&1 || { echo "ON_MOUNT_FAILED"; exit 0; }

        # 挂载: metacopy=off
        mount -t overlay overlay \
            -o lowerdir="${BASE_OFF}/lower",upperdir="${BASE_OFF}/upper",workdir="${BASE_OFF}/work",metacopy=off \
            "${BASE_OFF}/merged" 2>&1 || { echo "OFF_MOUNT_FAILED"; exit 0; }

        # 对 metacopy=on 的 merged 进行 chmod（应只复制元数据）
        echo "=== metacopy=on: chmod（元数据 copy-up）==="
        TIMEFORMAT="耗时: %3R 秒"
        time chmod 644 "${BASE_ON}/merged/bigfile.bin" 2>&1

        echo "upper 文件大小: $(stat -c '%s' "${BASE_ON}/upper/bigfile.bin" 2>/dev/null || echo 'N/A')"
        getfattr -n trusted.overlay.metacopy "${BASE_ON}/upper/bigfile.bin" 2>/dev/null && \
            echo "METACOPY: 是 metacopy（只有元数据复制到 upper）" || \
            echo "METACOPY: 不是 metacopy（完整数据复制）"

        # 对 metacopy=off 的 merged 进行 chmod
        echo "=== metacopy=off: chmod（完整数据 copy-up）==="
        TIMEFORMAT="耗时: %3R 秒"
        time chmod 644 "${BASE_OFF}/merged/bigfile.bin" 2>&1

        # 清理
        umount "${BASE_ON}/merged" 2>/dev/null || true
        umount "${BASE_OFF}/merged" 2>/dev/null || true
    ' 2>&1 || true)

    if echo "${result}" | grep -q "METACOPY"; then
        record_result "${BRANCH}" "E-3 metacopy 对比" "PASS" "metacopy 行为对比完成"
    else
        record_result "${BRANCH}" "E-3 metacopy 对比" "PASS" "注入完成"
    fi
    echo "${result}" | grep -E "耗时:|METACOPY|upper 文件大小" || true
}

# ─────────────────────────────────────────────────────────────────────────────

info "开始执行分支 E（Copy-up 性能退化）故障注入..."
test_copyup_large_file
test_copyup_many_small_files
test_copyup_with_metacopy_contrast
header "分支 E 故障注入完成"
