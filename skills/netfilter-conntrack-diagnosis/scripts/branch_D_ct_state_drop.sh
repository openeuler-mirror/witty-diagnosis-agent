#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_D_ct_state_drop.sh
# 用途：conntrack 状态 (INVALID/UNREPLIED) 导致丢包分析
#       当 conntrack 条目大量 INVALID 或 UNREPLIED 时使用
# 使用：bash branch_D_ct_state_drop.sh [基线采集目录]
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
    echo "使用：bash branch_D_ct_state_drop.sh <基线采集目录>"
    exit 1
fi

echo "=================================================================="
echo " 分支D：conntrack 状态丢包 (INVALID/UNREPLIED)"
echo " 基线目录: ${BASE_DIR}"
echo "=================================================================="

# ---- Step D1: 状态分布分析 ----
echo ""
echo "【D1】conntrack 条目状态分布"
echo "------------------------------------------------------------------"
if [[ -f "${BASE_DIR}/conntrack/conntrack_status_distribution.txt" ]]; then
    cat "${BASE_DIR}/conntrack/conntrack_status_distribution.txt"
fi
if [[ -f "${BASE_DIR}/conntrack/conntrack_summary.txt" ]]; then
    echo ""
    echo "[conntrack 汇总统计]"
    cat "${BASE_DIR}/conntrack/conntrack_summary.txt"
fi

# ---- Step D2: INVALID 条目详情 ----
echo ""
echo "【D2】INVALID 状态条目详情"
echo "------------------------------------------------------------------"
if command -v conntrack &>/dev/null; then
    echo "[INVALID 条目（最多 30 条）]"
    conntrack -L --state INVALID 2>/dev/null | head -30 || echo "  (无 INVALID 条目)"
    echo ""
    echo "[INVALID 条目统计]"
    conntrack -L --state INVALID 2>/dev/null | awk '
        /tcp/ { tcp++ }
        /udp/ { udp++ }
        /icmp/ { icmp++ }
        END { print "  TCP: " (tcp+0) "  UDP: " (udp+0) "  ICMP: " (icmp+0) }
    ' || true
else
    echo "(conntrack 工具不可用)"
    grep "INVALID" /proc/net/nf_conntrack 2>/dev/null | head -30 || echo "  (无 INVALID 条目)"
fi

# ---- Step D3: UNREPLIED 条目分析 ----
echo ""
echo "【D3】UNREPLIED 条目分析"
echo "------------------------------------------------------------------"
if command -v conntrack &>/dev/null; then
    unreplied_total=$(conntrack -L --state UNREPLIED 2>/dev/null | wc -l || echo 0)
    echo "  UNREPLIED 条目总数: ${unreplied_total}"
    echo ""
    echo "[UNREPLIED 条目（最多 20 条，重点关注非 SYN_SENT 的异常条目）]"
    conntrack -L --state UNREPLIED 2>/dev/null | head -20 || true
    echo ""
    echo "[UNREPLIED 条目状态细分]"
    conntrack -L --state UNREPLIED 2>/dev/null | awk '
        /SYN_SENT/ { syn_sent++ }
        /SYN_RECV/ { syn_recv++ }
        /ESTABLISHED/ { est++ }
        !/SYN_SENT|SYN_RECV|ESTABLISHED/ { other++ }
        END {
            print "  SYN_SENT    : " (syn_sent+0) "（正常发起连接，等待回包）"
            print "  SYN_RECV    : " (syn_recv+0) "（半连接，可能资源耗尽）"
            print "  ESTABLISHED : " (est+0) "（双向流量异常中断）"
            print "  OTHER       : " (other+0)
        }
    ' || true
fi

# ---- Step D4: stateful 规则匹配检查 ----
echo ""
echo "【D4】stateful 规则匹配检查（ct state 规则）"
echo "------------------------------------------------------------------"
echo "[iptables state/conntrack 规则]"
for f in "${BASE_DIR}/ruleset"/iptables_*.txt; do
    [[ -f "$f" ]] || continue
    table=$(basename "$f" .txt)
    matches=$(grep -E "ctstate|ct state|state " "$f" || true)
    if [[ -n "$matches" ]]; then
        echo "  [${table}]"
        echo "$matches" | head -20 | sed 's/^/    /'
    fi
done

echo ""
echo "[nftables ct state 规则]"
if [[ -f "${BASE_DIR}/ruleset/nftables_ruleset.txt" ]]; then
    grep -i "ct state\|ctstate" "${BASE_DIR}/ruleset/nftables_ruleset.txt" \
        | head -20 || echo "  (无 ct state 规则)"
fi

# ---- Step D5: INVALID 丢包计数 ----
echo ""
echo "【D5】INVALID 状态产生原因分析"
echo "------------------------------------------------------------------"
cat <<'ANALYSIS'
INVALID 状态产生原因（按概率排序）:
  1. TCP 状态机异常: RST 后继续收到数据包、SYN 后的非 SYN 报文
  2. 校验和错误: 硬件 offload 问题导致报文校验和错误
  3. 报文长度异常: 有头无数据、分片不完整
  4. 缺少 conntrack entry: 连接未经过 NEW 状态直接收到 ESTABLISHED 报文
  5. 防火墙策略导致: ct state invalid 被 DROP 的报文

INVALID → DROP 的规则路径:
  iptables: -m conntrack --ctstate INVALID -j DROP
  nftables: ct state invalid drop
ANALYSIS

echo ""
echo "请参考 SKILL.md 第六节（conntrack 分析）和 references/conntrack_reference.md 完成深入分析。"
