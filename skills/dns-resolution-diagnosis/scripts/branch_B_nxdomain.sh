#!/bin/bash
# Branch B: NXDOMAIN 误报诊断
# L2 → L3 下钻：权威追踪 → 本地缓存 → DNSSEC 验证
# 用法: bash branch_B_nxdomain.sh <TARGET_HOST> <DOMAIN>
# 示例: bash branch_B_nxdomain.sh web01 example.com

TARGET_HOST="${1:-localhost}"
DOMAIN="${2:-google.com}"
SSH_CMD="bash"
[ "$TARGET_HOST" != "localhost" ] && SSH_CMD="ssh $TARGET_HOST"

REPORT_DIR="${HOME}/.witty-diagnosis-agent/kuafu"
mkdir -p "$REPORT_DIR"
REPORT_FILE="${REPORT_DIR}/kuafu_T2_$(date +%Y%m%d_%H%M%S).md"

exec > >(tee -a "$REPORT_FILE") 2>&1

echo "# Branch B: NXDOMAIN 误报诊断"
echo "TARGET_HOST=${TARGET_HOST}  DOMAIN=${DOMAIN}"
echo "Timestamp: $(date -Iseconds)"
echo ""

# L2: 权威链路追踪
echo "## L2: 权威解析链路追踪"
echo ""

echo "### 1. dig +trace 完整递归路径"
dig +trace "$DOMAIN" 2>&1 | head -60
TRACE_OK=$?
echo ""

echo "### 2. 对比不同权威 NS"
# 获取权威 NS 列表
NS_LIST=$(dig +short NS "$DOMAIN" 2>/dev/null | head -5)
if [ -n "$NS_LIST" ]; then
    for ns in $NS_LIST; do
        echo "--- dig @${ns} ${DOMAIN} ---"
        dig +short @"$ns" "$DOMAIN" 2>&1 | head -5
    done
else
    echo "无法获取 ${DOMAIN} 的权威 NS 列表"
    echo "尝试从根开始追踪..."
    dig @"$(dig +short NS . | head -1)" "$DOMAIN" 2>&1 | head -20
fi
echo ""

echo "### 3. 对比外部公共 DNS"
echo "--- dig @8.8.8.8 ---"
dig +short @8.8.8.8 "$DOMAIN" 2>&1
echo "--- dig @1.1.1.1 ---"
dig +short @1.1.1.1 "$DOMAIN" 2>&1
echo "--- dig @114.114.114.114 ---"
dig +short @114.114.114.114 "$DOMAIN" 2>&1
echo ""

# L2: 本地存根检查
echo "## L2: 本地 DNS 存根检查"
echo ""

echo "### 4. nslookup 本地存根"
nslookup "$DOMAIN" 127.0.0.53 2>&1 | head -15 || echo "127.0.0.53 not available"
echo ""

echo "### 5. resolvectl query"
if command -v resolvectl &>/dev/null; then
    resolvectl query "$DOMAIN" 2>&1
else
    echo "resolvectl not available"
fi
echo ""

# L2: HTTP 层面验证
echo "## L2: HTTP 层面验证"
echo ""

echo "### 6. curl HTTP 验证"
curl -v --connect-timeout 5 "http://${DOMAIN}" 2>&1 | head -20 || echo "HTTP connection failed (expected if NXDOMAIN)"
echo ""

# L3: DNSSEC 验证
echo "## L3: DNSSEC 与深度分析"
echo ""

echo "### 7. DNSSEC 验证"
delv +multiline "$DOMAIN" 2>&1 | head -30 || echo "delv not available or DNSSEC validation failed"
echo ""

echo "### 8. dig +dnssec 查询"
dig +dnssec "$DOMAIN" 2>&1 | grep -E "status|flags:|RRSIG|ad" | head -10
echo ""

# L3: 缓存状态检查
echo "## L3: 缓存状态检查"
echo ""

if command -v resolvectl &>/dev/null; then
    echo "### 9. resolvectl 缓存统计"
    resolvectl statistics 2>&1 | grep -E "Cache|NXDOMAIN"
    
    echo ""
    echo "### 10. 清空缓存后对比"
    resolvectl flush-caches 2>&1
    sleep 1
    echo "--- After flush ---"
    dig +short "$DOMAIN" 2>&1
    echo "--- resolvectl query after flush ---"
    resolvectl query "$DOMAIN" 2>&1
else
    echo "resolvectl not available, cannot check/flush cache"
fi
echo ""

# L3 根因判定
echo "## L3: 根因判定"
echo ""

LOCAL_RESULT=$(dig +short "$DOMAIN" 2>&1)
EXT_RESULT=$(dig +short @8.8.8.8 "$DOMAIN" 2>&1)
LOCAL_STATUS=$(dig "$DOMAIN" 2>&1 | grep "status:")

if echo "$LOCAL_STATUS" | grep -q "NXDOMAIN"; then
    if [ -n "$EXT_RESULT" ]; then
        echo "结论: 本地解析返回 NXDOMAIN，但外部公共 DNS 可正常解析"
        if command -v resolvectl &>/dev/null; then
            echo "根因: 本地 DNS 缓存污染（NXDOMAIN 否定缓存）"
            echo "      resolvectl flush-caches 可临时解决"
        else
            echo "根因: 本地 DNS 存根服务器返回了错误的 NXDOMAIN"
            echo "      检查本地 DNS 服务器（可能是 dnsmasq/unbound）"
        fi
    else
        echo "结论: 所有 DNS 服务器均返回 NXDOMAIN"
        echo "根因: 域名 ${DOMAIN} 确实不存在（已过期/未注册/被暂停）"
        echo "      或上游 DNS 链路故障导致连锁 NXDOMAIN"
    fi
elif echo "$LOCAL_STATUS" | grep -q "SERVFAIL"; then
    echo "结论: 本地 DNS 返回 SERVFAIL"
    echo "根因: DNSSEC 验证失败或上游递归服务器内部错误"
elif [ -z "$LOCAL_RESULT" ] && [ -z "$EXT_RESULT" ]; then
    echo "结论: 所有 DNS 服务器均无应答"
    echo "根因: 域名 ${DOMAIN} 可能已过期或无 DNS 记录"
else
    echo "结论: 当前解析正常（NXDOMAIN 已恢复）"
    echo "建议: 监控是否间歇性出现，检查网络稳定性"
fi
echo ""
echo "--- Report written to ${REPORT_FILE} ---"
