#!/bin/bash
# Branch A: DNS 解析超时/查询失败诊断
# L2 → L3 下钻：网络连通性 → 防火墙 → 协议层抓包
# 用法: bash branch_A_timeout.sh <TARGET_HOST> <DNS_SERVER>
# 示例: bash branch_A_timeout.sh web01 8.8.8.8

TARGET_HOST="${1:-localhost}"
DNS_SERVER="${2:-8.8.8.8}"
SSH_CMD="bash"
[ "$TARGET_HOST" != "localhost" ] && SSH_CMD="ssh $TARGET_HOST"

REPORT_DIR="${HOME}/.witty-diagnosis-agent/kuafu"
mkdir -p "$REPORT_DIR"
REPORT_FILE="${REPORT_DIR}/kuafu_T1_$(date +%Y%m%d_%H%M%S).md"

exec > >(tee -a "$REPORT_FILE") 2>&1

echo "# Branch A: DNS 解析超时/查询失败诊断"
echo "TARGET_HOST=${TARGET_HOST}  DNS_SERVER=${DNS_SERVER}"
echo "Timestamp: $(date -Iseconds)"
echo ""

# L2: 网络层连通性检查
echo "## L2: 网络连通性检查"
echo ""

echo "### 1. ping DNS 服务器"
ping -c 3 -W 2 "$DNS_SERVER" 2>&1
PING_OK=$?
echo ""

echo "### 2. UDP 53 端口连通性"
nc -zvu "$DNS_SERVER" 53 2>&1 || echo "nc UDP test failed/hung (timeout 3s)"
UDP_OK=$?
echo ""

echo "### 3. TCP 53 端口连通性"
timeout 3 nc -zv "$DNS_SERVER" 53 2>&1 || echo "TCP 53 unreachable or timeout"
TCP_OK=$?
echo ""

# L2: DNS 协议层测试
echo "## L2: DNS 协议层测试"
echo ""

echo "### 4. dig 默认查询"
dig +timeout=3 "$DNS_SERVER" 2>&1 | head -20
echo ""

echo "### 5. dig +tcp 查询"
dig +tcp +timeout=3 @"$DNS_SERVER" google.com 2>&1 | head -20
echo ""

echo "### 6. dig 短超时多轮测试"
for i in 1 2 3; do
    echo "--- Attempt $i ---"
    dig +timeout=2 @"$DNS_SERVER" google.com 2>&1 | grep -E "status|timed out|SERVER"
done
echo ""

# L2: 本地防火墙检查
echo "## L2: 本地防火墙检查"
echo ""

echo "### 7. iptables 规则"
iptables -L -n -v 2>&1 | grep -E '53|dns|DROP|REJECT' || echo "No matching rules found"
echo ""

echo "### 8. nftables 规则"
nft list ruleset 2>&1 | grep -E '53|dns' || echo "No nft rules found or nft not available"
echo ""

# L2: traceroute
echo "## L2: 路由跟踪"
echo ""
traceroute -n -p 53 -m 15 "$DNS_SERVER" 2>&1 | head -20 || echo "traceroute failed"
echo ""

# L3: 抓包分析（若 tcpdump 可用）
echo "## L3: 数据包分析"
echo ""

if command -v tcpdump &>/dev/null; then
    echo "### 9. tcpdump DNS 抓包（5 秒捕获）"
    timeout 5 tcpdump -i any port 53 -c 5 -n 2>&1 || echo "No DNS packets captured"
else
    echo "tcpdump not available, skip packet capture"
fi
echo ""

echo "### 10. 检查接口统计（丢包/错误）"
for iface in $(ip -o link show | awk -F': ' '{print $2}' 2>/dev/null); do
    ethtool -S "$iface" 2>/dev/null | grep -E "drop|error|fifo" | head -5
done
echo ""

# L3 根因判定
echo "## L3: 根因判定"
echo ""

if [ $PING_OK -ne 0 ]; then
    echo "结论: DNS 服务器 ${DNS_SERVER} ping 不可达"
    echo "根因: 网络层故障（路由不可达/链路中断/主机宕机）"
elif [ $UDP_OK -ne 0 ] && [ $TCP_OK -ne 0 ]; then
    echo "结论: DNS 服务器 ${DNS_SERVER} UDP 和 TCP 53 均不可达"
    echo "根因: 中间防火墙或网络设备拦截了所有 DNS 流量"
elif [ $UDP_OK -ne 0 ]; then
    echo "结论: DNS 服务器 ${DNS_SERVER} UDP 53 不可达，TCP 可达"
    echo "根因: 防火墙策略仅拦截 UDP 53 流量（TCP DNS 可用）"
elif [ $TCP_OK -ne 0 ]; then
    echo "结论: DNS 服务器 ${DNS_SERVER} UDP 53 可达，TCP 53 不可达"
    echo "根因: 防火墙拦截 TCP 53（影响大响应/区域传输）"
else
    echo "结论: DNS 服务器 ${DNS_SERVER} 网络连通性正常"
    echo "建议: 继续排查 DNS 服务器端负载、递归链路或 EDNS0 兼容性"
fi
echo ""
echo "--- Report written to ${REPORT_FILE} ---"
