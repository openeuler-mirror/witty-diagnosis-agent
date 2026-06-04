#!/bin/bash
# DNS 诊断 L1 基线采集脚本
# 用法: bash 01_baseline_info.sh [TARGET_HOST]
# 示例: bash 01_baseline_info.sh web01

TARGET_HOST="${1:-localhost}"
SSH_CMD="ssh"
[ "$TARGET_HOST" != "localhost" ] && SSH_CMD="ssh $TARGET_HOST" || SSH_CMD="bash"

$SSH_CMD << 'SCRIPT'
echo "========================================="
echo " DNS L1 基线信息采集"
echo " 主机: $(hostname)"
echo " 时间: $(date -Iseconds)"
echo "========================================="

echo ""
echo "=== 1. /etc/resolv.conf ==="
cat /etc/resolv.conf 2>&1

echo ""
echo "=== 2. /etc/resolv.conf 文件属性 ==="
stat /etc/resolv.conf 2>&1

echo ""
echo "=== 3. /etc/nsswitch.conf hosts 行 ==="
grep ^hosts /etc/nsswitch.conf 2>&1

echo ""
echo "=== 4. /etc/hosts 文件 ==="
cat /etc/hosts 2>&1

echo ""
echo "=== 5. systemd-resolved 状态 ==="
if command -v resolvectl &>/dev/null; then
    resolvectl status 2>&1 || echo "resolvectl status failed"
    echo ""
    echo "--- resolvectl statistics ---"
    resolvectl statistics 2>&1
elif command -v systemd-resolve &>/dev/null; then
    systemd-resolve --status 2>&1 || echo "systemd-resolve failed"
else
    echo "systemd-resolved not detected"
fi

echo ""
echo "=== 6. 基础 DNS 解析测试 ==="
echo "--- dig google.com ---"
dig +short google.com 2>&1
echo "--- dig @8.8.8.8 google.com ---"
dig +short @8.8.8.8 google.com 2>&1
echo "--- dig @114.114.114.114 google.com ---"
dig +short @114.114.114.114 google.com 2>&1

echo ""
echo "=== 7. 网络连通性 ==="
echo "--- DNS 服务器 ping ---"
for ns in $(awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null); do
    ping -c 2 -W 2 $ns 2>&1 | head -5
done

echo ""
echo "=== 8. 防火墙规则 (port 53) ==="
if command -v iptables &>/dev/null; then
    iptables -L -n -v 2>&1 | grep -E '53|dns' || echo "No DNS-related iptables rules"
fi
if command -v nft &>/dev/null; then
    nft list ruleset 2>&1 | grep -E '53|dns' || echo "No DNS-related nft rules"
fi

echo ""
echo "=== 9. 监听中的 DNS 服务 ==="
ss -tulpn 2>/dev/null | grep -E ':53\b' || netstat -tulpn 2>/dev/null | grep ':53' || echo "No DNS services found"

echo ""
echo "=== 10. DNS 缓存统计 ==="
if command -v resolvectl &>/dev/null; then
    resolvectl statistics 2>&1 | grep -E "Cache|Current"
fi

SCRIPT
