#!/bin/bash

# Session start hook for witty-diagnosis-agent
# This script is executed when a new diagnosis session starts

set -e

echo "Starting diagnosis session: $(date)"
echo "Session ID: ${SESSION_ID:-unknown}"
echo "User: ${USER:-unknown}"
echo "Hostname: $(hostname)"

# Log session start
logger -t witty-diagnosis-agent "Diagnosis session started: ${SESSION_ID:-unknown}"

# Create session directory if needed
if [ -n "${SESSION_DIR}" ]; then
    mkdir -p "${SESSION_DIR}"
    echo "Session directory: ${SESSION_DIR}"
fi

# Initialize session variables
export DIAGNOSIS_START_TIME=$(date +%s)
export SYSTEM_INFO=$(uname -a)

echo "System info: ${SYSTEM_INFO}"
echo "Session start time: ${DIAGNOSIS_START_TIME}"

# Check system requirements
echo "Checking system requirements..."

# Check for required commands
REQUIRED_COMMANDS=("python3" "curl" "jq" "systemctl")
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if command -v "${cmd}" >/dev/null 2>&1; then
        echo "✓ ${cmd} is available"
    else
        echo "⚠ ${cmd} is not available"
    fi
done

# Check disk space
DISK_SPACE=$(df -h / | awk 'NR==2 {print $4}')
echo "Available disk space: ${DISK_SPACE}"

# Check memory
MEMORY=$(free -h | awk 'NR==2 {print $7}')
echo "Available memory: ${MEMORY}"

echo "Session start hook completed successfully"