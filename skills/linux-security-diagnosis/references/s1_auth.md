# S1 — 用户认证/登录安全：诊断参考

## 目录
1. [典型故障模式与故障链](#故障模式)
2. [PAM 配置诊断](#pam)
3. [SSSD/LDAP 故障诊断](#sssd)
4. [SSH 服务故障诊断](#ssh)
5. [账户锁定与密码策略](#lockout)
6. [日志关键字速查](#logs)
7. [常见根因与排除逻辑](#rootcause)

---

## 1. 典型故障模式与故障链 {#故障模式}

### 故障链模型

```
用户尝试登录
    │
    ├─► SSH层 → sshd 接收连接 → 检查 AllowUsers/DenyUsers
    │            → 调用 PAM 进行认证
    │
    ├─► PAM层 → pam_unix（本地认证）
    │         → pam_sss（SSSD/LDAP认证）
    │         → pam_faillock/pam_tally2（锁定检查）
    │         → pam_pwquality（密码策略）
    │
    ├─► SSSD层 → 查询 LDAP/AD → 网络连通性
    │          → 缓存状态
    │          → Kerberos/TLS 证书
    │
    └─► 账户层 → /etc/passwd → /etc/shadow → chage 有效期
```

### 常见故障链

**链1：SSSD服务崩溃导致域用户全部无法登录**
```
LDAP响应超时 → SSSD多次重试失败 → SSSD进程OOM/崩溃
→ getent passwd 无法解析域用户 → PAM pam_sss返回失败
→ SSH返回 "Permission denied" (所有域用户)
```

**链2：PAM pam_faillock触发全量账户锁定**
```
暴力破解脚本持续失败登录 → pam_faillock计数超过deny阈值
→ 账户状态置为locked → 合法用户也无法登录
→ /etc/security/faillock/<user> 文件记录锁定状态
```

**链3：PAM配置误修改导致认证方式断裂**
```
管理员修改 /etc/pam.d/system-auth → 误删除 pam_unix.so 行
→ 本地账户认证路径消失 → 所有本地用户无法登录
→ root 也无法本地登录（系统完全失控）
```

---

## 2. PAM 配置诊断 {#pam}

### 配置文件优先级
```
/etc/pam.d/sshd           → SSH登录PAM配置（直接调用）
/etc/pam.d/system-auth    → CentOS系统认证链（被sshd包含）
/etc/pam.d/password-auth  → 网络/密码认证链
```

### 关键 control 标志含义
| 标志 | 含义 | 失败时行为 |
|------|------|-----------|
| `required` | 必须成功，但继续执行后续模块 | 最终失败 |
| `requisite` | 必须成功，立即返回失败 | 立即失败 |
| `sufficient` | 成功则立即通过（前提required都过了） | 立即成功 |
| `optional` | 可选，不影响最终结果 | 忽略 |

### 典型错误配置识别
```
# 错误1：pam_faillock deny太低
auth required pam_faillock.so preauth deny=3   # 3次失败即锁

# 错误2：pam_unix missing（本地认证断裂）
# 正常应有：auth sufficient pam_unix.so nullok try_first_pass
# 若此行缺失，所有本地用户认证失败

# 错误3：pam_tally2与pam_faillock同时配置（计数双重触发）
auth required pam_tally2.so
auth required pam_faillock.so  # 两者同时存在会引起混乱
```

### faillock 状态检查与手动解锁
```bash
# 查看用户锁定状态
faillock --user <username>

# 手动解锁
faillock --user <username> --reset

# 旧版 pam_tally2
pam_tally2 --user=<username> --reset
```

---

## 3. SSSD/LDAP 故障诊断 {#sssd}

### SSSD 常见故障模式

| 症状 | 可能原因 | 验证方法 |
|------|---------|---------|
| 域用户getent失败 | SSSD服务停止 | `systemctl status sssd` |
| SSSD启动但用户无法解析 | LDAP服务器不可达 | `ldapsearch -x -H ldap://server -b dc=xx` |
| 偶发性认证失败 | SSSD缓存过期 | `sss_cache -E` 清除缓存 |
| 认证延迟高 | LDAP服务器响应慢 | `time getent passwd user` |
| 所有认证失败（离线） | SSSD offline_credentials_expiration | 查看sssd.conf |

### SSSD 关键日志路径
```
/var/log/sssd/sssd.log          → 主进程日志
/var/log/sssd/sssd_<domain>.log → 域连接日志（关键！）
/var/log/sssd/sssd_pam.log      → PAM接口日志
/var/log/sssd/sssd_nss.log      → NSS解析日志
```

### SSSD 诊断命令序列
```bash
# 1. 检查所有SSSD日志的错误
grep -iE "error|fail|crit" /var/log/sssd/*.log | tail -50

# 2. 测试LDAP连通性
ldapsearch -x -H ldap://<server> -b "dc=example,dc=com" "(uid=testuser)"

# 3. 查看SSSD缓存状态
sssctl domain-status <domain_name>

# 4. 强制刷新SSSD缓存
sss_cache -E && systemctl restart sssd

# 5. 开启SSSD调试（临时，级别0-9，9最详细）
sssctl debug-level 7
```

---

## 4. SSH 服务故障诊断 {#ssh}

### sshd_config 关键配置导致的问题
```
PermitRootLogin no      → root无法直接SSH
AllowUsers user1 user2  → 只有列出的用户可以登录（其他人全拒绝）
MaxAuthTries 3          → 3次失败即断开连接（不是锁定）
PasswordAuthentication no → 只允许公钥认证（密码登录失败）
```

### SSH 公钥认证失败排查
```bash
# 检查authorized_keys权限（最常见问题）
ls -la ~/.ssh/authorized_keys
# 正确权限：-rw------- (600), ~/.ssh 必须是 700

# SELinux标签问题
ls -laZ ~/.ssh/
restorecon -Rv ~/.ssh/  # 修复SELinux标签

# 检查sshd详细日志（临时提高日志级别）
# 在sshd_config中设置: LogLevel DEBUG3
# 然后查看: journalctl -u sshd -f
```

### 常见SSH错误信息解读
| 错误信息 | 根因 |
|---------|------|
| `Connection refused` | sshd未启动或端口未监听 |
| `Permission denied (publickey)` | 公钥不匹配/权限问题/SELinux |
| `Permission denied (password)` | 密码错误/PasswordAuthentication no |
| `Too many authentication failures` | MaxAuthTries耗尽 |
| `Connection closed by remote host` | sshd PAM配置错误/账户问题 |
| `Network error: Connection timed out` | 防火墙阻断/网络不通 |

---

## 5. 账户锁定与密码策略 {#lockout}

### 账户状态判断（/etc/shadow字段）
```
用户名:密码哈希:最后修改:最小天数:最大天数:警告天数:非活跃天数:过期日期:保留
          ^
          密码字段前缀:
          !  → 账户被lock（passwd -l 或 usermod -L）
          !! → 账户从未设置密码（新建账户）
          $6 → SHA-512加密的正常密码
```

### chage 输出解读
```bash
chage -l username
# Last password change         : 最近密码修改日期
# Password expires             : 密码过期日期（never=无限制）
# Password inactive            : 密码过期后还可登录的天数
# Account expires              : 账户过期日期（never=永不过期）
# Minimum number of days between password change : 0
# Maximum number of days between password change : 99999
# Number of days of warning before password expires : 7
```

### 密码策略配置位置
- `/etc/security/pwquality.conf` → 复杂度规则（pam_pwquality.so）
- `/etc/login.defs` → PASS_MAX_DAYS等基础策略
- `/etc/pam.d/system-auth` → PAM密码模块配置

---

## 6. 日志关键字速查 {#logs}

### 登录失败关键字（/var/log/secure 或 journald）
```
"Failed password for"           → 密码错误
"Failed password for invalid user" → 用户名不存在
"Invalid user"                  → 用户名无效
"Connection closed by"          → 连接被关闭（可能是PAM拒绝）
"pam_unix(sshd:auth): authentication failure" → PAM本地认证失败
"pam_sss(sshd:auth): authentication failure"  → PAM SSSD认证失败
"Account locked due to"         → 账户被锁定
"User account has expired"      → 账户已过期
"Your account has expired"      → 账户过期（提示信息）
```

### SSSD 日志关键字
```
"Backend is offline"            → LDAP后端不可达，进入离线模式
"Backend is online"             → LDAP后端恢复
"TGT expired"                   → Kerberos票据过期
"LDAP connection failed"        → LDAP连接失败
"Enumeration request failed"    → 用户枚举失败
```

---

## 7. 常见根因与排除逻辑 {#rootcause}

### 分类根因决策树

```
登录失败
  ├── 只有域用户失败，本地账户正常？
  │     YES → SSSD/LDAP问题（检查sssd状态和LDAP连通性）
  │     NO  → 继续
  │
  ├── 所有用户都失败（包括root）？
  │     YES → PAM配置损坏 或 sshd配置问题（检查pam.d/sshd）
  │     NO  → 继续
  │
  ├── 特定用户失败？
  │     → 账户状态（chage -l, /etc/shadow前缀）
  │     → faillock/pam_tally2 锁定状态
  │     → AllowUsers/DenyUsers配置
  │
  └── 失败发生在SSH连接阶段（not even prompt）？
        YES → 防火墙/sshd服务/AllowUsers问题
        NO（有密码提示但拒绝）→ PAM认证问题
```

### 为什么是PAM而不是LDAP？
- 如果本地账户也失败 → PAM链断裂（LDAP无关）
- 如果getent passwd 成功但登录失败 → PAM执行层面问题

### 为什么是SSSD而不是PAM？
- `pam_sss` 能调用但SSSD服务不可用 → SSSD问题
- sssctl domain-status 显示 offline → LDAP网络问题

### 为什么是账户锁定而不是密码错误？
- 密码正确但仍拒绝 → 锁定
- faillock --user 显示非零 fail_count 且时间近期 → 确认锁定
