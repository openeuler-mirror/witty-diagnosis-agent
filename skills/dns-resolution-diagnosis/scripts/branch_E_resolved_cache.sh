#!/bin/bash
# Branch E: systemd-resolved 缓存污染诊断
# L2 → L3 下钻：缓存统计 → 缓存内容 → 清空对比 → 根源分析
# 用法: bash branch_E_resolved_cache.sh <TARGET_HOST> [<DOMAIN>]
# 示例: bash branch_E_resolved_cache.sh web01 example.com

TARGET_HOST="${1:-localhost}"
DOMAIN="${2:-google.com}"
SSH_CMD="bash"
[ "$TARGET_HOST" != "localhost" ] && SSH_CMD="ssh $TARGET_HOST"

REPORT_DIR="${HOME}/.witty-diagnosis-agent/kuafu"
mkdir -p "$REPORT_DIR"
REPORT_FILE="${REPORT_DIR}/kuafu_T5_$(date +%Y%m%d_%H%M%S).md"

exec > >(tee -a "$REPORT_FILE") 2>&1

echo "# Branch E: systemd-resolved 缓存污染诊断"
echo "TARGET_HOST=${TARGET_HOST}  DOMAIN=${DOMAIN}"
echo "Timestamp: $(date -Iseconds)"
echo ""

# 检查 resolved 是否运行
RESOLVED_RUNNING=false
command -v resolvectl &>/dev/null && RESOLVED_RUNNING=true

if [ "$RESOLVED_RUNNING" = false ]; then
    echo "systemd-resolved 未运行或 resolvectl 不可用"
    echo "跳转检查: dnsmasq/unbound 等其他 DNS 缓存"
    
    if command -v dnsmasq &>/dev/null; then
        echo ""
        echo "### dnsmasq 缓存状态"
        # 向 dnsmasq 发送 SIGUSR1 获取缓存统计
        killall -USR1 dnsmasq 2>&1
        journalctl -u dnsmasq --since "1 min ago" 2>&1 | grep -i "cache" | tail -10
    fi
    exit 0
fi

# L2: 缓存统计
echo "## L2: 缓存统计"
echo ""

echo "### 1. resolvectl 全局状态"
resolvectl status 2>&1
echo ""

echo "### 2. resolvectl 缓存统计"
resolvectl statistics 2>&1
echo ""

echo "### 3. 各接口 DNS 配置"
resolvectl dns 2>&1
echo ""

echo "### 4. 各接口搜索域"
resolvectl domain 2>&1
echo ""

# L2: 缓存内容检查
echo "## L2: 缓存内容检查"
echo ""

echo "### 5. resolvectl query 目标域名"
resolvectl query "$DOMAIN" 2>&1
echo ""

echo "### 6. resolvectl query 随机对照域名"
resolvectl query "cloudflare.com" 2>&1
echo ""

# L2: 清空缓存前后对比
echo "## L2: 清空缓存前后对比"
echo ""

echo "### 7. 缓存清空前解析"
echo "--- dig before flush ---"
dig +short "$DOMAIN" 2>&1
echo "--- dig +dnssec before flush ---"
dig +dnssec "$DOMAIN" 2>&1 | grep -E "status|flags:" | head -3
echo ""

echo "### 8. 清空 DNS 缓存"
resolvectl flush-caches 2>&1
echo "Cache flushed at $(date -Iseconds)"
sleep 1
echo ""

echo "### 9. 缓存清空后解析"
echo "--- dig after flush ---"
dig +short "$DOMAIN" 2>&1
echo "--- resolvectl query after flush ---"
resolvectl query "$DOMAIN" 2>&1
echo ""

echo "### 10. 清空后缓存统计"
resolvectl statistics 2>&1
echo ""

# L3: 配置层面检查
echo "## L3: 配置与根源分析"
echo ""

echo "### 11. /etc/systemd/resolved.conf"
cat /etc/systemd/resolved.conf 2>&1 || echo "File not found"
echo ""

echo "### 12. resolved 日志排查（最近 50 条）"
journalctl -u systemd-resolved --since "1 hour ago" --no-pager 2>&1 | tail -50
echo ""

echo "### 13. DNSSEC 缓存状态"
resolvectl statistics 2>&1 | grep -i "dnssec"
echo ""

echo "### 14. 检查 TTL 异常"
echo "--- 清空前 dig 应答 TTL ---"
dig "$DOMAIN" 2>&1 | grep -E "^[^;].*IN\s+A\s+" | head -3
echo ""

# L3 根因判定
echo "## L3: 根因判定"
echo ""

CURRENT_CACHE=$(resolvectl statistics 2>&1 | grep "Current Cache Size" | awk '{print $NF}')
echo "当前缓存大小: ${CURRENT_CACHE:-unknown}"

# 比较清空前后的解析结果（通过日志已有记录）
echo ""
echo "分析结论:"
if resolvectl statistics 2>&1 | grep -q "Cache Miss: 0" && [ "$(resolvectl statistics 2>&1 | grep "Current Cache Size" | awk '{print $NF}')" -gt 0 ]; then
    echo "- 缓存中存在条目，但无查询未命中（全部命中缓存）"
fi
if resolvectl statistics 2>&1 | grep -q "NXDOMAIN"; then
    echo "- 缓存中包含 NXDOMAIN 否定缓存条目"
fi

echo ""
echo "潜在根因:"
echo "1. 上游 DNS TTL 过大 → systemd-resolved 长时间缓存过期记录"
echo "2. 否定缓存（NXDOMAIN）未及时过期 → 原本存在的域名无法访问"
echo "3. DNSSEC 验证失败缓存 → 即使问题修复也仍返回 SERVFAIL"
echo "4. 多网络接口 DNS 配置冲突 → resolved 选择错误的上游"
echo "5. 缓存大小限制导致频繁逐出 → 非污染，而是性能问题"

# 建议
echo ""
echo "修复建议:"
echo "- 临时: resolvectl flush-caches"
echo "- 永久: 在 resolved.conf 中设置 Cache=no 禁用缓存"
echo "- 检查上游 DNS TTL 策略"
echo ""
echo "--- Report written to ${REPORT_FILE} ---"
