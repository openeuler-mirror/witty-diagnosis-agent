#!/usr/bin/env bash
# diagnose_ca_trust.sh — 分支 C: CA 信任库缺失/过期诊断
set -euo pipefail
OUTDIR="/tmp/ca_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "$OUTDIR"
HOST=""; PORT="443"
while getopts "h:p:" opt; do case $opt in h) HOST="$OPTARG";; p) PORT="$OPTARG";; *) exit 1;; esac; done

echo "==========================================="
echo "  CA Trust Store Diagnosis (Branch C)"
echo "  Target: $HOST:$PORT"
echo "==========================================="

echo "--- C1. Get Issuer from Server Cert ---"
ISSUER=$(openssl s_client -connect "$HOST:$PORT" < /dev/null 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null)
echo "Server cert issuer: $ISSUER"

echo "--- C2. Check Local CA Trust Store ---"
for CA_PATH in /etc/ssl/certs/ca-certificates.crt /etc/pki/tls/certs/ca-bundle.crt /etc/ssl/cert.pem; do
  if [ -f "$CA_PATH" ]; then
    echo "CA store found: $CA_PATH"
    CA_COUNT=$(grep -c "BEGIN CERTIFICATE" "$CA_PATH" 2>/dev/null || echo 0)
    echo "CA certificates in store: $CA_COUNT"
    break
  fi
done

echo "--- C3. Verify with Local CA Store ---"
if [ -f /etc/ssl/certs/ca-certificates.crt ]; then
  ISSUER_CN=$(echo "$ISSUER" | sed 's/.*CN *= *//;s/ *$//' 2>/dev/null)
  echo "Checking issuer \"$ISSUER_CN\" in CA store..."
  timeout 10 openssl s_client -connect "$HOST:$PORT" -CAfile /etc/ssl/certs/ca-certificates.crt -verify_return_error < /dev/null 2>/dev/null | grep -E "Verify return code|verify error" || echo "[FAIL] Certificate not trusted by CA store"
fi

echo "--- C4. Save Certificate for OCSP Check ---"
CERT_FILE="$OUTDIR/server_cert.pem"
CERT_TEXT=$(openssl s_client -connect "$HOST:$PORT" < /dev/null 2>/dev/null)
echo "$CERT_TEXT" | openssl x509 -out "$CERT_FILE" 2>/dev/null || true
if [ -f "$CERT_FILE" ]; then
  OCSP_URL=$(openssl x509 -in "$CERT_FILE" -noout -ocsp_uri 2>/dev/null || echo "N/A")
  echo "OCSP responder: $OCSP_URL"
fi

echo "==========================================="
echo "  Summary: Issuer: $ISSUER"
echo "  Complete output saved to: $OUTDIR"
