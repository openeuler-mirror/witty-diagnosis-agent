#!/bin/bash
# collect_audit.sh — 系统审计与日志安全采集脚本
# 场景：审计日志缺失、rsyslog/auditd异常、日志被篡改、审计规则未生效
# 用法：bash collect_audit.sh [keyword] [user]
# user 可以是用户名（如 root）或 UID（如 0）

KEYWORD="${1:-}"
USER_FILTER="${2:-}"

echo "════════════════════════════════════════════"
echo " AUDIT/LOG DIAGNOSIS COLLECTOR"
echo " 采集时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo " 关键词过滤: ${KEYWORD:-无}"
echo " 用户过滤: ${USER_FILTER:-无}"
echo "════════════════════════════════════════════"

# ── 1. auditd 服务状态 ────────────────────────────
echo ""
echo "── [1] auditd 服务状态 ──"
systemctl status auditd --no-pager -l 2>/dev/null | head -25
echo ""
echo "[auditd 进程]"
ps -ef | grep auditd | grep -v grep
echo ""
echo "[audit.conf 配置]"
cat /etc/audit/auditd.conf 2>/dev/null | grep -v "^#" | grep -v "^$"

# ── 2. 审计规则 ──────────────────────────────────
echo ""
echo "── [2] 当前生效的审计规则 ──"
auditctl -l 2>/dev/null || echo "auditctl 不可用或无权限"
echo ""
echo "[规则文件]"
cat /etc/audit/rules.d/*.rules 2>/dev/null | grep -v "^#" | grep -v "^$" \
    || cat /etc/audit/audit.rules 2>/dev/null | grep -v "^#" | grep -v "^$"

# ── 3. 日志文件状态 ──────────────────────────────
echo ""
echo "── [3] 日志文件状态与完整性 ──"
echo "[/var/log 关键日志文件权限和大小]"
ls -la /var/log/{audit/audit.log,secure,auth.log,messages,syslog} 2>/dev/null
ls -la /var/log/audit/ 2>/dev/null
echo ""
echo "[磁盘空间]"
df -h /var/log 2>/dev/null
echo ""
echo "[日志目录写权限测试]"
touch /var/log/.write_test_$$ 2>/dev/null && echo "/var/log 可写" && rm -f /var/log/.write_test_$$ \
    || echo "/var/log 不可写（权限问题）"
touch /var/log/audit/.write_test_$$ 2>/dev/null && echo "/var/log/audit 可写" && rm -f /var/log/audit/.write_test_$$ \
    || echo "/var/log/audit 不可写"

# ── 4. rsyslog 状态 ───────────────────────────────
echo ""
echo "── [4] rsyslog/syslog 服务状态 ──"
systemctl status rsyslog --no-pager -l 2>/dev/null | head -20 \
    || systemctl status syslog --no-pager -l 2>/dev/null | head -20
echo ""
echo "[rsyslog 配置主要项]"
grep -v "^#" /etc/rsyslog.conf 2>/dev/null | grep -v "^$" | head -40
echo ""
echo "[rsyslog.d 配置]"
ls -la /etc/rsyslog.d/ 2>/dev/null
cat /etc/rsyslog.d/*.conf 2>/dev/null | grep -v "^#" | grep -v "^$"

# ── 5. 日志连续性检查 ─────────────────────────────
echo ""
echo "── [5] 日志连续性检查（时间gap检测）──"
echo "[secure/auth.log 最新50条时间戳]"
tail -50 /var/log/secure 2>/dev/null | awk '{print $1,$2,$3}' \
    || tail -50 /var/log/auth.log 2>/dev/null | awk '{print $1,$2,$3}'
echo ""
echo "[audit.log 最新时间戳]"
tail -5 /var/log/audit/audit.log 2>/dev/null | grep -oP 'time->\K[^\)]+' \
    && echo "" \
    && python3 -c "
import subprocess, time, re
try:
    out = subprocess.check_output(['tail','-200','/var/log/audit/audit.log'], text=True, stderr=subprocess.DEVNULL)
    times = re.findall(r'time->(\d+)', out)
    if len(times) > 1:
        gaps = [(int(times[i+1])-int(times[i])) for i in range(len(times)-1)]
        max_gap = max(gaps)
        gap_idx = gaps.index(max_gap)
        if max_gap > 300:
            import datetime
            t1 = datetime.datetime.fromtimestamp(int(times[gap_idx]))
            t2 = datetime.datetime.fromtimestamp(int(times[gap_idx+1]))
            print(f'⚠ 发现最大日志时间gap: {max_gap}秒 ({t1} → {t2})')
        else:
            print('日志时间连续性正常（最大gap<5min）')
except Exception as e:
    print(f'gap分析跳过: {e}')
" 2>/dev/null

# ── 6. 关键操作审计搜索 ──────────────────────────
echo ""
echo "── [6] 关键审计事件搜索（今日）──"
if [ -n "$USER_FILTER" ]; then
    echo "[针对用户/UID: $USER_FILTER 的命令执行]"
    ausearch -m execve -ts today -ui "$USER_FILTER" 2>/dev/null | tail -20 \
        || grep "type=EXECVE" /var/log/audit/audit.log 2>/dev/null | grep "$USER_FILTER" | tail -20
else
    echo "[特权命令执行]"
    ausearch -m execve -ts today 2>/dev/null | grep "uid=0" | tail -20 \
        || grep "type=EXECVE" /var/log/audit/audit.log 2>/dev/null | tail -20
fi

echo ""
if [ -n "$USER_FILTER" ]; then
    echo "[针对用户/UID: $USER_FILTER 的文件删除操作]"
    ausearch -m unlink,rename -ts today -ui "$USER_FILTER" 2>/dev/null | tail -20 \
        || grep "type=SYSCALL.*unlink\|rename" /var/log/audit/audit.log 2>/dev/null | grep "$USER_FILTER" | tail -20
else
    echo "[文件删除操作]"
    ausearch -m unlink,rename -ts today 2>/dev/null | tail -20 \
        || grep "type=SYSCALL.*unlink\|rename" /var/log/audit/audit.log 2>/dev/null | tail -20
fi

echo ""
if [ -n "$KEYWORD" ]; then
    echo "[关键词 '$KEYWORD' 审计搜索]"
    ausearch -k "$KEYWORD" -ts today 2>/dev/null | tail -30 \
        || grep "$KEYWORD" /var/log/audit/audit.log 2>/dev/null | tail -30
fi

# ── 7. 日志防篡改状态 ─────────────────────────────
echo ""
echo "── [7] 日志防篡改与不可变属性检查 ──"
echo "[audit.log 文件属性]"
lsattr /var/log/audit/audit.log 2>/dev/null || echo "lsattr不可用"
lsattr /var/log/secure 2>/dev/null
echo ""
echo "[auditctl 审计系统状态]"
auditctl -s 2>/dev/null

echo ""
echo "════════════════════════════════════════════"
echo " 采集完成 AUDIT COLLECTOR END"
echo "════════════════════════════════════════════"
