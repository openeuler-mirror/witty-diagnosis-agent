#!/bin/bash

# Default values（未指定 --crash 时由 resolve_crash_cmd 解析，优先 ./crash，否则系统 crash）
DEFAULT_CRASH_CMD="./crash"
DEFAULT_VMLINUX_PATH="./vmlinux"
DEFAULT_VMCORE_PATH="./vmcore"

# Help message
function show_help {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --crash <path>        Path to crash command (default: try ./crash, then system crash from PATH)"
    echo "  --vmlinux <path>      Path to vmlinux file (default: $DEFAULT_VMLINUX_PATH)"
    echo "  --vmcore <path>       Path to vmcore file (default: $DEFAULT_VMCORE_PATH)"
    echo "  --help                Show this help message"
}

# Parse arguments
CRASH_CMD="$DEFAULT_CRASH_CMD"
VMLINUX_PATH="$DEFAULT_VMLINUX_PATH"
VMCORE_PATH="$DEFAULT_VMCORE_PATH"
USER_SET_CRASH=false

while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --crash)
            CRASH_CMD="$2"
            USER_SET_CRASH=true
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

# 未指定 --crash：优先可执行的 ./crash，否则使用 PATH 中的 crash（与 which crash 等价）
resolve_crash_cmd() {
    if [[ "$USER_SET_CRASH" == true ]]; then
        return 0
    fi
    if [[ -x "./crash" ]]; then
        CRASH_CMD="./crash"
        return 0
    fi
    local sysc
    sysc=$(command -v crash 2>/dev/null) || true
    if [[ -n "$sysc" ]]; then
        CRASH_CMD="$sysc"
        return 0
    fi
    CRASH_CMD="./crash"
    return 0
}

resolve_crash_cmd

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
if [[ -x "$CRASH_CMD" ]]; then
    echo "OK"
elif command -v "$CRASH_CMD" &> /dev/null; then
    echo "OK"
else
    echo "FAILED"
    echo "Error: '$CRASH_CMD' command not found or not executable."
    if [[ "$USER_SET_CRASH" != true ]]; then
        echo "Hint: place a working ./crash in the current directory, or install crash on the system (PATH)."
    fi
    exit 1
fi

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

run_crash_minimal() {
    "$CRASH_CMD" --minimal "$VMLINUX_PATH" "$VMCORE_PATH" <<'EOF' > /dev/null 2>&1
quit
EOF
}

# 3. Dry run / Compatibility check
echo -n "[3/3] Checking compatibility (Dry Run)... "
if run_crash_minimal; then
    echo "OK"
    echo "----------------------------------------"
    echo "✅ Environment check passed! You are ready to analyze."
    echo "   Command to run:"
    echo "   $CRASH_CMD $VMLINUX_PATH $VMCORE_PATH"
    exit 0
fi
echo "FAILED"

# 用户未指定 --crash 且当前为 ./crash：试跑失败时用系统 crash 再跑一次
if [[ "$USER_SET_CRASH" != true ]] && [[ "$CRASH_CMD" == "./crash" ]]; then
    sysc=$(command -v crash 2>/dev/null) || true
    if [[ -n "$sysc" && "$sysc" != "./crash" ]]; then
        echo "[info] ./crash --minimal 未通过，尝试系统 crash: $sysc"
        CRASH_CMD="$sysc"
        echo -n "[3/3] Checking compatibility (Dry Run, system crash)... "
        if run_crash_minimal; then
            echo "OK"
            echo "----------------------------------------"
            echo "✅ Environment check passed! You are ready to analyze."
            echo "   (使用系统 crash) Command to run:"
            echo "   $CRASH_CMD $VMLINUX_PATH $VMCORE_PATH"
            exit 0
        fi
        echo "FAILED"
    fi
fi

echo "Error: crash execution failed. The vmlinux and vmcore files may not match, or the files are corrupted."
echo "Try running manually to see details:"
echo "$CRASH_CMD --minimal $VMLINUX_PATH $VMCORE_PATH"
exit 1
