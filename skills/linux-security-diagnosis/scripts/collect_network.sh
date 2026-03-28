#!/bin/bash
# collect_network.sh — 防火墙与网络访问信息采集脚本
# 场景：端口不通、连接被拒、异常端口暴露、防火墙规则冲突
# 用法：bash collect_network.sh [port] [dest_ip]

TARGET_PORT="${1:-}"
TARGET_IP="${2:-}"

echo "════════════════════════════════════════════"
echo " NETWORK/FIREWALL DIAGNOSIS COLLECTOR"
echo " 采集时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo " 目标端口: ${TARGET_PORT:-未指定}"
echo " 目标IP: ${TARGET_IP:-未指定}"
echo "════════════════════════════════════════════"

# ── 1. 网络接口与路由 ─────────────────────────────
echo ""
echo "── [1] 网络接口与路由 ──"
echo "[网络接口]"
ip addr show 2>/dev/null || ifconfig 2>/dev/null
echo ""
echo "[路由表]"
ip route show 2>/dev/null || route -n 2>/dev/null
echo ""
echo "[内核网络关键参数]"
sysctl net.ipv4.ip_forward net.ipv4.conf.all.rp_filter \
       net.ipv4.tcp_syncookies net.ipv4.conf.default.accept_redirects \
       net.ipv6.conf.all.disable_ipv6 2>/dev/null

# ── 2. 监听端口与连接 ─────────────────────────────
echo ""
echo "── [2] 监听端口与连接状态 ──"
echo "[所有监听端口(ss)]"
ss -tuln 2>/dev/null || netstat -tuln 2>/dev/null
echo ""
echo "[已建立连接(TOP20 by state)]"
ss -tn state established 2>/dev/null | head -20 || netstat -tn | grep ESTABLISHED | head -20
echo ""
if [ -n "$TARGET_PORT" ]; then
    echo "[端口 $TARGET_PORT 监听情况]"
    ss -tlnp "sport = :${TARGET_PORT}" 2>/dev/null || ss -tlnp | grep ":${TARGET_PORT}"
    echo "[端口 $TARGET_PORT 进程]"
    fuser -v "${TARGET_PORT}/tcp" 2>/dev/null || lsof -i ":${TARGET_PORT}" 2>/dev/null
fi

# ── 3. firewalld 状态 ─────────────────────────────
echo ""
echo "── [3] firewalld 配置 ──"
echo "[firewalld 服务状态]"
systemctl status firewalld --no-pager -l 2>/dev/null | head -20
echo ""
if systemctl is-active firewalld &>/dev/null; then
    echo "[默认zone]"
    firewall-cmd --get-default-zone 2>/dev/null
    echo "[所有zone规则]"
    firewall-cmd --list-all-zones 2>/dev/null
    echo "[rich rules]"
    firewall-cmd --list-rich-rules 2>/dev/null
fi

# ── 4. iptables 规则 ──────────────────────────────
echo ""
echo "── [4] iptables 规则 ──"
echo "[filter表]"
iptables -L -n -v --line-numbers 2>/dev/null || echo "iptables不可用"
echo ""
echo "[nat表]"
iptables -t nat -L -n -v 2>/dev/null
echo ""
echo "[ip6tables]"
ip6tables -L -n -v 2>/dev/null | head -30
echo ""
echo "[iptables规则文件（持久化）]"
cat /etc/sysconfig/iptables 2>/dev/null | head -50 \
    || iptables-save 2>/dev/null | head -50

# ── 5. 连通性验证 ─────────────────────────────────
if [ -n "$TARGET_IP" ] && [ -n "$TARGET_PORT" ]; then
    echo ""
    echo "── [5] 连通性测试 ──"
    echo "[ping 测试]"
    ping -c 3 -W 2 "$TARGET_IP" 2>&1
    echo "[TCP 端口连通性]"
    timeout 3 bash -c "echo >/dev/tcp/${TARGET_IP}/${TARGET_PORT}" 2>/dev/null \
        && echo "TCP ${TARGET_IP}:${TARGET_PORT} 可达" \
        || echo "TCP ${TARGET_IP}:${TARGET_PORT} 不可达"
fi

# ── 6. 近期网络异常日志 ──────────────────────────
echo ""
echo "── [6] 近期防火墙/网络日志（最近1小时）──"
echo "[firewalld 日志]"
journalctl -u firewalld --since "1 hour ago" --no-pager 2>/dev/null | grep -iE "error|warn|drop|reject" | tail -20
echo "[内核防火墙DROP记录]"
dmesg --since "1 hour ago" 2>/dev/null | grep -iE "iptables|nft|DROP|REJECT" | tail -20 \
    || journalctl -k --since "1 hour ago" 2>/dev/null | grep -iE "DROP|REJECT|iptables" | tail -20

# ── 7. 异常暴露端口检测 ──────────────────────────
echo ""
echo "── [7] 对外暴露端口检测（0.0.0.0监听）──"
echo "[监听在0.0.0.0的端口（可能对外暴露）]"
ss -tuln 2>/dev/null | grep "0.0.0.0:" | awk '{print $1, $5}' | sort -k2
echo ""
echo "[非标准高危端口检测（<1024非常用服务）]"
ss -tuln 2>/dev/null | grep -E "0\.0\.0\.0:(2[0-9]{3}|3[0-9]{3}|4[0-9]{3}|5[0-9]{3})" | head -20

echo ""
echo "════════════════════════════════════════════"
echo " 采集完成 NETWORK COLLECTOR END"
echo "════════════════════════════════════════════"
