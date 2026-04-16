#!/bin/bash
# tcp_state_summary.sh — TCP 连接状态分类汇总
# 用途：快速掌握当前 TCP 连接全貌，识别异常堆积状态

echo "=== TCP 连接状态汇总 [$(date '+%Y-%m-%d %H:%M:%S')] ==="
echo ""

# 状态统计
echo "── 状态分布 ──────────────────────────────"
ss -tn | awk 'NR>1 {print $1}' | sort | uniq -c | sort -rn | \
    awk '{printf "  %-20s %d\n", $2, $1}'
echo ""

# LISTEN 端口（含队列积压）
echo "── 监听端口（Recv-Q > 0 表示全连接队列积压）─"
ss -tlnp | awk 'NR>1 {
    split($4, a, ":");
    port = a[length(a)];
    recv_q = $2;
    send_q = $3;
    flag = (recv_q+0 > 0) ? " ⚠ QUEUE BACKLOG" : "";
    printf "  %-6s %-25s Recv-Q=%-4s Send-Q=%-4s%s\n", "TCP", $4, recv_q, send_q, flag
}'
echo ""

# TIME_WAIT 数量
tw_count=$(ss -tn | grep -c "TIME-WAIT" 2>/dev/null || echo 0)
echo "── TIME_WAIT 统计 ─────────────────────────"
echo "  当前 TIME_WAIT 连接数: ${tw_count}"
if [ "${tw_count}" -gt 1000 ]; then
    echo "  ⚠ TIME_WAIT 数量较多，检查 net.ipv4.tcp_tw_reuse"
fi
echo ""

# CLOSE_WAIT 数量（泄漏风险）
cw_count=$(ss -tn | grep -c "CLOSE-WAIT" 2>/dev/null || echo 0)
echo "── CLOSE_WAIT 统计 ────────────────────────"
echo "  当前 CLOSE_WAIT 连接数: ${cw_count}"
if [ "${cw_count}" -gt 100 ]; then
    echo "  ⚠ CLOSE_WAIT 较多，可能存在应用层连接泄漏"
fi
echo ""

# ESTABLISHED 连接 Top 5 对端
echo "── ESTABLISHED 连接 Top 5 对端 ───────────"
ss -tn state established | awk 'NR>1 {
    split($5, a, ":");
    ip = ""
    for (i=1; i<length(a); i++) ip = ip (i>1?":":"") a[i]
    print ip
}' | sort | uniq -c | sort -rn | head -5 | \
    awk '{printf "  %-6d %s\n", $1, $2}'
echo ""

# 重传统计
echo "── 内核重传计数器 ─────────────────────────"
grep -E "RetransSegs|TCPRetransFail|TCPLostRetransmit" /proc/net/snmp /proc/net/netstat 2>/dev/null | \
    awk -F: '{
        split($1, f, "/"); file=f[length(f)]; gsub(/^\s+/,"",f[2])
        split($2, keys, " "); getline line
        split(line, vals, " ")
        for(i=2;i<=length(keys);i++) {
            if (keys[i] ~ /Retrans|Retransmit/) printf "  %-30s %s\n", keys[i], vals[i]
        }
    }' 2>/dev/null | head -10 || true
