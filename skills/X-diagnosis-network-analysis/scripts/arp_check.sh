#!/bin/bash
# arp_check.sh — ARP 表检查与冲突检测
# 用途：检测 ARP 表异常、IP 冲突，配合 xd_arpstormcheck 使用

echo "=== ARP 诊断报告 [$(date '+%Y-%m-%d %H:%M:%S')] ==="
echo ""

# 当前 ARP 表
echo "── 当前 ARP 表 ─────────────────────────────"
ip neigh show | awk '{
    state = $NF
    flag = ""
    if (state == "FAILED") flag = " ⚠ FAILED"
    else if (state == "STALE") flag = " (stale)"
    print "  " $0 flag
}'
echo ""

# 检测重复 IP（多个 MAC 对应同一 IP）
echo "── IP 冲突检测（同一 IP 对应多个 MAC）──────"
ip neigh show | awk '{print $1, $5}' | sort | awk '
{
    count[$1]++; macs[$1] = macs[$1] " " $2
}
END {
    found = 0
    for (ip in count) {
        if (count[ip] > 1) {
            print "  ⚠ IP冲突: " ip " -> " macs[ip]
            found = 1
        }
    }
    if (!found) print "  未检测到 IP 冲突"
}'
echo ""

# 网关 ARP 可达性
echo "── 网关 ARP 可达性 ─────────────────────────"
gateways=$(ip route show | awk '/via/ {print $3}' | sort -u)
if [ -z "${gateways}" ]; then
    echo "  未找到网关配置"
else
    for gw in ${gateways}; do
        iface=$(ip route get "${gw}" 2>/dev/null | grep -oP 'dev \K\S+' | head -1)
        echo -n "  网关 ${gw} (${iface}): "
        if arping -c 2 -I "${iface}" "${gw}" &>/dev/null; then
            echo "✓ ARP 可达"
        else
            echo "✗ ARP 不可达 ⚠"
        fi
    done
fi
echo ""

# ARP 相关内核参数
echo "── ARP 内核参数 ─────────────────────────────"
sysctl -a 2>/dev/null | grep -E "arp_(ignore|announce|filter|gc_thresh)" | \
    awk '{printf "  %-45s = %s\n", $1, $3}' | sort
echo ""

echo "提示: 若怀疑 ARP 风暴，运行: xd_arpstormcheck -f 200"
