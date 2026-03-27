#!/usr/bin/env bash
# diag_storage.sh — 文件系统/存储故障诊断
# 用途：卷挂载权限、overlay2状态、I/O性能、文件系统完整性
# 使用：bash diag_storage.sh [container_name_or_id]

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

header "1. 磁盘空间与 inode"
df -hT | grep -v "tmpfs\|devtmpfs\|overlay"
echo "--- inode 使用率 ---"
df -iT | grep -v "tmpfs\|devtmpfs\|overlay"

header "2. Docker 存储驱动与数据目录"
docker info 2>/dev/null | grep -E "Storage Driver|Docker Root Dir|Backing Filesystem|Data file|Metadata file|Pool Name"

header "3. overlay2 层状态"
echo "--- overlay2 目录总大小 ---"
du -sh /var/lib/docker/overlay2/ 2>/dev/null
echo "--- 层数量 ---"
ls /var/lib/docker/overlay2/ 2>/dev/null | wc -l | xargs echo "overlay2 层总数:"
echo "--- 最大的10个 overlay2 层 ---"
du -sh /var/lib/docker/overlay2/*/ 2>/dev/null | sort -rh | head -10
echo "--- diff 目录是否存在异常空层（大小为0）---"
find /var/lib/docker/overlay2/ -maxdepth 2 -name "diff" -empty 2>/dev/null | head -10

header "4. 文件系统挂载状态"
mount | grep -E "overlay|aufs|devicemapper|btrfs|zfs|xfs|ext4" | head -30
echo "--- /proc/mounts 中 docker 相关挂载 ---"
grep "docker\|overlay\|container" /proc/mounts | head -30

header "5. 卷挂载路径检查"
python3 - <<'PYEOF'
import subprocess, json, os

try:
    result = subprocess.run(["docker", "ps", "-q"], capture_output=True, text=True)
    container_ids = result.stdout.strip().split()
except:
    container_ids = []

if not container_ids:
    print("无运行中的容器")
else:
    for cid in container_ids[:20]:
        try:
            r = subprocess.run(["docker", "inspect", cid], capture_output=True, text=True)
            data = json.loads(r.stdout)
            if not data:
                continue
            c = data[0]
            name = c.get("Name","?").lstrip("/")
            mounts = c.get("Mounts", [])
            for m in mounts:
                src = m.get("Source","")
                dst = m.get("Destination","")
                mode = m.get("Mode","")
                rw = m.get("RW", True)
                exists = os.path.exists(src) if src else False
                perm = oct(os.stat(src).st_mode)[-4:] if exists else "N/A"
                owner = f"{os.stat(src).st_uid}:{os.stat(src).st_gid}" if exists else "N/A"
                selinux_label = "N/A"
                if exists:
                    try:
                        ls_z = subprocess.run(["ls", "-ldZ", src], capture_output=True, text=True).stdout.strip()
                        if ls_z:
                            selinux_label = ls_z.split()[3] if len(ls_z.split()) > 3 else "N/A"
                    except:
                        pass
                status = "OK" if exists else "⚠ 路径不存在"
                print(f"容器 {name}: {src} -> {dst}  mode={mode} rw={rw}  host_exists={status}  perm={perm}  owner={owner}  selinux={selinux_label}")
        except Exception as e:
            print(f"容器 {cid}: 检查失败 {e}")
PYEOF

header "6. I/O 性能采样（iostat 5秒）"
if command -v iostat &>/dev/null; then
  iostat -xd 1 5 2>/dev/null | tail -30
else
  echo "iostat 不可用，尝试 /proc/diskstats..."
  python3 - <<'PYEOF'
import time, re

def read_diskstats():
    stats = {}
    with open("/proc/diskstats") as f:
        for line in f:
            parts = line.split()
            if len(parts) >= 14:
                dev = parts[2]
                if re.match(r'^(sd|vd|nvme|xvd|hd)[a-z]$', dev):
                    stats[dev] = {
                        "reads": int(parts[3]),
                        "read_sectors": int(parts[5]),
                        "writes": int(parts[7]),
                        "write_sectors": int(parts[9]),
                        "io_ms": int(parts[12]),
                    }
    return stats

s1 = read_diskstats()
time.sleep(3)
s2 = read_diskstats()

print(f"{'设备':<12} {'读IOPS':>8} {'写IOPS':>8} {'读MB/s':>8} {'写MB/s':>8} {'util%':>7}")
for dev in s1:
    if dev not in s2:
        continue
    d1, d2 = s1[dev], s2[dev]
    reads  = d2["reads"] - d1["reads"]
    writes = d2["writes"] - d1["writes"]
    read_mb= (d2["read_sectors"] - d1["read_sectors"]) * 512 / 1024 / 1024 / 3
    write_mb=(d2["write_sectors"] - d1["write_sectors"]) * 512 / 1024 / 1024 / 3
    util   = min((d2["io_ms"] - d1["io_ms"]) / 3000 * 100, 100)
    print(f"{dev:<12} {reads/3:>8.1f} {writes/3:>8.1f} {read_mb:>8.2f} {write_mb:>8.2f} {util:>6.1f}%")
PYEOF
fi

header "7. iotop 快照（若可用）"
if command -v iotop &>/dev/null; then
  iotop -b -n 1 -P 2>/dev/null  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | head -20
else
  echo "iotop 不可用，跳过"
fi

header "8. 文件系统错误检查"
echo "--- dmesg 文件系统错误 ---"
dmesg --time-format iso 2>/dev/null | grep -iE "(ext4|xfs|btrfs|filesystem|i/o error|read error|write error|corrupt|journal)" | tail -30 \
  || dmesg | grep -iE "(ext4|xfs|btrfs|filesystem|i/o error|read error|write error|corrupt)" | tail -30
echo "--- /var/log/messages 文件系统错误 ---"
grep -iE "(ext4|xfs|i/o error|filesystem error|read error|corrupt)" /var/log/messages 2>/dev/null | tail -20

header "9. device mapper / LVM 状态（若使用）"
if docker info 2>/dev/null | grep -q "devicemapper"; then
  echo "--- Device Mapper 状态 ---"
  dmsetup info 2>/dev/null
  docker info 2>/dev/null | grep -A 20 "Storage Driver: devicemapper"
else
  echo "未使用 devicemapper 存储驱动"
fi

header "10. 磁盘 SMART 状态（若有 smartctl）"
if command -v smartctl &>/dev/null; then
  for disk in $(lsblk -dno NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}'); do
    echo "--- $disk ---"
    smartctl -H "$disk" 2>/dev/null | grep -E "(overall|PASSED|FAILED|result)"
  done
else
  echo "smartctl 不可用，跳过磁盘健康检查"
fi

if [ -n "$CONTAINER" ]; then
  header "11. 容器存储详情 (${CONTAINER})"
  docker inspect "$CONTAINER" 2>/dev/null | python3 -c "
import sys, json, os
data = json.load(sys.stdin)
if data:
  c = data[0]
  print('GraphDriver:', json.dumps(c.get('GraphDriver',{}), indent=2))
  print('Mounts:', json.dumps(c.get('Mounts',[]), indent=2))
" 2>/dev/null

  echo "--- 容器 rootfs 大小 ---"
  docker inspect "$CONTAINER" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data:
  layer = data[0].get('GraphDriver',{}).get('Data',{}).get('MergedDir','')
  if layer:
    print('MergedDir:', layer)
  else:
    print('MergedDir: 未找到')
" 2>/dev/null
fi

echo -e "\n${SEP}\n[诊断采集完成 - storage]\n时间: $(date '+%Y-%m-%d %H:%M:%S')\n${SEP}"
