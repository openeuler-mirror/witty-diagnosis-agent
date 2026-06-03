#!/bin/bash
# Cleanup all DNS fault injection artifacts
# Run this after test completion to restore normal DNS operations

echo "[Cleanup] Stopping all DNS fault injectors..."

# Kill background injectors
for pid_file in /tmp/dns_timeout_inject.pid /tmp/dns_nxdomain_inject.pid \
                /tmp/dns_hijack_inject.pid /tmp/dns_tcp_block_inject.pid \
                /tmp/dns_edns0_inject.pid; do
    if [ -f "$pid_file" ]; then
        pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
            echo "[Cleanup] Killed PID $pid ($pid_file)"
        fi
        rm -f "$pid_file"
    fi
done

# Kill any remaining Python injectors
for proc in dns_timeout_inject dns_nxdomain_fake dns_hijack_fake dns_tcp_block; do
    pkill -f "$proc" 2>/dev/null && echo "[Cleanup] Killed remaining $proc"
done

# Restore iptables rules
echo "[Cleanup] Restoring iptables rules..."

# Remove DNS DROP rules
for proto in udp tcp; do
    while iptables -D OUTPUT -p "$proto" --dport 53 -j DROP 2>/dev/null; do :; done
    while iptables -D OUTPUT -p "$proto" --dport 5353 -j ACCEPT 2>/dev/null; do :; done
done

# Remove length-based DROP rules
while iptables -D OUTPUT -p udp --dport 53 -m length --length 512:65535 -j DROP 2>/dev/null; do :; done
while iptables -D OUTPUT -p udp --dport 53 -m length --length 1024:65535 -j DROP 2>/dev/null; do :; done

# Remove NAT redirect rules
while iptables -t nat -D OUTPUT -p udp --dport 53 -j DNAT --to-destination 127.0.0.1:5353 2>/dev/null; do :; done
while iptables -t nat -D OUTPUT -p tcp --dport 53 -j DNAT --to-destination 127.0.0.1:5353 2>/dev/null; do :; done

# Restore /etc/resolv.conf
if [ -f /etc/resolv.conf.dns_backup ]; then
    cp /etc/resolv.conf.dns_backup /etc/resolv.conf
    rm -f /etc/resolv.conf.dns_backup
    echo "[Cleanup] Restored /etc/resolv.conf from backup"
fi

# Restore /etc/nsswitch.conf
if [ -f /etc/nsswitch.conf.dns_backup ]; then
    cp /etc/nsswitch.conf.dns_backup /etc/nsswitch.conf
    rm -f /etc/nsswitch.conf.dns_backup
    echo "[Cleanup] Restored /etc/nsswitch.conf from backup"
fi

# Run EDNS0 cleanup script if exists
if [ -f /tmp/dns_edns0_cleanup.sh ]; then
    bash /tmp/dns_edns0_cleanup.sh 2>/dev/null
    rm -f /tmp/dns_edns0_cleanup.sh
    echo "[Cleanup] EDNS0 rules cleaned"
fi

# Flush resolved cache
if command -v resolvectl &>/dev/null; then
    resolvectl flush-caches 2>/dev/null
    echo "[Cleanup] systemd-resolved cache flushed"
fi

echo "[Cleanup] All DNS injection artifacts removed"
