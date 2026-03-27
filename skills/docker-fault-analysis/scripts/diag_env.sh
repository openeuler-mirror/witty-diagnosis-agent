#!/usr/bin/env bash
# env_collect.sh — Docker 故障环境基础信息全量采集
# 用途：在进行深度分析前，快速获取 OS、内核、Docker 状态及系统资源的全局快照。
# 使用：bash env_collect.sh [options]

START_TIME=""
END_TIME=""

show_help() {
  echo "Usage: $(basename $0) [options]"
  echo "Options:"
  echo "  -s, --start-time <time> Start time for logs (e.g. \"2023-10-01 12:00:00\", \"1 hour ago\")"
  echo "  -e, --end-time <time>   End time for logs (e.g. \"2023-10-01 13:00:00\")"
  echo "  -h, --help              Show this help message"
  exit 0
}

while [[ "$#" -gt 0 ]]; do
  case $1 in
    -s|--start-time) START_TIME="$2"; shift 2 ;;
    -e|--end-time) END_TIME="$2"; shift 2 ;;
    -h|--help) show_help ;;
    *) shift ;;
  esac
done

JOURNAL_TIME_ARGS=""
[ -n "$START_TIME" ] && JOURNAL_TIME_ARGS="--since \"$START_TIME\""
[ -n "$END_TIME" ] && JOURNAL_TIME_ARGS="$JOURNAL_TIME_ARGS --until \"$END_TIME\""
[ -z "$JOURNAL_TIME_ARGS" ] && JOURNAL_TIME_ARGS="--since \"24 hours ago\""

SEP="========================================"
header() { echo -e "\n${SEP}\n[$1]\n${SEP}"; }

header "1. 操作系统与内核信息"
cat /etc/os-release 2>/dev/null | grep -E "^(NAME|VERSION|PRETTY_NAME)="
uname -r
uname -m
uptime

header "2. Docker 版本与全局配置"
docker version 2>/dev/null
echo "--- Docker Info ---"
docker info 2>/dev/null | grep -E "Server Version|Storage Driver|Logging Driver|Cgroup Driver|Plugins|Runtimes|Registry Mirrors|Live Restore|Docker Root Dir|Debug Mode"
echo "--- Daemon.json ---"
[ -f /etc/docker/daemon.json ] && cat /etc/docker/daemon.json || echo "No daemon.json found"
echo "--- Systemd Drop-in Configs (/etc/systemd/system/docker.service.d/) ---"
if [ -d /etc/systemd/system/docker.service.d ]; then
  find /etc/systemd/system/docker.service.d/ -name "*.conf" -exec echo "File: {}" \; -exec cat {} \; -exec echo "" \;
else
  echo "No systemd drop-in configs found"
fi

header "3. Docker 运行状态与基础信息"
systemctl status docker --no-pager 2>/dev/null | head -n 10
echo "--- Docker/Containerd Process Resource Usage ---"
ps -eo pid,ppid,%cpu,%mem,vsz,rss,stat,start,time,command --sort=-%cpu | grep -iE 'dockerd|containerd' | grep -v grep | head -n 10
echo "--- Running Containers Summary ---"
docker ps -a --format 'table {{.ID}}\t{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.State}}' 2>/dev/null | head -n 20

header "4. 故障日志采集 (Docker及系统级错误)"
echo "--- Docker Daemon Logs (Errors & Warnings) ---"
# Using eval to properly expand JOURNAL_TIME_ARGS
eval "journalctl -u docker $JOURNAL_TIME_ARGS -p warning..emerg --no-pager 2>/dev/null | tail -n 50"
echo "--- System Kernel Logs (OOM/Panic/Hardware) ---"
eval "dmesg -T 2>/dev/null | grep -iE 'oom|killed|error|fail|panic|warn|docker|containerd' | tail -n 50"

header "5. 基础资源信息 (CPU/内存/磁盘/网络)"
echo "--- CPU & Memory ---"
free -h
echo ""
top -b -n 1 | head -n 5
echo "--- Disk Usage ---"
df -hT | grep -E "^/dev/|overlay|tmpfs"
echo "--- Network Interfaces ---"
ip -brief address show
