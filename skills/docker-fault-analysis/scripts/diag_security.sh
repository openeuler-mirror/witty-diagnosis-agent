#!/usr/bin/env bash
# diag_security.sh — 权限/安全故障诊断
# 用途：docker 用户组、SELinux/AppArmor 审计日志、seccomp、capability
# 使用：bash diag_security.sh [container_name_or_id] [username]

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
USERNAME="${2:-}"
SEP="========================================"

header() { echo -e "\n${SEP}\n[$1]\n${SEP}"; }

header "1. Docker 用户组与权限"
echo "--- docker 组成员 ---"
getent group docker 2>/dev/null || grep "^docker:" /etc/group
echo "--- dockerd socket 权限 ---"
ls -la /var/run/docker.sock 2>/dev/null
echo "--- docker 二进制权限 ---"
ls -la $(which docker 2>/dev/null) 2>/dev/null

if [ -n "$USERNAME" ]; then
  echo "--- 用户 $USERNAME 的组 ---"
  id "$USERNAME" 2>/dev/null
  groups "$USERNAME" 2>/dev/null
fi

header "2. SELinux 状态与策略"
echo "--- SELinux 模式 ---"
getenforce 2>/dev/null || echo "SELinux 未安装"
sestatus 2>/dev/null | head -15

echo "--- docker 相关 SELinux 布尔值 ---"
getsebool -a 2>/dev/null | grep -iE "(docker|container|virt)"  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | head -20

echo "--- SELinux 上下文: dockerd ---"
DOCKER_PID=$(pgrep dockerd | head -1)
[ -n "$DOCKER_PID" ] && ls -Z /proc/$DOCKER_PID/exe 2>/dev/null || echo "dockerd 未运行"

header "3. audit 日志 — AVC 拒绝（最近200条）"
if [ -f /var/log/audit/audit.log ]; then
  echo "--- 所有 AVC denied 事件（近1000行）---"
  tail -1000 /var/log/audit/audit.log | grep "avc:.*denied"  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | tail -50

  echo "--- AVC denied 按 comm 统计 ---"
  grep "avc:.*denied" /var/log/audit/audit.log | grep -oP 'comm="\K[^"]+' | sort | uniq -c | sort -rn  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | head -20

  echo "--- AVC denied 按 tcontext 统计 ---"
  grep "avc:.*denied" /var/log/audit/audit.log | grep -oP 'tcontext=\K\S+' | sort | uniq -c | sort -rn  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | head -20

  echo "--- 最近 docker/container 相关 AVC ---"
  grep "avc:.*denied" /var/log/audit/audit.log | grep -iE "(docker|container|svirt)" | tail -30
else
  echo "audit.log 不存在，尝试 journalctl..."
  journalctl $JOURNAL_TIME_ARGS"$TIME_SINCE" 2>/dev/null | grep -iE "avc.*denied|selinux"  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | tail -50
fi

header "4. ausearch — 最近 AVC 事件（若 ausearch 可用）"
if command -v ausearch &>/dev/null; then
  ausearch -m AVC -ts recent 2>/dev/null  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | tail -50
  echo "--- docker/container AVC ---"
  ausearch -m AVC -c docker -ts today 2>/dev/null | tail -30
  ausearch -m AVC -c runc -ts today 2>/dev/null | tail -20
else
  echo "ausearch 不可用"
fi

header "5. AppArmor 状态"
if command -v apparmor_status &>/dev/null; then
  apparmor_status 2>/dev/null
  echo "--- AppArmor 日志 ---"
  dmesg | grep -i "apparmor" | tail -20
  journalctl $JOURNAL_TIME_ARGS"$TIME_SINCE" 2>/dev/null | grep -i "apparmor" | tail -20
else
  echo "AppArmor 未安装"
fi

header "6. Docker daemon 安全配置"
echo "--- /etc/docker/daemon.json ---"
cat /etc/docker/daemon.json 2>/dev/null | python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
  keys = ['selinux-enabled','userns-remap','seccomp-profile','no-new-privileges',
          'live-restore','userland-proxy','log-driver']
  for k in keys:
    if k in d:
      print(f'{k}: {d[k]}')
  print('完整配置:', json.dumps(d, indent=2))
except:
  print('daemon.json 解析失败')
" 2>/dev/null || echo "daemon.json 不存在"

header "7. seccomp 状态"
echo "--- 默认 seccomp profile 位置 ---"
ls -la /etc/docker/seccomp* 2>/dev/null || echo "未找到自定义 seccomp profile"
echo "--- 内核 seccomp 支持 ---"
grep CONFIG_SECCOMP /boot/config-$(uname -r) 2>/dev/null || zcat /proc/config.gz 2>/dev/null | grep CONFIG_SECCOMP

header "8. capabilities 检查"
if [ -n "$CONTAINER" ]; then
  docker inspect "$CONTAINER" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data:
  hc = data[0].get('HostConfig', {})
  print('Privileged:', hc.get('Privileged'))
  print('CapAdd:', hc.get('CapAdd'))
  print('CapDrop:', hc.get('CapDrop'))
  print('SecurityOpt:', hc.get('SecurityOpt'))
  print('UsernsMode:', hc.get('UsernsMode'))
  print('User:', data[0].get('Config',{}).get('User'))
" 2>/dev/null
fi

header "9. 文件系统 ACL 与扩展属性（针对挂载目录）"
if [ -n "$CONTAINER" ]; then
  docker inspect "$CONTAINER" 2>/dev/null | python3 -c "
import sys,json,subprocess,os
data = json.load(sys.stdin)
if data:
  for m in data[0].get('Mounts',[]):
    src = m.get('Source','')
    if src and os.path.exists(src):
      print(f'--- {src} ---')
      r = subprocess.run(['ls','-laZ',src], capture_output=True, text=True)
      print(r.stdout[:500])
      r2 = subprocess.run(['getfattr','-n','security.selinux',src], capture_output=True, text=True)
      if r2.stdout:
        print('SELinux xattr:', r2.stdout)
" 2>/dev/null
fi

header "10. namespace 隔离状态"
if [ -n "$CONTAINER" ]; then
  PID=$(docker inspect --format '{{.State.Pid}}' "$CONTAINER" 2>/dev/null)
  if [ -n "$PID" ] && [ "$PID" != "0" ]; then
    echo "容器 PID: $PID"
    ls -la /proc/$PID/ns/ 2>/dev/null
    echo "--- 容器内用户 ---"
    docker exec "$CONTAINER" id 2>/dev/null
    docker exec "$CONTAINER" cat /proc/1/status 2>/dev/null | grep -E "^(Uid|Gid|Groups|CapInh|CapPrm|CapEff|CapBnd)"
  fi
fi

header "11. 最近权限相关系统日志"
journalctl $JOURNAL_TIME_ARGS"$TIME_SINCE" 2>/dev/null | grep -iE "(permission denied|access denied|operation not permitted|selinux|apparmor)" | tail -30 \
  || grep -iE "(permission denied|access denied|operation not permitted)" /var/log/messages 2>/dev/null | tail -30

echo -e "\n${SEP}\n[诊断采集完成 - security]\n时间: $(date '+%Y-%m-%d %H:%M:%S')\n${SEP}"
