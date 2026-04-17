#!/bin/bash
# port_listen_check.sh — 端口监听状态与全连接队列积压检查
# 用途：快速排查服务未监听、绑定地址错误、连接队列积压等问题
# 用法: bash port_listen_check.sh [PORT]  （不指定端口则检查所有）

TARGET_PORT=${1:-""}

echo "=== 端口监听诊断 [$(date '+%Y-%m-%d %H:%M:%S')] ==="
[ -n "${TARGET_PORT}" ] && echo "过滤端口: ${TARGET_PORT}"
echo ""

# TCP 监听端口
echo "── TCP 监听端口 ─────────────────────────────"
echo "  Recv-Q: 全连接队列当前积压量（>0 表示积压）"
echo "  Send-Q: 全连接队列最大值（backlog）"
echo ""
if [ -n "${TARGET_PORT}" ]; then
    ss -tlnp | awk -v port="${TARGET_PORT}" 'NR==1 || $4 ~ ":"port"$"'
else
    ss -tlnp
fi
echo ""

# 检测全连接队列积压
echo "── 全连接队列积压告警 ───────────────────────"
backlog_issues=$(ss -tlnp | awk 'NR>1 && $2+0 > 0 {
    printf "  ⚠ %s  Recv-Q=%s (backlog=%s)  %s\n", $4, $2, $3, $6
}')
if [ -n "${backlog_issues}" ]; then
    echo "${backlog_issues}"
    echo ""
    echo "  建议: 检查应用 accept() 速率，或调大 net.core.somaxconn"
else
    echo "  未发现全连接队列积压"
fi
echo ""

# 检测仅绑定 127.0.0.1 的服务
echo "── 仅绑定本地回环（127.0.0.1）的服务 ──────"
loopback_only=$(ss -tlnp | awk 'NR>1 && $4 ~ /^127\./ {print "  ⚠ " $4 "  " $6}')
if [ -n "${loopback_only}" ]; then
    echo "${loopback_only}"
    echo "  提示: 如需远程访问，需将绑定地址改为 0.0.0.0 或具体 IP"
else
    echo "  未发现仅绑定本地回环的服务"
fi
echo ""

# UDP 监听端口
echo "── UDP 监听端口 ─────────────────────────────"
if [ -n "${TARGET_PORT}" ]; then
    ss -ulnp | awk -v port="${TARGET_PORT}" 'NR==1 || $4 ~ ":"port"$"'
else
    ss -ulnp | head -20
fi
echo ""

# 半连接队列（SYN backlog）
echo "── 半连接队列参数 ───────────────────────────"
printf "  net.ipv4.tcp_max_syn_backlog = %s\n" "$(sysctl -n net.ipv4.tcp_max_syn_backlog 2>/dev/null)"
printf "  net.core.somaxconn           = %s\n" "$(sysctl -n net.core.somaxconn 2>/dev/null)"
printf "  net.ipv4.tcp_syncookies      = %s\n" "$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null)"

# SYN flood 检测
syn_recv=$(ss -tn | grep -c "SYN-RECV" 2>/dev/null || echo 0)
echo "  当前 SYN_RECV 连接数: ${syn_recv}"
[ "${syn_recv}" -gt 100 ] && echo "  ⚠ SYN_RECV 较多，可能遭受 SYN Flood 攻击"
