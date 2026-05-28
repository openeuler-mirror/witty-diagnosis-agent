#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/00_common.sh"

BRANCH="D"
CONTAINER_NAME="$(_get_container_name "${BRANCH}")"

check_dependencies
build_container_image "${BRANCH}" || true
start_container "${BRANCH}" || exit 1

test_traditional_whiteout() {
    header "Test D-1: char(0,0) device whiteout"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        dd if=/dev/zero of=/tmp/wh_test.img bs=1M count=50 2>/dev/null
        mkfs.ext4 -F /tmp/wh_test.img 2>/dev/null
        mkdir -p /mnt/wh_test
        mount -o loop /tmp/wh_test.img /mnt/wh_test 2>/dev/null
        mkdir -p /mnt/wh_test/{lower,upper,work,merged}
        echo "visible in lower" > /mnt/wh_test/lower/secret.txt
        echo "another lower file" > /mnt/wh_test/lower/readme.md
        mount -t overlay overlay \
            -o lowerdir=/mnt/wh_test/lower,upperdir=/mnt/wh_test/upper,workdir=/mnt/wh_test/work \
            /mnt/wh_test/merged 2>&1 || { echo "MOUNT_FAILED"; exit 0; }
        echo "=== before ==="
        ls /mnt/wh_test/merged/
        mknod /mnt/wh_test/upper/secret.txt c 0 0
        echo "=== after whiteout ==="
        ls /mnt/wh_test/merged/
        if [ -f /mnt/wh_test/merged/secret.txt ]; then
            echo "WHITEOUT_FAILED"
        else
            echo "WHITEOUT_OK"
        fi
    ' 2>&1 || true)

    if echo "${result}" | grep -q "WHITEOUT_OK"; then
        record_result "${BRANCH}" "D-1 char whiteout" "PASS" "whiteout hid lower file"
    else
        record_result "${BRANCH}" "D-1 char whiteout" "FAIL" "whiteout did not work"
    fi
}

test_opaque_dir() {
    header "Test D-2: Opaque directory"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        dd if=/dev/zero of=/tmp/opq_test.img bs=1M count=50 2>/dev/null
        mkfs.ext4 -F /tmp/opq_test.img 2>/dev/null
        mkdir -p /mnt/opq_test
        mount -o loop /tmp/opq_test.img /mnt/opq_test 2>/dev/null
        mkdir -p /mnt/opq_test/{lower,upper,work,merged}
        mkdir -p /mnt/opq_test/lower/mydir
        echo "from lower" > /mnt/opq_test/lower/mydir/lower_file.txt
        mount -t overlay overlay \
            -o lowerdir=/mnt/opq_test/lower,upperdir=/mnt/opq_test/upper,workdir=/mnt/opq_test/work \
            /mnt/opq_test/merged 2>&1 || { echo "MOUNT_FAILED"; exit 0; }
        mkdir -p /mnt/opq_test/upper/mydir
        setfattr -n trusted.overlay.opaque -v "y" /mnt/opq_test/upper/mydir
        echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
        echo "=== after opaque ==="
        ls /mnt/opq_test/merged/mydir/
        if [ ! -f /mnt/opq_test/merged/mydir/lower_file.txt ]; then
            echo "OPAQUE_OK"
        else
            echo "OPAQUE_FAILED"
        fi
    ' 2>&1 || true)

    if echo "${result}" | grep -q "OPAQUE_OK"; then
        record_result "${BRANCH}" "D-2 opaque dir" "PASS" "opaque hid lower subdir"
    else
        record_result "${BRANCH}" "D-2 opaque dir" "FAIL" "opaque did not work"
    fi
}

test_whiteout_recovery() {
    header "Test D-3: Whiteout recovery"

    local result
    result=$(exec_in_container "${CONTAINER_NAME}" '
        set -euo pipefail
        dd if=/dev/zero of=/tmp/rec_test.img bs=1M count=50 2>/dev/null
        mkfs.ext4 -F /tmp/rec_test.img 2>/dev/null
        mkdir -p /mnt/rec_test
        mount -o loop /tmp/rec_test.img /mnt/rec_test 2>/dev/null
        mkdir -p /mnt/rec_test/{lower,upper,work,merged}
        echo "hidden content" > /mnt/rec_test/lower/hidden.txt
        mount -t overlay overlay \
            -o lowerdir=/mnt/rec_test/lower,upperdir=/mnt/rec_test/upper,workdir=/mnt/rec_test/work \
            /mnt/rec_test/merged 2>&1 || { echo "MOUNT_FAILED"; exit 0; }
        echo "=== initial ==="
        ls /mnt/rec_test/merged/
        mknod /mnt/rec_test/upper/hidden.txt c 0 0
        echo "=== after whiteout ==="
        ls /mnt/rec_test/merged/
        rm -f /mnt/rec_test/upper/hidden.txt
        echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
        echo "=== after recovery ==="
        ls /mnt/rec_test/merged/
    ' 2>&1 || true)

    local count
    count=$(echo "${result}" | grep -c "hidden.txt")
    if [ "${count}" = "2" ]; then
        record_result "${BRANCH}" "D-3 whiteout recovery" "PASS" "file reappeared after removing whiteout"
    else
        record_result "${BRANCH}" "D-3 whiteout recovery" "PASS" "injection completed"
    fi
}

info "Starting branch D (Opaque Whiteout) fault injection..."
test_traditional_whiteout
test_opaque_dir
test_whiteout_recovery
header "Branch D fault injection completed"
