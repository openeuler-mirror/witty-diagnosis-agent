#!/bin/bash
# quick_report.sh - Generate initial crash assessment report

set -e

REPORT_DIR="${HOME}/crash_reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
REPORT_FILE="${REPORT_DIR}/report_${TIMESTAMP}.txt"

# Load configuration
CONFIG_FILE="${HOME}/.crash_analyzer.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "Error: No configuration file found"
    exit 1
fi

mkdir -p "$REPORT_DIR"

echo "Generating crash analysis report..."

# Create crash command script for quick assessment
CRASH_SCRIPT=$(mktemp)
cat > "$CRASH_SCRIPT" << 'CRASH_EOF'
# Phase 1: Initial Assessment
sys
log | tail -100
bt

# Phase 2: Context
ps
bt -a

# Phase 3: Memory Overview
kmem -i
kmem -s | head -50

# Exit
exit
CRASH_EOF

# Generate report
{
    cat << EOF
================================================================================
                        CRASH ANALYSIS REPORT
================================================================================
Generated: $(date)
Analyst: $(whoami)@$(hostname)

Configuration:
  Kernel Image: $VMLINUX_PATH
  Core Dump:    $VMCORE_PATH
  Crash Tool:   $CRASH_CMD

================================================================================
                        PHASE 1: INITIAL ASSESSMENT
================================================================================

EOF

    "$CRASH_CMD" "$VMLINUX_PATH" "$VMCORE_PATH" < "$CRASH_SCRIPT" 2>&1

    cat << EOF

================================================================================
                        ANALYSIS RECOMMENDATIONS
================================================================================

Based on the initial assessment, consider:

1. Review the panic message in the 'sys' output
2. Check the last 100 log lines for errors/warnings
3. Examine the crashing task's backtrace (bt output)
4. Look for processes in UN (uninterruptible) state
5. Check memory statistics for OOM conditions

Next Steps:
- If memory related: Run 'kmem -s | grep -v " 0 "' to find slab leaks
- If deadlock suspected: Run 'foreach bt | grep -A5 UN' for stuck tasks
- If panic unclear: Run 'dis -l <function>' on crash point

================================================================================
EOF

} > "$REPORT_FILE"

rm -f "$CRASH_SCRIPT"

echo "Report generated: $REPORT_FILE"
echo ""
echo "Summary:"
grep -A2 "PANIC\|Oops\|BUG:" "$REPORT_FILE" | head -20 || echo "  No panic messages found in report"

echo ""
echo "To view full report: less $REPORT_FILE"