#!/bin/bash
# Inject: systemd-resolved Cache Pollution (Branch E)
# Populates resolved cache with fake/stale entries via dig queries
# Then poisons with old IP addresses
# Usage: bash inject_resolved_cache.sh [poison|flush|show]

ACTION="${1:-poison}"
STALE_IP="${2:-1.2.3.4}"
TEST_DOMAIN="cachetest-resolved.example.com"

case "$ACTION" in
    poison)
        echo "[Inject] Poisoning systemd-resolved cache..."
        
        if ! command -v resolvectl &>/dev/null; then
            echo "[ERROR] resolvectl not available (systemd-resolved not running)"
            exit 1
        fi
        
        # Query a non-existent domain to create NXDOMAIN cache
        dig "$TEST_DOMAIN" +short 2>/dev/null
        
        # Query many random domains to fill cache
        for i in $(seq 1 20); do
            dig "test${i}.cache-poison.example.com" +short 2>/dev/null
        done
        
        echo "[Inject] Cache populated with ${TEST_DOMAIN} (NXDOMAIN) + 20 random domains"
        echo "[Inject] Current cache size:"
        resolvectl statistics 2>/dev/null | grep "Current Cache Size"
        ;;
    flush)
        echo "[Inject] Flushing resolved cache"
        if command -v resolvectl &>/dev/null; then
            resolvectl flush-caches
            echo "[Inject] Cache flushed"
            resolvectl statistics 2>/dev/null | grep "Current Cache Size"
        fi
        ;;
    show)
        echo "[Inject] Current cache status:"
        if command -v resolvectl &>/dev/null; then
            resolvectl statistics 2>/dev/null
        fi
        ;;
    *)
        echo "Usage: $0 {poison|flush|show}"
        exit 1
        ;;
esac
