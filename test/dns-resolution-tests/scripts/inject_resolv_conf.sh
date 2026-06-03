#!/bin/bash
# Inject: /etc/resolv.conf Corruption (Branch C)
# Replaces resolv.conf with empty file to simulate configuration loss
# Usage: bash inject_resolv_conf.sh [backup|restore|corrupt]

ACTION="${1:-corrupt}"
BACKUP_FILE="/etc/resolv.conf.dns_backup"

case "$ACTION" in
    corrupt)
        echo "[Inject] Corrupting /etc/resolv.conf"
        if [ ! -f "$BACKUP_FILE" ]; then
            cp /etc/resolv.conf "$BACKUP_FILE"
            echo "[Inject] Backup saved to $BACKUP_FILE"
        fi
        : > /etc/resolv.conf
        echo "[Inject] /etc/resolv.conf now empty - DNS resolution will fail"
        ;;
    restore)
        echo "[Inject] Restoring /etc/resolv.conf"
        if [ -f "$BACKUP_FILE" ]; then
            cp "$BACKUP_FILE" /etc/resolv.conf
            rm -f "$BACKUP_FILE"
            echo "[Inject] Restored from backup"
        else
            echo "[ERROR] No backup found at $BACKUP_FILE"
            echo "nameserver 8.8.8.8" > /etc/resolv.conf
            echo "[Inject] Created fallback with 8.8.8.8"
        fi
        ;;
    backup)
        echo "[Inject] Current resolv.conf:"
        cat /etc/resolv.conf
        ;;
    *)
        echo "Usage: $0 {corrupt|restore|backup}"
        exit 1
        ;;
esac
