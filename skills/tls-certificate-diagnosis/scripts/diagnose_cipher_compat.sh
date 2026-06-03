#!/usr/bin/env bash
# diagnose_cipher_compat.sh — 分支 D: TLS 版本/密码套件诊断
set -euo pipefail
HOST=""; PORT="443"
while getopts "h:p:" opt; do case $opt in h) HOST="$OPTARG";; p) PORT="$OPTARG";; *) exit 1;; esac; done

echo "==========================================="
echo "  TLS Cipher Compatibility (Branch D)"
echo "  Target: $HOST:$PORT"
echo "==========================================="

echo "--- D1. TLS Version Test ---"
for ver in tls1_2 tls1_3; do
  RESULT=$(timeout 5 openssl s_client -connect "$HOST:$PORT" -"$ver" < /dev/null 2>/dev/null | grep -E "Cipher|Protocol" | head -1)
  if [ -n "$RESULT" ]; then echo "[OK] $ver: $RESULT"; else echo "[FAIL] $ver: not supported"; fi
done

echo "--- D2. Negotiated Cipher ---"
openssl s_client -connect "$HOST:$PORT" < /dev/null 2>/dev/null | grep "Cipher" | head -3

echo "--- D3. Available Ciphers (Client Side) ---"
openssl ciphers -v 'ALL:COMPLEMENTOFALL' | head -10
echo "... ($(openssl ciphers 'ALL:COMPLEMENTOFALL' | tr ':' '\n' | wc -l) total)"

echo "--- D4. Test Specific Cipher Groups ---"
for CIPHER in "ECDHE-RSA-AES256-GCM-SHA384" "ECDHE-RSA-AES128-GCM-SHA256" "AES256-GCM-SHA384"; do
  RESULT=$(timeout 5 openssl s_client -connect "$HOST:$PORT" -cipher "$CIPHER" < /dev/null 2>/dev/null | grep -E "Cipher.*is" | head -1)
  if [ -n "$RESULT" ]; then echo "[OK] $CIPHER: supported"; else echo "[FAIL] $CIPHER: not supported"; fi
done

echo "==========================================="
echo "  Complete"
