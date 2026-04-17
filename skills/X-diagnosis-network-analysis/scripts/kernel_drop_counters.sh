#!/bin/bash
# kernel_drop_counters.sh — 内核各层丢包计数器快照
# 用途：全面采集内核协议栈各钩子点丢包计数，辅助静默丢包定位
# 配合 xd_ntrace 使用：xd_ntrace 定位丢包点，本脚本提供计数器变化趋势

INTERVAL=${1:-5}  # 采样间隔（秒），默认 5s

echo "=== 内核丢包计数器 [$(date '+%Y-%m-%d %H:%M:%S')] ==="
echo "采样间隔: ${INTERVAL}s（可通过参数指定，例如: bash kernel_drop_counters.sh 10）"
echo ""

snapshot() {
    # netfilter 丢包（iptables 计数）
    echo "── iptables DROP/REJECT 规则命中计数 ──"
    iptables -nvL 2>/dev/null | awk '$1+0>0 && ($3=="DROP" || $3=="REJECT") {
        printf "  pkts=%-8s bytes=%-10s target=%-8s %s\n", $1, $2, $3, $8
    }' | head -20 || echo "  （无命中或 iptables 不可用）"
    echo ""

    # TCP 层丢包
    echo "── TCP 层关键计数器 ───────────────────"
    grep -E "ListenDrops|ListenOverflows|TCPBacklogDrop|TCPMinTTLDrop|TCPAbortOnMemory|TCPRcvQDrop" \
        /proc/net/netstat 2>/dev/null | \
    awk 'NR%2==1{split($0,k," ")} NR%2==0{split($0,v," "); for(i=2;i<=length(k);i++) if(v[i]+0>0) printf "  %-30s %d\n", k[i], v[i]}' \
    || true

    grep -E "InErrors|InDiscards|OutDiscards" /proc/net/snmp 2>/dev/null | \
    awk 'NR%2==1{split($0,k," ")} NR%2==0{split($0,v," "); for(i=2;i<=length(k);i++) if(v[i]+0>0) printf "  %-30s %d\n", k[i], v[i]}' \
    || true
    echo ""

    # 网卡层丢包
    echo "── 网卡层丢包统计 ─────────────────────"
    cat /proc/net/dev | awk 'NR>2 {
        iface=$1; gsub(":","",iface)
        rx_drop=$5; tx_drop=$13
        if (rx_drop+0 > 0 || tx_drop+0 > 0)
            printf "  %-12s rx_drop=%-8s tx_drop=%s\n", iface, rx_drop, tx_drop
    }'
    echo ""

    # socket 缓冲区溢出
    echo "── Socket 缓冲区溢出 ───────────────────"
    grep -E "RcvbufErrors|SndbufErrors" /proc/net/netstat 2>/dev/null | \
    awk 'NR%2==1{split($0,k," ")} NR%2==0{split($0,v," "); for(i=2;i<=length(k);i++) if(v[i]+0>0) printf "  %-30s %d\n", k[i], v[i]}' \
    || true
    echo ""

    # conntrack 丢包
    echo "── Conntrack 溢出 ──────────────────────"
    local ct_max ct_cur
    ct_max=$(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo "N/A")
    ct_cur=$(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo "N/A")
    echo "  当前连接数: ${ct_cur} / 最大: ${ct_max}"
    if [ "${ct_cur}" != "N/A" ] && [ "${ct_max}" != "N/A" ]; then
        local pct=$(( ct_cur * 100 / ct_max ))
        [ "${pct}" -gt 80 ] && echo "  ⚠ 连接跟踪表使用率 ${pct}%，接近上限！"
    fi
}

snapshot

if [ "${INTERVAL}" -gt 0 ]; then
    echo "════════════════════════════════════════"
    echo "等待 ${INTERVAL}s 后采集第二次快照（用于对比变化量）..."
    sleep "${INTERVAL}"
    echo ""
    echo "=== 内核丢包计数器 [$(date '+%Y-%m-%d %H:%M:%S')] — 第二次快照 ==="
    snapshot
fi
