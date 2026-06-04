#!/bin/bash
# Branch G: DNS TCP Fallback 失败诊断
# L2 → L3 下钻：UDP 截断检测 → TCP 连通性 → 包大小测试 → DNSSEC 关联
# 用法: bash branch_G_tcp_fallback.sh <TARGET_HOST> <DNS_SERVER>
# 示例: bash branch_G_tcp_fallback.sh web01 8.8.8.8

TARGET_HOST="${1:-localhost}"
DNS_SERVER="${2:-8.8.8.8}"
SSH_CMD="bash"
[ "$TARGET_HOST" != "localhost" ] && SSH_CMD="ssh $TARGET_HOST"

REPORT_DIR="${HOME}/.witty-diagnosis-agent/kuafu"
mkdir -p "$REPORT_DIR"
REPORT_FILE="${REPORT_DIR}/kuafu_T7_$(date +%Y%m%d_%H%M%S).md"

exec > >(tee -a "$REPORT_FILE") 2>&1

echo "# Branch G: DNS TCP Fallback 失败诊断"
echo "TARGET_HOST=${TARGET_HOST}  DNS_SERVER=${DNS_SERVER}"
echo "Timestamp: $(date -Iseconds)"
echo ""

# L2: UDP 截断检测
echo "## L2: UDP 截断检测"
echo ""

echo "### 1. 基础 dig（检查 TC 标志）"
dig @"$DNS_SERVER" google.com 2>&1 | grep -E "flags:|status:|SERVER"
echo ""

echo "### 2. 大响应触发 TC（RRSIG 记录类型）"
echo "--- dig +dnssec ANY ---"
dig +dnssec @"$DNS_SERVER" google.com ANY 2>&1 | grep -E "flags:|TC|status:" | head -5
echo ""
echo "--- dig +bufsize=512（限制 UDP 大小触发 TC）---"
dig +bufsize=512 @"$DNS_SERVER" google.com ANY 2>&1 | grep -E "flags:|TC|status:" | head -5
echo ""

echo "### 3. 检查 TC 标志位"
for qtype in A AAAA MX ANY; do
    TC_FLAG=$(dig +dnssec @"$DNS_SERVER" google.com "$qtype" 2>&1 | grep "flags:" | grep -o "tc")
    if [ -n "$TC_FLAG" ]; then
        echo "QTYPE=${qtype}: ⚠️  TC 标志置位（需要 TCP fallback）"
    else
        echo "QTYPE=${qtype}: ✓ 无 TC 标志"
    fi
done
echo ""

# L2: TCP 连通性测试
echo "## L2: TCP 连通性测试"
echo ""

echo "### 4. TCP 端口可达性"
timeout 3 nc -zv "$DNS_SERVER" 53 2>&1 || echo "TCP 53 unreachable or timeout"
TCP_OK=$?
echo ""

echo "### 5. dig +tcp 查询"
dig +tcp +timeout=5 @"$DNS_SERVER" google.com 2>&1 | grep -E "status:|flags:|SERVER" | head -5
TCP_DIG_OK=$?
echo ""

echo "### 6. dig +tcp +dnssec（TCP + DNSSEC 联合测试）"
dig +tcp +dnssec +timeout=5 @"$DNS_SERVER" google.com ANY 2>&1 | grep -E "status:|flags:|TC|SERVER" | head -5
echo ""

# L2: 包大小测试
echo "## L2: DNS 包大小测试"
echo ""

echo "### 7. 递增 UDP 包大小测试"
for size in 512 1024 1500 2048 3000 4096; do
    echo -n "bufsize=${size}: "
    dig +bufsize="$size" +timeout=3 @"$DNS_SERVER" google.com 2>&1 | grep "status:" | head -1
done
echo ""

echo "### 8. EDNS0 大包测试"
echo "--- dig +edns0 +bufsize=4096 ---"
dig +edns0 +bufsize=4096 +timeout=3 @"$DNS_SERVER" google.com ANY 2>&1 | grep -E "flags:|status:|TC" | head -5
echo ""

# L3: PMTU 路径检测
echo "## L3: PMTU 与网络路径检测"
echo ""

echo "### 9. PMTU 检测（ping 不可分片）"
for size in 1472 1400 1300 1200 1000; do
    ping -M do -c 2 -W 2 -s "$size" "$DNS_SERVER" 2>&1 | tail -1
done
echo ""

echo "### 10. 接口 MTU"
ip link show 2>&1 | grep -E "mtu|UP" | head -5
echo ""

echo "### 11. TCP traceroute"
traceroute -n -p 53 -T "$DNS_SERVER" 2>&1 | head -15 || echo "traceroute not available"
echo ""

echo "### 12. iptables 对 TCP 53 的规则"
iptables -L -n -v 2>&1 | grep -E ':53|dns' || echo "No specific rules for DNS"
nft list ruleset 2>&1 | grep -E '53|dns' || true
echo ""

# L3 根因判定
echo "## L3: 根因判定"
echo ""

if [ "$TCP_OK" -ne 0 ]; then
    echo "结论: TCP 53 端口不可达"
    if [ "$TCP_DIG_OK" -ne 0 ]; then
        echo "根因: 防火墙或网络设备拦截了 TCP 53 出站流量"
        echo "影响: 所有需要 TCP fallback 的场景（大响应、区域传输）均失败"
        echo "修复: 放行出站 TCP 53 流量"
    fi
else
    # 检查 TC 标志位
    TC_FOUND=$(dig +dnssec @"$DNS_SERVER" google.com ANY 2>&1 | grep -c "tc")
    if [ "$TC_FOUND" -gt 0 ]; then
        echo "结论: UDP DNS 响应该截断（TC=1），TCP 连通性正常"
        echo "根因: 上游 DNS 响应超过 UDP 大小限制，强制使用 TCP"
        echo "      虽然 TCP 可用，但可能因额外延迟导致查询缓慢"
    else
        echo "结论: 未检测到 TCP fallback 异常"
        echo "建议: 如果仍有解析问题，检查 EDNS0 兼容性（Branch H）"
    fi
fi
echo ""

# 额外建议
echo "### 综合建议"
echo ""
echo "| 场景 | 推荐操作 |"
echo "|------|---------|"
echo "| UDP 正常，TCP 不可达 | 放行防火墙 TCP 53 |"
echo "| UDP 截断，TCP 正常 | 接受正常 fallback 行为 |"
echo "| UDP 截断，TCP 超时 | 检查中间设备 TCP 策略 |"
echo "| DNSSEC 查询失败 | 检查 EDNS0 兼容性 |"
echo "| 特定查询类型失败 | 检查上游 DNS 对该类型的支持 |"
echo ""
echo "--- Report written to ${REPORT_FILE} ---"
