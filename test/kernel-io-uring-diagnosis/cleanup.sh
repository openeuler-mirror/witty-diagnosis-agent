#!/usr/bin/env bash
# Cleanup generated files for kernel-io-uring-diagnosis tests.

set -u

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT_DIR="$ROOT_DIR/out"

rm -rf "$OUT_DIR"
echo "cleaned $OUT_DIR"
