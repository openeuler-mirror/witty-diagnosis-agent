#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_H_ipset.sh
# 用途：ipset 匹配异常分析
#       当预期命中的规则未匹配或不应命中的规则匹配时使用
# 使用：bash branch_H_ipset.sh [基线采集目录]
# =============================================================================

set -euo pipefail

BASE_DIR="${1:-/tmp/netfilter_diag_*}"
if [[ "$BASE_DIR" == *"*"* ]]; then
    BASE_DIR=$(ls -dt /tmp/netfilter_diag_* 2>/dev/null | head -1)
fi
if [[ -z "$BASE_DIR" || ! -d "$BASE_DIR" ]]; then
    echo "错误：请先执行 01_collect_baseline.sh，然后传入其输出目录"
    echo "使用：bash branch_H_ipset.sh <基线采集目录>"
    exit 1
fi

echo "=================================================================="
echo " 分支H：ipset 匹配异常"
echo " 基线目录: ${BASE_DIR}"
echo "=================================================================="

# ---- Step H1: ipset 列表信息 ----
echo ""
echo "【H1】ipset 列表及类型"
echo "------------------------------------------------------------------"
if [[ -f "${BASE_DIR}/ruleset/ipset_list.txt" ]]; then
    cat "${BASE_DIR}/ruleset/ipset_list.txt"
else
    # 实时获取
    if command -v ipset &>/dev/null; then
        ipset list > /tmp/ipset_list_$$.txt 2>&1 || true
        cat /tmp/ipset_list_$$.txt 2>/dev/null || echo "(ipset 无输出)"
        rm -f /tmp/ipset_list_$$.txt
    else
        echo "(ipset 工具不可用)"
    fi
fi

# ---- Step H2: ipset 引用规则检查 ----
echo ""
echo "【H2】引用 ipset 的 iptables 规则"
echo "------------------------------------------------------------------"
for f in "${BASE_DIR}/ruleset"/iptables_*.txt; do
    [[ -f "$f" ]] || continue
    table=$(basename "$f" .txt)
    matches=$(grep -E "match-set|set " "$f" || true)
    if [[ -n "$matches" ]]; then
        echo "  [${table}]"
        echo "$matches" | while IFS= read -r line; do
            pkts=$(echo "$line" | awk '{print $1}')
            if [[ "$pkts" =~ ^[0-9]+$ ]]; then
                if [[ "$pkts" -eq 0 ]]; then
                    echo "    ❌ pkts=0: $line"
                else
                    echo "    ⚠️  pkts=${pkts}: $line"
                fi
            fi
        done
    fi
done

echo ""
echo "[引用 ipset 的 nftables 规则]"
if [[ -f "${BASE_DIR}/ruleset/nftables_ruleset.txt" ]]; then
    grep -E "set |@|vmap" "${BASE_DIR}/ruleset/nftables_ruleset.txt" \
        | head -20 || echo "  (无 ipset/vmap 引用)"
fi

# ---- Step H3: ipset 条目校验 ----
echo ""
echo "【H3】ipset 条目与预期流量匹配校验（手动比对指南）"
echo "------------------------------------------------------------------"
cat <<'IPSET_CHECK'
[ipset 匹配异常排查步骤]

1. 确认 ipset 类型与语法
   - bitmap:ip 类型: 检查 IP 是否在 range 范围内
   - hash:ip 类型: 检查 IP 是否被精确添加
   - hash:net 类型: 检查网段掩码是否匹配
   - hash:ip,port 类型: 检查 IP+端口组合
   - list:set 类型: 检查嵌套的 set 列表

2. 检查 ipset 超时
   - ipset 条目设置了 timeout 吗？
   - timeout 过短导致条目被提前删除？
   - ipset list 的输出中 timeleft 字段

3. 检查 ipset 计数器
   - 使用 ipset list 查看每个条目的 packets/bytes
   - pkts=0 的条目从未被命中
   - pkts 增长是否与预期一致

4. 检查 ipset 更新问题
   - ipset 条目是否被及时更新？
   - 动态 IP 场景下 ipset 是否过时？

5. 常见问题:
   - ipset 类型与规则不匹配（如 hash:ip 但规则用 hash:net 逻辑）
   - ipset 条目超时被自动删除
   - ipset 名大小写错误
   - 多条 ipset 规则顺序导致预期外的匹配
   - nftables vmap 使用 ipset 时的映射错误
IPSET_CHECK

echo ""
echo "请参考 SKILL.md 第七节（决策树）和 references/iptables_nftables_reference.md 完成深入分析。"
