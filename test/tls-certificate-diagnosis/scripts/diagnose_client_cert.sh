#!/usr/bin/env bash
# diagnose_client_cert.sh — 分支 G: 客户端证书认证失败诊断
set -euo pipefail
HOST=""; PORT="443"
while getopts "h:p:" opt; do case $opt in h) HOST="$OPTARG";; p) PORT="$OPTARG";; *) exit 1;; esac; done

echo "==========================================="
echo "  Client Certificate Diagnosis (Branch G)"
echo "  Target: $HOST:$PORT"
echo "==========================================="

echo "--- G1. Check if Server Requires Client Cert ---"
CONN_OUT=$(openssl s_client -connect "$HOST:$PORT" < /dev/null 2>/dev/null)
echo "$CONN_OUT" | grep -i "Acceptable client certificate CA names" | head -5 || echo "[OK] No client certificate required"
# Also check for certificate request alert
echo "$CONN_OUT" | grep -i "certificate required" | head -3 || true

echo "--- G2. Client Certificate Check ---"
if [ -f "${CLIENT_CERT:-}" ]; then
  echo "Client cert: $CLIENT_CERT"
  openssl x509 -in "$CLIENT_CERT" -noout -subject -dates -ext extendedKeyUsage 2>/dev/null
else
  echo "[INFO] No client cert specified (set CLIENT_CERT env var)"
  echo "[INFO] Usage: CLIENT_CERT=client.pem CLIENT_KEY=client.key $0 -h $HOST"
fi

echo "--- G3. Test with Client Cert (if available) ---"
if [ -n "${CLIENT_CERT:-}" ] && [ -n "${CLIENT_KEY:-}" ]; then
  echo "--- Attempting TLS 1.2 connection with client cert (more reliable for mTLS) ---"
  timeout 10 openssl s_client -connect "$HOST:$PORT" -cert "$CLIENT_CERT" -key "$CLIENT_KEY" -tls1_2 < /dev/null 2>/dev/null | grep -E "Cipher|Verify|error|return code" | head -5
  echo "--- Attempting TLS 1.3 connection with client cert ---"
  timeout 10 openssl s_client -connect "$HOST:$PORT" -cert "$CLIENT_CERT" -key "$CLIENT_KEY" < /dev/null 2>/dev/null | grep -E "Cipher|Alert|error|return code" | head -5
fi

echo "==========================================="
echo "  Complete"
