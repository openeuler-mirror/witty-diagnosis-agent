#!/bin/bash
# fault2_entry.sh — 容器2入口: SIGBUS 故障 + 保持运行
echo "=== SIGBUS 故障注入 ==="
/test/fault_sigbus 2>&1 || true
dmesg 2>/dev/null | grep -iE "SIGBUS|bus error|segfault" | tail -5
echo "=== 故障注入完毕，保持运行等待诊断... ==="
sleep 3600
