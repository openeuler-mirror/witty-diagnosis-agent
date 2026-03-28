#!/bin/bash
# collect_auth.sh — 认证/登录安全信息采集脚本
# 场景：用户无法登录、SSH失败、账号锁定、PAM/SSSD/LDAP异常
# 用法：bash collect_auth.sh [username]
# 输出：结构化诊断数据，供模型分析

TARGET_USER="${1:-}"
SINCE="${2:-today}"

echo "════════════════════════════════════════════"
echo " AUTH DIAGNOSIS COLLECTOR"
echo " 采集时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo " 目标用户: ${TARGET_USER:-all}"
echo "════════════════════════════════════════════"

# ── 1. 系统基础信息 ──────────────────────────────
echo ""
echo "── [1] 系统基础信息 ──"
echo "Hostname: $(hostname -f 2>/dev/null || hostname)"
echo "OS: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
echo "Kernel: $(uname -r)"
echo "Uptime: $(uptime -p 2>/dev/null || uptime)"

# ── 2. 账户状态 ──────────────────────────────────
echo ""
echo "── [2] 账户状态检查 ──"
if [ -n "$TARGET_USER" ]; then
    echo "[账户基本信息]"
    id "$TARGET_USER" 2>&1
    echo "[密码/有效期状态]"
    chage -l "$TARGET_USER" 2>&1
    echo "[账户锁定状态 /etc/shadow]"
    grep "^${TARGET_USER}:" /etc/shadow 2>/dev/null | awk -F: '{
        if ($2 ~ /^!/) print "账户已锁定(密码前有!)";
        else if ($2 == "!!" || $2 == "") print "账户无密码或未激活";
        else print "密码状态: 正常"
    }' || echo "无法读取shadow文件"
    echo "[失败登录次数]"
    faillog -u "$TARGET_USER" 2>/dev/null || pam_tally2 --user="$TARGET_USER" 2>/dev/null || echo "faillog/pam_tally2不可用"
else
    echo "[近期有失败登录的账户 TOP10]"
    faillog -a 2>/dev/null | grep -v "^Username" | awk '$3 > 0 {print}' | sort -k3 -rn | head -10 || echo "faillog不可用"
fi

# ── 3. PAM 配置 ──────────────────────────────────
echo ""
echo "── [3] PAM 配置检查 ──"
echo "[/etc/pam.d/sshd 内容]"
cat /etc/pam.d/sshd 2>/dev/null || echo "文件不存在"
echo ""
echo "[/etc/pam.d/system-auth 内容]"
cat /etc/pam.d/system-auth 2>/dev/null || echo "文件不存在"
echo ""
echo "[/etc/pam.d/password-auth 内容]"
cat /etc/pam.d/password-auth 2>/dev/null || echo "文件不存在"
echo ""
echo "[pam_tally2/faillock 锁定策略]"
grep -r "pam_tally2\|pam_faillock\|deny=\|unlock_time=" /etc/pam.d/ 2>/dev/null | grep -v "^#"

# ── 4. SSH 服务状态与配置 ──────────────────────────
echo ""
echo "── [4] SSH 服务状态与配置 ──"
echo "[sshd 服务状态]"
systemctl status sshd 2>/dev/null || systemctl status openssh-server 2>/dev/null
echo ""
echo "[sshd 关键配置项]"
grep -E "^(PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|AuthorizedKeysFile|UsePAM|AllowUsers|DenyUsers|AllowGroups|DenyGroups|MaxAuthTries|ChallengeResponseAuthentication)" /etc/ssh/sshd_config 2>/dev/null

# ── 5. SSSD / LDAP 服务状态 ──────────────────────
echo ""
echo "── [5] SSSD/LDAP 服务状态 ──"
systemctl is-active sssd 2>/dev/null && echo "SSSD: 运行中" || echo "SSSD: 未运行或未安装"
if systemctl is-active sssd &>/dev/null; then
    echo "[sssd 服务详情]"
    systemctl status sssd --no-pager -l 2>/dev/null | head -30
    echo ""
    echo "[sssd.conf 主要配置]"
    cat /etc/sssd/sssd.conf 2>/dev/null | grep -v "^#" | grep -v "^$"
    echo ""
    echo "[SSSD 最近错误日志]"
    journalctl -u sssd --since "1 hour ago" --no-pager -l 2>/dev/null | grep -iE "error|fail|crit|warn" | tail -30 \
        || find /var/log/sssd -name "*.log" -newer /tmp 2>/dev/null -exec tail -20 {} \;
    echo "[LDAP 连通性测试]"
    LDAP_URI=$(grep -i "ldap_uri\|uri" /etc/sssd/sssd.conf 2>/dev/null | head -1 | awk -F= '{print $2}' | tr -d ' ')
    if [ -n "$LDAP_URI" ]; then
        LDAP_HOST=$(echo "$LDAP_URI" | sed 's|ldap[s]*://||' | cut -d: -f1)
        LDAP_PORT=$(echo "$LDAP_URI" | grep -oP ':\K[0-9]+' | head -1)
        LDAP_PORT=${LDAP_PORT:-389}
        timeout 3 bash -c "echo >/dev/tcp/${LDAP_HOST}/${LDAP_PORT}" 2>/dev/null \
            && echo "LDAP ${LDAP_HOST}:${LDAP_PORT} 可达" \
            || echo "LDAP ${LDAP_HOST}:${LDAP_PORT} 不可达（超时/被拒）"
    fi
    echo "[getent passwd 验证]"
    if [ -n "$TARGET_USER" ]; then
        getent passwd "$TARGET_USER" 2>&1 && echo "用户可通过NSS解析" || echo "用户无法解析（LDAP可能不可达）"
    fi
fi

# ── 6. 近期认证日志 ──────────────────────────────
echo ""
echo "── [6] 近期认证日志（最近24小时）──"
echo "[SSH 认证日志 - 失败]"
journalctl -u sshd --since "24 hours ago" --no-pager 2>/dev/null \
    | grep -iE "failed|invalid|error|refused|disconnect" | tail -40 \
    || grep -iE "failed|invalid|refused" /var/log/secure 2>/dev/null | tail -40 \
    || grep -iE "failed|invalid|refused" /var/log/auth.log 2>/dev/null | tail -40

echo ""
echo "[SSH 认证日志 - 成功登录]"
journalctl -u sshd --since "24 hours ago" --no-pager 2>/dev/null \
    | grep -iE "Accepted|session opened" | tail -20 \
    || grep -iE "Accepted|session opened" /var/log/secure 2>/dev/null | tail -20

echo ""
echo "[登录历史 last]"
last -n 20 -F 2>/dev/null || last -n 20

echo ""
echo "[失败登录历史 lastb]"
lastb -n 20 2>/dev/null | head -25

# ── 7. 失败来源IP统计 ─────────────────────────────
echo ""
echo "── [7] 失败登录来源IP统计（TOP15）──"
journalctl -u sshd --since "24 hours ago" --no-pager 2>/dev/null \
    | grep "Failed password" \
    | grep -oP 'from \K[\d.]+' \
    | sort | uniq -c | sort -rn | head -15 \
    || grep "Failed password" /var/log/secure 2>/dev/null \
    | grep -oP 'from \K[\d.]+' \
    | sort | uniq -c | sort -rn | head -15

# ── 8. 密码策略 ──────────────────────────────────
echo ""
echo "── [8] 密码策略配置 ──"
echo "[/etc/login.defs 密码相关]"
grep -E "^(PASS_MAX_DAYS|PASS_MIN_DAYS|PASS_MIN_LEN|PASS_WARN_AGE|ENCRYPT_METHOD)" /etc/login.defs 2>/dev/null
echo "[pwquality 配置]"
cat /etc/security/pwquality.conf 2>/dev/null | grep -v "^#" | grep -v "^$"

echo ""
echo "════════════════════════════════════════════"
echo " 采集完成 AUTH COLLECTOR END"
echo "════════════════════════════════════════════"
