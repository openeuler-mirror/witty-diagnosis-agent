#!/bin/bash
# net_baseline.sh — 网络故障现场一键基线采集
# 用途：修改系统配置前完整保留故障现场，供前后对比
# 输出：/tmp/net_baseline_<timestamp>/ 目录

set -euo pipefail

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="/tmp/net_baseline_${TIMESTAMP}"
mkdir -p "${OUTPUT_DIR}"

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "${OUTPUT_DIR}/collect.log"; }
run() {
    local label="$1"; shift
    log "采集: ${label}"
    { echo "=== ${label} ==="; "$@" 2>&1 || true; echo; } >> "${OUTPUT_DIR}/${label//\//_}.txt"
}

log "==== 网络基线采集开始 ===="
log "输出目录: ${OUTPUT_DIR}"

# ── 1. 链路层 ──────────────────────────────────────────────
run "ip_link_show"          ip link show
run "ip_addr_show"          ip addr show
run "ethtool_stats"         bash -c '
    for iface in $(ip link show | grep "^[0-9]" | awk -F": " "{print \$2}" | tr -d "@" | cut -d@ -f1); do
        echo "--- $iface ---"
        ethtool "$iface" 2>/dev/null || true
        ethtool -S "$iface" 2>/dev/null | grep -E "error|drop|miss|over|rx_|tx_" || true
        ethtool -g "$iface" 2>/dev/null || true
        echo
    done
'
run "proc_net_dev"          cat /proc/net/dev
run "dmesg_nic"             bash -c 'dmesg | grep -iE "eth|nic|driver|firmware|link|carrier" | tail -50 || true'

# ── 2. IP & 路由层 ─────────────────────────────────────────
run "ip_route_show"         ip route show
run "ip_neigh_show"         ip neigh show
run "arp_table"             arp -n 2>/dev/null || true
run "proc_net_arp"          cat /proc/net/arp

# ── 3. DNS ────────────────────────────────────────────────
run "resolv_conf"           cat /etc/resolv.conf
run "nsswitch_conf"         cat /etc/nsswitch.conf 2>/dev/null || true

# ── 4. TCP 连接状态 ────────────────────────────────────────
run "ss_summary"            ss -s
run "ss_tcp_all"            ss -tnap
run "ss_udp_all"            ss -unap
run "netstat_stats"         netstat -s 2>/dev/null || ss -s

# ── 5. 内核网络参数 ────────────────────────────────────────
run "sysctl_net"            sysctl -a 2>/dev/null | grep -E "^net\.(core|ipv4|ipv6)\." | sort

# ── 6. 防火墙规则 ─────────────────────────────────────────
run "iptables_filter"       bash -c 'iptables -nvL --line-numbers 2>/dev/null || true'
run "iptables_nat"          bash -c 'iptables -t nat -nvL 2>/dev/null || true'
run "nftables"              bash -c 'nft list ruleset 2>/dev/null || true'
run "conntrack_count"       bash -c 'conntrack -C 2>/dev/null || cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || true'

# ── 7. 内核丢包计数器 ──────────────────────────────────────
run "snmp_stats"            cat /proc/net/snmp
run "netstat_drop"          bash -c 'netstat -s 2>/dev/null | grep -iE "drop|fail|error|reset|retrans|overflow" || ss -s'
run "softirqs"              cat /proc/softirqs
run "interrupts"            cat /proc/interrupts | grep -iE "eth|net|virtio" || true

# ── 8. SELinux / AppArmor ────────────────────────────────
run "selinux_status"        bash -c 'getenforce 2>/dev/null; sestatus 2>/dev/null || true'
run "dmesg_avc"             bash -c 'dmesg | grep -i "avc\|selinux" | tail -20 || true'

log "==== 采集完成 ===="
log "所有文件保存至: ${OUTPUT_DIR}"
echo ""
echo "📁 基线数据目录: ${OUTPUT_DIR}"
ls -lh "${OUTPUT_DIR}/"
