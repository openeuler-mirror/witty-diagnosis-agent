#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_E_tcp_window.sh
# 用途：TCP window tracking 异常分析
#       当 /proc/net/stat/nf_conntrack TCP window 相关计数异常时使用
# 使用：bash branch_E_tcp_window.sh [基线采集目录]
# =============================================================================

set -euo pipefail

BASE_DIR="${1:-/tmp/netfilter_diag_*}"
if [[ "$BASE_DIR" == *"*"* ]]; then
    BASE_DIR=$(ls -dt /tmp/netfilter_diag_* 2>/dev/null | head -1)
fi
if [[ -z "$BASE_DIR" || ! -d "$BASE_DIR" ]]; then
    echo "错误：请先执行 01_collect_baseline.sh，然后传入其输出目录"
    echo "使用：bash branch_E_tcp_window.sh <基线采集目录>"
    exit 1
fi

echo "=================================================================="
echo " 分支E：TCP window tracking 异常"
echo " 基线目录: ${BASE_DIR}"
echo "=================================================================="

# ---- Step E1: nf_conntrack TCP window 计数 ----
echo ""
echo "【E1】nf_conntrack TCP window tracking 计数"
echo "------------------------------------------------------------------"
if [[ -f "${BASE_DIR}/conntrack/conntrack_stats.txt" ]]; then
    # 多数内核中 tcp_window 不是独立字段，这里从完整统计读取
    echo "[nf_conntrack 全量统计]"
    cat "${BASE_DIR}/conntrack/conntrack_stats.txt"
    echo ""
    echo "[重点关注字段]"
    awk 'NR>1 {
        printf "  %-25s = %s\n", "found", $1
        printf "  %-25s = %s\n", "searched", $2
        printf "  %-25s = %s\n", "new", $3
        printf "  %-25s = %s\n", "invalid", $4
        printf "  %-25s = %s\n", "delete", $5
        printf "  %-25s = %s\n", "insert_failed", $8
        printf "  %-25s = %s\n", "drop", $9
        printf "  %-25s = %s\n", "early_drop", $10
        printf "  %-25s = %s\n", "search_restart", $15
    }' "${BASE_DIR}/conntrack/conntrack_stats.txt" 2>/dev/null
fi

# ---- Step E2: TCP 连接窗口相关统计 ----
echo ""
echo "【E2】TCP 连接状态统计"
echo "------------------------------------------------------------------"
if [[ -f "${BASE_DIR}/counters/netstat_tcp_stats.txt" ]]; then
    echo "[netstat TCP 统计摘要]"
    grep -E "segments|retransmit|window|sack|prune|congestion|resets" \
        "${BASE_DIR}/counters/netstat_tcp_stats.txt" \
        | head -20 || echo "  (无相关统计)"
fi

echo ""
echo "【E3】内核参数：TCP window 跟踪配置"
echo "------------------------------------------------------------------"
sysctl net.netfilter.nf_conntrack_tcp_be_liberal 2>/dev/null \
    || echo "  nf_conntrack_tcp_be_liberal: N/A（0=严格模式，1=宽松模式）"
sysctl net.netfilter.nf_conntrack_tcp_loose 2>/dev/null \
    || echo "  nf_conntrack_tcp_loose: N/A（0=严格 conntrack，1=宽松）"
sysctl net.ipv4.tcp_rmem 2>/dev/null || true
sysctl net.ipv4.tcp_wmem 2>/dev/null || true

echo ""
echo "【E4】TCP window tracking 异常诊断指南"
echo "------------------------------------------------------------------"
cat <<'ANALYSIS'
TCP window tracking 异常的可能原因:

1. nf_conntrack_tcp_be_liberal=0（默认严格模式）
   - 当 TCP 窗口缩放(window scaling)协商不一致时
   - 收到窗口外的数据包(window violation) → conntrack 标记 INVALID
   - 现象：连接间歇性中断，大窗口连接的异常更频繁

2. TCP window scaling 协商问题
   - 中间设备修改了 TCP 选项
   - 服务器和客户端 wscale 因子不一致
   - 现象：建立了连接但数据传输出错

3. 内核计数器观察
   - invalid 计数增长可能表示 TCP window 违规
   - 结合 tcpdump 抓包确认是否是窗口外数据

4. 排查方法:
   a. 确认 nf_conntrack_tcp_be_liberal 当前值
   b. 检查 TCP 窗口缩放参数: sysctl net.ipv4.tcp_window_scaling
   c. 在故障时间窗口内抓包分析窗口变化 (tcpdump)
   d. 对比 cwnd/ssthresh 在 conntrack 前后的变化
ANALYSIS

echo ""
echo "请结合 tcpdump、ss -ti 等手段进行 TCP 层深入分析。"
