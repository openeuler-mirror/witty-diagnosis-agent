#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_A_conntrack_full.sh
# 用途：nf_conntrack 表满溢出分析
#       当内核日志出现 "nf_conntrack: table full, dropping packet" 时使用
# 使用：bash branch_A_conntrack_full.sh [基线采集目录]
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
    echo "使用：bash branch_A_conntrack_full.sh <基线采集目录>"
    exit 1
fi

echo "=================================================================="
echo " 分支A：nf_conntrack 表满溢出"
echo " 基线目录: ${BASE_DIR}"
echo "=================================================================="

# ---- Step A1: 确认表满症状 ----
echo ""
echo "【A1】确认 nf_conntrack 表满症状"
echo "------------------------------------------------------------------"
if [[ -f "${BASE_DIR}/counters/dmesg_conntrack.txt" ]]; then
    grep -i "table full\|dropping packet\|nf_conntrack" "${BASE_DIR}/counters/dmesg_conntrack.txt" \
        | tail -20 || echo "(dmesg 中无明确 table full 记录)"
fi
if [[ -f "${BASE_DIR}/counters/journal_netfilter.txt" ]]; then
    echo ""
    echo "journalctl 中 conntrack 相关:"
    grep -i "table full\|dropping packet" "${BASE_DIR}/counters/journal_netfilter.txt" \
        | tail -20 || echo "(journalctl 中无明确 table full 记录)"
fi

# ---- Step A2: 容量分析 ----
echo ""
echo "【A2】容量分析"
echo "------------------------------------------------------------------"
if [[ -f "${BASE_DIR}/conntrack/conntrack_status.txt" ]]; then
    echo "[conntrack 使用率]"
    grep -E "当前条目|最大条目|使用率|过载" "${BASE_DIR}/conntrack/conntrack_status.txt"
fi

echo ""
echo "[nf_conntrack 关键参数]"
sysctl net.netfilter.nf_conntrack_max 2>/dev/null || echo "  nf_conntrack_max: N/A"
sysctl net.netfilter.nf_conntrack_buckets 2>/dev/null || echo "  nf_conntrack_buckets: N/A"
if [[ -f "${BASE_DIR}/counters/conntrack_sysctl.txt" ]]; then
    grep -E "bucket|hash|max" "${BASE_DIR}/counters/conntrack_sysctl.txt" | head -10
fi

# ---- Step A3: 丢包计数分析 ----
echo ""
echo "【A3】丢包计数分析"
echo "------------------------------------------------------------------"
if [[ -f "${BASE_DIR}/counters/nf_conntrack_drop_counters.txt" ]]; then
    echo "[nf_conntrack 统计计数（关键字段）]"
    awk 'NR>1 { printf "  insert_failed = %s\n  drop          = %s\n  early_drop   = %s\n  search_restart = %s\n", $8, $9, $10, $15 }' \
        "${BASE_DIR}/conntrack/conntrack_stats.txt" 2>/dev/null || true
    echo ""
    echo "[解读]"
    grep -E "^insert_failed|^drop|^early_drop|^search_restart" \
        "${BASE_DIR}/counters/nf_conntrack_drop_counters.txt" 2>/dev/null || true
fi

# ---- Step A4: 状态分布分析 ----
echo ""
echo "【A4】conntrack 条目状态分布"
echo "------------------------------------------------------------------"
if [[ -f "${BASE_DIR}/conntrack/conntrack_status_distribution.txt" ]]; then
    cat "${BASE_DIR}/conntrack/conntrack_status_distribution.txt"
else
    echo "(无 conntrack 条目分布数据)"
fi

echo ""
echo "【A5】诊断结论（模板）"
echo "------------------------------------------------------------------"
echo "  故障类型: nf_conntrack 表满溢出"
echo "  C1 容量: $(grep -oP '当前条目数.*' "${BASE_DIR}/conntrack/conntrack_status.txt" 2>/dev/null || echo 'N/A')"
echo "  C2 状态分布: $(grep -oP 'INVALID.*\d+' "${BASE_DIR}/conntrack/conntrack_status_distribution.txt" 2>/dev/null || echo 'N/A')"
echo "  C4 丢包计数: $(awk 'NR>1 {printf "drop=%s early_drop=%s insert_failed=%s", $9, $10, $8}' "${BASE_DIR}/conntrack/conntrack_stats.txt" 2>/dev/null || echo 'N/A')"
echo ""
echo "  建议修复动作（仅建议，不自动执行）:"
echo "  🟡 中危: 临时增大 nf_conntrack_max"
echo "     sysctl -w net.netfilter.nf_conntrack_max=1048576"
echo "     sysctl -w net.netfilter.nf_conntrack_buckets=262144"
echo "  🟢 低危: 调整 conntrack 超时参数缩短 entry 生命周期"
echo "     sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=600"
echo "     sysctl -w net.netfilter.nf_conntrack_udp_timeout=30"
echo "  🔴 高危: 如需永久修改，请编辑 /etc/sysctl.conf 并在业务低峰期 reload"
echo ""
echo "请参考 SKILL.md 第四节 Step 5（交叉验证）和第八节（报告模板）完成最终输出。"
