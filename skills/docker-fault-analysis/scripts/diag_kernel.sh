#!/usr/bin/env bash
# diag_kernel.sh — 内核/系统调用故障诊断
# 用途：采集内核版本、cgroup/namespace、内核参数、SELinux/AppArmor/seccomp 状态及审计日志
# 使用：bash diag_kernel.sh [container_name_or_id]
# 兼容：CentOS 7/8/9、EulerOS、RHEL 系列

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

header "1. 宿主机内核版本与架构"
uname -r
uname -m
cat /etc/os-release 2>/dev/null | grep -E "^(NAME|VERSION)=" || cat /etc/redhat-release 2>/dev/null

header "2. Docker 版本与存储驱动"
docker version --format 'Server: {{.Server.Version}}  Client: {{.Client.Version}}' 2>/dev/null
docker info 2>/dev/null | grep -E "Storage Driver|Cgroup Driver|Cgroup Version|Kernel Version|Operating System"

header "3. cgroup 支持检查"
echo "--- /proc/cgroups (top 15) ---"
head -16 /proc/cgroups
echo "--- cgroup v1 挂载 ---"
mount | grep cgroup
echo "--- cgroup v2 检查 ---"
[ -f /sys/fs/cgroup/cgroup.controllers ] && cat /sys/fs/cgroup/cgroup.controllers || echo "cgroup v2 未启用"

header "4. namespace 支持检查"
ls /proc/1/ns/ 2>/dev/null
for ns in ipc mnt net pid user uts; do
  [ -e /proc/1/ns/$ns ] && echo "$ns: OK" || echo "$ns: MISSING"
done

header "5. overlay/overlay2 文件系统支持"
grep -E "overlay" /proc/filesystems || echo "overlay 未在 /proc/filesystems"
modinfo overlay 2>/dev/null | grep -E "^(filename|version|description)" || echo "overlay 模块信息获取失败"
lsmod | grep overlay || echo "overlay 模块未加载"
echo "--- XFS ftype 检查 ---"
DOCKER_ROOT=$(docker info 2>/dev/null | grep "Docker Root Dir" | awk -F': ' '{print $2}')
if [ -n "$DOCKER_ROOT" ] && df -T "$DOCKER_ROOT" 2>/dev/null | grep -q xfs; then
  xfs_info "$DOCKER_ROOT" 2>/dev/null | grep ftype || echo "未找到 ftype 信息或非 XFS"
else
  echo "Docker 根目录 (${DOCKER_ROOT:-未找到}) 非 XFS 或未获取到路径"
fi

header "6. 关键 sysctl 参数"
sysctl fs.file-max fs.file-nr fs.inotify.max_user_instances fs.inotify.max_user_watches \
       vm.max_map_count vm.swappiness kernel.pid_max net.ipv4.ip_forward \
       net.bridge.bridge-nf-call-iptables 2>/dev/null

header "7. SELinux 状态"
if command -v getenforce &>/dev/null; then
  echo "SELinux状态: $(getenforce)"
  sestatus 2>/dev/null  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | head -20
else
  echo "SELinux 未安装"
fi

header "8. AppArmor 状态"
if command -v apparmor_status &>/dev/null; then
  apparmor_status 2>/dev/null  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | head -20
else
  echo "AppArmor 未安装"
fi

header "9. dmesg 最近100行（过滤关键异常）"
dmesg --time-format iso 2>/dev/null | grep -iE "(overlay|cgroup|namespace|oom|killed|panic|call trace|docker|containerd|runc)"  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | tail -50 \
  || dmesg | grep -iE "(overlay|cgroup|namespace|oom|killed|panic|docker|containerd|runc)"  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | tail -50

header "10. audit 日志（SELinux AVC 拒绝，最近50条）"
if command -v ausearch &>/dev/null; then
  echo "--- ausearch (AVC recent) ---"
  ausearch -m AVC -ts recent 2>/dev/null | tail -50
else
  echo "ausearch 命令不可用"
fi
if [ -f /var/log/audit/audit.log ]; then
  grep "avc:.*denied" /var/log/audit/audit.log  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | tail -50
  echo "--- AVC denied 统计 ---"
  grep "avc:.*denied" /var/log/audit/audit.log | grep -oP 'comm="\K[^"]+' | sort | uniq -c | sort -rn  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | head -20
else
  echo "audit.log 不存在，尝试 journalctl..."
  journalctl -k $JOURNAL_TIME_ARGS"$TIME_SINCE" 2>/dev/null | grep -iE "avc|denied|overlay|cgroup"  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | tail -50
fi

header "11. systemd-journalctl 内核消息（最近1小时）"
journalctl -k $JOURNAL_TIME_ARGS"$TIME_SINCE" 2>/dev/null | grep -iE "(error|fail|denied|overlay|cgroup|namespace|oom)"  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | tail -50 \
  || echo "journalctl 不可用，已在 dmesg 中采集"

if [ -n "$CONTAINER" ]; then
  header "12. 容器详情 (${CONTAINER})"
  docker inspect "$CONTAINER" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data:
  c = data[0]
  state = c.get('State', {})
  hc = c.get('HostConfig', {})
  print('Status:', state.get('Status'))
  print('ExitCode:', state.get('ExitCode'))
  print('Error:', state.get('Error'))
  print('OOMKilled:', state.get('OOMKilled'))
  print('StartedAt:', state.get('StartedAt'))
  print('FinishedAt:', state.get('FinishedAt'))
  print('RestartPolicy:', hc.get('RestartPolicy'))
  print('SecurityOpt:', hc.get('SecurityOpt'))
  print('Privileged:', hc.get('Privileged'))
  print('CapAdd:', hc.get('CapAdd'))
  print('CapDrop:', hc.get('CapDrop'))
" 2>/dev/null

  echo "--- 容器日志（最后50行）---"
  docker logs --tail 50 --timestamps "$CONTAINER" 2>&1

  echo "--- docker events（最近1小时）---"
  docker events $JOURNAL_TIME_ARGS"$TIME_SINCE" --until "0s" --filter "container=$CONTAINER" 2>/dev/null | tail -30
fi

header "13. Docker daemon 日志（最近50条错误）"
journalctl -u docker $JOURNAL_TIME_ARGS"$TIME_SINCE" 2>/dev/null | grep -iE "(error|fail|overlay|cgroup|panic)"  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | tail -50 \
  || grep -iE "(error|fail|overlay|cgroup)" /var/log/docker.log 2>/dev/null  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | tail -50 \
  || echo "无法读取 docker daemon 日志"

header "14. containerd 日志（最近50条错误）"
journalctl -u containerd $JOURNAL_TIME_ARGS"$TIME_SINCE" 2>/dev/null | grep -iE "(error|fail|overlay|cgroup|runc)"  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | tail -50 \
  || echo "containerd 日志不可用"

echo -e "\n${SEP}\n[诊断采集完成 - kernel]\n时间: $(date '+%Y-%m-%d %H:%M:%S')\n${SEP}"
