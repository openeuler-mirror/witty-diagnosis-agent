#!/bin/bash
# Inject: EDNS0 Compatibility Issue (Branch H)
# Drops DNS packets containing EDNS0 OPT records by matching packet size
# Packets > 512 bytes (containing EDNS0) are dropped
# Usage: bash inject_edns0.sh [max_udp_size]

MAX_SIZE="${1:-512}"
PID_FILE="/tmp/dns_edns0_inject.pid"

echo "[Inject] EDNS0 Compatibility - Dropping UDP DNS > ${MAX_SIZE} bytes"

# Use iptables to drop large UDP DNS packets
iptables -A OUTPUT -p udp --dport 53 -m length --length "$MAX_SIZE":65535 -j DROP
echo $! > "$PID_FILE"

echo "[Inject] UDP DNS packets > ${MAX_SIZE} bytes will be dropped"
echo "[Inject] This simulates PMTU issues or middlebox interference"
echo "[Inject] dig +edns0 +bufsize=4096 will fail"
echo "[Inject] dig +noedns or small responses will work"

# Save for cleanup
echo "iptables -D OUTPUT -p udp --dport 53 -m length --length ${MAX_SIZE}:65535 -j DROP" > /tmp/dns_edns0_cleanup.sh
chmod +x /tmp/dns_edns0_cleanup.sh
