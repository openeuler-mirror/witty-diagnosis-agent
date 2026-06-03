#!/usr/bin/env bash
# diagnose_sni.sh — 分支 E: SNI 配置错误诊断
set -euo pipefail
HOST=""; PORT="443"
while getopts "h:p:" opt; do case $opt in h) HOST="$OPTARG";; p) PORT="$OPTARG";; *) exit 1;; esac; done

echo "==========================================="
echo "  SNI Configuration Diagnosis (Branch E)"
echo "  Target: $HOST:$PORT"
echo "==========================================="

echo "--- E1. With SNI (correct domain) ---"
WITH_SNI=$(openssl s_client -connect "$HOST:$PORT" -servername "$HOST" < /dev/null 2>/dev/null | openssl x509 -noout -subject 2>/dev/null)
echo "SNI subject: $WITH_SNI"

echo "--- E2. Without SNI (default cert) ---"
WITHOUT_SNI=$(openssl s_client -connect "$HOST:$PORT" < /dev/null 2>/dev/null | openssl x509 -noout -subject 2>/dev/null)
echo "Default subject: $WITHOUT_SNI"

if [ "$WITH_SNI" != "$WITHOUT_SNI" ]; then
  echo "[INFO] SNI configuration active - different certs for SNI vs non-SNI connections"
fi

echo "--- E3. SAN Check ---"
SAN_OUTPUT=$(openssl s_client -connect "$HOST:$PORT" -servername "$HOST" < /dev/null 2>/dev/null | openssl x509 -noout -ext subjectAltName 2>/dev/null)
if [ -n "$SAN_OUTPUT" ]; then
  echo "SAN: $SAN_OUTPUT"
  if echo "$SAN_OUTPUT" | grep -qi "$HOST" 2>/dev/null; then
    echo "[OK] Host $HOST found in SAN"
  else
    echo "[WARN] Host $HOST NOT found in SAN - possible name mismatch"
  fi
else
  echo "[WARN] No SAN extension (certificate may be X.509 v1)"
fi

echo "--- E4. Domain Validation ---"
echo "[INFO] Verify that $HOST is listed in the SAN above"
echo "[INFO] Wildcard *.example.com does NOT match sub.sub.example.com"

echo "==========================================="
echo "  Complete"
