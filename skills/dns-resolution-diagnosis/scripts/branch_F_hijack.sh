#!/bin/bash
# Branch F: DNS 劫持检测
# L2 → L3 下钻：多源对比 → 证书验证 → 抓包分析 → 中间人检测
# 用法: bash branch_F_hijack.sh <TARGET_HOST> <DOMAIN>
# 示例: bash branch_F_hijack.sh web01 example.com

TARGET_HOST="${1:-localhost}"
DOMAIN="${2:-google.com}"
SSH_CMD="bash"
[ "$TARGET_HOST" != "localhost" ] && SSH_CMD="ssh $TARGET_HOST"

REPORT_DIR="${HOME}/.witty-diagnosis-agent/kuafu"
mkdir -p "$REPORT_DIR"
REPORT_FILE="${REPORT_DIR}/kuafu_T6_$(date +%Y%m%d_%H%M%S).md"

exec > >(tee -a "$REPORT_FILE") 2>&1

echo "# Branch F: DNS 劫持检测"
echo "TARGET_HOST=${TARGET_HOST}  DOMAIN=${DOMAIN}"
echo "Timestamp: $(date -Iseconds)"
echo ""

# L2: 多源 DNS 对比
echo "## L2: 多源 DNS 对比"
echo ""

echo "### 1. 本地 DNS 解析"
LOCAL_IP=$(dig +short "$DOMAIN" 2>&1)
echo "本地解析: ${LOCAL_IP:-无应答}"
echo ""

echo "### 2. 外部公共 DNS 解析"
GOOGLE_IP=$(dig +short @8.8.8.8 "$DOMAIN" 2>&1)
CLOUDFLARE_IP=$(dig +short @1.1.1.1 "$DOMAIN" 2>&1)
ALIYUN_IP=$(dig +short @223.5.5.5 "$DOMAIN" 2>&1)
echo "Google (8.8.8.8):     ${GOOGLE_IP:-无应答}"
echo "Cloudflare (1.1.1.1): ${CLOUDFLARE_IP:-无应答}"
echo "Aliyun (223.5.5.5):   ${ALIYUN_IP:-无应答}"
echo ""

echo "### 3. 网关 DNS 解析"
# 尝试获取网关 IP
GATEWAY=$(ip route | grep default | awk '{print $3}' 2>/dev/null)
if [ -n "$GATEWAY" ]; then
    GW_IP=$(dig +short @"$GATEWAY" "$DOMAIN" 2>&1)
    echo "网关 (${GATEWAY}): ${GW_IP:-无应答或非 DNS 服务器}"
fi
echo ""

# L2: IP 一致性检测
echo "## L2: IP 一致性检测"
echo ""

echo "### 4. IP 对比矩阵"
echo ""
echo "| DNS 源 | 返回 IP |"
echo "|--------|---------|"
echo "| 本地默认 | ${LOCAL_IP:----} |"
echo "| 8.8.8.8 | ${GOOGLE_IP:----} |"
echo "| 1.1.1.1 | ${CLOUDFLARE_IP:----} |"
echo "| 223.5.5.5 | ${ALIYUN_IP:----} |"
echo ""

# 检查一致性
ALL_IPS=$(echo "$GOOGLE_IP $CLOUDFLARE_IP $ALIYUN_IP" | tr ' ' '\n' | sort -u | grep -v '^$')
if [ -n "$LOCAL_IP" ] && [ -n "$GOOGLE_IP" ] && [ "$LOCAL_IP" != "$GOOGLE_IP" ]; then
    echo "⚠️  告警: 本地解析与外部公共 DNS 不一致！"
    echo "   本地: ${LOCAL_IP}"
    echo "   外部: ${GOOGLE_IP}"
fi
echo ""

# L2: HTTP/TLS 验证
echo "## L2: HTTP/TLS 验证"
echo ""

echo "### 5. curl HTTP 访问"
echo "--- 通过域名 ---"
curl -v --connect-timeout 5 "http://${DOMAIN}" 2>&1 | head -25
echo ""
echo "--- 直接通过 IP（如果已知）---"
if [ -n "$GOOGLE_IP" ]; then
    FIRST_IP=$(echo "$GOOGLE_IP" | head -1)
    curl -v --connect-timeout 5 -H "Host: ${DOMAIN}" "http://${FIRST_IP}" 2>&1 | head -20
fi
echo ""

echo "### 6. TLS 证书验证"
echo "--- HTTPS 证书链 ---"
openssl s_client -connect "${DOMAIN}:443" -servername "$DOMAIN" -brief 2>&1 | head -20
CERT_CHECK=$?
if [ $CERT_CHECK -ne 0 ]; then
    echo "TLS 连接失败（可能被劫持）"
fi
echo ""

# L3: 抓包分析
echo "## L3: 抓包与中间人检测"
echo ""

if command -v tcpdump &>/dev/null; then
    echo "### 7. DNS 应答抓包分析"
    timeout 10 tcpdump -i any port 53 -c 5 -n -vv 2>&1 || echo "No DNS packets captured in 10s"
    echo ""
    
    echo "### 8. 重发查询并捕获详细应答"
    dig "$DOMAIN" 2>&1 &
    sleep 1
    timeout 5 tcpdump -i any port 53 -c 2 -X 2>&1
else
    echo "tcpdump not available, skip packet capture"
fi
echo ""

echo "### 9. DNS 应答特征分析"
echo "--- 本地应答 TTL ---"
dig "$DOMAIN" 2>&1 | grep -E "^[^;].*IN\s+A\s+" | head -3
echo "--- 外部应答 TTL ---"
dig @8.8.8.8 "$DOMAIN" 2>&1 | grep -E "^[^;].*IN\s+A\s+" | head -3
echo ""

echo "### 10. RPZ/过滤检测"
# 检查是否使用了 RPZ
if command -v dig &>/dev/null; then
    dig +short "$DOMAIN" @"$GATEWAY" 2>&1 | head -3
fi
echo ""

# L3 根因判定
echo "## L3: 根因判定"
echo ""

if [ -z "$LOCAL_IP" ] && [ -n "$GOOGLE_IP" ]; then
    echo "结论: 本地 DNS 无应答，外部 DNS 正常"
    echo "根因: 本地 DNS 服务可能被关闭、配置错误或存在访问控制"
elif [ -n "$LOCAL_IP" ] && [ -n "$GOOGLE_IP" ] && [ "$LOCAL_IP" != "$GOOGLE_IP" ]; then
    echo "结论: 本地和外部 DNS 返回 IP 不一致（劫持高度可疑）"
    echo ""
    echo "根因判定:"
    echo "1. 路由器 DNS 劫持 → 检查网关 DNS 配置"
    echo "2. 运营商 DNS 劫持 → 本地 DNS 是运营商 DNS 时常见"
    echo "3. 本地 hosts 文件覆盖 → 检查 /etc/hosts"
    echo "4. DNSSEC 缺失 → 无 DNSSEC 验证时易被中间人攻击"
    echo ""
    echo "验证方法:"
    echo "  curl -v http://${LOCAL_IP} 检查是否为预期页面"
    echo "  openssl s_client -connect ${LOCAL_IP}:443 检查证书"
elif [ -z "$LOCAL_IP" ] && [ -z "$GOOGLE_IP" ]; then
    echo "结论: 所有 DNS 服务器均无应答"
    echo "根因: 网络层故障或全局 DNS 不可用，非劫持"
else
    echo "结论: 所有 DNS 源返回一致，未检测到劫持"
fi
echo ""
echo "--- Report written to ${REPORT_FILE} ---"
