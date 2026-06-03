#!/usr/bin/env bash
# diagnose_cert_expiry.sh — 分支 A: 证书过期/即将过期诊断
set -euo pipefail
OUTDIR="/tmp/cert_expiry_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "$OUTDIR"

usage() { echo "Usage: $0 -h <host> [-p <port>]"; exit 1; }
HOST=""; PORT="443"
while getopts "h:p:" opt; do case $opt in h) HOST="$OPTARG";; p) PORT="$OPTARG";; *) usage;; esac; done
[ -z "$HOST" ] && usage

echo "==========================================="
echo "  Certificate Expiry Diagnosis (Branch A)"
echo "  Target: $HOST:$PORT"
echo "==========================================="

echo "--- A1. Certificate Validity Period ---"
CERT_TEXT=$(openssl s_client -connect "$HOST:$PORT" -showcerts < /dev/null 2>/dev/null)
CERT_DATES=$(echo "$CERT_TEXT" | openssl x509 -noout -dates 2>/dev/null) || echo "FAILED"
echo "$CERT_DATES"

NOTBEFORE=$(echo "$CERT_DATES" | grep "notBefore" | sed 's/notBefore=//')
NOTAFTER=$(echo "$CERT_DATES" | grep "notAfter" | sed 's/notAfter=//')
if [ -n "$NOTAFTER" ] && [ -n "$NOTBEFORE" ]; then
  NB_EPOCH=$(date -d "$NOTBEFORE" +%s 2>/dev/null || echo 0)
  NA_EPOCH=$(date -d "$NOTAFTER" +%s 2>/dev/null || echo 0)
  NOW_EPOCH=$(date +%s)
  REMAINING_DAYS=$(( (NA_EPOCH - NOW_EPOCH) / 86400 ))
  TOTAL_VALID_SEC=$(( NA_EPOCH - NB_EPOCH ))
  TOTAL_VALID_DAYS=$(( TOTAL_VALID_SEC / 86400 ))
  echo "Total validity: $TOTAL_VALID_DAYS days"
  echo "Remaining days: $REMAINING_DAYS"
  if [ $TOTAL_VALID_SEC -le 0 ]; then
    echo "[ALERT] Certificate has ZERO validity (notBefore equals or after notAfter)"
  elif [ $REMAINING_DAYS -lt 0 ]; then
    echo "[ALERT] Certificate has EXPIRED ($((-REMAINING_DAYS)) days ago)"
  elif [ $REMAINING_DAYS -lt 30 ]; then
    echo "[WARN] Certificate will expire in $REMAINING_DAYS days"
  else
    echo "[OK] Certificate valid for $REMAINING_DAYS more days"
  fi
fi

echo "--- A2. System Time Check ---"
date
if command -v chronyc &>/dev/null; then
  chronyc tracking 2>/dev/null | grep -E "Ref time|Stratum|Last offset" || true
elif command -v ntpq &>/dev/null; then
  ntpq -p 2>/dev/null | head -5 || true
fi

echo "--- A3. Full Certificate Details ---"
openssl s_client -connect "$HOST:$PORT" -showcerts < /dev/null 2>/dev/null | openssl x509 -noout -subject -issuer -dates -fingerprint -sha256 2>/dev/null || echo "FAILED"

echo "==========================================="
echo "  Diagnosis Summary"
echo "  notAfter: $NOTAFTER"
echo "  Remaining: ${REMAINING_DAYS:-N/A} days"
echo "  Complete output saved to: $OUTDIR"
