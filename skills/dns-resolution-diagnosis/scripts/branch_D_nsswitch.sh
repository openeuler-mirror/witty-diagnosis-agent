#!/bin/bash
# Branch D: nsswitch.conf 顺序错误诊断
# L2 → L3 下钻：配置解析 → 实际查找行为 → 追踪调用链
# 用法: bash branch_D_nsswitch.sh <TARGET_HOST>
# 示例: bash branch_D_nsswitch.sh web01

TARGET_HOST="${1:-localhost}"
SSH_CMD="bash"
[ "$TARGET_HOST" != "localhost" ] && SSH_CMD="ssh $TARGET_HOST"

REPORT_DIR="${HOME}/.witty-diagnosis-agent/kuafu"
mkdir -p "$REPORT_DIR"
REPORT_FILE="${REPORT_DIR}/kuafu_T4_$(date +%Y%m%d_%H%M%S).md"

exec > >(tee -a "$REPORT_FILE") 2>&1

echo "# Branch D: nsswitch.conf 顺序错误诊断"
echo "TARGET_HOST=${TARGET_HOST}"
echo "Timestamp: $(date -Iseconds)"
echo ""

# L2: 配置解析
echo "## L2: nsswitch.conf 配置解析"
echo ""

echo "### 1. hosts 数据库配置"
grep ^hosts /etc/nsswitch.conf 2>&1
HOSTS_LINE=$(grep ^hosts /etc/nsswitch.conf 2>/dev/null)
echo ""

echo "### 2. 完整 nsswitch.conf"
cat /etc/nsswitch.conf 2>&1
echo ""

echo "### 3. 各服务状态"
echo "--- systemd-resolved ---"
systemctl is-active systemd-resolved 2>&1
echo "--- mDNS (avahi) ---"
if systemctl is-active avahi-daemon 2>&1; then
    echo "avahi-daemon is running (mDNS available)"
else
    echo "avahi-daemon not active"
fi
echo "--- SSSD ---"
systemctl is-active sssd 2>&1 || echo "sssd not active"
echo ""

# L2: 实际查找行为
echo "## L2: 实际查找行为测试"
echo ""

echo "### 4. getent hosts 测试"
echo "--- 正常域名 ---"
getent hosts google.com 2>&1 | head -5
echo "--- 本地 localhost ---"
getent hosts localhost 2>&1
echo "--- .local 域名 ---"
getent hosts test.local 2>&1 || echo "test.local not resolved (expected)"
echo ""

echo "### 5. dig vs getent 对比"
DIG_RESULT=$(dig +short google.com 2>&1)
GETENT_RESULT=$(getent hosts google.com 2>&1)
echo "dig 结果: $DIG_RESULT"
echo "getent 结果: $GETENT_RESULT"
if [ "$DIG_RESULT" != "$(echo "$GETENT_RESULT" | awk '{print $1}' 2>/dev/null)" ]; then
    echo "差异检测: dig 和 getent 返回不一致！"
fi
echo ""

echo "### 6. 本机主机名解析"
HOSTNAME=$(hostname)
echo "--- getent hosts ${HOSTNAME} ---"
getent hosts "$HOSTNAME" 2>&1
echo "--- dig ${HOSTNAME} ---"
dig +short "$HOSTNAME" 2>&1
echo ""

# L2: /etc/hosts 检查
echo "## L2: /etc/hosts 内容检查"
echo ""

echo "### 7. /etc/hosts 完整内容"
cat /etc/hosts 2>&1
echo ""

# L3: strace 追踪调用链
echo "## L3: 调用链追踪"
echo ""

echo "### 8. strace getent 调用（追踪 openat 系统调用）"
if command -v strace &>/dev/null; then
    strace -e openat,open,stat -f getent hosts google.com 2>&1 | grep -E "hosts|nsswitch|resolv|libnss" | head -20
else
    echo "strace not available"
fi
echo ""

echo "### 9. 加载的 nss 模块"
ldd /lib/x86_64-linux-gnu/libnss_dns.so.2 2>/dev/null || ldd /lib64/libnss_dns.so.2 2>/dev/null || echo "Cannot check libnss_dns"
ls -la /lib*/libnss_* 2>/dev/null | grep -E "dns|mdns|hosts|resolve" | head -10 || echo "No libnss modules found"
echo ""

echo "### 10. 不同解析方式对比矩阵"
echo ""
echo "| 查询方式 | google.com | localhost | 本机主机名 |"
echo "|---------|-----------|----------|-----------|"
echo "| dig +short | $(dig +short google.com 2>&1 | head -c 40) | - | $(dig +short "$(hostname)" 2>&1 | head -c 40) |"
echo "| getent hosts | $(getent hosts google.com 2>&1 | head -c 40) | $(getent hosts localhost 2>&1 | head -c 40) | $(getent hosts "$(hostname)" 2>&1 | head -c 40) |"
echo "| ping (ICMP) | $(ping -c 1 google.com 2>&1 | head -1 | head -c 50) | $(ping -c 1 localhost 2>&1 | head -1 | head -c 50) | $(ping -c 1 "$(hostname)" 2>&1 | head -1 | head -c 50) |"
echo ""

# L3 根因判定
echo "## L3: 根因判定"
echo ""

if echo "$HOSTS_LINE" | grep -q "myhostname.*\[.*NOTFOUND=return\]"; then
    echo "结论: myhostname 配置了 NOTFOUND=return"
    echo "根因: myhostname 模块在未找到匹配时即返回，不继续下个源"
elif echo "$HOSTS_LINE" | grep -q "mdns\[^_\]" || echo "$HOSTS_LINE" | grep -q "mdns .*dns"; then
    echo "结论: mDNS 优先级高于 DNS"
    echo "根因: mDNS 模块可能抢答非 .local 域名，导致 DNS 查询被跳过"
elif echo "$HOSTS_LINE" | grep -qv "dns"; then
    echo "结论: hosts 配置中缺少 dns 源"
    echo "根因: nsswitch.conf 未包含 DNS 源，系统不会通过 DNS 解析域名"
elif echo "$HOSTS_LINE" | grep -q "resolve" && echo "$HOSTS_LINE" | grep -q "dns"; then
    echo "结论: 同时配置了 resolve 和 dns（双重）"
    echo "根因: systemd-resolved 和 glibc DNS 解析器共存，可能导致不一致"
elif [ "$DIG_RESULT" != "$(echo "$GETENT_RESULT" | awk '{print $1}')" ]; then
    echo "结论: dig 和 getent 返回结果不一致"
    echo "根因: nsswitch 配置导致 getent 跳过了 DNS 源，或使用了其他源"
else
    echo "结论: nsswitch.conf hosts 配置正常"
    echo "建议: 如仍有解析问题，接续排查其他分支"
fi
echo ""
echo "--- Report written to ${REPORT_FILE} ---"
