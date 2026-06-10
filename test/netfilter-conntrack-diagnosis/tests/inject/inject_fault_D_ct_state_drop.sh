#!/usr/bin/env bash
# =============================================================================
# 故障注入 D: conntrack 状态丢包 (INVALID/UNREPLIED)
# 分支对应: branch_D_ct_state_drop.sh
# 注入方式: 
#   - UNREPLIED: 大量 SYN 包不完成握手（纯 TCP socket 方式）
#   - INVALID: 设置 tcp_loose=0 + 发送孤立非 SYN 包 + iptables ctstate INVALID 规则
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

readonly FAULT_NAME="ct_state_drop"
readonly CONTAINER_NAME="netfilter-fault-${FAULT_NAME}"
readonly SERVICE_PORT=7777

inject_fault() {
    print_banner "故障注入 D: conntrack 状态丢包 (INVALID/UNREPLIED)"
    check_docker && build_base_image && ensure_test_network
    start_fault_container "${CONTAINER_NAME}"
    wait_container_ready "${CONTAINER_NAME}"
    local cip; cip=$(get_container_ip "${CONTAINER_NAME}")
    log_info "容器 IP: ${cip}"

    # ---- Step 1: 配置严格模式 + ctstate INVALID 规则 ----
    log_step "[1/5] 配置严格 conntrack 模式和 INVALID DROP 规则"
    docker exec "${CONTAINER_NAME}" bash -c '
        echo 0 > /proc/sys/net/netfilter/nf_conntrack_tcp_loose 2>/dev/null || true
        echo 0 > /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal 2>/dev/null || true
        iptables -F
        iptables -A INPUT -i lo -j ACCEPT
        # 添加 ctstate INVALID 规则（使诊断脚本可以检测）
        iptables -A INPUT -m conntrack --ctstate INVALID -j DROP
        iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
        iptables -P INPUT ACCEPT
        echo "tcp_loose=0, ctstate INVALID DROP 已配置"
        iptables -L INPUT -n -v --line-numbers
    '

    # ---- Step 2: 启动服务 ----
    log_step "[2/5] 启动 TCP 服务（端口 ${SERVICE_PORT}）"
    docker exec -d "${CONTAINER_NAME}" python3 -c "
import socket, threading
s=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
s.bind(('0.0.0.0',${SERVICE_PORT}))
s.listen(50)
def h(c): c.send(b'ok\n'); c.close()
while True:
    c,_=s.accept()
    threading.Thread(target=h,args=(c,)).start()
" 2>/dev/null &
    sleep 1

    # ---- Step 3: 创建 UNREPLIED 条目 ----
    log_step "[3/5] 创建 UNREPLIED 条目（大量 SYN 不握手）"
    docker exec "${CONTAINER_NAME}" python3 -c "
import socket, time
# 发送大量 SYN 包但不完成握手 → UNREPLIED
# 用 raw socket 构造 SYN 包（走内核栈，不 bypass netfilter）
import struct

target='${cip}'
port=${SERVICE_PORT}

def send_syn(sport):
    s=socket.socket(socket.AF_INET,socket.SOCK_RAW,socket.IPPROTO_RAW)
    s.setsockopt(socket.IPPROTO_IP, socket.IP_HDRINCL, 1)
    ip=struct.pack('!BBHHHBBH4s4s', 0x45,0,40,0,0,64,6,0,
        socket.inet_aton('10.0.0.'+str(sport%250+1)),
        socket.inet_aton(target))
    tcp=struct.pack('!HHIIBBHHH', sport,port,10000+sport,0,0x50,2,65535,0,0)
    s.sendto(ip+tcp,(target,0))
    s.close()

for i in range(300):
    send_syn(40000+i)
    if i%100==0: time.sleep(0.1)
print('300 SYN 包已发送')
" 2>&1 || true

    sleep 2

    # ---- Step 4: 发送孤立非 SYN 包 → 触发 INVALID 计数 ----
    log_step "[4/5] 发送孤立非 SYN 包（触发 INVALID 计数）"
    docker exec "${CONTAINER_NAME}" python3 -c "
import socket, struct, time

target='${cip}'
port=${SERVICE_PORT}

def send_non_syn(sport,flags):
    s=socket.socket(socket.AF_INET,socket.SOCK_RAW,socket.IPPROTO_RAW)
    s.setsockopt(socket.IPPROTO_IP, socket.IP_HDRINCL, 1)
    ip=struct.pack('!BBHHHBBH4s4s',0x45,0,40,0,0,64,6,0,
        socket.inet_aton('10.0.99.'+str(sport%250+1)),
        socket.inet_aton(target))
    tcp=struct.pack('!HHIIBBHHH',sport,port,30000+sport,1,0x50,flags,65535,0,0)
    s.sendto(ip+tcp,(target,0))
    s.close()

# 孤立 SYN-ACK
for i in range(100):
    send_non_syn(50000+i,0x12)  # SYN-ACK
# 孤立 ACK
for i in range(100):
    send_non_syn(60000+i,0x10)  # ACK
# 孤立 RST
for i in range(50):
    send_non_syn(70000+i,0x04)  # RST

time.sleep(1)
print('250 孤立非SYN包已发送')
" 2>&1 || true

    sleep 2

    # ---- Step 5: 验证 ----
    log_step "[5/5] 验证注入效果"
    docker exec "${CONTAINER_NAME}" bash -c '
        echo "=== conntrack 状态 ==="
        echo "UNREPLIED: $(conntrack -L --state UNREPLIED 2>/dev/null | wc -l)"
        echo "INVALID 条目: $(conntrack -L --state INVALID 2>/dev/null | wc -l)"
        echo "总条目: $(conntrack -C 2>/dev/null)"
        echo "nf_conntrack invalid 计数: $(awk "NR>1{print \$4;exit}" /proc/net/stat/nf_conntrack 2>/dev/null)"
        echo ""
        echo "=== iptables ctstate INVALID 命中 ==="
        iptables -L INPUT -n -v --line-numbers
    '

    local unreplied invalid_cnt
    unreplied=$(docker exec "${CONTAINER_NAME}" bash -c 'conntrack -L --state UNREPLIED 2>/dev/null | wc -l' || echo "0")
    invalid_cnt=$(docker exec "${CONTAINER_NAME}" bash -c 'awk "NR>1{print \$4;exit}" /proc/net/stat/nf_conntrack 2>/dev/null' || echo "0")

    record_fault_injection "${CONTAINER_NAME}" "D_ct_state_drop" \
        "{\"unreplied\": ${unreplied}, \"invalid_counter\": \"${invalid_cnt}\", \"ctstate_invalid_rule\": true}" \
        "{\"keyword\": \"INVALID\", \"detail\": \"conntrack 的 INVALID 计数增长 + UNREPLIED 条目堆积\"}"

    echo "  容器: ${CONTAINER_NAME}  IP: ${cip}"
    echo "诊断: docker exec ${CONTAINER_NAME} bash /scripts/01_collect_baseline.sh"
    echo "      docker exec ${CONTAINER_NAME} bash /scripts/branch_D_ct_state_drop.sh /tmp/netfilter_diag_*"
}

clean() { stop_fault_container "${CONTAINER_NAME}"; log_info "故障 D 清理完成"; }
main() { if [[ "${1:-}" == "--clean" ]]; then clean; else inject_fault; fi; }
main "$@"
