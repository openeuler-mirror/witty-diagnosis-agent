#!/bin/bash
# collect_all.sh — 综合安全信息采集脚本（场景不明确时使用）
# 覆盖所有安全类别的快速概览采集
# 用法：bash collect_all.sh

echo "════════════════════════════════════════════"
echo " COMPREHENSIVE SECURITY DIAGNOSIS COLLECTOR"
echo " 采集时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo " 主机: $(hostname -f 2>/dev/null || hostname)"
echo "════════════════════════════════════════════"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

run_section() {
    local title="$1"; local script="$2"; shift 2
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║  $title"
    echo "╚══════════════════════════════════════════╝"
    if [ -f "$SCRIPT_DIR/$script" ]; then
        bash "$SCRIPT_DIR/$script" "$@" 2>&1
    else
        echo "脚本 $script 不存在，跳过"
    fi
}

# 快速系统健康检查
echo ""
echo "── [系统快速健康检查] ──"
echo "[CPU/内存/磁盘]"
top -bn1 2>/dev/null | head -5
df -h / /var /tmp 2>/dev/null
free -h 2>/dev/null

echo ""
echo "[关键安全服务状态汇总]"
for svc in sshd sssd auditd rsyslog firewalld fail2ban; do
    status=$(systemctl is-active "$svc" 2>/dev/null)
    printf "  %-15s %s\n" "$svc:" "$status"
done

echo ""
echo "[SELinux模式]"
getenforce 2>/dev/null || echo "未安装"

# 各模块采集（精简模式）
echo ""
echo "════════ [认证安全] ════════"
bash "$SCRIPT_DIR/collect_auth.sh" 2>&1 | grep -v "^$" | head -80

echo ""
echo "════════ [审计日志] ════════"
bash "$SCRIPT_DIR/collect_audit.sh" 2>&1 | grep -v "^$" | head -60

echo ""
echo "════════ [网络防火墙] ════════"
bash "$SCRIPT_DIR/collect_network.sh" 2>&1 | grep -v "^$" | head -60

echo ""
echo "════════ [账户异常] ════════"
bash "$SCRIPT_DIR/collect_account_abuse.sh" 12 2>&1 | grep -v "^$" | head -60

echo ""
echo "════════ [内核状态] ════════"
bash "$SCRIPT_DIR/collect_kernel.sh" 2>&1 | grep -v "^$" | head -60

echo ""
echo "════════════════════════════════════════════"
echo " 综合采集完成 | 如需深入分析请执行各专项脚本"
echo "════════════════════════════════════════════"
