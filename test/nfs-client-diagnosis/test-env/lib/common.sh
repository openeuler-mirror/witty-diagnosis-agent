#!/bin/bash
# ============================================================
# 通用函数库 — nfs-client-diagnosis 故障注入测试框架
# ============================================================

# ---------- 容器常量 ----------
SERVER_CONTAINER="nfs-fault-server"
CLIENT_CONTAINER="nfs-fault-client"
COMPOSE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_HOST="nfs-server"
MOUNT_DIR="/mnt/nfs-test"

# ---------- 颜色输出 ----------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()   { echo -e "${RED}[ERROR]${NC} $*"; }
header(){ echo -e "\n${CYAN}══════════════════════════════════════════════${NC}"; }

# ---------- 容器执行函数 ----------
# 用法: exec_srv <command>        # 在 server 容器执行
#       exec_cli <command>        # 在 client 容器执行
exec_srv() {
    docker exec "$SERVER_CONTAINER" bash -c "$1"
}
exec_cli() {
    docker exec "$CLIENT_CONTAINER" bash -c "$1"
}

# ---------- 获取容器信息 ----------
get_server_ip() {
    docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$SERVER_CONTAINER" 2>/dev/null || echo ""
}
get_client_ip() {
    docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CLIENT_CONTAINER" 2>/dev/null || echo ""
}

# ---------- 环境检查 ----------
check_env() {
    # 检查 Docker 可用
    if ! command -v docker &>/dev/null; then
        err "Docker 不可用，请先安装 Docker"
        exit 1
    fi

    # 检查 docker compose
    if ! docker compose version &>/dev/null && ! docker-compose --version &>/dev/null; then
        err "docker compose 不可用"
        exit 1
    fi

    # 检查容器是否运行
    for c in "$SERVER_CONTAINER" "$CLIENT_CONTAINER"; do
        if ! docker ps --format '{{.Names}}' | grep -q "^$c$"; then
            err "容器 $c 未运行！请先执行: bash setup.sh"
            exit 1
        fi
    done
}

# ---------- 等待 NFS 服务就绪 ----------
wait_nfs_server() {
    local timeout=${1:-30}
    info "等待 NFS Server 就绪（超时 ${timeout}s）..."
    for i in $(seq 1 "$timeout"); do
        if exec_srv 'rpcinfo -p localhost 2>/dev/null | grep -q nfs' 2>/dev/null; then
            ok "NFS Server 就绪（${i}s）"
            return 0
        fi
        sleep 1
    done
    err "NFS Server 未在 ${timeout}s 内就绪"
    exec_srv 'rpcinfo -p localhost 2>/dev/null' || true
    return 1
}

# ---------- NFS 挂载 / 卸载 ----------
nfs_mount() {
    local mount_opts="${1:-vers=3,hard,timeo=600,retrans=2}"
    local export_path="/exports"
    # NFSv4 使用伪文件系统根路径 (fsid=0 映射)
    if echo "$mount_opts" | grep -qE 'vers=4\.'; then
        export_path="/"
    fi
    info "挂载 NFS (${SERVER_HOST}:${export_path} → ${MOUNT_DIR}) [${mount_opts}]"
    exec_cli "mkdir -p ${MOUNT_DIR} && mount -t nfs -o ${mount_opts} ${SERVER_HOST}:${export_path} ${MOUNT_DIR} 2>&1"
}

nfs_umount() {
    info "卸载 ${MOUNT_DIR}"
    exec_cli "umount -f ${MOUNT_DIR} 2>/dev/null; umount -l ${MOUNT_DIR} 2>/dev/null; true"
}

nfs_ensure_mounted() {
    local mount_opts="${1:-vers=4.2,hard,timeo=600,retrans=2}"
    if ! exec_cli "mountpoint -q ${MOUNT_DIR}" 2>/dev/null; then
        nfs_mount "$mount_opts"
    else
        ok "NFS 已挂载在 ${MOUNT_DIR}"
    fi
}

# ---------- tc (流量控制) 辅助 ----------
tc_add_latency() {
    local iface="${1:-eth0}"
    local delay="${2:-300ms}"
    local jitter="${3:-50ms}"
    local loss="${4:-0}"
    info "添加 tc 规则: ${iface} delay=${delay} jitter=${jitter} loss=${loss}%"
    if [ "$loss" != "0" ]; then
        exec_cli "tc qdisc add dev ${iface} root netem delay ${delay} ${jitter} loss ${loss}% 2>&1"
    else
        exec_cli "tc qdisc add dev ${iface} root netem delay ${delay} ${jitter} 2>&1"
    fi
}

tc_del() {
    local iface="${1:-eth0}"
    info "删除 tc 规则: ${iface}"
    exec_cli "tc qdisc del dev ${iface} root 2>/dev/null; true"
}

# ---------- iptables 辅助 ----------
iptables_block_port() {
    local target="${1:-INPUT}"
    local port="${2:-2049}"
    local container="${3:-srv}"  # srv=server, cli=client
    info "屏蔽端口 ${port} (${target}, ${container}侧)"
    if [ "$container" = "srv" ]; then
        exec_srv "iptables -A ${target} -p tcp --dport ${port} -j DROP 2>&1"
    else
        exec_cli "iptables -A ${target} -p tcp --dport ${port} -j DROP 2>&1"
    fi
}

iptables_unblock_port() {
    local target="${1:-INPUT}"
    local port="${2:-2049}"
    local container="${3:-srv}"
    if [ "$container" = "srv" ]; then
        exec_srv "iptables -D ${target} -p tcp --dport ${port} -j DROP 2>/dev/null; true"
    else
        exec_cli "iptables -D ${target} -p tcp --dport ${port} -j DROP 2>/dev/null; true"
    fi
}

iptables_clear_all() {
    exec_srv "iptables -F 2>/dev/null; true" 2>/dev/null
    exec_cli "iptables -F 2>/dev/null; true" 2>/dev/null
}

# ---------- 场景输出 ----------
print_scenario_header() {
    local branch="$1"
    local desc="$2"
    echo ""
    header
    echo -e "${CYAN}  场景: ${branch}${NC}"
    echo -e "${CYAN}  描述: ${desc}${NC}"
    header
    echo ""
}

print_injection_result() {
    local fault_desc="$1"
    echo ""
    echo "═══════════════════════════════════════════"
    echo "  故障注入完成"
    echo "-------------------------------------------"
    echo "  注入故障: ${fault_desc}"
    echo "  时间: $(date -Iseconds)"
    echo "═══════════════════════════════════════════"
    echo ""
    echo "现在可以运行 witty-agent 进行诊断。"
    echo "诊断结束后运行对应的 clean 脚本清理。"
}
