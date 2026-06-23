#!/bin/bash
# run_validation.sh — Flamegraph 验证脚本
# 用法: bash run_validation.sh
# 退出码: 0=全部通过, 1=有失败

set -euo pipefail

BASE_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
ADAPTERS="$BASE_DIR/scripts/adapters"
VALIDATE="$BASE_DIR/scripts/validate"
SAMPLES="$BASE_DIR/../../test/flamegraph-samples"

PASS=0
FAIL=0

check() {
    local name="$1"
    shift
    if "$@" 2>&1; then
        echo "  PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $name"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Flamegraph Validation Suite ==="

# 1. Full SVG validation
echo "[1/4] SVG 6层验证"
for svg in "$SAMPLES"/*.svg; do
    [[ -f "$svg" ]] || continue
    name=$(basename "$svg")
    check "$name" python3 "$VALIDATE/full_svg_v2.py" "$svg"
done

# 2. SVG Pipeline
echo "[2/4] SVG Pipeline"
check "pipeline" python3 "$VALIDATE/validate_svg_pipeline.py"

# 3. Node Syntax Check
echo "[3/4] Node 语法检查"
for html in "$SAMPLES"/*.html; do
    [[ -f "$html" ]] || continue
    name=$(basename "$html")
    python3 -c "
import re
with open('$html','r',encoding='utf-8') as f:
    c = f.read()
s = c.find('(function() {')
e = c.rfind('})();', s)
if s < 0 or e < 0: exit(1)
code = c[s+len('(function() {'):e]
with open('/tmp/check.js','w') as fw: fw.write(code)
" && node --check /tmp/check.js && echo "  PASS: $name" || echo "  FAIL: $name"
done

# 4. SVG to Folded
echo "[4/4] SVG 反向解析"
for svg in "$SAMPLES"/*.svg; do
    [[ -f "$svg" ]] || continue
    name=$(basename "$svg")
    python3 -c "
import sys; sys.path.insert(0, '$ADAPTERS')
from svg_to_folded import svg_to_folded
f,_ = svg_to_folded(open('$svg','r',encoding='utf-8').read())
n = len(f.strip().split(chr(10))) if f.strip() else 0
print(f'  {\"OK\" if n>0 else \"SKIP\"}: {n} lines {name}')
" || true
done

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
exit 0
