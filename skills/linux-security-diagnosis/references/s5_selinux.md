# S5 — 安全策略与防护：诊断参考

## 目录
1. [SELinux 故障定位模式](#selinux)
2. [AppArmor 故障定位模式](#apparmor)
3. [AVC 拒绝事件解读](#avc)
4. [SELinux 布尔值与策略调整](#bool)
5. [防护服务异常诊断](#services)

---

## 1. SELinux 故障定位模式 {#selinux}

### 三种模式影响
```
Enforcing  → 策略生效，拒绝未授权访问（会产生AVC日志）
Permissive → 策略不生效，只记录日志（用于调试）
Disabled   → SELinux完全关闭

判断SELinux是否是问题根因：
临时切换到Permissive: setenforce 0
重试操作 → 成功 = SELinux是原因
重试操作 → 失败 = SELinux不是原因（恢复: setenforce 1）
```

### SELinux 策略被禁用的常见原因
1. 管理员修改 `/etc/selinux/config` 设置 `SELINUX=disabled` 后重启
2. 内核启动参数添加 `selinux=0`（查看 `/proc/cmdline`）
3. 系统升级或配置管理工具（Ansible/Puppet）修改
4. 攻击者已获得root权限后关闭（高危告警）

### 检测SELinux是否被篡改
```bash
# 检查配置文件最后修改时间
stat /etc/selinux/config

# 检查审计日志中是否有禁用SELinux的操作
ausearch -m mac_status -ts today 2>/dev/null
# 或查看 setenforce 操作记录
ausearch -c setenforce -ts today 2>/dev/null

# 检查是否有异常的策略模块
semodule -l 2>/dev/null | grep -v "^\(base\|targeted\|mcs\)"
```

---

## 2. AVC 拒绝事件解读 {#avc}

### AVC 日志结构解析
```
type=AVC msg=audit(1700000000.123:456): avc: denied
  { read write }                    → 被拒绝的操作（权限）
  for pid=1234                      → 进程PID
  comm="httpd"                      → 进程名
  name="upload.php"                 → 目标文件名
  dev="sda1" ino=12345
  scontext=system_u:system_r:httpd_t:s0          → 源SELinux上下文（进程）
  tcontext=unconfined_u:object_r:user_home_t:s0  → 目标SELinux上下文（文件）
  tclass=file                       → 目标对象类型
```

### 常见AVC拒绝模式

| 场景 | tclass | 操作 | 原因 |
|------|--------|------|------|
| Web服务无法访问上传目录 | file | read/write | 文件SELinux标签不对（应为httpd_sys_rw_content_t）|
| 服务无法绑定端口 | tcp_socket | name_bind | 端口不在服务允许的端口类型中 |
| 服务无法写日志 | file | write | 日志目录标签类型不对 |
| 服务无法连接网络 | tcp_socket | connect | 布尔值未开启（httpd_can_network_connect）|

### audit2why / audit2allow 使用
```bash
# 解释拒绝原因
ausearch -m avc -ts recent 2>/dev/null | audit2why

# 生成允许策略模块（谨慎使用，可能放宽过多权限）
ausearch -m avc -ts recent 2>/dev/null | audit2allow -M mymodule
semodule -i mymodule.pp

# 更好的做法：先理解后用restorecon修复标签
restorecon -Rv /path/to/affected/files
```

---

## 3. SELinux 布尔值常用调整 {#bool}

| 布尔值 | 说明 | 启用场景 |
|--------|------|---------|
| `httpd_can_network_connect` | 允许httpd连接网络 | PHP反向代理/curl |
| `httpd_can_sendmail` | 允许httpd发邮件 | Web表单邮件 |
| `httpd_use_nfs` | 允许httpd访问NFS | NFS挂载网站目录 |
| `samba_enable_home_dirs` | samba访问home目录 | Samba文件共享 |
| `allow_user_exec_content` | 用户执行home目录程序 | 开发环境 |

```bash
# 查看布尔值当前状态
getsebool httpd_can_network_connect

# 临时修改（重启失效）
setsebool httpd_can_network_connect on

# 永久修改
setsebool -P httpd_can_network_connect on
```

---

## 4. 防护服务异常诊断 {#services}

### firewalld 常见故障
```bash
# 问题：firewalld启动失败
# 原因1：与iptables规则冲突
iptables -F  # 清空iptables规则
systemctl start firewalld

# 原因2：nftables冲突（RHEL8/CentOS8）
systemctl stop nftables
systemctl start firewalld

# 检查是否有iptables/nftables共存问题
systemctl is-active iptables nftables firewalld
```

### fail2ban 故障
```bash
# fail2ban未阻断暴力破解
# 检查1：jail是否启用
fail2ban-client status
fail2ban-client status sshd

# 检查2：日志文件路径是否正确
grep logpath /etc/fail2ban/jail.local /etc/fail2ban/jail.conf 2>/dev/null

# 检查3：filter正则是否匹配
fail2ban-regex /var/log/secure /etc/fail2ban/filter.d/sshd.conf | tail -10
```

### IDS/IPS（snort/suricata）故障
```bash
# 查看snort/suricata状态
systemctl status snort suricata 2>/dev/null
ps -ef | grep -E "snort|suricata" | grep -v grep

# 检查规则是否加载
snort --version 2>/dev/null
suricata --list-runmodes 2>/dev/null

# 检查告警日志
tail -50 /var/log/snort/alert 2>/dev/null
tail -50 /var/log/suricata/fast.log 2>/dev/null
```
