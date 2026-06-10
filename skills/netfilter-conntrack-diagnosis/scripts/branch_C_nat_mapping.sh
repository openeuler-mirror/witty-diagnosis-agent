#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_C_nat_mapping.sh
# 用途：NAT/SNAT/DNAT 映射异常分析
#       当 NAT 映射异常、SNAT 未生效、DNAT 未到达目标时使用
# 使用：bash branch_C_nat_mapping.sh [基线采集目录]
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
    echo "使用：bash branch_C_nat_mapping.sh <基线采集目录>"
    exit 1
fi

echo "=================================================================="
echo " 分支C：NAT/SNAT/DNAT 映射异常"
echo " 基线目录: ${BASE_DIR}"
echo "=================================================================="

# ---- Step C1: NAT 规则链检查 ----
echo ""
echo "【C1】NAT 规则链"
echo "------------------------------------------------------------------"
if [[ -f "${BASE_DIR}/ruleset/iptables_nat.txt" ]]; then
    echo "[iptables nat 表]"
    cat "${BASE_DIR}/ruleset/iptables_nat.txt"
else
    echo "(无 iptables nat 表数据)"
fi

echo ""
echo "[iptables NAT 规则 save 格式]"
if [[ -f "${BASE_DIR}/ruleset/iptables_save.txt" ]]; then
    grep -E "nat|SNAT|DNAT|MASQUERADE|REDIRECT" "${BASE_DIR}/ruleset/iptables_save.txt" \
        | head -30 || echo "  (无 NAT 相关规则)"
fi

# ---- Step C2: conntrack NAT entry 核验 ----
echo ""
echo "【C2】conntrack NAT 映射条目"
echo "------------------------------------------------------------------"
if command -v conntrack &>/dev/null; then
    echo "[NAT 映射条目 (conntrack -L -n)]"
    conntrack -L -n 2>/dev/null | head -50 || echo "  (无 NAT 映射条目或工具不可用)"
    echo ""
    echo "[NAT 映射统计]"
    conntrack -L -n 2>/dev/null | awk '
        /SNAT/ { snat++ }
        /DNAT/ { dnat++ }
        END {
            print "  SNAT mappings: " (snat+0)
            print "  DNAT mappings: " (dnat+0)
        }
    ' || true
else
    echo "(conntrack 工具不可用，使用 /proc/net/nf_conntrack 降级)"
    grep -E "SNAT|DNAT" /proc/net/nf_conntrack 2>/dev/null | head -50 || echo "  (无 NAT entry)"
fi

# ---- Step C3: NAT 转换前后地址比对 ----
echo ""
echo "【C3】NAT 转换前后地址比对"
echo "------------------------------------------------------------------"
echo "[转换前 → 转换后 示例条目]"
if command -v conntrack &>/dev/null; then
    conntrack -L -n 2>/dev/null | head -20 | while IFS= read -r entry; do
        if echo "$entry" | grep -q "SNAT"; then
            src=$(echo "$entry" | grep -oP 'src=\S+' | head -1)
            dst=$(echo "$entry" | grep -oP 'dst=\S+' | head -1)
            echo "  SNAT: $src → $dst"
        elif echo "$entry" | grep -q "DNAT"; then
            src=$(echo "$entry" | grep -oP 'src=\S+' | head -1)
            dst=$(echo "$entry" | grep -oP 'dst=\S+' | head -1)
            echo "  DNAT: $src → $dst"
        fi
    done
fi

# ---- Step C4: MASQUERADE 检查 ----
echo ""
echo "【C4】MASQUERADE 和 SNAT 规则检查"
echo "------------------------------------------------------------------"
if [[ -f "${BASE_DIR}/ruleset/iptables_nat.txt" ]]; then
    grep -E "MASQUERADE|SNAT" "${BASE_DIR}/ruleset/iptables_nat.txt" \
        | head -20 || echo "  (无 MASQUERADE 或 SNAT 规则)"
fi
if [[ -f "${BASE_DIR}/ruleset/iptables_save.txt" ]]; then
    grep -E "MASQUERADE" "${BASE_DIR}/ruleset/iptables_save.txt" \
        | head -10 || true
fi

echo ""
echo "【C5】NAT 映射核验（手动比对指南）"
echo "------------------------------------------------------------------"
echo "  ① 确认 NAT 规则存在：iptables -t nat -L -n -v（见 C1）"
echo "  ② 确认 conntrack 中有对应 entry：conntrack -L -n（见 C2）"
echo "  ③ 比对转换前后的地址是否符合预期（见 C3）"
echo "  ④ 如果是 MASQUERADE，确认出接口有有效 IP 地址"
echo ""
echo "  常见问题:"
echo "  - SNAT 规则不存在 → 出站流量使用原始 IP"
echo "  - DNAT 规则顺序错误 → 最具体的规则应放在最前面"
echo "  - MASQUERADE + 接口 IP 变化 → 映射中断"
echo "  - conntrack entry 被提前删除 → 参考分支F（ct timeout）"
echo ""
echo "请参考 SKILL.md 第四节 Step 4（C3）和 references/nat_reference.md 完成深入分析。"
