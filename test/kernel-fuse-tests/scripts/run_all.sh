#!/bin/bash
# run_all.sh — Sequential FUSE test suite runner
# Usage: sudo bash run_all.sh [scenario]
#   scenario: A, B, C, D, E, F, H, or ALL (default)

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_DIR="$SCRIPT_DIR/.."
SRC_DIR="$TEST_DIR/src"

echo "============================================"
echo " FUSE Kernel Fault Diagnosis Test Suite"
echo "============================================"
echo ""

# Ensure environment
echo "[Pre-check] Building test daemons..."
make -C "$SRC_DIR" 2>&1 | tail -3
echo ""

run_scenario() {
    local name="$1"
    local script="$2"
    local desc="$3"

    echo "============================================"
    echo " Scenario $name: $desc"
    echo "============================================"

    # Run inject script
    bash "$SCRIPT_DIR/$script"
    echo ""

    # Wait for observation
    echo "  [Manual step] Run Witty pipeline with fault description."
    echo "  Then press Enter to continue to cleanup..."
    read -p "  Press Enter to cleanup and continue... " dummy

    # Cleanup
    bash "$SCRIPT_DIR/cleanup.sh"
    echo ""
}

# Run selected or all
SCENARIO="${1:-ALL}"

case "$SCENARIO" in
    A|a)
        run_scenario "A" "inject_daemon_crash.sh /tmp/fuse_test sigkill" "Daemon Crash → EIO"
        ;;
    B|b)
        run_scenario "B" "inject_req_queue.sh /tmp/fuse_slow_test 500" "Request Queue Block"
        ;;
    C|c)
        run_scenario "C" "inject_max_read_write.sh /tmp/fuse_test_mount 4096" "max_read Misconfig"
        ;;
    D|d)
        echo "Scenario D: Writeback Cache — requires custom daemon implementation"
        echo "  Enable writeback_cache mount option and test consistency"
        echo "  Manual test only at this time."
        ;;
    E|e)
        run_scenario "E" "inject_mt_deadlock.sh /tmp/fuse_deadlock_test" "MT Deadlock"
        ;;
    F|f)
        run_scenario "F" "inject_dev_fuse_perm.sh 0600 root:root" "/dev/fuse Permission"
        ;;
    H|h)
        echo "Scenario H: Mixed — run multiple scenarios"
        run_scenario "A" "inject_daemon_crash.sh /tmp/fuse_test sigsegv" "A: Daemon Crash"
        run_scenario "C" "inject_max_read_write.sh /tmp/fuse_test_mount 4096" "C: max_read"
        ;;
    ALL|all)
        echo "Running all scenarios..."
        run_scenario "A" "inject_daemon_crash.sh /tmp/fuse_test sigsegv" "Daemon Crash"
        run_scenario "B" "inject_req_queue.sh /tmp/fuse_slow_test 500" "Request Queue Block"
        run_scenario "C" "inject_max_read_write.sh /tmp/fuse_test_mount 4096" "max_read Misconfig"
        run_scenario "E" "inject_mt_deadlock.sh /tmp/fuse_deadlock_test" "MT Deadlock"
        run_scenario "F" "inject_dev_fuse_perm.sh 0600 root:root" "/dev/fuse Permission"
        echo ""
        echo "Note: Scenarios D (Writeback Cache) and G (Kernel Bug) require"
        echo "      manual setup. See test plan for details."
        ;;
    *)
        echo "Unknown scenario: $SCENARIO"
        echo "Usage: $0 [A|B|C|D|E|F|G|H|ALL]"
        exit 1
        ;;
esac

echo ""
echo "============================================"
echo " Test suite complete."
echo "============================================"
