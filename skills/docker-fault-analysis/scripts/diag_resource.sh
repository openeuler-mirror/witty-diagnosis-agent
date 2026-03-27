#!/usr/bin/env bash
# diag_resource.sh — 资源限制故障诊断（OOM / 磁盘 / fd 限制）
# 使用：bash diag_resource.sh [container_name_or_id]

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

header "1. 内存概览"
free -h
echo "--- /proc/meminfo 关键字段 ---"
grep -E "^(MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree|Cached|Buffers|Committed_AS|CommitLimit)" /proc/meminfo

header "2. OOM 事件检测"
echo "--- dmesg OOM（最近100行）---"
dmesg --time-format iso 2>/dev/null | grep -iE "(oom|killed process|out of memory)" | tail -30 \
  || dmesg | grep -iE "(oom|killed process|out of memory)" | tail -30
echo "--- journalctl OOM（最近24小时）---"
journalctl $JOURNAL_TIME_ARGS"$TIME_SINCE" 2>/dev/null | grep -iE "(oom|killed process|out of memory)" | tail -30
echo "--- /var/log/messages OOM ---"
grep -iE "(oom|killed process|out of memory)" /var/log/messages 2>/dev/null | tail -30

header "3. CPU 负载"
uptime
echo "--- top 快照（batch，1次，20进程）---"
top -b -n1 | head -30

header "4. 磁盘空间"
df -h
echo "--- Docker 数据目录 ---"
du -sh /var/lib/docker/ 2>/dev/null
du -sh /var/lib/docker/containers/ 2>/dev/null
du -sh /var/lib/docker/overlay2/ 2>/dev/null
echo "--- inode 使用率 ---"
df -i | grep -v "tmpfs\|udev"
echo "--- 已删除但仍被进程持有的文件 (Top 10) ---"
if command -v lsof >/dev/null 2>&1; then
  lsof +L1 2>/dev/null | head -n 1
  lsof +L1 2>/dev/null | grep -v "COMMAND" | sort -rnk7 | head -10
else
  echo "lsof 命令未安装"
fi

header "5. Docker 磁盘用量 (docker system df)"
docker system df 2>/dev/null

header "6. 容器日志大小（Top 10）"
find /var/lib/docker/containers/ -name "*.log" -printf "%s %p\n" 2>/dev/null \
  | sort -rn | head -10 \
  | awk '{printf "%.1f MB  %s\n", $1/1024/1024, $2}'

header "7. 文件描述符限制"
echo "--- 系统级 fd 限制 ---"
cat /proc/sys/fs/file-max
cat /proc/sys/fs/file-nr
echo "--- Docker 进程 fd 限制 ---"
DOCKER_PID=$(pgrep -f "dockerd" | head -1)
if [ -n "$DOCKER_PID" ]; then
  echo "dockerd PID: $DOCKER_PID"
  cat /proc/$DOCKER_PID/limits 2>/dev/null | grep -E "(open files|processes|max)"
  ls /proc/$DOCKER_PID/fd 2>/dev/null | wc -l | xargs echo "当前已打开 fd 数:"
fi
echo "--- /etc/security/limits.conf ---"
grep -vE "^#|^$" /etc/security/limits.conf 2>/dev/null
grep -r "." /etc/security/limits.d/ 2>/dev/null | grep -vE "^.*:#|^.*:$"

header "8. 进程数限制"
ulimit -u
cat /proc/sys/kernel/pid_max
echo "当前进程总数: $(ps aux | wc -l)"

header "9. swap 状态"
swapon --show 2>/dev/null || cat /proc/swaps

header "10. cgroup 资源配额（dockerd管理的容器）"
python3 - <<'PYEOF'
import os, glob

cgroup_paths = [
    "/sys/fs/cgroup/memory/docker",
    "/sys/fs/cgroup/docker",  # cgroup v2
]

def read_file(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except:
        return "N/A"

found = False
for base in cgroup_paths:
    if not os.path.isdir(base):
        continue
    for container_dir in glob.glob(f"{base}/*"):
        if not os.path.isdir(container_dir):
            continue
        cid = os.path.basename(container_dir)[:12]
        mem_limit = read_file(f"{container_dir}/memory.limit_in_bytes")
        mem_usage = read_file(f"{container_dir}/memory.usage_in_bytes")
        oom_ctrl  = read_file(f"{container_dir}/memory.oom_control")
        cpu_shares= read_file(f"{container_dir}/cpu.shares")
        cpu_quota = read_file(f"{container_dir}/cpu.cfs_quota_us")
        try:
            limit_mb = int(mem_limit) // (1024*1024)
            usage_mb = int(mem_usage) // (1024*1024)
            limit_str = f"{limit_mb} MB" if limit_mb < 9000000 else "无限制"
            usage_str = f"{usage_mb} MB"
        except:
            limit_str, usage_str = mem_limit, mem_usage
        print(f"容器 {cid}: 内存限制={limit_str}, 使用={usage_str}, CPU shares={cpu_shares}, CPU quota={cpu_quota}")
        # oom_control 中检查 oom_kill_disable
        if "oom_kill_disable 1" in oom_ctrl:
            print(f"  ⚠ OOM Killer 已禁用")
        found = True

# cgroup v2
v2_base = "/sys/fs/cgroup/system.slice"
if os.path.isdir(v2_base):
    for entry in glob.glob(f"{v2_base}/docker-*.scope"):
        cid = os.path.basename(entry).replace("docker-","").replace(".scope","")[:12]
        mem_max  = read_file(f"{entry}/memory.max")
        mem_curr = read_file(f"{entry}/memory.current")
        cpu_max  = read_file(f"{entry}/cpu.max")
        print(f"容器(v2) {cid}: mem.max={mem_max}, mem.current={mem_curr}, cpu.max={cpu_max}")
        found = True

if not found:
    print("未找到 cgroup 容器目录，可能容器未运行或路径不同")
PYEOF

if [ -n "$CONTAINER" ]; then
  header "11. 容器资源状态 (${CONTAINER})"
  docker stats --no-stream "$CONTAINER" 2>/dev/null
  echo "--- 容器 inspect 资源配置 ---"
  docker inspect "$CONTAINER" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data:
  c = data[0]
  state = c.get('State', {})
  hc = c.get('HostConfig', {})
  print('OOMKilled:', state.get('OOMKilled'))
  print('ExitCode:', state.get('ExitCode'))
  print('Memory:', hc.get('Memory'))
  print('MemorySwap:', hc.get('MemorySwap'))
  print('CpuQuota:', hc.get('CpuQuota'))
  print('CpuShares:', hc.get('CpuShares'))
  print('PidsLimit:', hc.get('PidsLimit'))
  print('Ulimits:', hc.get('Ulimits'))
" 2>/dev/null

  echo "--- 容器日志（最后50行，含时间戳）---"
  docker logs --tail 50 --timestamps "$CONTAINER" 2>&1
fi

header "12. 最近重启的容器（ExitCode != 0）"
docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.RunningFor}}' 2>/dev/null | grep -v "Up "  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | head -20

echo -e "\n${SEP}\n[诊断采集完成 - resource]\n时间: $(date '+%Y-%m-%d %H:%M:%S')\n${SEP}"
