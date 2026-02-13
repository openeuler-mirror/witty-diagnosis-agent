#!/bin/bash
# rca_wizard.sh - Interactive Root Cause Analysis Wizard
# Guides through systematic RCA process

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
RCA_DIR="${HOME}/rca_reports"
RCA_FILE="${RCA_DIR}/rca_${TIMESTAMP}.txt"

mkdir -p "$RCA_DIR"

# Header
clear
cat << 'EOF'
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║        ROOT CAUSE ANALYSIS WIZARD                            ║
║        Systematic approach to finding true root causes       ║
║                                                               ║
║  ⚠️  CRITICAL: Every claim needs concrete evidence          ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝

This wizard will guide you through deep root cause analysis.

IMPORTANT: You will be asked for EVIDENCE for every claim you make.
Evidence means: specific crash commands, addresses, values, code locations.
NOT: "probably", "seems like", "I think", "usually".

TIP: Have your crash dump analysis results ready. You'll need to cite:
  - crash> sys, log, bt outputs
  - crash> struct, dis, kmem results  
  - Code files, git commits, log files

All responses will be saved to: 
EOF
echo -e "${CYAN}${RCA_FILE}${NC}"
echo ""
echo -e "${YELLOW}建议: 先运行 ./evidence_chain.sh 构建证据链，再运行本向导${NC}"
read -p "按Enter继续..."
echo ""

# Initialize report
cat > "$RCA_FILE" << REPORT_EOF
================================================================================
                     ROOT CAUSE ANALYSIS REPORT
================================================================================
Date: $(date)
Analyst: $(whoami)
System: $(hostname)

REPORT_EOF

# Function to prompt for input
prompt() {
    local question="$1"
    local var_name="$2"
    echo -e "${YELLOW}${question}${NC}"
    read -p "> " response
    echo "$response"
    
    # Save to report
    echo "" >> "$RCA_FILE"
    echo "$question" >> "$RCA_FILE"
    echo "→ $response" >> "$RCA_FILE"
}

# Section 1: Basic Information
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}SECTION 1: BASIC INFORMATION${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "SECTION 1: BASIC INFORMATION" >> "$RCA_FILE"
echo "==============================" >> "$RCA_FILE"

SYMPTOM=$(prompt "What is the observable symptom? (e.g., 'kernel panic', 'system hang')")
WHEN=$(prompt "When did this occur? (timestamp or 'T-Xh' format)")
FREQUENCY=$(prompt "How often does this occur? (first time / intermittent / always)")
WORKLOAD=$(prompt "What was the system doing? (workload description)")

# Section 2: Initial Findings
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}SECTION 2: INITIAL FINDINGS FROM CRASH DUMP${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "" >> "$RCA_FILE"
echo "SECTION 2: INITIAL FINDINGS" >> "$RCA_FILE"
echo "===========================" >> "$RCA_FILE"

PANIC_MSG=$(prompt "Panic message from 'crash> sys':")
CRASH_FUNC=$(prompt "Function where crash occurred (from 'crash> bt'):")
CRASH_ADDR=$(prompt "Crash address (if NULL deref, enter '0x0'):")

# Section 3: The 5 Whys
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}SECTION 3: THE 5 WHYS ANALYSIS${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}Keep asking 'why' until you reach a systemic issue${NC}"
echo ""

echo "" >> "$RCA_FILE"
echo "SECTION 3: THE 5 WHYS" >> "$RCA_FILE"
echo "=====================" >> "$RCA_FILE"

WHY1=$(prompt "1. Why did the crash occur? (the immediate technical cause)")
WHY2=$(prompt "2. Why did that condition exist? (what led to it)")
WHY3=$(prompt "3. Why was that possible? (what allowed it)")
WHY4=$(prompt "4. Why wasn't this prevented? (what protection was missing)")
WHY5=$(prompt "5. Why is this issue possible in the design? (the systemic issue)")

echo ""
echo -e "${YELLOW}⚠️  CHECKPOINT: Is answer #5 a systemic/design issue?${NC}"
echo -e "If it's still a specific technical detail, keep asking 'why'"
read -p "Press Enter to continue..."

# Section 4: Evidence Collection
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}SECTION 4: EVIDENCE FROM CRASH DUMP${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}List specific findings that support your root cause${NC}"
echo ""

echo "" >> "$RCA_FILE"
echo "SECTION 4: SUPPORTING EVIDENCE" >> "$RCA_FILE"
echo "==============================" >> "$RCA_FILE"

EVIDENCE1=$(prompt "Evidence #1 (e.g., 'struct foo.bar = 0x0'):")
EVIDENCE2=$(prompt "Evidence #2 (e.g., 'bt shows function X called without init'):")
EVIDENCE3=$(prompt "Evidence #3 (e.g., 'log shows 1000 errors before crash'):")
EVIDENCE4=$(prompt "Evidence #4 (additional evidence, or press Enter to skip):")

# Section 5: Alternative Hypotheses
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}SECTION 5: ALTERNATIVE HYPOTHESES${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}What ELSE could explain this crash?${NC}"
echo ""

echo "" >> "$RCA_FILE"
echo "SECTION 5: ALTERNATIVE HYPOTHESES" >> "$RCA_FILE"
echo "=================================" >> "$RCA_FILE"

ALT1=$(prompt "Alternative hypothesis #1:")
ALT1_DISPROOF=$(prompt "Why is this disproven? (evidence from crash dump):")

ALT2=$(prompt "Alternative hypothesis #2:")
ALT2_DISPROOF=$(prompt "Why is this disproven? (evidence from crash dump):")

# Section 6: Validation Checklist
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}SECTION 6: ROOT CAUSE VALIDATION${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}Answer YES or NO to each validation question${NC}"
echo ""

echo "" >> "$RCA_FILE"
echo "SECTION 6: VALIDATION CHECKLIST" >> "$RCA_FILE"
echo "===============================" >> "$RCA_FILE"

validate() {
    local question="$1"
    echo -e "${YELLOW}$question${NC}"
    read -p "[Y/N]> " answer
    echo "$question → $answer" >> "$RCA_FILE"
    if [[ "$answer" =~ ^[Nn] ]]; then
        return 1
    fi
    return 0
}

FAIL_COUNT=0

validate "Can you show the exact memory state that caused the crash?" || ((FAIL_COUNT++))
validate "Can you trace the sequence of function calls that led here?" || ((FAIL_COUNT++))
validate "Can you explain WHY the system was in this state?" || ((FAIL_COUNT++))
validate "Does your explanation account for ALL observations?" || ((FAIL_COUNT++))
validate "Is your root cause specific enough to guide a fix?" || ((FAIL_COUNT++))
validate "Would the fix prevent this CLASS of errors, not just this instance?" || ((FAIL_COUNT++))

echo ""
if [ $FAIL_COUNT -eq 0 ]; then
    echo -e "${GREEN}✓ All validation checks passed!${NC}"
    echo "VALIDATION: PASSED (0 failures)" >> "$RCA_FILE"
else
    echo -e "${RED}⚠ $FAIL_COUNT validation checks failed${NC}"
    echo -e "${YELLOW}You may need deeper analysis before concluding root cause${NC}"
    echo "VALIDATION: NEEDS MORE WORK ($FAIL_COUNT failures)" >> "$RCA_FILE"
fi

# Section 7: Root Cause Statement
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}SECTION 7: ROOT CAUSE STATEMENT${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "" >> "$RCA_FILE"
echo "SECTION 7: ROOT CAUSE STATEMENT" >> "$RCA_FILE"
echo "================================" >> "$RCA_FILE"

ROOT_CAUSE=$(prompt "ROOT CAUSE (the fundamental systemic issue):")
MECHANISM=$(prompt "MECHANISM (how it manifested as a crash):")
SYSTEMIC=$(prompt "SYSTEMIC ISSUE (why this was possible):")
SCOPE=$(prompt "SCOPE (one-time or recurring? local or widespread?):")

# Section 8: Recommended Actions
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}SECTION 8: RECOMMENDED ACTIONS${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "" >> "$RCA_FILE"
echo "SECTION 8: RECOMMENDED ACTIONS" >> "$RCA_FILE"
echo "==============================" >> "$RCA_FILE"

IMMEDIATE=$(prompt "IMMEDIATE FIX (what fixes this specific crash):")
SYSTEMIC_FIX=$(prompt "SYSTEMIC FIX #1 (what prevents this class of issues):")
SYSTEMIC_FIX2=$(prompt "SYSTEMIC FIX #2 (additional preventive measure):")
VERIFICATION=$(prompt "VERIFICATION (how to test the fix):")

# Generate Summary
echo "" >> "$RCA_FILE"
echo "" >> "$RCA_FILE"
echo "================================================================================" >> "$RCA_FILE"
echo "                               EXECUTIVE SUMMARY" >> "$RCA_FILE"
echo "================================================================================" >> "$RCA_FILE"
echo "" >> "$RCA_FILE"
echo "SYMPTOM: $SYMPTOM" >> "$RCA_FILE"
echo "" >> "$RCA_FILE"
echo "ROOT CAUSE: $ROOT_CAUSE" >> "$RCA_FILE"
echo "" >> "$RCA_FILE"
echo "MECHANISM: $MECHANISM" >> "$RCA_FILE"
echo "" >> "$RCA_FILE"
echo "SCOPE: $SCOPE" >> "$RCA_FILE"
echo "" >> "$RCA_FILE"
echo "RECOMMENDED ACTIONS:" >> "$RCA_FILE"
echo "  Immediate: $IMMEDIATE" >> "$RCA_FILE"
echo "  Systemic:  $SYSTEMIC_FIX" >> "$RCA_FILE"
echo "            $SYSTEMIC_FIX2" >> "$RCA_FILE"
echo "" >> "$RCA_FILE"
echo "================================================================================" >> "$RCA_FILE"

# Final output
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ ROOT CAUSE ANALYSIS COMPLETE${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "Full report saved to: ${CYAN}${RCA_FILE}${NC}"
echo ""
echo "EXECUTIVE SUMMARY:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Symptom:     $SYMPTOM"
echo "Root Cause:  $ROOT_CAUSE"
echo "Scope:       $SCOPE"
echo ""
echo "To review full report:"
echo "  less $RCA_FILE"
echo ""

if [ $FAIL_COUNT -gt 0 ]; then
    echo -e "${YELLOW}⚠️  ATTENTION: $FAIL_COUNT validation checks failed${NC}"
    echo -e "${YELLOW}Consider additional analysis before finalizing root cause${NC}"
    echo ""
fi

echo -e "${CYAN}Remember: The goal is to find the SYSTEMIC issue, not just fix this crash!${NC}"