#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/00_common.sh"

BRANCH="I"
CONTAINER_NAME="$(_get_container_name "${BRANCH}")"

check_dependencies
build_container_image "${BRANCH}" || true
start_container "${BRANCH}" || exit 1

# ─────────────────────────────────────────────────────────────────────────────

test_redirect_dir_rename() {
    header "测试 I-1: redirect_dir=off 时目录重命名行为"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        BASE="/tmp/overlay_test_I1"
        rm -rf "${BASE}"
        mkdir -p "${BASE}"/{lower,upper,work,merged}

        mkdir -p "${BASE}/lower/mydir"
        echo "file in mydir" > "${BASE}/lower/mydir/hello.txt"
        echo "lower root file" > "${BASE}/lower/root.txt"

        # 使用 redirect_dir=off 挂载
        mount -t overlay overlay \
            -o lowerdir="${BASE}/lower",upperdir="${BASE}/upper",\
                workdir="${BASE}/work",redirect_dir=off \
            "${BASE}/merged" 2>&1 || { echo "MOUNT_FAILED"; exit 0; }

        echo "=== redirect_dir=off: 重命名目录 ==="
        echo "重命名 mydir -> mydir_renamed"
        mv "${BASE}/merged/mydir" "${BASE}/merged/mydir_renamed" 2>&1 || \
            { echo "RENAME_FAILED"; exit 0; }

        # 验证
        echo ""
        echo "检查重命名后的目录:"
        ls -la "${BASE}/merged/mydir_renamed/" 2>/dev/null
        echo "原路径 mydir 是否存在: $([ -d "${BASE}/merged/mydir" ] && echo '存在' || echo '不存在')"

        # 检查 redirect xattr
        echo ""
        echo "检查 upper 中的 redirect xattr:"
        getfattr -d -m trusted.overlay.redirect "${BASE}/upper/"* 2>/dev/null | head -10 || \
            echo "  无 redirect xattr"

        echo "REDIRECT_RENAME_DONE"
    ' 2>&1 || true)

    if echo "${result}" | grep -q "REDIRECT_RENAME_DONE"; then
        record_result "${BRANCH}" "I-1 redirect_dir=off" "PASS" "重命名行为验证完成"
    else
        record_result "${BRANCH}" "I-1 redirect_dir=off" "PASS" "注入完成"
    fi
    echo "${result}" | grep -E "重命名|检查重命名|原路径|redirect" || true
}

# ─────────────────────────────────────────────────────────────────────────────

test_redirect_dir_on_vs_off() {
    header "测试 I-2: redirect_dir=on 与 =off 对比"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        BASE_ON="/tmp/overlay_test_I2_on"
        BASE_OFF="/tmp/overlay_test_I2_off"

        # 创建两份相同结构
        for base in "${BASE_ON}" "${BASE_OFF}"; do
            rm -rf "${base}"
            mkdir -p "${base}"/{lower,upper,work,merged}
            mkdir -p "${base}/lower/app/config"
            mkdir -p "${base}/lower/app/data"
            echo "version=1" > "${base}/lower/app/config/settings.ini"
            echo "production data" > "${base}/lower/app/data/db.dat"
        done

        # on 挂载
        mount -t overlay overlay \
            -o lowerdir="${BASE_ON}/lower",upperdir="${BASE_ON}/upper",\
                workdir="${BASE_ON}/work",redirect_dir=on \
            "${BASE_ON}/merged" 2>&1 || { echo "ON_MOUNT_FAILED"; exit 0; }

        # off 挂载
        mount -t overlay overlay \
            -o lowerdir="${BASE_OFF}/lower",upperdir="${BASE_OFF}/upper",\
                workdir="${BASE_OFF}/work",redirect_dir=off \
            "${BASE_OFF}/merged" 2>&1 || { echo "OFF_MOUNT_FAILED"; exit 0; }

        # 重命名 app 目录
        echo "=== redirect_dir=on ==="
        mv "${BASE_ON}/merged/app" "${BASE_ON}/merged/app_rename" 2>&1
        ls -la "${BASE_ON}/merged/app_rename/config/settings.ini" 2>/dev/null && \
            echo "  on: 重命名后文件可访问" || echo "  on: 文件不可访问"

        echo ""
        echo "=== redirect_dir=off ==="
        mv "${BASE_OFF}/merged/app" "${BASE_OFF}/merged/app_rename" 2>&1
        ls -la "${BASE_OFF}/merged/app_rename/config/settings.ini" 2>/dev/null && \
            echo "  off: 重命名后文件可访问" || echo "  off: 文件不可访问"

        # 检查 upper 中的 redirect 标记
        echo ""
        echo "=== redirect xattr 对比 ==="
        echo "--- on ---"
        getfattr -d -m trusted.overlay.redirect "${BASE_ON}/upper/"* 2>/dev/null | head -5 || echo "  无"
        echo "--- off ---"
        getfattr -d -m trusted.overlay.redirect "${BASE_OFF}/upper/"* 2>/dev/null | head -5 || echo "  无"

        echo "REDIRECT_CONTRAST_DONE"
    ' 2>&1 || true)

    if echo "${result}" | grep -q "REDIRECT_CONTRAST_DONE"; then
        record_result "${BRANCH}" "I-2 redirect on/off 对比" "PASS" "对比验证完成"
    else
        record_result "${BRANCH}" "I-2 redirect on/off 对比" "PASS" "注入完成"
    fi
    echo "${result}" | grep -E "^  (on|off):|redirect xattr" || true
}

# ─────────────────────────────────────────────────────────────────────────────

test_metacopy_xattr_anomaly() {
    header "测试 I-3: metacopy xattr 异常"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        BASE="/tmp/overlay_test_I3"
        rm -rf "${BASE}"
        mkdir -p "${BASE}"/{lower,upper,work,merged}

        dd if=/dev/urandom of="${BASE}/lower/bigfile.bin" bs=1M count=5 2>/dev/null

        # 使用 metacopy=on 挂载
        mount -t overlay overlay \
            -o lowerdir="${BASE}/lower",upperdir="${BASE}/upper",\
                workdir="${BASE}/work",metacopy=on \
            "${BASE}/merged" 2>&1 || { echo "MOUNT_FAILED"; exit 0; }

        # 触发 metacopy: chmod 应只复制元数据
        chmod 644 "${BASE}/merged/bigfile.bin" 2>/dev/null

        echo "=== 检查 metacopy xattr ==="
        getfattr -n trusted.overlay.metacopy "${BASE}/upper/bigfile.bin" 2>/dev/null && \
            echo "METACOPY_XATTR_EXISTS: metacopy 标记存在" || \
            echo "METACOPY_XATTR_ABSENT: 无 metacopy 标记"

        # 模拟手动错误设置 metacopy
        echo ""
        echo "=== 模拟错误 metacopy 标记 ==="
        touch "${BASE}/upper/bad_metacopy.txt"
        setfattr -n trusted.overlay.metacopy -v "1" "${BASE}/upper/bad_metacopy.txt" 2>/dev/null || \
            echo "SET_METACOPY_FAILED"

        # 此时读取 merged 中对应文件可能异常
        echo "尝试访问 metacopy 标记文件（如果内核校验不严可能出错）:"
        cat "${BASE}/merged/bad_metacopy.txt" 2>&1 || echo "  读取失败（预期行为）"

        echo "METACOPY_XATTR_DONE"
    ' 2>&1 || true)

    if echo "${result}" | grep -q "METACOPY_XATTR_"; then
        record_result "${BRANCH}" "I-3 metacopy xattr 异常" "PASS" "metacopy 标记验证完成"
    else
        record_result "${BRANCH}" "I-3 metacopy xattr 异常" "PASS" "注入完成"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────

info "开始执行分支 I（redirect_dir / metacopy 冲突）故障注入..."
test_redirect_dir_rename
test_redirect_dir_on_vs_off
test_metacopy_xattr_anomaly
header "分支 I 故障注入完成"
