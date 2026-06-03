#!/usr/bin/env bash
# diagnose_ocsp.sh — 分支 F: OCSP stapling 失败诊断
set -euo pipefail
HOST=""; PORT="443"
OUTDIR="/tmp/ocsp_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "$OUTDIR"
while getopts "h:p:" opt; do case $opt in h) HOST="$OPTARG";; p) PORT="$OPTARG";; *) exit 1;; esac; done

echo "==========================================="
echo "  OCSP Stapling Diagnosis (Branch F)"
echo "  Target: $HOST:$PORT"
echo "==========================================="

echo "--- F1. OCSP Stapling Status ---"
OCSP_OUT=$(openssl s_client -connect "$HOST:$PORT" -status < /dev/null 2>/dev/null)
echo "$OCSP_OUT" > "$OUTDIR/ocsp_full_output.txt"
echo "$OCSP_OUT" | grep -A20 "OCSP response" | head -20

echo "--- F2. OCSP Response Status ---"
echo "$OCSP_OUT" | grep "OCSP Response Status" || echo "[INFO] No OCSP stapling"

echo "--- F3. OCSP Responder URL ---"
CERT_PEM=$(openssl s_client -connect "$HOST:$PORT" < /dev/null 2>/dev/null | sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p')
if [ -n "$CERT_PEM" ]; then
  echo "$CERT_PEM" > "$OUTDIR/server_cert_for_ocsp.pem"
  OCSP_URL=$(echo "$CERT_PEM" | openssl x509 -noout -ocsp_uri 2>/dev/null || echo "N/A")
  echo "OCSP responder URL: $OCSP_URL"
fi

echo "--- F4. Certificate Revocation Status ---"
echo "$OCSP_OUT" | grep "Cert Status" || echo "[INFO] Cert status not available via stapling"

echo "==========================================="
echo "  Complete"
echo "[INFO] Output saved to: $OUTDIR"
