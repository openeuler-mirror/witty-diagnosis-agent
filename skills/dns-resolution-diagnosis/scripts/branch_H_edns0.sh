#!/bin/bash
# Branch H: EDNS0 兼容性问题诊断
# L2 → L3 下钻：EDNS0 有无对比 → OPT 记录分析 → PMTU → 中间盒检测
# 用法: bash branch_H_edns0.sh <TARGET_HOST> <DNS_SERVER>
# 示例: bash branch_H_edns0.sh web01 8.8.8.8

TARGET_HOST="${1:-localhost}"
DNS_SERVER="${2:-8.8.8.8}"
SSH_CMD="bash"
[ "$TARGET_HOST" != "localhost" ] && SSH_CMD="ssh $TARGET_HOST"

REPORT_DIR="${HOME}/.witty-diagnosis-agent/kuafu"
mkdir -p "$REPORT_DIR"
REPORT_FILE="${REPORT_DIR}/kuafu_T8_$(date +%Y%m%d_%H%M%S).md"

exec > >(tee -a "$REPORT_FILE") 2>&1

echo "# Branch H: EDNS0 兼容性问题诊断"
echo "TARGET_HOST=${TARGET_HOST}  DNS_SERVER=${DNS_SERVER}"
echo "Timestamp: $(date -Iseconds)"
echo ""

# L2: EDNS0 有无对比
echo "## L2: EDNS0 有无对比"
echo ""

echo "### 1. dig +edns0（默认启用 EDNS0）"
dig +edns0 +timeout=3 @"$DNS_SERVER" google.com 2>&1 | grep -E "status:|flags:|OPT|SERVER|timed out" | head -10
EDNS0_OK=$?
echo ""

echo "### 2. dig +noedns（禁用 EDNS0）"
dig +noedns +timeout=3 @"$DNS_SERVER" google.com 2>&1 | grep -E "status:|flags:|SERVER" | head -10
NOEDNS_OK=$?
echo ""

echo "### 3. OPT 伪记录对比"
echo "--- +edns0 OPT section ---"
dig +edns0 @"$DNS_SERVER" google.com 2>&1 | sed -n '/OPT PSEUDOSECTION/,/^[^;]/p' | head -10
echo ""
echo "--- +noedns（无 OPT section）---"
dig +noedns @"$DNS_SERVER" google.com 2>&1 | grep -c "OPT PSEUDOSECTION" || echo "No OPT section (expected)"
echo ""

# L2: UDP 包大小测试
echo "## L2: UDP 包大小测试"
echo ""

echo "### 4. 递增 bufsize 测试"
echo "| bufsize | 状态 |"
echo "|---------|------|"
for size in 512 1024 1500 2048 3000 4096; do
    STATUS=$(dig +bufsize="$size" +timeout=3 @"$DNS_SERVER" google.com 2>&1 | grep "status:" | head -1 | awk '{print $2}')
    TC_FLAG=$(dig +bufsize="$size" +timeout=3 @"$DNS_SERVER" google.com ANY 2>&1 | grep "flags:" | grep -o "tc" || echo "")
    TC_STR=""
    [ -n "$TC_FLAG" ] && TC_STR=" (TC=1)"
    echo "| $size | ${STATUS:-TIMEOUT}${TC_STR} |"
done
echo ""

# L2: DNSSEC 依赖测试（EDNS0 是 DNSSEC 的前置条件）
echo "## L2: DNSSEC 依赖测试"
echo ""

echo "### 5. dig +dnssec（依赖 EDNS0）"
dig +dnssec +timeout=3 @"$DNS_SERVER" google.com 2>&1 | grep -E "status:|flags:|RRSIG|ad" | head -5
echo ""

echo "### 6. delv DNSSEC 验证"
delv +multiline +time=3 @"$DNS_SERVER" google.com 2>&1 | head -20 || echo "delv failed"
echo ""

# L3: 中间盒检测
echo "## L3: 中间盒与 PMTU 检测"
echo ""

echo "### 7. EDNS0 Client Subnet (ECS) 测试"
# ECS 选项代码为 8
echo "--- dig +client=203.0.113.0 ---"
dig +client=203.0.113.0 +timeout=3 @"$DNS_SERVER" google.com 2>&1 | grep -E "status:|CLIENT-SUBNET|OPT" | head -10
echo ""

echo "### 8. 未知 OPT 代码测试"
echo "--- dig +unknownopt=0x1234 ---"
dig +unknownopt=0x1234 +timeout=3 @"$DNS_SERVER" google.com 2>&1 | grep -E "status:|timed out" | head -5
echo ""

echo "### 9. DNS Cookie 测试（OPT 代码 9）"
echo "--- dig +cookie ---"
dig +cookie +timeout=3 @"$DNS_SERVER" google.com 2>&1 | grep -E "COOKIE|status:|timed out" | head -5
echo ""

echo "### 10. PMTU 路径检测"
echo "--- PMTU 探测 ---"
for size in 1472 1400 1300 1200; do
    ping -M do -c 2 -W 2 -s "$size" "$DNS_SERVER" 2>&1 | tail -1
done
echo ""

echo "### 11. TCP fallback 关联测试（EDNS0 大包可能导致 TCP fallback）"
dig +tcp +bufsize=4096 +timeout=3 @"$DNS_SERVER" google.com ANY 2>&1 | grep -E "status:|flags:" | head -3
echo ""

# L3: OPT 记录深度分析
echo "## L3: OPT 记录深度分析"
echo ""

echo "### 12. 完整 OPT 记录解析"
dig +edns0 +bufsize=4096 @"$DNS_SERVER" google.com 2>&1 | sed -n '/OPT PSEUDOSECTION/,/^[^;]/p' | head -20
echo ""

echo "### 13. 检查 OPT 版本与标志"
dig +edns0 @"$DNS_SERVER" google.com 2>&1 | grep -E "version:|flags:|MBZ|DO" | head -5
echo ""

# L3 根因判定
echo "## L3: 根因判定"
echo ""

# 分析对比结果
if [ $EDNS0_OK -ne 0 ] && [ $NOEDNS_OK -eq 0 ]; then
    echo "结论: 含 EDNS0 查询失败，禁用 EDNS0 后正常"
    echo "根因: 上游 DNS 服务器或中间设备存在 EDNS0 兼容性问题"
    echo "      （不理解 OPT 记录、丢弃大 UDP 包、或错误处理 EDNS0 标志）"
    echo ""
    echo "修复建议:"
    echo "1. 在 resolv.conf 中添加 'options edns0'（已默认启用）"
    echo "2. 使用 dig +noedns 临时绕过（不推荐长期）"
    echo "3. 联系上游 DNS 管理员修复 EDNS0 支持"
elif dig +bufsize=4096 +timeout=3 @"$DNS_SERVER" google.com 2>&1 | grep -q "timed out"; then
    echo "结论: 大 UDP 包（4096）超时，小包正常"
    echo "根因: PMTU 路径问题或中间设备丢弃大 UDP 包"
    echo "      常见于 VPN、GRE 隧道或 MTU 小于 1500 的网络"
    echo ""
    echo "修复建议:"
    echo "1. 检查路径 MTU: ping -M do -s 1472" 
    echo "2. 在 resolv.conf 设置较小的 edns0 大小: options edns0 max-udp-size=1280"
elif dig +dnssec @"$DNS_SERVER" google.com 2>&1 | grep -q "SERVFAIL"; then
    echo "结论: DNSSEC 查询返回 SERVFAIL"
    echo "根因: EDNS0 支持但 DNSSEC 验证链不完整或签名过期"
    echo "      或上游 DNS 不支持 DNSSEC"
else
    echo "结论: EDNS0 兼容性基本正常"
    echo "建议: 如仍有问题，检查特定 OPT 代码兼容性（ECS/Cookie/未知 OPT）"
fi
echo ""
echo "--- Report written to ${REPORT_FILE} ---"
