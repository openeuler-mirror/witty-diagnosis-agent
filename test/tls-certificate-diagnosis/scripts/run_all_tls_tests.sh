#!/bin/bash
# run_all_tls_tests.sh — 全 7 分支 TLS 故障注入与诊断测试
set -e
CERTDIR="/test/certs"
mkdir -p "$CERTDIR"
OUTDIR="/tmp/tls_test_results"
mkdir -p "$OUTDIR"
echo "================================================"
echo "  TLS Certificate Diagnosis — Full Test Suite"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================"

# ---- Generate all test certificates ----
echo "=== Generating CA and test certificates ==="
# Root CA
openssl req -x509 -newkey rsa:2048 -keyout "$CERTDIR/ca.key" -out "$CERTDIR/ca.pem" -days 3650 -nodes -subj '/CN=TestRootCA' 2>/dev/null
# Intermediate CA
openssl req -x509 -newkey rsa:2048 -keyout "$CERTDIR/interm.key" -out "$CERTDIR/interm.pem" -days 365 -nodes -subj '/CN=TestIntermediateCA' 2>/dev/null

# 1. EXPIRED cert (A1)
openssl req -newkey rsa:2048 -keyout "$CERTDIR/expired.key" -out "$CERTDIR/expired.csr" -nodes -subj '/CN=expired.example.com' 2>/dev/null
openssl x509 -req -in "$CERTDIR/expired.csr" -CA "$CERTDIR/ca.pem" -CAkey "$CERTDIR/ca.key" -out "$CERTDIR/expired.pem" -days 0 -CAcreateserial 2>/dev/null

# 2. VALID cert (baseline)
openssl req -newkey rsa:2048 -keyout "$CERTDIR/valid.key" -out "$CERTDIR/valid.csr" -nodes -subj '/CN=valid.example.com' 2>/dev/null
openssl x509 -req -in "$CERTDIR/valid.csr" -CA "$CERTDIR/ca.pem" -CAkey "$CERTDIR/ca.key" -out "$CERTDIR/valid.pem" -days 365 -CAcreateserial 2>/dev/null

# 3. SELF-SIGNED cert (C benchmark)
openssl req -x509 -newkey rsa:2048 -keyout "$CERTDIR/selfsigned.key" -out "$CERTDIR/selfsigned.pem" -days 365 -nodes -subj '/CN=selfsigned.example.com' 2>/dev/null

# 4. CHAIN-INCOMPLETE cert (B1) — signed by intermediate, no intermediate sent
openssl req -newkey rsa:2048 -keyout "$CERTDIR/chain_bad.key" -out "$CERTDIR/chain_bad.csr" -nodes -subj '/CN=chain.example.com' 2>/dev/null
openssl x509 -req -in "$CERTDIR/chain_bad.csr" -CA "$CERTDIR/interm.pem" -CAkey "$CERTDIR/interm.key" -out "$CERTDIR/chain_bad.pem" -days 365 -CAcreateserial 2>/dev/null

# 5. UNKNOWN CA cert (C1)
openssl req -x509 -newkey rsa:2048 -keyout "$CERTDIR/otherca.key" -out "$CERTDIR/otherca.pem" -days 365 -nodes -subj '/CN=OtherCA' 2>/dev/null
openssl req -newkey rsa:2048 -keyout "$CERTDIR/unknownca.key" -out "$CERTDIR/unknownca.csr" -nodes -subj '/CN=unknownca.example.com' 2>/dev/null
openssl x509 -req -in "$CERTDIR/unknownca.csr" -CA "$CERTDIR/otherca.pem" -CAkey "$CERTDIR/otherca.key" -out "$CERTDIR/unknownca.pem" -days 365 -CAcreateserial 2>/dev/null

# 6. CLIENT CERT for test (G)
openssl req -newkey rsa:2048 -keyout "$CERTDIR/client.key" -out "$CERTDIR/client.csr" -nodes -subj '/CN=client.example.com' 2>/dev/null
openssl x509 -req -in "$CERTDIR/client.csr" -CA "$CERTDIR/ca.pem" -CAkey "$CERTDIR/ca.key" -out "$CERTDIR/client.pem" -days 365 -CAcreateserial 2>/dev/null

# 7. SNI-specific cert (E)
openssl req -newkey rsa:2048 -keyout "$CERTDIR/sni_www.key" -out "$CERTDIR/sni_www.csr" -nodes -subj '/CN=www.example.com' 2>/dev/null
openssl x509 -req -in "$CERTDIR/sni_www.csr" -CA "$CERTDIR/ca.pem" -CAkey "$CERTDIR/ca.key" -out "$CERTDIR/sni_www.pem" -days 365 -CAcreateserial 2>/dev/null

echo "=== All certificates generated ==="

# ---- Kill any existing openssl s_server instances ----
pkill openssl 2>/dev/null || true
sleep 1

# ---- Start TLS servers for each fault scenario ----
echo "=== Starting TLS test servers ==="

# Port 4433: EXPIRED cert (Branch A)
openssl s_server -key "$CERTDIR/expired.key" -cert "$CERTDIR/expired.pem" -accept 4433 -www &
echo "  4433: EXPIRED cert"

# Port 4434: VALID cert (baseline)
openssl s_server -key "$CERTDIR/valid.key" -cert "$CERTDIR/valid.pem" -accept 4434 -www &
echo "  4434: VALID cert (baseline)"

# Port 4435: SELF-SIGNED cert
openssl s_server -key "$CERTDIR/selfsigned.key" -cert "$CERTDIR/selfsigned.pem" -accept 4435 -www &
echo "  4435: SELF-SIGNED cert"

# Port 4436: CHAIN-INCOMPLETE (Branch B)
openssl s_server -key "$CERTDIR/chain_bad.key" -cert "$CERTDIR/chain_bad.pem" -accept 4436 -www &
echo "  4436: CHAIN-INCOMPLETE"

# Port 4437: UNKNOWN CA (Branch C)
openssl s_server -key "$CERTDIR/unknownca.key" -cert "$CERTDIR/unknownca.pem" -accept 4437 -www &
echo "  4437: UNKNOWN CA"

# Port 4438: TLS 1.2 ONLY — no TLS 1.3 (Branch D1)
openssl s_server -key "$CERTDIR/valid.key" -cert "$CERTDIR/valid.pem" -accept 4438 -www -no_tls1_3 &
echo "  4438: TLS 1.2 ONLY (no 1.3)"

# Port 4439: WEAK CIPHER only — e.g. CAMELLIA only (Branch D2)
openssl s_server -key "$CERTDIR/valid.key" -cert "$CERTDIR/valid.pem" -accept 4439 -www -cipher CAMELLIA256-SHA &
echo "  4439: WEAK CIPHER only"

# Port 4440: DEFAULT cert (no SNI, for comparison in Branch E)
openssl s_server -key "$CERTDIR/valid.key" -cert "$CERTDIR/valid.pem" -accept 4440 -www &
echo "  4440: DEFAULT cert (no SNI)"

# Port 4441: www.example.com cert — for SNI test (Branch E)
# Using same cert with different servername context
openssl s_server -key "$CERTDIR/sni_www.key" -cert "$CERTDIR/sni_www.pem" -accept 4441 -www &
echo "  4441: www.example.com cert"

# Port 4442: Client cert required (Branch G)
openssl s_server -key "$CERTDIR/valid.key" -cert "$CERTDIR/valid.pem" -accept 4442 -Verify 1 -CAfile "$CERTDIR/ca.pem" -www &
echo "  4442: CLIENT CERT required"

# Port 4443: OCSP stapling test (Branch F) — openssl s_server does not support OCSP stapling natively
# This port is for diagnosing the absence of OCSP stapling
openssl s_server -key "$CERTDIR/valid.key" -cert "$CERTDIR/valid.pem" -accept 4443 -www -status_timeout 1 &
echo "  4443: OCSP disabled (no stapling)"

sleep 2
echo "=== All servers running ==="

# ---- Run diagnosis scripts against each server ----
echo ""
echo "================================================"
echo "  Running Branch A: Certificate Expiry"
echo "================================================"
bash /skills/tls-certificate-diagnosis/diagnose_cert_expiry.sh -h localhost -p 4433 2>&1 | tee "$OUTDIR/branch_a_expired.txt"

echo ""
echo "================================================"
echo "  Running Branch B: Chain Incomplete"
echo "================================================"
bash /skills/tls-certificate-diagnosis/diagnose_chain_incomplete.sh -h localhost -p 4436 2>&1 | tee "$OUTDIR/branch_b_chain.txt"

echo ""
echo "================================================"
echo "  Running Branch C: CA Trust Missing"
echo "================================================"
bash /skills/tls-certificate-diagnosis/diagnose_ca_trust.sh -h localhost -p 4437 2>&1 | tee "$OUTDIR/branch_c_ca.txt"

echo ""
echo "================================================"
echo "  Running Branch D: TLS Version (1.2 only)"
echo "================================================"
bash /skills/tls-certificate-diagnosis/diagnose_cipher_compat.sh -h localhost -p 4438 2>&1 | tee "$OUTDIR/branch_d_tls12.txt"

echo ""
echo "================================================"
echo "  Running Branch D: Weak Cipher"
echo "================================================"
bash /skills/tls-certificate-diagnosis/diagnose_cipher_compat.sh -h localhost -p 4439 2>&1 | tee "$OUTDIR/branch_d_weak_cipher.txt"

echo ""
echo "================================================"
echo "  Running Branch E: SNI Test"
echo "================================================"
bash /skills/tls-certificate-diagnosis/diagnose_sni.sh -h localhost -p 4441 2>&1 | tee "$OUTDIR/branch_e_sni.txt"

echo ""
echo "================================================"
echo "  Running Branch G: Client Cert Required"
echo "================================================"
CLIENT_CERT="$CERTDIR/client.pem" CLIENT_KEY="$CERTDIR/client.key" \
  bash /skills/tls-certificate-diagnosis/diagnose_client_cert.sh -h localhost -p 4442 2>&1 | tee "$OUTDIR/branch_g_client_cert.txt"

echo ""
echo "================================================"
echo "  Running Branch F: OCSP Stapling (absent)"
echo "================================================"
bash /skills/tls-certificate-diagnosis/diagnose_ocsp.sh -h localhost -p 4443 2>&1 | tee "$OUTDIR/branch_f_ocsp.txt"

echo ""
echo "================================================"
echo "  ALL TESTS COMPLETE"
echo "  Results saved to: $OUTDIR"
echo "================================================"
