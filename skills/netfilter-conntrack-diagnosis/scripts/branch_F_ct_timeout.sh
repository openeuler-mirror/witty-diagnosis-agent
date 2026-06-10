#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_F_ct_timeout.sh
# 用途：conntrack timeout 超时问题分析
#       当连接过早从 conntrack 表移除或超时配置不匹配时使用
# 使用：bash branch_F_ct_timeout.sh [基线采集目录]
# =============================================================================

set -euo pipefail

BASE_DIR="${1:-/tmp/netfilter_diag_*}"
if [[ "$BASE_DIR" == *"*"* ]]; then
    BASE_DIR=$(ls -dt /tmp/netfilter_diag_* 2>/dev/null | head -1)
fi
if [[ -z "$BASE_DIR" || ! -d "$BASE_DIR" ]]; then
    echo "错误：请先执行 01_collect_baseline.sh，然后传入其输出目录"
    echo "使用：bash branch_F_ct_timeout.sh <基线采集目录>"
    exit 1
fi

echo "=================================================================="
echo " 分支F：conntrack timeout 超时问题"
echo " 基线目录: ${BASE_DIR}"
echo "=================================================================="

# ---- Step F1: 当前超时配置 ----
echo ""
echo "【F1】conntrack 超时配置现状"
echo "------------------------------------------------------------------"
sysctl -a 2>/dev/null | grep -E "conntrack.*timeout" | sort \
    || echo "(无超时配置)"

echo ""
echo "【F2】当前超时配置速览"
echo "------------------------------------------------------------------"
echo "  TCP:"
sysctl net.netfilter.nf_conntrack_tcp_timeout_established 2>/dev/null \
    && echo "    established (建议 432000=5天, 当前值见上)"
sysctl net.netfilter.nf_conntrack_tcp_timeout_time_wait 2>/dev/null \
    && echo "    time_wait (建议 120, 当前值见上)"
sysctl net.netfilter.nf_conntrack_tcp_timeout_syn_recv 2>/dev/null \
    && echo "    syn_recv (建议 60, 当前值见上)"
sysctl net.netfilter.nf_conntrack_tcp_timeout_syn_sent 2>/dev/null \
    && echo "    syn_sent (建议 120, 当前值见上)"
echo "  UDP:"
sysctl net.netfilter.nf_conntrack_udp_timeout 2>/dev/null \
    && echo "    udp (建议 30, 当前值见上)"
sysctl net.netfilter.nf_conntrack_udp_timeout_stream 2>/dev/null \
    && echo "    udp_stream (建议 180, 当前值见上)"
echo "  ICMP:"
sysctl net.netfilter.nf_conntrack_icmp_timeout 2>/dev/null \
    && echo "    icmp (建议 30, 当前值见上)"

# ---- Step F3: 业务场景与超时匹配性分析 ----
echo ""
echo "【F3】业务场景与超时配置匹配分析"
echo "------------------------------------------------------------------"
cat <<'ANALYSIS'
[业务场景 vs 超时配置参考]

| 业务类型 | 关键超时 | 推荐值 | 超时过短的后果 |
|---------|---------|-------|--------------|
| HTTP/HTTPS Web | tcp_timeout_established | 432000 (5天) | 长连接被 conntrack 提前拆除 |
| 数据库长连接 | tcp_timeout_established | 604800 (7天) | 空闲连接中断、连接池报错 |
| VoIP/SIP | udp_timeout | 60-120 | 通话中注册信息丢失 |
| DNS | udp_timeout | 30-60 | 频繁重新查询 |
| FTP数据通道 | tcp_timeout_established | 86400 (1天) | 大文件传输中断 |
| VPN (IPsec) | udp_timeout_stream | 180-600 | VPN 隧道中断 |

判断方法:
  ① 确认业务使用的协议和连接模型
  ② 对比当前超时配置与推荐值
  ③ 查看 /proc/net/stat/nf_conntrack 的 early_drop 计数
  ④ 检查是否有 "forced_evict" 或 "table full" 日志
ANALYSIS

echo ""
echo "【F4】参考基线数据（C1 容量 + C4 丢包计数）"
echo "------------------------------------------------------------------"
if [[ -f "${BASE_DIR}/conntrack/conntrack_status.txt" ]]; then
    echo "[容量数据]"
    grep -E "当前条目|使用率" "${BASE_DIR}/conntrack/conntrack_status.txt" || true
fi
if [[ -f "${BASE_DIR}/counters/nf_conntrack_drop_counters.txt" ]]; then
    echo "[丢包计数]"
    grep -E "early_drop|insert_failed|drop" \
        "${BASE_DIR}/counters/nf_conntrack_drop_counters.txt" || true
fi

echo ""
echo "请参考 SKILL.md 第六节 6.3（超时配置）和 references/conntrack_reference.md 完成深入分析。"
