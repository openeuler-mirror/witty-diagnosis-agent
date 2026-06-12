#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_B_rule_mishit.sh
# 用途：iptables/nftables 规则误命中导致 DROP/REJECT
#       当基线采集显示有 DROP/REJECT 规则且 pkts > 0 时使用
# 使用：bash branch_B_rule_mishit.sh [基线采集目录]
# 参数：
#   $1  基线采集目录（由 01_collect_baseline.sh 生成的输出目录）
# =============================================================================

set -euo pipefail

BASE_DIR="${1:-/tmp/netfilter_diag_*}"
if [[ "$BASE_DIR" == *"*"* ]]; then
    BASE_DIR=$(ls -dt /tmp/netfilter_diag_* 2>/dev/null | head -1)
fi
if [[ -z "$BASE_DIR" || ! -d "$BASE_DIR" ]]; then
    echo "错误：请先执行 01_collect_baseline.sh，然后传入其输出目录"
    echo "使用：bash branch_B_rule_mishit.sh <基线采集目录>"
    exit 1
fi

echo "=================================================================="
echo " 分支B：iptables/nftables 规则误命中 DROP/REJECT"
echo " 基线目录: ${BASE_DIR}"
echo "=================================================================="

# ---- Step B1: iptables 规则命中审计 ----
echo ""
echo "【B1】iptables 规则命中审计"
echo "------------------------------------------------------------------"
for table in raw mangle nat filter security; do
    rule_file="${BASE_DIR}/ruleset/iptables_${table}.txt"
    if [[ -f "$rule_file" ]]; then
        echo "=== table: ${table} ==="
        # 查找 pkts > 0 的 DROP/REJECT 规则
        grep -n 'DROP\|REJECT' "$rule_file" | while IFS= read -r line; do
            pkts=$(echo "$line" | awk '{print $1}')
            if [[ "$pkts" =~ ^[0-9]+$ ]] && [[ "$pkts" -gt 0 ]]; then
                echo "  ⚠️  ACTIVE: $line"
            fi
        done
        # 查找 pkts > 0 的其他规则（可能显示流量方向）
        echo ""
    fi
done

# ---- Step B2: nftables 规则命中审计 ----
echo ""
echo "【B2】nftables 规则命中审计"
echo "------------------------------------------------------------------"
if [[ -f "${BASE_DIR}/ruleset/nftables_ruleset.txt" ]]; then
    echo "[nftables 规则集摘要]"
    grep -n "drop\|reject\|counter" "${BASE_DIR}/ruleset/nftables_ruleset.txt" \
        | head -40 || echo "  (无 drop/reject 规则或 counter)"
fi
if [[ -f "${BASE_DIR}/ruleset/nftables_counters.txt" ]]; then
    echo ""
    echo "[nftables counters]"
    head -30 "${BASE_DIR}/ruleset/nftables_counters.txt" || true
fi

# ---- Step B3: 规则链路径推导 ----
echo ""
echo "【B3】规则链流量路径推导"
echo "------------------------------------------------------------------"
echo "[INPUT 路径]"
if [[ -f "${BASE_DIR}/ruleset/iptables_raw.txt" ]]; then
    echo "  raw:PREROUTING → "
fi
echo "  mangle:PREROUTING → nat:PREROUTING → 路由决策 →"
if [[ -f "${BASE_DIR}/ruleset/iptables_filter.txt" ]]; then
    filter_policy=$(grep "Chain INPUT" "${BASE_DIR}/ruleset/iptables_filter.txt" | grep -oP 'policy \K\w+')
    echo "  filter:INPUT (policy=${filter_policy}) →"
fi
echo "  本机应用"

echo ""
echo "[FORWARD 路径]"
echo "  PRE_ROUTING → 路由决策（转发）→"
if [[ -f "${BASE_DIR}/ruleset/iptables_filter.txt" ]]; then
    forward_policy=$(grep "Chain FORWARD" "${BASE_DIR}/ruleset/iptables_filter.txt" | grep -oP 'policy \K\w+')
    echo "  filter:FORWARD (policy=${forward_policy}) →"
fi
echo "  POST_ROUTING → 出站"

# ---- Step B4: DROP 规则命中计数汇总 ----
echo ""
echo "【B4】DROP/REJECT 规则命中计数汇总"
echo "------------------------------------------------------------------"
echo "规则来源: iptables"
find "${BASE_DIR}/ruleset" -name "iptables_*.txt" -exec grep -cE "DROP|REJECT" {} \; 2>/dev/null \
    | awk -F: '{sum+=$2} END {print "  DROP/REJECT 规则总数: " sum}'
echo ""
echo "pkts > 0 的 DROP/REJECT 规则:"
for f in "${BASE_DIR}/ruleset"/iptables_*.txt; do
    [[ -f "$f" ]] || continue
    table_name=$(basename "$f" .txt | sed 's/iptables_//')
    while IFS= read -r line; do
        pkts=$(echo "$line" | awk '{print $1}')
        if [[ "$pkts" =~ ^[0-9]+$ ]] && [[ "$pkts" -gt 0 ]]; then
            echo "  [${table_name}] $line"
        fi
    done < <(grep -E "DROP|REJECT" "$f")
done

echo ""
echo "【B5】诊断结论（模板）"
echo "------------------------------------------------------------------"
echo "  故障类型: 规则误命中 DROP/REJECT"
echo "  R2 命中计数: （见上方 R4 汇总）"
echo "  R4 路径推导: filter:INPUT/FORWARD policy 及 DROP 规则决定流量命运"
echo ""
echo "  建议修复动作（仅建议，不自动执行）:"
echo "  🟡 中危: 确认 DROP 规则是否为预期配置"
echo "     检查对应规则的来源和目的是否匹配故障流量"
echo "  🟡 中危: 如需调整规则顺序，确保 ACCEPT 规则在 DROP 之前"
echo "     iptables -I <chain> <position> ... -j ACCEPT"
echo "  🔴 高危: 如需删除规则，确认业务影响后在低峰期操作"
echo "     iptables -D <chain> <rule-number>"
echo "     nft delete rule <table> <chain> handle <handle>"
echo ""
echo "请参考 SKILL.md 第四节 Step 5（交叉验证）和第八节（报告模板）完成最终输出。"
