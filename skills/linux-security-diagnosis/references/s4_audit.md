# S4 — 系统审计/日志安全：诊断参考

## 1. auditd 故障层次

```
审计事件产生
  │
  ├─[1] 内核审计子系统（kauditd）→ 产生审计记录
  ├─[2] auditd 守护进程 → 接收并写入磁盘
  ├─[3] 磁盘写入 → /var/log/audit/audit.log
  └─[4] 审计规则 → 决定哪些事件被记录（auditctl -l）

故障可发生在任何层：
- 内核参数关闭审计：audit=0 in /proc/cmdline
- auditd服务停止：systemctl status auditd
- 磁盘满/权限问题：df -h /var/log; ls -la /var/log/audit/
- 规则未配置：auditctl -l 输出空
```

## 2. 关键审计规则模板（CentOS）

```bash
# 监控/etc/passwd和/etc/shadow修改
-w /etc/passwd -p wa -k user_changes
-w /etc/shadow -p wa -k user_changes

# 监控sudo使用
-w /etc/sudoers -p wa -k sudoers_changes
-w /usr/bin/sudo -p x -k sudo_exec

# 监控关键配置文件修改
-w /etc/ssh/sshd_config -p wa -k sshd_config
-w /etc/selinux/config -p wa -k selinux_config
-w /etc/pam.d/ -p wa -k pam_changes

# 监控特权命令执行
-a always,exit -F arch=b64 -S execve -F uid=0 -k root_cmds

# 监控文件删除操作
-a always,exit -F arch=b64 -S unlink,rename -F auid>=500 -k file_deletion

# 写入规则文件
cat >> /etc/audit/rules.d/security.rules << 'EOF'
# 以上规则内容
EOF
auditctl -R /etc/audit/rules.d/security.rules
```

## 3. 日志时间gap分析（日志被清理检测）

正常的auditd日志应该是连续的。如果发现时间跳跃（gap），可能意味着：
1. auditd服务在该时间段停止
2. 日志文件被轮转
3. 攻击者删除了部分日志（恶意清理）

```bash
# 检查日志轮转是否正常
ls -lth /var/log/audit/
cat /etc/audit/auditd.conf | grep -E "num_logs|max_log_file"

# 检查auditd是否在gap期间运行
journalctl -u auditd --since "2024-01-01" --until "2024-01-02" | grep -iE "start|stop|restart"
```

## 4. rsyslog 故障排查

```bash
# rsyslog测试写入
logger -t test "Security test message $(date)"
sleep 1
grep "Security test message" /var/log/messages

# rsyslog配置验证
rsyslogd -N1  # 语法检查
rsyslogd -N2  # 详细语法检查

# 远程日志服务器连通性（如配置了远程转发）
grep -E "@[0-9]|@@[0-9]|omfwd" /etc/rsyslog.conf /etc/rsyslog.d/*.conf 2>/dev/null
```

## 5. auditd 与 disk full 处理策略

```bash
# auditd.conf 关键参数
grep -E "disk_full_action|disk_error_action|admin_space_left_action" /etc/audit/auditd.conf

# 可能值及含义：
# IGNORE  → 磁盘满时忽略（丢失审计记录！）
# SYSLOG  → 写syslog告警
# SUSPEND → 暂停审计
# HALT    → 系统停机（最安全但影响可用性）
# ROTATE  → 强制轮转日志
```
