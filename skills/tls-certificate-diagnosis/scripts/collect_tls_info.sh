#!/usr/bin/env bash
# collect_tls_info.sh — TLS/SSL 综合信息收集（基线）
set -euo pipefail
OUTDIR="/tmp/tls_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "$OUTDIR"

usage() { echo "Usage: $0 -h <host> [-p <port>] [-t <timeout>]"; exit 1; }
HOST=""; PORT="443"; TIMEOUT="10"
while getopts "h:p:t:" opt; do case $opt in
  h) HOST="$OPTARG";; p) PORT="$OPTARG";; t) TIMEOUT="$OPTARG";; *) usage;; esac; done
[ -z "$HOST" ] && usage

echo "============================================"
echo "  TLS/SSL Baseline Collection"
echo "  Target: $HOST:$PORT"
echo "  Time: $(date '+%Y-%m-%d %H:%M:%S')"
echo "  OutDir: $OUTDIR"
echo "============================================"

echo "--- S1. TLS Connection Test ---"
openssl s_client -connect "$HOST:$PORT" -showcerts < /dev/null 2>&1 | tee "$OUTDIR/s_client_full.txt" || echo "[WARN] Connection failed"

echo "--- S2. Certificate Dates ---"
openssl s_client -connect "$HOST:$PORT" < /dev/null 2>/dev/null | openssl x509 -noout -dates 2>/dev/null | tee "$OUTDIR/cert_dates.txt" || echo "[WARN] Could not get cert dates"

echo "--- S3. Certificate Subject/Issuer ---"
openssl s_client -connect "$HOST:$PORT" < /dev/null 2>/dev/null | openssl x509 -noout -subject -issuer 2>/dev/null | tee "$OUTDIR/cert_subject.txt" || true

echo "--- S4. Certificate Fingerprint ---"
openssl s_client -connect "$HOST:$PORT" < /dev/null 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null | tee "$OUTDIR/cert_fingerprint.txt" || true

echo "--- S5. Certificate Chain Count ---"
CHAIN_COUNT=$(openssl s_client -connect "$HOST:$PORT" -showcerts < /dev/null 2>/dev/null | grep -c "subject=" || echo 0)
echo "Chain depth: $CHAIN_COUNT" | tee "$OUTDIR/chain_count.txt"

echo "--- S6. TLS Version Test ---"
for ver in tls1_2 tls1_3; do
  timeout 5 openssl s_client -connect "$HOST:$PORT" -"$ver" < /dev/null 2>/dev/null | grep -E "Cipher|Protocol|error" | head -3 | tee -a "$OUTDIR/tls_versions.txt" || echo "$ver: FAILED" | tee -a "$OUTDIR/tls_versions.txt"
done

echo "--- S7. Cipher Suite Info ---"
CIPHER=$(openssl s_client -connect "$HOST:$PORT" < /dev/null 2>/dev/null | grep "Cipher" | head -1)
echo "Negotiated cipher: $CIPHER" | tee "$OUTDIR/cipher.txt"

echo "--- S8. SNI Test ---"
openssl s_client -connect "$HOST:$PORT" -servername "$HOST" < /dev/null 2>/dev/null | openssl x509 -noout -ext subjectAltName 2>/dev/null | tee "$OUTDIR/sni_san.txt" || echo "[WARN] No SAN"

echo "--- S9. OCSP Stapling ---"
openssl s_client -connect "$HOST:$PORT" -status < /dev/null 2>/dev/null | grep -A20 "OCSP response" | head -20 | tee "$OUTDIR/ocsp_status.txt" || echo "[WARN] No OCSP"

echo "--- S10. Client Certificate Check ---"
openssl s_client -connect "$HOST:$PORT" < /dev/null 2>/dev/null | grep -i "Acceptable client certificate" | tee "$OUTDIR/client_cert_required.txt" || echo "[INFO] No client cert required"

echo "============================================"
echo "[SUMMARY]"
echo "  Target: $HOST:$PORT"
echo "  Chain depth: $CHAIN_COUNT"
echo "  OCSP Status: see $OUTDIR/ocsp_status.txt"
echo "  Complete output saved to: $OUTDIR"
