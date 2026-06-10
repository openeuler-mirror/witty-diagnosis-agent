#!/bin/bash
# branch_F_dev_fuse_perm.sh — /dev/fuse 设备权限问题诊断
# 场景: FUSE daemon 启动时报 Permission denied
# 对应 SKILL.md Branch F
#
# Usage: bash branch_F_dev_fuse_perm.sh [daemon_user] [daemon_name]

DAEMON_USER="${1:-}"
DAEMON_NAME="${2:-}"

echo "============================================"
echo " Branch F: /dev/fuse 设备权限诊断"
echo "============================================"
echo ""

# ---- L2: 类型层诊断 ----

# 1. /dev/fuse 设备节点
echo "--- [L2-1] /dev/fuse 设备节点 ---"
if [ -c /dev/fuse ]; then
    ls -la /dev/fuse
    echo "  主次设备号: $(stat -c '%t %T' /dev/fuse 2>/dev/null)"
else
    echo "  /dev/fuse 设备节点不存在"
fi
echo ""

# 2. ACL 权限
echo "--- [L2-2] ACL 权限 ---"
getfacl /dev/fuse 2>/dev/null || echo "  (getfacl 不可用或无 ACL)"
echo ""

# 3. daemon 用户能力集
if [ -n "$DAEMON_USER" ]; then
    echo "--- [L2-3] 用户 $DAEMON_USER 信息 ---"
    groups "$DAEMON_USER" 2>/dev/null || echo "  用户: $DAEMON_USER 不存在"
    echo ""
fi

# 4. daemon 进程能力（如果有 PID）
if [ -n "$DAEMON_NAME" ]; then
    daemon_pid=$(pgrep -f "$DAEMON_NAME" 2>/dev/null | head -1)
    if [ -n "$daemon_pid" ]; then
        echo "--- [L2-4] Daemon 进程能力 (PID $daemon_pid) ---"
        echo "  CapInh:  $(cat /proc/$daemon_pid/status 2>/dev/null | grep "CapInh:" | awk '{print $2}')"
        echo "  CapPrm:  $(cat /proc/$daemon_pid/status 2>/dev/null | grep "CapPrm:" | awk '{print $2}')"
        echo "  CapEff:  $(cat /proc/$daemon_pid/status 2>/dev/null | grep "CapEff:" | awk '{print $2}')"
        echo "  CapBnd:  $(cat /proc/$daemon_pid/status 2>/dev/null | grep "CapBnd:" | awk '{print $2}')"
        capsh --decode=$(cat /proc/$daemon_pid/status 2>/dev/null | grep "CapEff:" | awk '{print $2}') 2>/dev/null || echo "  (capsh 不可用)"
        echo ""
    fi
fi

# 5. fuse 用户组
echo "--- [L2-5] fuse 用户组 ---"
grep -E "^fuse:" /etc/group 2>/dev/null || echo "  fuse 组不存在"
if [ -n "$DAEMON_USER" ]; then
    groups "$DAEMON_USER" 2>/dev/null | grep -q fuse
    if [ $? -eq 0 ]; then
        echo "  用户 $DAEMON_USER 在 fuse 组中 ✓"
    else
        echo "  用户 $DAEMON_USER 不在 fuse 组中 ✗"
    fi
fi
echo ""

# 6. /etc/fuse.conf
echo "--- [L2-6] FUSE 全局配置 ---"
if [ -f /etc/fuse.conf ]; then
    echo "  /etc/fuse.conf 内容:"
    cat /etc/fuse.conf
    grep -q "^user_allow_other" /etc/fuse.conf 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "  user_allow_other: 已启用"
    else
        echo "  user_allow_other: 未启用（如需 allow_other 选项需配置）"
    fi
else
    echo "  /etc/fuse.conf 不存在"
fi
echo ""

# 7. 容器环境检查
echo "--- [L2-7] 容器环境检查 ---"
if [ -f /proc/1/cgroup ]; then
    is_container=$(grep -q "docker\|kubepods\|container" /proc/1/cgroup 2>/dev/null && echo 1 || echo 0)
    if [ "$is_container" = 1 ]; then
        echo "  当前环境: 容器"
        cat /proc/1/cgroup 2>/dev/null | head -3
        echo "  /dev/fuse 是否挂载: $(ls -la /dev/fuse 2>/dev/null || echo '不存在')"
        capsh --print 2>/dev/null | grep -E "cap_sys_admin|cap_mknod" || echo "  (capsh 不可用)"
    else
        echo "  当前环境: 非容器（物理机/虚拟机）"
    fi
fi
echo ""

# 8. SELinux / AppArmor
echo "--- [L2-8] 安全策略检查 ---"
if command -v getenforce &>/dev/null; then
    echo "  SELinux: $(getenforce 2>/dev/null)"
    if [ -n "$DAEMON_NAME" ]; then
        ausearch -m avc -ts recent 2>/dev/null | grep -i fuse | head -5 || echo "  (无 SELinux FUSE 拒绝记录)"
    fi
elif command -v aa-status &>/dev/null; then
    echo "  AppArmor: $(aa-status 2>/dev/null | head -3)"
else
    echo "  无 SELinux/AppArmor 或不可用"
fi
echo ""

# ---- L3: 根因判定 ----
echo "============================================"
echo " L3 根因判定"
echo "============================================"

dev_perm=$(stat -c '%a' /dev/fuse 2>/dev/null)
dev_owner=$(stat -c '%U:%G' /dev/fuse 2>/dev/null)
has_fuse_group=$(grep -q "^fuse:" /etc/group 2>/dev/null && echo 1 || echo 0)
user_in_fuse=0
if [ -n "$DAEMON_USER" ]; then
    groups "$DAEMON_USER" 2>/dev/null | grep -q fuse && user_in_fuse=1
fi

if [ ! -c /dev/fuse ]; then
    echo "结论: /dev/fuse 设备节点不存在。"
    echo "根因: FUSE 设备节点未创建，可能 fuse 内核模块未加载或容器中未挂载设备。"
    echo "建议: 确保 fuse 模块已加载 (modprobe fuse)，或容器中传递 --device /dev/fuse"
elif [ -n "$DAEMON_USER" ] && [ "$dev_perm" = "660" ] && [ "$dev_owner" != "root:fuse" ]; then
    echo "结论: /dev/fuse 权限为 660 且用户 $DAEMON_USER 可能无权限访问。"
    echo "根因: /dev/fuse 设备节点权限限制，非 root 用户或无 fuse 组成员无法访问。"
    echo "建议: 将 $DAEMON_USER 添加到 fuse 组，或修改 /dev/fuse 权限为 666"
elif [ -n "$DAEMON_USER" ] && [ "$user_in_fuse" -eq 0 ] && [ "$dev_perm" != "666" ]; then
    echo "结论: 用户 $DAEMON_USER 不在 fuse 组，且 /dev/fuse 非全局可读写。"
    echo "根因: /dev/fuse 限制 root/fuse 组访问，而 daemon 以普通用户运行。"
    echo "建议: 将 $DAEMON_USER 加入 fuse 组: usermod -aG fuse $DAEMON_USER"
elif [ -f /etc/fuse.conf ] && ! grep -q "^user_allow_other" /etc/fuse.conf 2>/dev/null; then
    echo "结论: /etc/fuse.conf 中未启用 user_allow_other。"
    echo "根因: 使用 allow_other 挂载选项需要配置 user_allow_other。"
    echo "建议: 在 /etc/fuse.conf 中添加 user_allow_other"
else
    echo "结论: 基本权限检查正常。"
    echo "根因: 当前权限配置可能非故障原因，建议进一步检查 daemon 日志。"
fi

echo ""
echo "诊断完成: $(date '+%Y-%m-%d %H:%M:%S')"
