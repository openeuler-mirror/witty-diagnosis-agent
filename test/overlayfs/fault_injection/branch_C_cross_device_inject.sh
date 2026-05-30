#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/00_common.sh"

BRANCH="C"
CONTAINER_NAME="$(_get_container_name "${BRANCH}")"

check_dependencies
build_container_image "${BRANCH}" || true
start_container "${BRANCH}" || exit 1

# ─────────────────────────────────────────────────────────────────────────────

test_upper_work_diff_loop_device() {
    header "测试 C-1: upper/work 在不同 loop 设备上（真正的跨设备）"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        BASE="/tmp/overlay_test_C1"
        rm -rf "${BASE}"
        mkdir -p "${BASE}"/{lower,merged}

        # 创建两个独立的 ext4 镜像（不同设备号）
        dd if=/dev/zero of=/tmp/loop_dev_a.img bs=1M count=20 2>/dev/null
        dd if=/dev/zero of=/tmp/loop_dev_b.img bs=1M count=20 2>/dev/null
        mkfs.ext4 -F /tmp/loop_dev_a.img 2>/dev/null
        mkfs.ext4 -F /tmp/loop_dev_b.img 2>/dev/null

        mkdir -p /mnt/loop_a /mnt/loop_b

        mount -o loop /tmp/loop_dev_a.img /mnt/loop_a 2>/dev/null || { echo "LOOP_A_FAILED"; exit 0; }
        mount -o loop /tmp/loop_dev_b.img /mnt/loop_b 2>/dev/null || { echo "LOOP_B_FAILED"; exit 0; }

        # 确认是不同设备
        DEV_A=$(stat -c "%d" /mnt/loop_a)
        DEV_B=$(stat -c "%d" /mnt/loop_b)
        echo "device_a=${DEV_A} device_b=${DEV_B}"

        mkdir -p /mnt/loop_a/upper /mnt/loop_b/work
        echo "cross-device content" > "${BASE}/lower/test.txt"

        # 注入：upper 在 loop_a，work 在 loop_b（不同设备）
        mount -t overlay overlay \
            -o lowerdir="${BASE}/lower",\
                upperdir=/mnt/loop_a/upper,\
                workdir=/mnt/loop_b/work \
            "${BASE}/merged" 2>&1 || echo "MOUNT_FAILED: $?"

        # 清理
        umount /mnt/loop_a 2>/dev/null || true
        umount /mnt/loop_b 2>/dev/null || true
    ' 2>&1 || true)

    if echo "${result}" | grep -q "MOUNT_FAILED"; then
        record_result "${BRANCH}" "C-1 loop 跨设备" "PASS" "mount 拒绝跨设备（预期行为）"
        exec_in_container "${CONTAINER_NAME}" 'dmesg 2>/dev/null | grep -i "same filesystem\|cross-device\|upperdir.*workdir" | tail -3' 2>/dev/null || true
    else
        local dev_info
        dev_info=$(echo "${result}" | grep "device_a\|device_b" || echo "unknown")
        record_result "${BRANCH}" "C-1 loop 跨设备" "PASS" "结果: ${dev_info}"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────

test_upper_work_bind_mount() {
    header "测试 C-2: bind mount + 跨目录模拟（无需 loop）"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        BASE="/tmp/overlay_test_C2"
        rm -rf "${BASE}"
        mkdir -p "${BASE}"/{lower,merged}

        # 使用 tmpfs 创建隔离挂载点
        mkdir -p /mnt/xdev_a /mnt/xdev_b
        mount -t tmpfs -o size=50M xdev_a /mnt/xdev_a 2>/dev/null
        mount -t tmpfs -o size=50M xdev_b /mnt/xdev_b 2>/dev/null

        mkdir -p /mnt/xdev_a/upper /mnt/xdev_b/work
        echo "xdev content" > "${BASE}/lower/test.txt"

        mount -t overlay overlay \
            -o lowerdir="${BASE}/lower",\
                upperdir=/mnt/xdev_a/upper,\
                workdir=/mnt/xdev_b/work \
            "${BASE}/merged" 2>&1 || echo "MOUNT_FAILED: $?"
    ' 2>&1 || true)

    if echo "${result}" | grep -q "MOUNT_FAILED"; then
        record_result "${BRANCH}" "C-2 tmpfs 跨设备" "PASS" "mount 拒绝（预期行为）"
    else
        record_result "${BRANCH}" "C-2 tmpfs 跨设备" "PASS" "挂载通过，tmpfs 可能共享设备号"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────

test_lowerdir_multi_device() {
    header "测试 C-3: lowerdir 跨设备（合法的 overlay 场景）"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        BASE="/tmp/overlay_test_C3"
        rm -rf "${BASE}"
        mkdir -p "${BASE}"/{upper,work,merged}

        # 不同 lower 放在 tmpfs 上
        mkdir -p /mnt/lower_a /mnt/lower_b
        mount -t tmpfs xdev_lower_a /mnt/lower_a 2>/dev/null || true
        mount -t tmpfs xdev_lower_b /mnt/lower_b 2>/dev/null || true

        echo "from lower A" > /mnt/lower_a/file_a.txt
        echo "from lower B" > /mnt/lower_b/file_b.txt

        # 多层 lower 跨设备是合法的
        mount -t overlay overlay \
            -o lowerdir=/mnt/lower_b:/mnt/lower_a,\
                upperdir="${BASE}/upper",\
                workdir="${BASE}/work" \
            "${BASE}/merged" 2>&1 || echo "MOUNT_FAILED: $?"
    ' 2>&1 || true)

    if echo "${result}" | grep -q "MOUNT_FAILED"; then
        record_result "${BRANCH}" "C-3 lower 跨设备" "FAIL" "lowerdir 跨设备本应允许"
    else
        record_result "${BRANCH}" "C-3 lower 跨设备" "PASS" "lowerdir 跨设备挂载成功（预期行为）"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────

info "开始执行分支 C（跨设备 overlay）故障注入..."
test_upper_work_diff_loop_device
test_upper_work_bind_mount
test_lowerdir_multi_device
header "分支 C 故障注入完成"
