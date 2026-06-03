#!/bin/bash
# entrypoint.sh — TLS certificate diagnosis test entrypoint
set -e
CERTDIR="/test/certs"
mkdir -p "$CERTDIR"
echo "================================================"
echo "  TLS Certificate Diagnosis — Test Entry"
echo "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "================================================"
echo ""
echo "=== Generating test certificates ==="
# Self-signed CA
openssl req -x509 -newkey rsa:2048 -keyout "$CERTDIR/ca.key" -out "$CERTDIR/ca.pem" -days 365 -nodes -subj '/CN=TestCA' 2>/dev/null
# Generate expired certificate (zero validity)
openssl req -newkey rsa:2048 -keyout "$CERTDIR/expired.key" -out "$CERTDIR/expired.csr" -nodes -subj '/CN=expired.example.com' 2>/dev/null
openssl x509 -req -in "$CERTDIR/expired.csr" -CA "$CERTDIR/ca.pem" -CAkey "$CERTDIR/ca.key" -out "$CERTDIR/expired.pem" -days 0 -CAcreateserial 2>/dev/null
# Generate valid certificate
openssl req -newkey rsa:2048 -keyout "$CERTDIR/valid.key" -out "$CERTDIR/valid.csr" -nodes -subj '/CN=valid.example.com' 2>/dev/null
openssl x509 -req -in "$CERTDIR/valid.csr" -CA "$CERTDIR/ca.pem" -CAkey "$CERTDIR/ca.key" -out "$CERTDIR/valid.pem" -days 365 -CAcreateserial 2>/dev/null
echo "=== Test certificates ready ==="
echo ""
echo "=== Tests done, keeping container alive ==="
sleep 3600
