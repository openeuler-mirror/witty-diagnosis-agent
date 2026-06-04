#!/bin/bash
# Branch C: /etc/resolv.conf 配置异常诊断
# L2 → L3 下钻：文件完整性 → 后端生成器 → 托管服务
# 用法: bash branch_C_resolv_conf.sh <TARGET_HOST>
# 示例: bash branch_C_resolv_conf.sh web01

TARGET_HOST="${1:-localhost}"
SSH_CMD="bash"
[ "$TARGET_HOST" != "localhost" ] && SSH_CMD="ssh $TARGET_HOST"

REPORT_DIR="${HOME}/.witty-diagnosis-agent/kuafu"
mkdir -p "$REPORT_DIR"
REPORT_FILE="${REPORT_DIR}/kuafu_T3_$(date +%Y%m%d_%H%M%S).md"

exec > >(tee -a "$REPORT_FILE") 2>&1

echo "# Branch C: /etc/resolv.conf 配置异常诊断"
echo "TARGET_HOST=${TARGET_HOST}"
echo "Timestamp: $(date -Iseconds)"
echo ""

# L2: 文件完整性检查
echo "## L2: 文件完整性检查"
echo ""

echo "### 1. 文件属性与链接关系"
echo "--- stat ---"
stat /etc/resolv.conf 2>&1
echo ""
echo "--- file type ---"
file /etc/resolv.conf 2>&1
echo ""
echo "--- readlink ---"
readlink -f /etc/resolv.conf 2>&1
echo ""
echo "--- ls -la ---"
ls -la /etc/resolv.conf 2>&1
echo ""

echo "### 2. 文件内容"
cat -A /etc/resolv.conf 2>&1 || cat /etc/resolv.conf 2>&1
echo ""

echo "### 3. 文件权限与所有者"
ls -n /etc/resolv.conf 2>&1
getfacl /etc/resolv.conf 2>&1 || echo "getfacl not available"
echo ""

echo "### 4. 文件大小"
wc -c /etc/resolv.conf 2>&1
echo ""

# L2: 后端生成器检查
echo "## L2: DNS 配置后端检查"
echo ""

echo "### 5. resolvconf 后端"
if [ -d /etc/resolvconf ]; then
    echo "--- resolvconf head ---"
    cat /etc/resolvconf/resolv.conf.d/head 2>&1
    echo ""
    echo "--- resolvconf base ---"
    cat /etc/resolvconf/resolv.conf.d/base 2>&1
    echo ""
    echo "--- resolvconf tail ---"
    cat /etc/resolvconf/resolv.conf.d/tail 2>&1
else
    echo "resolvconf package not installed"
fi
echo ""

echo "### 6. NetworkManager DNS 配置"
if command -v nmcli &>/dev/null; then
    nmcli dev show 2>&1 | grep -E "DNS|IP4.DNS" | head -10
else
    echo "NetworkManager not detected"
fi
echo ""

echo "### 7. systemd-networkd DNS 配置"
if command -v networkctl &>/dev/null; then
    networkctl status 2>&1 | grep -E "DNS|NTP"
else
    echo "systemd-networkd not detected"
fi
echo ""

echo "### 8. 其他 resolv.conf 生成器"
for gen in /etc/network/interfaces /etc/netplan/*.yaml /etc/sysconfig/network-scripts/ifcfg-*; do
    if [ -f "$gen" ]; then
        echo "--- ${gen} ---"
        grep -E "dns|DNS|nameserver" "$gen" 2>&1 | head -5
    fi
done
echo ""

# L2: 语法验证
echo "## L2: 语法验证"
echo ""

echo "### 9. resolv.conf 语法检查"
CONF_CONTENT=$(cat /etc/resolv.conf 2>&1)
# 检查是否为空
if [ ! -s /etc/resolv.conf ]; then
    echo "错误: /etc/resolv.conf 为空文件"
fi
# 检查 nameserver
NS_COUNT=$(grep -c '^nameserver' /etc/resolv.conf 2>/dev/null || echo 0)
echo "nameserver 行数: ${NS_COUNT}"
# 检查无效行
INVALID_LINES=$(grep -v '^#' /etc/resolv.conf 2>/dev/null | grep -v '^nameserver' | grep -v '^search' | grep -v '^domain' | grep -v '^option' | grep -v '^sortlist' | grep -v '^$' || echo "")
if [ -n "$INVALID_LINES" ]; then
    echo "警告: 存在无效配置行:"
    echo "$INVALID_LINES"
fi
echo ""

# L3: systemd-resolved 集成检查
echo "## L3: systemd-resolved 集成检查"
echo ""

echo "### 10. resolved 配置一致性"
if command -v resolvectl &>/dev/null; then
    echo "--- resolvectl DNS 配置 ---"
    resolvectl dns 2>&1
    echo ""
    echo "--- resolvectl 全局配置 ---"
    resolvectl status 2>&1 | grep -E "DNS|Domain|Server"
fi
echo ""

# L3 根因判定
echo "## L3: 根因判定"
echo ""

if [ ! -f /etc/resolv.conf ]; then
    echo "结论: /etc/resolv.conf 文件不存在"
    echo "根因: 配置文件丢失，需手动创建或重新配置网络"
elif [ "$(wc -c < /etc/resolv.conf 2>/dev/null || echo 0)" -eq 0 ]; then
    echo "结论: /etc/resolv.conf 为空文件（0 字节）"
    echo "根因: resolvconf 服务未运行或未正确生成配置文件"
elif [ -L /etc/resolv.conf ]; then
    LINK_TARGET=$(readlink -f /etc/resolv.conf)
    if [ ! -f "$LINK_TARGET" ]; then
        echo "结论: /etc/resolv.conf 符号链接指向不存在的文件"
        echo "根因: 符号链接 ${LINK_TARGET} 损坏或指向不存在路径"
    fi
elif [ "$NS_COUNT" -eq 0 ]; then
    echo "结论: /etc/resolv.conf 中未配置 nameserver"
    echo "根因: 缺少 nameserver 配置，需至少配置一个 DNS 服务器"
else
    echo "结论: /etc/resolv.conf 基本配置正常"
    echo "建议: 检查 nameserver 可达性（运行 branch_A）或接续排查其他问题"
fi
echo ""
echo "--- Report written to ${REPORT_FILE} ---"
