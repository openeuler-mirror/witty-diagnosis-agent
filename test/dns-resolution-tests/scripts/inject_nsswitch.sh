#!/bin/bash
# Inject: nsswitch.conf Order Misconfiguration (Branch D)
# Modifies nsswitch.conf to place mdns before dns
# Usage: bash inject_nsswitch.sh [corrupt|restore|show]

ACTION="${1:-corrupt}"
BACKUP_FILE="/etc/nsswitch.conf.dns_backup"
NSSWITCH="/etc/nsswitch.conf"

case "$ACTION" in
    corrupt)
        echo "[Inject] Misconfiguring nsswitch.conf"
        if [ ! -f "$BACKUP_FILE" ]; then
            cp "$NSSWITCH" "$BACKUP_FILE"
            echo "[Inject] Backup saved to $BACKUP_FILE"
        fi
        # Change hosts line to put mdns before dns
        if grep -q "^hosts:" "$NSSWITCH"; then
            sed -i 's/^hosts:.*$/hosts:          files mdns [NOTFOUND=return] dns myhostname/' "$NSSWITCH"
            echo "[Inject] hosts line changed to: files mdns [NOTFOUND=return] dns myhostname"
            echo "[Inject] mDNS now has priority over DNS"
        else
            echo "[ERROR] No hosts line found in nsswitch.conf"
        fi
        ;;
    restore)
        echo "[Inject] Restoring nsswitch.conf"
        if [ -f "$BACKUP_FILE" ]; then
            cp "$BACKUP_FILE" "$NSSWITCH"
            rm -f "$BACKUP_FILE"
            echo "[Inject] Restored from backup"
        else
            echo "[ERROR] No backup found"
        fi
        ;;
    show)
        grep ^hosts "$NSSWITCH"
        ;;
    *)
        echo "Usage: $0 {corrupt|restore|show}"
        exit 1
        ;;
esac
