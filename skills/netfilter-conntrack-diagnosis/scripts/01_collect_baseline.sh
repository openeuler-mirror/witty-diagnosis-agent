#!/usr/bin/env bash
# =============================================================================
# 脚本：01_collect_baseline.sh
# 用途：Netfilter / iptables / conntrack 基线信息采集
#       采集防火墙规则链快照、conntrack 状态、内核丢包计数器
# 使用：bash 01_collect_baseline.sh [--out <输出目录>]
# 参数：
#   --out <目录>   输出目录（默认 /tmp/netfilter_diag_<timestamp>）
# =============================================================================

set -euo pipefail

OUT_DIR="${1:-/tmp/netfilter_diag_$(date +%Y%m%d%H%M%S)}"
if [[ "$1" == "--out" && -n "${2:-}" ]]; then
    OUT_DIR="$2"
fi

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}/ruleset"
mkdir -p "${OUT_DIR}/conntrack"
mkdir -p "${OUT_DIR}/counters"

echo "=================================================================="
echo " Netfilter / iptables / conntrack 基线信息采集"
echo " 输出目录: ${OUT_DIR}"
echo " 采集时间: $(date)"
echo "=================================================================="
echo ""

# ===========================================================================
# 一、规则链快照
# ===========================================================================
echo "【1/3】采集规则链快照..."

# --- iptables 全表 ---
if command -v iptables &>/dev/null; then
    echo "[iptables] 正在采集所有表规则..."
    for table in raw mangle nat filter security; do
        iptables -t "$table" -L -n -v --line-numbers 2>/dev/null \
            > "${OUT_DIR}/ruleset/iptables_${table}.txt" 2>&1 || true
    done
    iptables-save 2>/dev/null > "${OUT_DIR}/ruleset/iptables_save.txt" || true
else
    echo "[iptables] 未安装，跳过" | tee -a "${OUT_DIR}/ruleset/iptables_missing.txt"
fi

# --- nftables ---
if command -v nft &>/dev/null; then
    echo "[nftables] 正在采集规则集..."
    nft list ruleset > "${OUT_DIR}/ruleset/nftables_ruleset.txt" 2>&1 || true
    nft list ruleset -a > "${OUT_DIR}/ruleset/nftables_ruleset_handle.txt" 2>&1 || true
    nft list counters > "${OUT_DIR}/ruleset/nftables_counters.txt" 2>&1 || true
else
    echo "[nftables] 未安装，跳过" | tee -a "${OUT_DIR}/ruleset/nftables_missing.txt"
fi

# --- ipset ---
if command -v ipset &>/dev/null; then
    echo "[ipset] 正在采集..."
    ipset list > "${OUT_DIR}/ruleset/ipset_list.txt" 2>&1 || true
else
    echo "[ipset] 未安装，跳过" | tee -a "${OUT_DIR}/ruleset/ipset_missing.txt"
fi

# ===========================================================================
# 二、conntrack 快照
# ===========================================================================
echo "【2/3】采集 conntrack 快照..."

# --- conntrack 使用率与上限 ---
if [[ -f /proc/sys/net/netfilter/nf_conntrack_count ]]; then
    CT_COUNT=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 0)
    CT_MAX=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 0)
    if [[ "$CT_MAX" -gt 0 ]]; then
        CT_USAGE=$(awk "BEGIN {printf \"%.1f\", $CT_COUNT * 100.0 / $CT_MAX}")
    else
        CT_USAGE="N/A"
    fi

    cat > "${OUT_DIR}/conntrack/conntrack_status.txt" <<CTSTATUS
conntrack 状态报告
====================
当前条目数 (count):   ${CT_COUNT}
最大条目数 (max):     ${CT_MAX}
使用率 (usage):       ${CT_USAGE}%
阈值 (warning):       90%
过载状态:             $(awk "BEGIN {if (${CT_COUNT} * 100.0 / ${CT_MAX} >= 90) print \"⚠️ OVERLOAD\" else print \"正常\"}" 2>/dev/null || echo "未知")

超时配置 (sysctl):
$(sysctl -a 2>/dev/null | grep -E "conntrack.*timeout" | sort || true)
CTSTATUS
else
    echo "conntrack: nf_conntrack 模块未加载或不可用" > "${OUT_DIR}/conntrack/conntrack_status.txt"
fi

# --- conntrack 统计 ---
if [[ -f /proc/net/stat/nf_conntrack ]]; then
    cp /proc/net/stat/nf_conntrack "${OUT_DIR}/conntrack/conntrack_stats.txt"
else
    echo "nf_conntrack 统计不可用" > "${OUT_DIR}/conntrack/conntrack_stats.txt"
fi

# --- conntrack 条目状态聚合 ---
if command -v conntrack &>/dev/null; then
    echo "[conntrack] 正在采集条目快照..."

    # 总条目数
    conntrack -C > "${OUT_DIR}/conntrack/conntrack_total_count.txt" 2>&1 || true

    # 按状态聚合
    conntrack -S > "${OUT_DIR}/conntrack/conntrack_summary.txt" 2>&1 || true

    # 完整条目（限制数量避免过大）
    conntrack -L 2>/dev/null | head -2000 > "${OUT_DIR}/conntrack/conntrack_entries_all.txt" || true

    # 按协议和状态聚合统计
    echo "=== conntrack 条目状态分布 ===" > "${OUT_DIR}/conntrack/conntrack_status_distribution.txt"
    conntrack -L 2>/dev/null | awk '
        /tcp/ { tcp++; if ($0 ~ "ESTABLISHED") tcp_est++; else if ($0 ~ "TIME_WAIT") tcp_tw++; else if ($0 ~ "CLOSE") tcp_cl++; else if ($0 ~ "SYN_SENT") tcp_ss++; else if ($0 ~ "SYN_RECV") tcp_sr++; else tcp_other++ }
        /udp/ { udp++ }
        /icmp/{ icmp++ }
        /INVALID/ { invalid++ }
        /UNREPLIED/ { unreplied++ }
        END {
            printf "TCP        : %6d  (ESTABLISHED=%d, TIME_WAIT=%d, CLOSE=%d, SYN_SENT=%d, SYN_RECV=%d, OTHER=%d)\n", tcp, tcp_est, tcp_tw, tcp_cl, tcp_ss, tcp_sr, tcp_other
            printf "UDP        : %6d\n", udp
            printf "ICMP       : %6d\n", icmp
            printf "INVALID    : %6d\n", invalid
            printf "UNREPLIED  : %6d\n", unreplied
        }
    ' >> "${OUT_DIR}/conntrack/conntrack_status_distribution.txt" 2>/dev/null || true
else
    echo "[conntrack] conntrack 工具未安装或不可用" > "${OUT_DIR}/conntrack/conntrack_tool_missing.txt"
    # 降级：使用 /proc/net/nf_conntrack
    if [[ -f /proc/net/nf_conntrack ]]; then
        wc -l /proc/net/nf_conntrack > "${OUT_DIR}/conntrack/conntrack_proc_count.txt" 2>&1 || true
        head -500 /proc/net/nf_conntrack > "${OUT_DIR}/conntrack/conntrack_proc_entries.txt" 2>&1 || true
    fi
fi

# ===========================================================================
# 三、内核计数器与日志
# ===========================================================================
echo "【3/3】采集内核计数器与日志..."

# --- nf_conntrack 丢包计数 ---
{
    echo "=== nf_conntrack 统计计数 ==="
    if [[ -f /proc/net/stat/nf_conntrack ]]; then
        head -1 /proc/net/stat/nf_conntrack
        tail -1 /proc/net/stat/nf_conntrack
    fi
    echo ""
    echo "=== key fields ==="
    awk 'NR>1 { print "found=" $1 " searched=" $2 " new=" $3 " invalid=" $4 " delete=" $5 " delete_list=" $6 " insert=" $7 " insert_failed=" $8 " drop=" $9 " early_drop=" $10 " icmp_error=" $11 " expect_new=" $12 " expect_create=" $13 " expect_delete=" $14 " search_restart=" $15 }' /proc/net/stat/nf_conntrack 2>/dev/null || true
    echo ""
    echo "=== 解读 ==="
    echo "insert_failed > 0 → 新连接插入失败（表满或内存不足）"
    echo "drop         > 0 → conntrack 丢弃数据包"
    echo "early_drop   > 0 → 因表满被迫提前丢弃连接"
    echo "search_restart > 0 → 哈希链表过长导致搜索性能下降"
} > "${OUT_DIR}/counters/nf_conntrack_drop_counters.txt"

# --- conntrack 相关 dmesg ---
dmesg -T 2>/dev/null | grep -iE "conntrack|nf_conntrack|table full|dropping packet|nf_tables" \
    | tail -100 > "${OUT_DIR}/counters/dmesg_conntrack.txt" || true

# --- netfilter 日志 ---
if command -v journalctl &>/dev/null; then
    journalctl -k --no-pager 2>/dev/null \
        | grep -iE "conntrack|nf_conntrack|iptables|nf_tables|ipset|nf_ct" \
        | tail -200 > "${OUT_DIR}/counters/journal_netfilter.txt" || true
fi

# --- netstat 连接统计 ---
if command -v netstat &>/dev/null; then
    netstat -s -t 2>/dev/null > "${OUT_DIR}/counters/netstat_tcp_stats.txt" || true
fi

# --- nf_conntrack 内核参数 ---
sysctl -a 2>/dev/null \
    | grep -E "net\.(netfilter|ipv4\.conf|ipv4\.neigh)" \
    | grep -iE "conntrack|nf_|bucket|hash" \
    | sort > "${OUT_DIR}/counters/conntrack_sysctl.txt" || true

# ===========================================================================
# 四、汇总报告
# ===========================================================================
echo ""
echo "=================================================================="
echo " 采集完成"
echo "=================================================================="
echo ""
echo "输出目录结构:"
find "${OUT_DIR}" -type f | sort | while read -r f; do
    size=$(wc -c < "$f" 2>/dev/null || echo 0)
    echo "  ${f} (${size} bytes)"
done

# generate summary
{
    echo "=================================================================="
    echo " Netfilter / iptables / conntrack 基线采集汇总"
    echo " 采集时间: $(date)"
    echo "=================================================================="
    echo ""
    # conntrack usage
    if [[ -f "${OUT_DIR}/conntrack/conntrack_status.txt" ]]; then
        grep -E "当前条目|最大条目|使用率|过载" "${OUT_DIR}/conntrack/conntrack_status.txt" || true
    fi
    echo ""
    # drop counters
    if [[ -f "${OUT_DIR}/counters/nf_conntrack_drop_counters.txt" ]]; then
        grep -E "^(insert_failed|drop|early_drop|search_restart)" "${OUT_DIR}/counters/nf_conntrack_drop_counters.txt" || true
    fi
    echo ""
    # dmesg signals
    if [[ -s "${OUT_DIR}/counters/dmesg_conntrack.txt" ]]; then
        echo "dmesg conntrack 告警行数: $(wc -l < "${OUT_DIR}/counters/dmesg_conntrack.txt")"
        echo "最新告警:"
        tail -5 "${OUT_DIR}/counters/dmesg_conntrack.txt"
    else
        echo "dmesg 中无 conntrack 相关告警"
    fi
    echo ""
    # rule hit signals
    hit_count=$(cat "${OUT_DIR}"/ruleset/iptables_*.txt 2>/dev/null \
        | grep -cE "DROP|REJECT" 2>/dev/null || echo 0)
    echo "iptables DROP/REJECT 规则数: ${hit_count}"
    echo ""
    echo "建议下一步分支:"
    if grep -qi "table full" "${OUT_DIR}/counters/dmesg_conntrack.txt" 2>/dev/null; then
        echo "  → 分支A: nf_conntrack 表满溢出 (bash scripts/branch_A_conntrack_full.sh)"
    fi
    if grep -qiE "[0-9]+ +DROP|[0-9]+ +REJECT" "${OUT_DIR}"/ruleset/iptables_*.txt 2>/dev/null; then
        echo "  → 分支B: 规则误命中 DROP/REJECT (bash scripts/branch_B_rule_mishit.sh)"
    fi
    if [[ -s "${OUT_DIR}/conntrack/conntrack_status_distribution.txt" ]]; then
        invalid=$(grep "INVALID" "${OUT_DIR}/conntrack/conntrack_status_distribution.txt" | grep -oP '\d+' || echo 0)
        unreplied=$(grep "UNREPLIED" "${OUT_DIR}/conntrack/conntrack_status_distribution.txt" | grep -oP '\d+' || echo 0)
        if [[ "$invalid" -gt 100 || "$unreplied" -gt 1000 ]]; then
            echo "  → 分支D: conntrack 状态丢包 (bash scripts/branch_D_ct_state_drop.sh)"
        fi
    fi
    echo "  → 详细分类请参考 SKILL.md 第七节决策树"
} > "${OUT_DIR}/summary.txt"

echo ""
echo "汇总报告: ${OUT_DIR}/summary.txt"
cat "${OUT_DIR}/summary.txt"
