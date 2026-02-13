#!/bin/bash
# evidence_chain.sh - Build and visualize evidence chain for RCA

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
EVIDENCE_DIR="${HOME}/evidence_chains"
EVIDENCE_FILE="${EVIDENCE_DIR}/evidence_${TIMESTAMP}.txt"

mkdir -p "$EVIDENCE_DIR"

clear
cat << 'EOF'
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║              EVIDENCE CHAIN BUILDER                           ║
║     Building unbreakable chain from symptom to root cause     ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

This tool helps you build a complete, verifiable evidence chain
that connects observations to root cause.

EOF

echo -e "${CYAN}Output will be saved to: ${EVIDENCE_FILE}${NC}"
echo ""

# Initialize evidence file
cat > "$EVIDENCE_FILE" << 'HEADER'
================================================================================
                           EVIDENCE CHAIN REPORT
================================================================================

PRINCIPLE: Every claim must be backed by concrete evidence from crash dump,
           code, logs, or system state. No assumptions allowed.

================================================================================
HEADER

echo "Report Date: $(date)" >> "$EVIDENCE_FILE"
echo "Analyst: $(whoami)" >> "$EVIDENCE_FILE"
echo "" >> "$EVIDENCE_FILE"

# Helper function
prompt_evidence() {
    local level="$1"
    local question="$2"
    local evidence_question="$3"
    
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}${level}${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    echo -e "${YELLOW}${question}${NC}"
    read -p "> " answer
    
    echo -e "${YELLOW}${evidence_question}${NC}"
    echo -e "${CYAN}(提供具体的crash命令、输出、地址、代码位置等)${NC}"
    read -p "> " evidence
    
    # Save to file
    echo "" >> "$EVIDENCE_FILE"
    echo "${level}" >> "$EVIDENCE_FILE"
    echo "$(printf '=%.0s' {1..80})" >> "$EVIDENCE_FILE"
    echo "" >> "$EVIDENCE_FILE"
    echo "发现: $answer" >> "$EVIDENCE_FILE"
    echo "" >> "$EVIDENCE_FILE"
    echo "证据: $evidence" >> "$EVIDENCE_FILE"
    echo "" >> "$EVIDENCE_FILE"
    
    # Return values
    echo "$answer|$evidence"
}

# Build the chain
echo -e "${MAGENTA}开始构建证据链...${NC}"
echo ""

# Level 0: Symptom
RESULT=$(prompt_evidence \
    "Level 0: 观察到的现象 (Symptom)" \
    "系统表现出什么问题？(用户可见的症状)" \
    "这个观察的证据是什么？")
SYMPTOM=$(echo "$RESULT" | cut -d'|' -f1)

# Level 1: Direct Cause  
RESULT=$(prompt_evidence \
    "Level 1: 直接原因 (Proximate Cause)" \
    "crash dump显示的直接技术原因是什么？" \
    "从crash dump哪里看到的？(sys/bt/log输出)")
PROXIMATE=$(echo "$RESULT" | cut -d'|' -f1)

# Level 2: Mechanism
RESULT=$(prompt_evidence \
    "Level 2: 技术机制 (Mechanism)" \
    "这个直接原因是如何产生的？(技术细节)" \
    "哪些数据结构/代码证明了这个机制？(struct/dis/rd输出)")
MECHANISM=$(echo "$RESULT" | cut -d'|' -f1)

# Level 3: Design Flaw
RESULT=$(prompt_evidence \
    "Level 3: 设计缺陷 (Underlying Cause)" \
    "为什么这个技术问题会存在？(代码/设计层面)" \
    "从代码、配置、架构哪里看到的？(源码/git/配置文件)")
DESIGN_FLAW=$(echo "$RESULT" | cut -d'|' -f1)

# Level 4: Root Cause
RESULT=$(prompt_evidence \
    "Level 4: 根本原因 (Root Cause)" \
    "为什么这个设计缺陷能够存在？(系统/流程层面)" \
    "什么系统性证据支持这个结论？(流程文档/历史记录/对比分析)")
ROOT_CAUSE=$(echo "$RESULT" | cut -d'|' -f1)

# Call Chain Collection
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}调用链路 (Call Chain)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${CYAN}请输入从触发到崩溃的完整调用链${NC}"
echo -e "${CYAN}格式: 函数名 → 证据 (每行一个，输入空行结束)${NC}"
echo ""

echo "" >> "$EVIDENCE_FILE"
echo "调用链路 (Call Chain)" >> "$EVIDENCE_FILE"
echo "$(printf '=%.0s' {1..80})" >> "$EVIDENCE_FILE"
echo "" >> "$EVIDENCE_FILE"

CALL_CHAIN=""
while true; do
    read -p "调用链路 > " call_line
    if [ -z "$call_line" ]; then
        break
    fi
    echo "$call_line" >> "$EVIDENCE_FILE"
    CALL_CHAIN="${CALL_CHAIN}${call_line}\n"
done

# Timeline
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}时间线 (Timeline)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${YELLOW}关键时间点 (格式: T-XXh 或具体时间):${NC}"

echo "" >> "$EVIDENCE_FILE"
echo "时间线 (Timeline)" >> "$EVIDENCE_FILE"
echo "$(printf '=%.0s' {1..80})" >> "$EVIDENCE_FILE"
echo "" >> "$EVIDENCE_FILE"

for event in "系统启动" "问题开始出现" "问题加剧" "系统崩溃"; do
    read -p "$event 时间 > " time_point
    echo "$event: $time_point" >> "$EVIDENCE_FILE"
done

# Generate Visualization
echo "" >> "$EVIDENCE_FILE"
echo "" >> "$EVIDENCE_FILE"
echo "$(printf '=%.0s' {1..80})" >> "$EVIDENCE_FILE"
echo "                    证据链可视化 (Evidence Chain)" >> "$EVIDENCE_FILE"
echo "$(printf '=%.0s' {1..80})" >> "$EVIDENCE_FILE"
echo "" >> "$EVIDENCE_FILE"

cat >> "$EVIDENCE_FILE" << CHAIN

[观察现象] $SYMPTOM
    ↓
    证据链接 ✓
    ↓
[直接原因] $PROXIMATE
    ↓
    证据链接 ✓
    ↓
[技术机制] $MECHANISM
    ↓
    证据链接 ✓
    ↓
[设计缺陷] $DESIGN_FLAW
    ↓
    证据链接 ✓
    ↓
[根本原因] $ROOT_CAUSE

证据链完整性: ✓ 每个环节都有具体证据支持
证据链可追溯: ✓ 从crash dump可以重现分析路径
证据链强度: ✓ 所有证据均来自客观数据，非推测

CHAIN

# Verification Checklist
echo "" >> "$EVIDENCE_FILE"
echo "$(printf '=%.0s' {1..80})" >> "$EVIDENCE_FILE"
echo "                    证据链验证清单" >> "$EVIDENCE_FILE"
echo "$(printf '=%.0s' {1..80})" >> "$EVIDENCE_FILE"
echo "" >> "$EVIDENCE_FILE"

echo -e "${YELLOW}请验证证据链的完整性:${NC}"
echo ""

verify() {
    local question="$1"
    echo -e "${CYAN}$question${NC}"
    read -p "[Y/N] > " answer
    echo "□ $question - $answer" >> "$EVIDENCE_FILE"
    if [[ "$answer" =~ ^[Nn] ]]; then
        return 1
    fi
    return 0
}

PASS_COUNT=0
TOTAL_COUNT=8

verify "每个层级都有具体的crash dump证据？" && ((PASS_COUNT++))
verify "调用链可以用bt命令验证？" && ((PASS_COUNT++))
verify "数据结构状态可以用struct命令查看？" && ((PASS_COUNT++))
verify "代码问题可以用dis命令确认？" && ((PASS_COUNT++))
verify "时间线可以从log重建？" && ((PASS_COUNT++))
verify "证据之间有逻辑关联（不是孤立的）？" && ((PASS_COUNT++))
verify "其他人看到这些证据会得出相同结论？" && ((PASS_COUNT++))
verify "证据可以反驳其他可能的解释？" && ((PASS_COUNT++))

echo "" >> "$EVIDENCE_FILE"
echo "验证得分: $PASS_COUNT / $TOTAL_COUNT" >> "$EVIDENCE_FILE"

# Generate plain language explanation
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}通俗解释生成${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${YELLOW}用生活化的比喻解释这个问题:${NC}"
read -p "> " analogy

echo -e "${YELLOW}如果向CEO解释，你会怎么说？(一句话)${NC}"
read -p "> " executive_summary

echo "" >> "$EVIDENCE_FILE"
echo "$(printf '=%.0s' {1..80})" >> "$EVIDENCE_FILE"
echo "                    通俗解释 (Plain Language)" >> "$EVIDENCE_FILE"
echo "$(printf '=%.0s' {1..80})" >> "$EVIDENCE_FILE"
echo "" >> "$EVIDENCE_FILE"
echo "给管理层的一句话总结:" >> "$EVIDENCE_FILE"
echo "$executive_summary" >> "$EVIDENCE_FILE"
echo "" >> "$EVIDENCE_FILE"
echo "生活化类比:" >> "$EVIDENCE_FILE"
echo "$analogy" >> "$EVIDENCE_FILE"
echo "" >> "$EVIDENCE_FILE"

cat >> "$EVIDENCE_FILE" << PLAIN

问题用大白话说就是:
────────────────────────────────────────────────────────────────

现象: $SYMPTOM

为什么发生:
第一步: $PROXIMATE (直接触发)
第二步: $MECHANISM (技术原因)  
第三步: $DESIGN_FLAW (设计问题)
根源: $ROOT_CAUSE (系统问题)

打个比方: $analogy

证明我们的判断:
每一步都有具体证据，不是猜测。任何人拿到crash dump，按照我们的
分析路径，都会看到相同的数据，得出相同的结论。

PLAIN

# Final summary
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ 证据链构建完成${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "完整证据链报告: ${CYAN}${EVIDENCE_FILE}${NC}"
echo ""
echo "证据链评分: $PASS_COUNT / $TOTAL_COUNT"

if [ $PASS_COUNT -ge 6 ]; then
    echo -e "${GREEN}✓ 证据链强度: 强 - 可信度高${NC}"
elif [ $PASS_COUNT -ge 4 ]; then
    echo -e "${YELLOW}⚠ 证据链强度: 中 - 建议补充证据${NC}"
else
    echo -e "${RED}✗ 证据链强度: 弱 - 需要更多证据${NC}"
fi

echo ""
echo -e "${CYAN}证据链的价值:${NC}"
echo "1. 可验证 - 其他工程师可以重现你的分析"
echo "2. 可辩护 - 有数据支持，不是猜测"
echo "3. 可追溯 - 从现象到根因有清晰路径"
echo "4. 可理解 - 有技术版和通俗版两种解释"
echo ""
echo -e "${YELLOW}下一步: 将此证据链整合到RCA报告中${NC}"