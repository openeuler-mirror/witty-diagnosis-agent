#!/usr/bin/env bash
# diag_network.sh — 网络故障诊断
# 用途：iptables规则、bridge/veth接口、端口占用、网络命名空间、DNS
# 使用：bash diag_network.sh [container_name_or_id]

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

header "1. 宿主机网络接口"
ip link show
echo "--- bridge 接口 ---"
ip link show type bridge 2>/dev/null
brctl show 2>/dev/null || echo "brctl 不可用"

header "2. Docker 网络列表"
docker network ls 2>/dev/null
echo "--- docker0 bridge IP ---"
ip addr show docker0 2>/dev/null || echo "docker0 不存在"

header "3. iptables 规则（DOCKER 相关）"
echo "--- filter 表 DOCKER 链 ---"
iptables -L DOCKER -n -v 2>/dev/null || echo "DOCKER 链不存在"
echo "--- DOCKER-ISOLATION 链 ---"
iptables -L DOCKER-ISOLATION-STAGE-1 -n -v 2>/dev/null
echo "--- nat 表 DOCKER 链 ---"
iptables -t nat -L DOCKER -n -v 2>/dev/null || echo "nat DOCKER 链不存在"
echo "--- nat 表 POSTROUTING (MASQUERADE 规则) ---"
iptables -t nat -L POSTROUTING -n -v 2>/dev/null | grep -i MASQUERADE || echo "无 MASQUERADE 规则"
echo "--- FORWARD 策略 ---"
iptables -L FORWARD -n -v 2>/dev/null  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | head -20
echo "--- ip_forward 状态 ---"
cat /proc/sys/net/ipv4/ip_forward
echo "--- net.bridge.bridge-nf-call-iptables ---"
sysctl net.bridge.bridge-nf-call-iptables net.bridge.bridge-nf-call-ip6tables 2>/dev/null

header "4. nftables（若系统使用 nft 替代 iptables）"
if command -v nft &>/dev/null; then
  nft list ruleset 2>/dev/null | grep -A5 "docker\|container\|bridge" | head -40
else
  echo "nft 不可用"
fi

header "5. 端口占用（ss）"
ss -ltnp 2>/dev/null | head -40
echo "--- 端口占用（netstat 备选）---"
netstat -ltnp 2>/dev/null | head -40 || echo "netstat 不可用"

header "6. veth 接口对应关系"
python3 - <<'PYEOF'
import subprocess, json, re

def run(cmd):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return r.stdout.strip()
    except:
        return ""

# 获取所有 veth 接口
links = run("ip link show type veth")
veths = re.findall(r'\d+: (veth\w+)@', links)
print(f"找到 veth 接口: {veths}")

# 尝试匹配容器
try:
    containers = json.loads(run("docker ps -q | xargs docker inspect 2>/dev/null") or "[]")
except:
    containers = []

for c in containers:
    name = c.get("Name","?").lstrip("/")
    pid = c.get("State",{}).get("Pid",0)
    if pid and pid > 0:
        iflink = run(f"nsenter -t {pid} -n ip link 2>/dev/null | grep -oP 'eth0@if\\K\\d+'")
        print(f"容器 {name} (pid={pid}): eth0 对应宿主机 ifindex={iflink}")
PYEOF

header "7. 网络命名空间检查"
echo "--- /var/run/docker/netns ---"
ls -la /var/run/docker/netns/ 2>/dev/null || echo "目录不存在"
echo "--- ip netns ---"
ip netns list 2>/dev/null  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | head -20

header "8. DNS 配置"
echo "--- 宿主机 /etc/resolv.conf ---"
cat /etc/resolv.conf
echo "--- Docker daemon DNS 配置 ---"
cat /etc/docker/daemon.json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print('dns:', d.get('dns','未配置'))" 2>/dev/null || echo "daemon.json 不存在或无 DNS 配置"

header "9. 防火墙状态"
if command -v firewall-cmd &>/dev/null; then
  echo "--- firewalld 状态 ---"
  firewall-cmd --state 2>/dev/null
  firewall-cmd --list-all 2>/dev/null  | { [ -n "$KEYWORD" ] && grep -i "$KEYWORD" || cat; } | head -20
else
  echo "firewalld 未安装"
fi

header "10. 容器间通信测试（docker network inspect）"
docker network inspect bridge 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data:
  n = data[0]
  print('网络名:', n.get('Name'))
  print('驱动:', n.get('Driver'))
  print('子网:', n.get('IPAM',{}).get('Config',[{}])[0].get('Subnet','?'))
  containers = n.get('Containers', {})
  print(f'接入容器数: {len(containers)}')
  for cid, info in list(containers.items())[:10]:
    print(f'  {info.get(\"Name\",\"?\")} : {info.get(\"IPv4Address\",\"?\")}')
" 2>/dev/null

header "11. 所有 Docker 网络详情"
docker network ls -q 2>/dev/null | while read nid; do
  name=$(docker network inspect "$nid" --format '{{.Name}}' 2>/dev/null)
  driver=$(docker network inspect "$nid" --format '{{.Driver}}' 2>/dev/null)
  containers=$(docker network inspect "$nid" --format '{{len .Containers}}' 2>/dev/null)
  echo "网络: $name  驱动: $driver  容器数: $containers"
done

if [ -n "$CONTAINER" ]; then
  header "12. 容器网络配置 (${CONTAINER})"
  docker inspect "$CONTAINER" 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data:
  c = data[0]
  nets = c.get('NetworkSettings',{})
  print('Ports:', json.dumps(nets.get('Ports',{}), indent=2))
  for netname, info in nets.get('Networks',{}).items():
    print(f'Network: {netname}')
    print(f'  IP: {info.get(\"IPAddress\")}')
    print(f'  Gateway: {info.get(\"Gateway\")}')
    print(f'  MacAddress: {info.get(\"MacAddress\")}')
    print(f'  NetworkID: {info.get(\"NetworkID\",\"\")[:12]}')
" 2>/dev/null

  echo "--- 容器内网络状态 ---"
  docker exec "$CONTAINER" ip addr 2>/dev/null || echo "容器未运行或 ip 命令不可用"
  docker exec "$CONTAINER" ip route 2>/dev/null
  docker exec "$CONTAINER" cat /etc/resolv.conf 2>/dev/null

  echo "--- 容器日志（最后30行）---"
  docker logs --tail 30 --timestamps "$CONTAINER" 2>&1
fi

header "13. dmesg 网络相关异常"
dmesg --time-format iso 2>/dev/null | grep -iE "(veth|bridge|iptables|nftables|net namespace|docker|conntrack)" | tail -30 \
  || dmesg | grep -iE "(veth|bridge|iptables|docker)" | tail -30

echo -e "\n${SEP}\n[诊断采集完成 - network]\n时间: $(date '+%Y-%m-%d %H:%M:%S')\n${SEP}"
