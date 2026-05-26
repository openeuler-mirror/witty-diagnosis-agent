#!/bin/bash
# collect_account_abuse.sh — 账户滥用与异常行为采集脚本
# 场景：异常登录、暴力破解、提权操作、过期账户使用、sudo滥用
# 用法：bash collect_account_abuse.sh [hours_back]

HOURS="${1:-24}"

echo "════════════════════════════════════════════"
echo " ACCOUNT ABUSE DIAGNOSIS COLLECTOR"
echo " 采集时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo " 分析时间窗口: 最近 ${HOURS} 小时"
echo "════════════════════════════════════════════"

# ── 1. 登录历史分析 ──────────────────────────────
echo ""
echo "── [1] 近期登录历史（last）──"
last -F -n 50 2>/dev/null || last -n 50

echo ""
echo "── [2] 失败登录历史（lastb）──"
lastb -F -n 50 2>/dev/null | head -55 || echo "lastb不可用或需要root"

# ── 2. 暴力破解检测 ──────────────────────────────
echo ""
echo "── [3] 暴力破解检测分析 ──"
echo "[失败登录来源IP统计（TOP20）]"
python3 - <<'PYEOF'
import subprocess, re, collections, datetime

# 尝试从journald读取
try:
    out = subprocess.check_output(
        ['journalctl', '-u', 'sshd', '--since', '24 hours ago', '--no-pager'],
        text=True, stderr=subprocess.DEVNULL
    )
except:
    out = ""

# 尝试从/var/log/secure读取
if not out:
    try:
        with open('/var/log/secure') as f:
            out = f.read()
    except:
        pass

if not out:
    try:
        with open('/var/log/auth.log') as f:
            out = f.read()
    except:
        pass

# 统计失败IP
ips = re.findall(r'Failed password.*?from (\d+\.\d+\.\d+\.\d+)', out)
users = re.findall(r'Failed password for (?:invalid user )?(\S+) from', out)
ip_counts = collections.Counter(ips)
user_counts = collections.Counter(users)

print("失败登录来源IP TOP20:")
for ip, cnt in ip_counts.most_common(20):
    flag = " ⚠️ 疑似暴力破解(>10次)" if cnt > 10 else ""
    print(f"  {cnt:5d}次  {ip}{flag}")

print("\n被攻击账户 TOP10:")
for user, cnt in user_counts.most_common(10):
    print(f"  {cnt:5d}次  {user}")

# 时间分布分析
timestamps = re.findall(r'(\w{3}\s+\d+\s+\d+:\d+:\d+).*Failed password', out)
if timestamps:
    print(f"\n失败登录时间分布（首次: {timestamps[0]}  末次: {timestamps[-1]}）")
    print(f"总失败次数: {len(timestamps)}")
PYEOF

# ── 3. sudo 滥用检测 ─────────────────────────────
echo ""
echo "── [4] sudo 操作日志分析 ──"
echo "[近期sudo操作]"
journalctl --since "${HOURS} hours ago" --no-pager 2>/dev/null | grep "sudo:" | tail -30 \
    || grep "sudo:" /var/log/secure 2>/dev/null | tail -30 \
    || grep "sudo:" /var/log/auth.log 2>/dev/null | tail -30
echo ""
echo "[sudo 失败（未授权操作）]"
journalctl --since "${HOURS} hours ago" --no-pager 2>/dev/null \
    | grep "sudo:.*NOT in sudoers\|authentication failure\|sudo.*incorrect password" | tail -20 \
    || grep "NOT in sudoers\|authentication failure" /var/log/secure 2>/dev/null | tail -20

# ── 4. 账户状态全量检查 ─────────────────────────
echo ""
echo "── [5] 账户状态全量检查 ──"
echo "[有效非系统账户（uid≥1000或UID500-999在CentOS旧版）]"
awk -F: '$3 >= 500 && $3 != 65534 {print $1":"$3":"$6":"$7}' /etc/passwd 2>/dev/null

echo ""
echo "[过期账户检测]"
python3 - <<'PYEOF'
import subprocess, datetime

try:
    out = subprocess.check_output(['cat', '/etc/passwd'], text=True)
    users = [line.split(':')[0] for line in out.strip().split('\n')
             if len(line.split(':')) > 2 and int(line.split(':')[2]) >= 500]
    for user in users:
        try:
            chage = subprocess.check_output(['chage', '-l', user], text=True, stderr=subprocess.DEVNULL)
            for line in chage.split('\n'):
                if 'Account expires' in line:
                    val = line.split(':')[-1].strip()
                    if val != 'never' and val:
                        try:
                            exp_date = datetime.datetime.strptime(val, '%b %d, %Y')
                            if exp_date < datetime.datetime.now():
                                print(f"  ⚠️  {user}: 账户已过期 ({val})")
                            else:
                                print(f"  OK  {user}: 到期日 {val}")
                        except:
                            pass
        except:
            pass
except Exception as e:
    print(f"跳过: {e}")
PYEOF

echo ""
echo "[长期未登录账户（>90天）]"
python3 - <<'PYEOF'
import subprocess, datetime, re

try:
    out = subprocess.check_output(['last', '-F', '-w'], text=True, stderr=subprocess.DEVNULL)
    user_times = {}
    for line in out.split('\n'):
        parts = line.split()
        if len(parts) < 5 or parts[0] in ('wtmp', 'reboot', 'shutdown', ''):
            continue
        user = parts[0]
        # 尝试解析最近登录时间
        try:
            date_str = ' '.join(parts[4:8])
            dt = datetime.datetime.strptime(date_str, '%a %b %d %H:%M:%S %Y')
            if user not in user_times or dt > user_times[user]:
                user_times[user] = dt
        except:
            pass
    now = datetime.datetime.now()
    for user, last_login in sorted(user_times.items()):
        delta = (now - last_login).days
        if delta > 90:
            print(f"  ⚠️  {user}: 最后登录 {last_login.strftime('%Y-%m-%d')} ({delta}天前)")
except Exception as e:
    print(f"分析跳过: {e}")
PYEOF

# ── 5. 特权操作审计 ──────────────────────────────
echo ""
echo "── [6] 近期特权操作审计 ──"
echo "[root用户操作（今日）]"
ausearch -ui 0 -ts today 2>/dev/null | grep "type=SYSCALL" | tail -20 \
    || grep "uid=0" /var/log/audit/audit.log 2>/dev/null | tail -20

echo ""
echo "[异常提权事件（su/sudo切换）]"
ausearch -m user_auth -ts today 2>/dev/null | tail -20 \
    || grep "su\|sudo" /var/log/secure 2>/dev/null | grep -iE "opened|session" | tail -20

# ── 6. 可疑进程/shell检测 ────────────────────────
echo ""
echo "── [7] 可疑进程/反弹shell检测 ──"
echo "[监听shell进程（bash/sh/python监听）]"
ss -tlnp 2>/dev/null | grep -E "bash|python|perl|ruby|nc|ncat"
echo ""
echo "[bash进程及其父进程]"
ps -ef 2>/dev/null | grep -E "\-bash|\-sh" | grep -v grep | head -20
echo ""
echo "[/dev/tcp 相关进程（反弹shell检测）]"
lsof 2>/dev/null | grep -E "bash.*TCP|python.*TCP" | grep -v "127.0.0.1" | head -10

echo ""
echo "════════════════════════════════════════════"
echo " 采集完成 ACCOUNT ABUSE COLLECTOR END"
echo "════════════════════════════════════════════"
