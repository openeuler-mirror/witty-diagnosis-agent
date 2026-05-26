#!/bin/bash
# run_fault2_sigbus.sh — 容器2: SIGBUS 文件截断故障
# 注入 SIGBUS 后保持容器运行，供 witty agent 诊断
set -e

echo "=== 注入 SIGBUS 故障 ==="
/test/fault_sigbus 2>&1 || true
echo ""

# 保留故障痕迹
echo "=== 内核日志中的 SIGBUS 记录 ==="
dmesg 2>/dev/null | grep -iE "SIGBUS|bus error|segfault" | tail -10 || echo "(无)"
echo "=== 故障文件残留 ==="
ls -la /tmp/fault_sigbus_test 2>/dev/null || echo "(临时文件已自动清理)"

# 保持容器运行
echo "容器将持续运行，等待外部诊断..."
sleep 3600
