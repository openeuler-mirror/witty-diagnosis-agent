#!/bin/bash
# Inject: DNS Hijack (Branch F)
# Starts a fake DNS server that returns rogue IPs for all queries
# Then redirects local DNS traffic to the fake server
# Usage: bash inject_hijack.sh [rogue_ip]

ROGUE_IP="${1:-103.235.46.96}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="/tmp/dns_hijack_inject.pid"
BACKUP_RULES="/tmp/dns_hijack_iptables_backup"

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "[Inject] Hijack injector already running (PID: $(cat $PID_FILE))"
    exit 1
fi

echo "[Inject] Starting DNS Hijack attack simulation..."
echo "[Inject] Rogue IP: $ROGUE_IP"

# 1. Start fake rogue DNS server on localhost:5353
python3 "$SCRIPT_DIR/../src/dns_hijack_fake.py" "$ROGUE_IP" &
echo $! > "$PID_FILE"
sleep 1

if ! kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "[ERROR] Failed to start fake DNS server"
    rm -f "$PID_FILE"
    exit 1
fi

# 2. Redirect local DNS traffic to fake server using NAT
iptables-save > "$BACKUP_RULES" 2>/dev/null
iptables -t nat -A OUTPUT -p udp --dport 53 -j DNAT --to-destination 127.0.0.1:5353
iptables -t nat -A OUTPUT -p tcp --dport 53 -j DNAT --to-destination 127.0.0.1:5353
# Prevent loopback
iptables -A OUTPUT -p udp --dport 5353 -j ACCEPT

echo "[Inject] DNS traffic redirected to rogue server"
echo "[Inject] All DNS queries will return ${ROGUE_IP}"
echo "[Inject] Run cleanup.sh to restore"
