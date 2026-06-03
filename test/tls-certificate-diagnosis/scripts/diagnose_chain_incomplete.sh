#!/usr/bin/env bash
# diagnose_chain_incomplete.sh — 分支 B: 证书链不完整诊断
set -euo pipefail
OUTDIR="/tmp/chain_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "$OUTDIR"
HOST=""; PORT="443"
while getopts "h:p:" opt; do case $opt in h) HOST="$OPTARG";; p) PORT="$OPTARG";; *) exit 1;; esac; done

echo "==========================================="
echo "  Certificate Chain Diagnosis (Branch B)"
echo "  Target: $HOST:$PORT"
echo "==========================================="

echo "--- B1. Chain Depth ---"
openssl s_client -connect "$HOST:$PORT" -showcerts < /dev/null 2>/dev/null > "$OUTDIR/full_chain.txt"
CHAIN=$(grep -c "subject=" "$OUTDIR/full_chain.txt" 2>/dev/null || echo 0)
echo "Chain depth: $CHAIN certificates"
if [ "$CHAIN" -lt 2 ]; then echo "[ALERT] Chain incomplete (only $CHAIN cert, expected >=2)"; fi

echo "--- B2. Extract Each Certificate ---"
csplit -f "$OUTDIR/cert_" "$OUTDIR/full_chain.txt" '/BEGIN CERTIFICATE/' '{*}' 2>/dev/null || true
for f in "$OUTDIR"/cert_*; do
  if [ -f "$f" ] && grep -q "BEGIN CERTIFICATE" "$f" 2>/dev/null; then
    echo "--- Cert: $(openssl x509 -in "$f" -noout -subject 2>/dev/null) ---"
    echo "  Issuer: $(openssl x509 -in "$f" -noout -issuer 2>/dev/null)"
    echo "  Dates: $(openssl x509 -in "$f" -noout -dates 2>/dev/null)"
  fi
done

echo "--- B3. Verify Chain (if saved locally) ---"
echo "[INFO] To verify: openssl verify -CAfile ca.pem -untrusted intermediate.pem server.pem"

echo "==========================================="
echo "  Summary: Chain depth = $CHAIN"
echo "  Complete output saved to: $OUTDIR"
