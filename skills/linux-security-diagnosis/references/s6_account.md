# S6 — 账户滥用与异常行为：诊断参考

## 目录
1. [异常登录检测与判断](#anomaly)
2. [暴力破解分析方法](#bruteforce)
3. [账户提权行为检测](#privilege)
4. [过期/僵尸账户风险](#stale)
5. [反弹Shell检测](#reverse)
6. [日志时间线重建方法](#timeline)

---

## 1. 异常登录检测与判断 {#anomaly}

### 正常 vs 异常登录特征

| 特征 | 正常 | 异常 |
|------|------|------|
| 登录时间 | 工作时间段 | 凌晨/非工作时间 |
| 来源IP | 已知内网/VPN IP | 陌生外网IP、Tor节点 |
| 登录频率 | 零星 | 密集（秒级）失败 |
| 登录账户 | 有效业务账户 | root、admin、test、oracle |
| 失败/成功比 | 低失败率 | 高失败率后突然成功 |

### 关键判断：暴力破解后成功登录
```bash
# 找到大量失败后出现成功的源IP（高危！）
python3 - <<'EOF'
import re, subprocess, collections

try:
    out = subprocess.check_output(['grep', '-E', 'Failed password|Accepted', '/var/log/secure'], text=True)
except:
    out = subprocess.check_output(['journalctl', '-u', 'sshd', '--no-pager'], text=True, stderr=subprocess.DEVNULL)

fails = collections.Counter(re.findall(r'Failed password.*?from (\d+\.\d+\.\d+\.\d+)', out))
accepts = re.findall(r'Accepted.*?from (\d+\.\d+\.\d+\.\d+)', out)
accept_set = set(accepts)

print("⚠️  暴力破解后成功登录的IP（高危）:")
for ip, cnt in fails.most_common():
    if ip in accept_set and cnt > 5:
        print(f"  IP {ip}: {cnt}次失败 + 登录成功！")
EOF
```

### last/lastb 分析模式
```bash
# 查看是否有非常规时间登录
last -F | awk '$5 ~ /^0[0-5]:/ {print "非工作时间登录:", $0}'

# 查看是否有同一账户多地同时在线
last | awk '{print $1}' | sort | uniq -d | while read u; do
    echo "多session用户: $u"
    last "$u" | head -5
done
```

---

## 2. 暴力破解分析方法 {#bruteforce}

### 判断暴力破解 vs 正常失败
- **暴力破解特征**：同一IP在短时间内（<1分钟）产生>10次失败
- **字典攻击特征**：多个不同用户名失败，IP固定
- **分布式攻击特征**：多个IP使用相同用户名攻击

### fail2ban 状态检查
```bash
# 查看当前被ban的IP
fail2ban-client status sshd

# 查看jail规则
fail2ban-client get sshd maxretry
fail2ban-client get sshd bantime
fail2ban-client get sshd findtime
```

### 暴力破解根因分析要点
1. 攻击是否仍在持续（查看最新fail时间）
2. 是否已突破防护（有Accepted记录来自同IP）
3. fail2ban/pam_faillock是否工作（IP被ban了吗）
4. 攻击目标账户是否敏感（root/admin）

---

## 3. 账户提权行为检测 {#privilege}

### sudo 滥用识别
```bash
# 查看sudo操作历史
grep "sudo:" /var/log/secure | grep -v "session\|pam_unix"

# 识别非授权sudo尝试
grep "NOT in sudoers" /var/log/secure

# 查看谁有sudo权限
grep -vE "^#|^$|^Defaults" /etc/sudoers
ls -la /etc/sudoers.d/
```

### 提权路径检测
```bash
# 检查SUID文件（潜在提权路径）
find / -perm -4000 -type f 2>/dev/null | grep -vE "/usr/bin/(su|sudo|passwd|chsh|chage|gpasswd|newgrp|pkexec)|/bin/(ping|mount|umount)"

# 检查可写目录中是否有SUID文件（极高危）
find /tmp /var/tmp /dev/shm -perm -4000 -type f 2>/dev/null

# 检查可疑capabilities
getcap -r / 2>/dev/null | grep -v "^$"
```

### Cron/定时任务提权检测
```bash
# 检查root crontab中是否有可写脚本
crontab -l -u root 2>/dev/null
cat /etc/cron* /var/spool/cron/* 2>/dev/null | grep -v "^#"

# 查找cron中使用的可写脚本
for f in $(grep -oP '/\S+\.sh' /etc/cron* /var/spool/cron/* 2>/dev/null | sort -u); do
    [ -w "$f" ] && echo "⚠️ Cron使用了可写脚本: $f"
done
```

---

## 4. 过期/僵尸账户风险 {#stale}

### 账户类型分类
```
UID < 500(或1000): 系统账户（正常，多为服务账户）
UID >= 500/1000  : 人员账户（重点审查）
shell=/sbin/nologin 或 /bin/false: 不能登录（服务账户标志）
```

### 僵尸账户识别标准
1. 账户存在但 `last` 输出中无近期登录（>90天）
2. 账户在AD/LDAP中已禁用，但本地/etc/passwd仍有记录
3. 离职员工账户（需结合人员变动记录）
4. 有登录shell但无密码（/etc/shadow中为!!）

### 账户审计脚本
```bash
# 列出可登录但长期未用的账户
while IFS=: read -r user _ uid _ _ home shell; do
    [ "$uid" -lt 500 ] 2>/dev/null && continue
    [[ "$shell" == *nologin* || "$shell" == *false* ]] && continue
    last_login=$(lastlog -u "$user" 2>/dev/null | tail -1 | awk '{print $4,$5,$6,$9}')
    echo "$user (uid=$uid): 最后登录=$last_login"
done < /etc/passwd
```

---

## 5. 反弹Shell检测 {#reverse}

### 检测方法
```bash
# 1. 查找异常网络连接的shell进程
ss -antp 2>/dev/null | awk '{print $5, $6}' | grep -v "127.0.0.1\|::1\|\*" | while read addr proc; do
    pid=$(echo "$proc" | grep -oP 'pid=\K\d+')
    [ -n "$pid" ] && comm=$(cat /proc/$pid/comm 2>/dev/null) && \
    echo "$comm ($pid) → $addr"
done | grep -E "bash|sh|python|perl|ruby|nc|socat"

# 2. 检查/proc下的bash/sh外联连接
for pid in $(pgrep -x bash -x sh 2>/dev/null); do
    ls -la /proc/$pid/fd 2>/dev/null | grep socket | head -3
    cat /proc/$pid/net/tcp6 2>/dev/null | grep -v "00000000:0000" | head -3
done

# 3. 历史命令检查
for user_home in /root /home/*; do
    hist="$user_home/.bash_history"
    [ -f "$hist" ] && grep -iE "bash.*>/dev/tcp|nc.*-e|python.*socket|socat" "$hist" | head -5 \
        && echo "  来自: $hist"
done
```

---

## 6. 日志时间线重建方法 {#timeline}

### 多源日志合并时间线
```bash
# 合并secure + audit + messages，按时间排序
python3 - <<'EOF'
import re, subprocess
from datetime import datetime

events = []

# 从/var/log/secure读取
try:
    with open('/var/log/secure') as f:
        for line in f:
            m = re.match(r'(\w{3}\s+\d+\s+\d+:\d+:\d+)\s+\S+\s+(.*)', line)
            if m:
                try:
                    t = datetime.strptime(f"{datetime.now().year} {m.group(1)}", "%Y %b %d %H:%M:%S")
                    events.append((t, 'secure', m.group(2)[:80]))
                except: pass
except: pass

# 从audit.log读取
try:
    with open('/var/log/audit/audit.log') as f:
        for line in f:
            m = re.search(r'time->(\d+\.\d+)', line)
            if m:
                t = datetime.fromtimestamp(float(m.group(1)))
                msg = re.search(r'msg=audit\([^)]+\):\s*(.*)', line)
                if msg:
                    events.append((t, 'audit', msg.group(1)[:80]))
except: pass

events.sort(key=lambda x: x[0])
for t, src, msg in events[-100:]:  # 最近100条
    print(f"[{t.strftime('%H:%M:%S')}][{src:6s}] {msg}")
EOF
```

### 关键时间点标记
在时间线中，特别关注：
1. **第一次出现** 失败登录的时间 → 攻击开始时间
2. **密集失败** 时间段 → 暴力破解窗口
3. **成功登录** 时间 → 入侵成功时间（如有）
4. **sudo/su** 操作时间 → 提权时间
5. **日志gap** 时间 → 可能的日志清理时间
