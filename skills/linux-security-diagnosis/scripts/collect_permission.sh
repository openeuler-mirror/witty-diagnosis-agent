#!/bin/bash
# collect_permission.sh — 权限控制信息采集脚本
# 场景：文件权限拒绝、服务无法启动、ACL/SELinux/Capabilities异常
# 用法：bash collect_permission.sh [path_or_file] [username]

TARGET_PATH="${1:-}"
TARGET_USER="${2:-}"

echo "════════════════════════════════════════════"
echo " PERMISSION DIAGNOSIS COLLECTOR"
echo " 采集时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo " 目标路径: ${TARGET_PATH:-未指定}"
echo " 目标用户: ${TARGET_USER:-未指定}"
echo "════════════════════════════════════════════"

# ── 1. 目标路径权限分析 ──────────────────────────
if [ -n "$TARGET_PATH" ]; then
    echo ""
    echo "── [1] 目标路径权限分析 ──"
    echo "[基础权限 ls -la]"
    ls -la "$TARGET_PATH" 2>&1
    echo ""
    echo "[ACL 权限 getfacl]"
    getfacl "$TARGET_PATH" 2>&1
    echo ""
    echo "[SELinux 标签]"
    ls -laZ "$TARGET_PATH" 2>/dev/null || echo "SELinux未启用或不支持"
    echo ""
    echo "[父目录权限链]"
    path="$TARGET_PATH"
    while [ "$path" != "/" ] && [ "$path" != "." ]; do
        ls -ld "$path" 2>/dev/null
        path=$(dirname "$path")
    done
    echo ""
    echo "[文件capabilities]"
    getcap "$TARGET_PATH" 2>&1 || echo "getcap不可用"
fi

# ── 2. 用户权限上下文 ─────────────────────────────
if [ -n "$TARGET_USER" ]; then
    echo ""
    echo "── [2] 用户权限上下文 ──"
    echo "[用户ID和组]"
    id "$TARGET_USER" 2>&1
    echo "[sudo 权限]"
    sudo -l -U "$TARGET_USER" 2>&1
    echo "[用户所属组详情]"
    groups "$TARGET_USER" 2>&1
fi

# ── 3. SELinux 状态 ────────────────────────────
echo ""
echo "── [3] SELinux / AppArmor 状态 ──"
echo "[SELinux 执行模式]"
getenforce 2>/dev/null || echo "SELinux未安装"
sestatus 2>/dev/null || echo "sestatus不可用"
echo ""
echo "[最近SELinux拒绝事件(最近200条)]"
ausearch -m avc,user_avc -ts today 2>/dev/null | grep "denied" | tail -30 \
    || journalctl --since "24 hours ago" 2>/dev/null | grep "avc.*denied" | tail -30 \
    || grep "avc.*denied" /var/log/audit/audit.log 2>/dev/null | tail -30
echo ""
echo "[AppArmor 状态]"
aa-status 2>/dev/null || apparmor_status 2>/dev/null || echo "AppArmor未安装"

# ── 4. 关键系统目录权限 ─────────────────────────
echo ""
echo "── [4] 关键系统目录/文件权限检查 ──"
for f in /etc/passwd /etc/shadow /etc/sudoers /etc/ssh/sshd_config /etc/pam.d/sshd; do
    if [ -e "$f" ]; then
        ls -la "$f" 2>/dev/null
    fi
done

# ── 5. SUID/SGID 文件扫描 ────────────────────────
echo ""
echo "── [5] SUID/SGID 敏感文件（非标准）──"
echo "[SUID文件列表]"
find /usr /bin /sbin -perm -4000 -type f 2>/dev/null | head -20
echo "[SGID文件列表]"
find /usr /bin /sbin -perm -2000 -type f 2>/dev/null | head -20

# ── 6. 近期权限变更审计 ──────────────────────────
echo ""
echo "── [6] 近期权限变更审计日志 ──"
echo "[chmod/chown 操作记录（审计日志）]"
ausearch -sc chmod,chown -ts today 2>/dev/null | tail -30 \
    || grep -E "chmod|chown" /var/log/audit/audit.log 2>/dev/null | tail -30 \
    || echo "无审计日志或未配置相关规则"

# ── 7. 进程权限上下文 ────────────────────────────
echo ""
echo "── [7] 关键服务进程权限上下文 ──"
ps -eo pid,user,group,comm,label 2>/dev/null | grep -vE "^PID|kworker|kthread" | head -30 \
    || ps -eo pid,user,group,comm 2>/dev/null | head -30

echo ""
echo "════════════════════════════════════════════"
echo " 采集完成 PERMISSION COLLECTOR END"
echo "════════════════════════════════════════════"
