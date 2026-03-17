#!/bin/bash

# Default values
DEFAULT_CRASH_CMD="crash"
DEFAULT_VMLINUX_PATH="/usr/lib/debug/lib/modules/$(uname -r)/vmlinux"
DEFAULT_VMCORE_PATH="/var/crash/vmcore"

# Help message
function show_help {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --crash-cmd <path>    Path to crash command (default: $DEFAULT_CRASH_CMD)"
    echo "  --vmlinux <path>      Path to vmlinux file (default: $DEFAULT_VMLINUX_PATH)"
    echo "  --vmcore <path>       Path to vmcore file (default: $DEFAULT_VMCORE_PATH)"
    echo "  --help                Show this help message"
}

# Parse arguments
CRASH_CMD="$DEFAULT_CRASH_CMD"
VMLINUX_PATH="$DEFAULT_VMLINUX_PATH"
VMCORE_PATH="$DEFAULT_VMCORE_PATH"

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --crash-cmd)
            CRASH_CMD="$2"
            shift
            shift
            ;;
        --vmlinux)
            VMLINUX_PATH="$2"
            shift
            shift
            ;;
        --vmcore)
            VMCORE_PATH="$2"
            shift
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

echo "========================================"
echo "OS Crash Analyzer Environment Check"
echo "========================================"
echo "Configuration:"
echo "  CRASH_CMD:    $CRASH_CMD"
echo "  VMLINUX_PATH: $VMLINUX_PATH"
echo "  VMCORE_PATH:  $VMCORE_PATH"
echo "----------------------------------------"

# 1. Check crash command
echo -n "[1/3] Checking crash command... "
if ! command -v "$CRASH_CMD" &> /dev/null; then
    echo "FAILED"
    echo "Error: '$CRASH_CMD' command not found or not executable."
    exit 1
fi
echo "OK"

# 2. Check files
echo -n "[2/3] Checking files existence... "
if [ ! -f "$VMLINUX_PATH" ]; then
    echo "FAILED"
    echo "Error: vmlinux file not found at $VMLINUX_PATH"
    exit 1
fi

if [ ! -f "$VMCORE_PATH" ]; then
    echo "FAILED"
    echo "Error: vmcore file not found at $VMCORE_PATH"
    exit 1
fi
echo "OK"

# 3. Dry run / Compatibility check
echo -n "[3/3] Checking compatibility (Dry Run)... "
if "$CRASH_CMD" --minimal "$VMLINUX_PATH" "$VMCORE_PATH" <<EOF > /dev/null 2>&1
quit
EOF
then
    echo "OK"
    echo "----------------------------------------"
    echo "✅ Environment check passed! You are ready to analyze."
    echo "   Command to run:"
    echo "   $CRASH_CMD $VMLINUX_PATH $VMCORE_PATH"
    exit 0
else
    echo "FAILED"
    echo "Error: crash execution failed. The vmlinux and vmcore files may not match, or the files are corrupted."
    echo "Try running manually to see details:"
    echo "$CRASH_CMD --minimal $VMLINUX_PATH $VMCORE_PATH"
    exit 1
fi