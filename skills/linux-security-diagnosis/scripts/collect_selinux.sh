#!/bin/bash
# collect_selinux.sh — SELinux/AppArmor 安全策略采集脚本
# 场景：SELinux拒绝访问、策略被禁用/篡改、防护服务异常、IDS/IPS未启动
# 用法：bash collect_selinux.sh [service_name]

TARGET_SVC="${1:-}"

echo "════════════════════════════════════════════"
echo " SELINUX/SECURITY POLICY DIAGNOSIS COLLECTOR"
echo " 采集时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo " 目标服务: ${TARGET_SVC:-未指定}"
echo "════════════════════════════════════════════"

# ── 1. SELinux 状态 ───────────────────────────────
echo ""
echo "── [1] SELinux 状态 ──"
echo "[执行模式]"
getenforce 2>/dev/null || echo "SELinux 未安装"
echo ""
sestatus 2>/dev/null
echo ""
echo "[SELinux 配置文件]"
cat /etc/selinux/config 2>/dev/null | grep -v "^#" | grep -v "^$"

# ── 2. SELinux 拒绝事件 ──────────────────────────
echo ""
echo "── [2] SELinux 拒绝事件分析 ──"
echo "[今日AVC拒绝（最近50条）]"
ausearch -m avc -ts today 2>/dev/null | grep "denied" | tail -50 \
    || grep "avc.*denied" /var/log/audit/audit.log 2>/dev/null | tail -50 \
    || journalctl --since today 2>/dev/null | grep "avc.*denied" | tail -50
echo ""
echo "[按操作类型统计拒绝事件]"
python3 -c "
import subprocess, re, collections
try:
    out = subprocess.check_output(['ausearch','-m','avc','-ts','today'], text=True, stderr=subprocess.DEVNULL)
    denials = re.findall(r'{([^}]+)}.*?tcontext=([^ ]+)', out)
    counts = collections.Counter(denials)
    for (ops, ctx), n in counts.most_common(15):
        print(f'  {n:3d}x  [{ops.strip()}]  target={ctx}')
except:
    pass
" 2>/dev/null
echo ""
if [ -n "$TARGET_SVC" ]; then
    echo "[服务 $TARGET_SVC 相关AVC拒绝]"
    ausearch -m avc -ts today 2>/dev/null | grep "$TARGET_SVC" | tail -20 \
        || grep "avc.*denied.*${TARGET_SVC}" /var/log/audit/audit.log 2>/dev/null | tail -20
    echo ""
    echo "[服务 $TARGET_SVC SELinux上下文]"
    ps -eZ 2>/dev/null | grep "$TARGET_SVC"
    echo "[服务相关文件SELinux标签]"
    systemctl cat "$TARGET_SVC" 2>/dev/null | grep ExecStart | awk '{print $2}' | xargs ls -laZ 2>/dev/null
fi

# ── 3. SELinux 布尔值 ────────────────────────────
echo ""
echo "── [3] SELinux 布尔值（非默认值）──"
getsebool -a 2>/dev/null | grep "on$" | grep -vE "^(allow_user_exec|ssh_sysadm)" | head -30

# ── 4. AppArmor 状态 ─────────────────────────────
echo ""
echo "── [4] AppArmor 状态 ──"
aa-status 2>/dev/null || apparmor_status 2>/dev/null || echo "AppArmor 未安装"
echo ""
echo "[AppArmor 拒绝日志]"
journalctl --since "24 hours ago" 2>/dev/null | grep "apparmor.*DENIED" | tail -20 \
    || grep "apparmor.*DENIED" /var/log/kern.log 2>/dev/null | tail -20 \
    || echo "无AppArmor拒绝日志"

# ── 5. 防护服务状态 ───────────────────────────────
echo ""
echo "── [5] 防护服务状态检查 ──"
declare -A SECURITY_SERVICES=(
    ["firewalld"]="防火墙"
    ["iptables"]="iptables防火墙"
    ["nftables"]="nftables防火墙"
    ["fail2ban"]="暴力破解防护"
    ["snort"]="入侵检测IDS"
    ["suricata"]="入侵检测IDS/IPS"
    ["aide"]="文件完整性检测"
    ["auditd"]="审计守护进程"
    ["clamav"]="反病毒"
    ["ossec-hids"]="OSSEC HIDS"
)
for svc in "${!SECURITY_SERVICES[@]}"; do
    status=$(systemctl is-active "$svc" 2>/dev/null)
    enabled=$(systemctl is-enabled "$svc" 2>/dev/null)
    printf "  %-20s %-15s [运行:%-8s 开机自启:%-8s]\n" \
        "$svc" "${SECURITY_SERVICES[$svc]}" "$status" "$enabled"
done

# ── 6. 策略最近变更检测 ──────────────────────────
echo ""
echo "── [6] 安全策略最近变更检测 ──"
echo "[SELinux 相关文件最近7天修改]"
find /etc/selinux /etc/audit /etc/pam.d /etc/ssh -newer /tmp -type f -ls 2>/dev/null | head -20
echo ""
echo "[semanage 导出的本地SELinux策略]"
semanage export 2>/dev/null | head -30 || echo "semanage不可用"

# ── 7. 安全模块内核状态 ──────────────────────────
echo ""
echo "── [7] 安全相关内核模块 ──"
echo "[LSM模块]"
cat /sys/kernel/security/lsm 2>/dev/null || grep -r "security=" /proc/cmdline 2>/dev/null
echo ""
echo "[安全相关模块]"
lsmod 2>/dev/null | grep -iE "selinux|apparmor|audit|keys|integrity"

echo ""
echo "════════════════════════════════════════════"
echo " 采集完成 SELINUX COLLECTOR END"
echo "════════════════════════════════════════════"
