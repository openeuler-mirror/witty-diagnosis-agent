#!/usr/bin/env bash
# diag_logtime.sh — 日志/监控/时间故障诊断
# 用途：容器日志大小、NTP 时间同步、证书时效
# 使用：bash diag_logtime.sh [container_name_or_id]

CONTAINER=""
KEYWORD=""
START_TIME=""
END_TIME=""

show_help() {
  echo "Usage: $(basename $0) [options]"
  echo "Options:"
  echo "  -c, --container <name>  Container name or ID (optional)"
  echo "  -k, --keyword <word>    Keyword to filter logs (optional)"
  echo "  -s, --start-time <time> Start time for logs (e.g. \"2023-10-01 12:00:00\", \"1 hour ago\")"
  echo "  -e, --end-time <time>   End time for logs (e.g. \"2023-10-01 13:00:00\")"
  echo "  -h, --help              Show this help message"
  exit 0
}

while [[ "$#" -gt 0 ]]; do
  case $1 in
    -c|--container) CONTAINER="$2"; shift 2 ;;
    -k|--keyword) KEYWORD="$2"; shift 2 ;;
    -s|--start-time) START_TIME="$2"; shift 2 ;;
    -e|--end-time) END_TIME="$2"; shift 2 ;;
    -h|--help) show_help ;;
    *) CONTAINER="$1"; shift ;; # Fallback for old positional arg
  esac
done
SEP="========================================"

header() { echo -e "\n${SEP}\n[$1]\n${SEP}"; }

header "1. 系统时间与时区"
date
timedatectl 2>/dev/null || date && cat /etc/localtime 2>/dev/null | od -c | head
echo "--- 硬件时钟 ---"
hwclock --show 2>/dev/null || echo "hwclock 不可用"

header "2. NTP 同步状态"
echo "--- chronyc 状态 ---"
if command -v chronyc &>/dev/null; then
  chronyc tracking 2>/dev/null
  chronyc sources -v 2>/dev/null  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | head -20
  echo "--- 时间偏移 ---"
  chronyc tracking 2>/dev/null | grep -E "(System time|RMS offset|Stratum)"
else
  echo "chronyc 不可用"
fi

echo "--- ntpq 状态 ---"
if command -v ntpq &>/dev/null; then
  ntpq -p 2>/dev/null | head -10
else
  echo "ntpq 不可用"
fi

echo "--- timedatectl NTP ---"
timedatectl show 2>/dev/null | grep -E "NTP|Time|TimeZone|Synchronized"

header "3. 容器日志大小（全量统计）"
python3 - <<'PYEOF'
import os, glob

log_dir = "/var/lib/docker/containers"
if not os.path.isdir(log_dir):
    print("容器日志目录不存在")
else:
    items = []
    for log_file in glob.glob(f"{log_dir}/*/*.log"):
        try:
            size = os.path.getsize(log_file)
            cid = os.path.basename(os.path.dirname(log_file))[:12]
            items.append((size, cid, log_file))
        except:
            pass
    items.sort(reverse=True)
    
    total = sum(s for s,_,_ in items)
    print(f"容器日志总大小: {total/1024/1024:.1f} MB ({len(items)} 个容器)")
    print(f"\n{'容器ID':<14} {'大小':>10}  {'路径'}")
    for size, cid, path in items[:20]:
        print(f"{cid:<14} {size/1024/1024:>9.1f}M  {path}")
    
    # 警告超大日志
    for size, cid, path in items:
        if size > 1024*1024*1024:  # >1GB
            print(f"\n⚠ 超大日志: {cid} = {size/1024/1024/1024:.2f} GB")
PYEOF

header "4. Docker 日志驱动配置"
echo "--- daemon.json 日志配置 ---"
cat /etc/docker/daemon.json 2>/dev/null | python3 -c "
import sys,json
try:
  d = json.load(sys.stdin)
  print('log-driver:', d.get('log-driver','json-file (默认)'))
  print('log-opts:', d.get('log-opts','未配置'))
except:
  print('daemon.json 无法解析')
" 2>/dev/null || echo "daemon.json 不存在，使用默认 json-file 驱动"

header "5. 磁盘空间（日志目录）"
df -h /var/lib/docker/containers/ 2>/dev/null
df -h /var/log/ 2>/dev/null
echo "--- /var/log 目录大小 ---"
du -sh /var/log/* 2>/dev/null | sort -rh | head -15

header "6. 证书时效检查"
python3 - <<'PYEOF'
import ssl, socket, datetime, os, glob, subprocess

def check_cert_file(path):
    try:
        r = subprocess.run(
            ["openssl", "x509", "-noout", "-dates", "-subject", "-in", path],
            capture_output=True, text=True, timeout=5
        )
        if r.returncode == 0:
            return r.stdout.strip()
    except:
        pass
    return None

# Docker TLS 证书
cert_dirs = ["/etc/docker", "/root/.docker", os.path.expanduser("~/.docker")]
for d in cert_dirs:
    for cert in glob.glob(f"{d}/*.crt") + glob.glob(f"{d}/*.pem"):
        info = check_cert_file(cert)
        if info:
            print(f"\n证书: {cert}")
            print(info)

# Registry 证书
registry_certs = glob.glob("/etc/docker/certs.d/**/*.crt", recursive=True)
for cert in registry_certs[:5]:
    info = check_cert_file(cert)
    if info:
        print(f"\nRegistry 证书: {cert}")
        print(info)

# 系统时间 vs 今天
now = datetime.datetime.utcnow()
print(f"\n当前 UTC 时间: {now.strftime('%Y-%m-%d %H:%M:%S')}")
print("提示：若证书 notAfter 早于当前时间，证书已过期")
PYEOF

header "7. logrotate 配置检查"
echo "--- /etc/logrotate.d/docker ---"
cat /etc/logrotate.d/docker 2>/dev/null || echo "未找到 docker logrotate 配置"
echo "--- /etc/logrotate.conf ---"
grep -A3 "rotate\|size\|compress" /etc/logrotate.conf 2>/dev/null  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | head -20

header "8. systemd journald 配置"
cat /etc/systemd/journald.conf 2>/dev/null | grep -vE "^#|^$"
echo "--- journald 磁盘用量 ---"
journalctl --disk-usage 2>/dev/null

header "9. 容器时间检查"
if [ -n "$CONTAINER" ]; then
  echo "--- 容器内时间 ---"
  docker exec "$CONTAINER" date 2>/dev/null
  echo "--- 宿主机时间 ---"
  date
  echo "--- 时间差（秒）---"
  python3 -c "
import subprocess, datetime
try:
  r = subprocess.run(['docker','exec','$CONTAINER','date','+%s'], capture_output=True, text=True)
  container_ts = int(r.stdout.strip())
  host_ts = int(datetime.datetime.now().timestamp())
  diff = abs(host_ts - container_ts)
  print(f'时间差: {diff} 秒')
  if diff > 60:
    print(f'⚠ 时间偏移超过60秒！可能影响证书校验和任务调度')
except Exception as e:
  print(f'时间差计算失败: {e}')
" 2>/dev/null
  
  echo "--- 容器日志（最后50行）---"
  docker logs --tail 50 --timestamps "$CONTAINER" 2>&1
fi

header "10. 最近相关日志错误"
journalctl $JOURNAL_TIME_ARGS"$TIME_SINCE" 2>/dev/null | grep -iE "(ntp|chrony|time|cert|certificate|tls|x509)" | tail -30 \
  || grep -iE "(ntp|time|cert|tls)" /var/log/messages 2>/dev/null | tail -20

echo -e "\n${SEP}\n[诊断采集完成 - logtime]\n时间: $(date '+%Y-%m-%d %H:%M:%S')\n${SEP}"
