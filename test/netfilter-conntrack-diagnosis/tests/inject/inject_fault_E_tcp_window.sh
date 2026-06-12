#!/usr/bin/env bash
# =============================================================================
# 故障注入 E: TCP window tracking 异常
# 分支对应: branch_E_tcp_window.sh
# 注入方式: tcp_be_liberal=0（严格模式）+ 原始 socket 发送窗口外 seq 数据
# 验证方式: /proc/net/stat/nf_conntrack 中 invalid 计数增长
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

readonly FAULT_NAME="tcp_window"
readonly CONTAINER_NAME="netfilter-fault-${FAULT_NAME}"
readonly SERVICE_PORT=6666

inject_fault() {
    print_banner "故障注入 E: TCP window tracking 异常"
    check_docker && build_base_image && ensure_test_network
    start_fault_container "${CONTAINER_NAME}"
    wait_container_ready "${CONTAINER_NAME}"
    local cip; cip=$(get_container_ip "${CONTAINER_NAME}")
    log_info "容器 IP: ${cip}"

    # ---- Step 1: 设置严格模式 ----
    log_step "[1/4] 设置 nf_conntrack_tcp_be_liberal=0（严格模式）"
    docker exec "${CONTAINER_NAME}" bash -c '
        echo 0 > /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal 2>/dev/null || true
        echo 0 > /proc/sys/net/netfilter/nf_conntrack_tcp_loose 2>/dev/null || true
        echo "tcp_be_liberal=$(cat /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal)"
        echo "tcp_loose=$(cat /proc/sys/net/netfilter/nf_conntrack_tcp_loose)"
    '

    # ---- Step 2: 记录初始 invalid 计数 ----
    log_step "[2/4] 记录初始 invalid 计数"
    local before_invalid
    before_invalid=$(docker exec "${CONTAINER_NAME}" awk 'NR>1{print $4;exit}' /proc/net/stat/nf_conntrack 2>/dev/null || echo "0")
    log_info "注入前 invalid 计数: ${before_invalid}"

    # ---- Step 3: 启动服务并发送 window violation 报文 ----
    log_step "[3/4] 建立连接后发送窗口外数据"
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

    # 使用 raw socket 发送 window violation
    docker exec "${CONTAINER_NAME}" python3 -c "
import socket, struct, time

target='${cip}'
port=${SERVICE_PORT}

# 先建立正常的 TCP 连接获取真实的 seq/ack 和窗口信息
s=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
s.settimeout(3)
try:
    s.connect((target,port))
    # 发送一些数据使窗口滑动
    s.send(b'hello\n')
    s.recv(1024)
    local_port = s.getsockname()[1]
    s.close()
    
    # 用 raw socket 发送 seq 远超当前窗口的数据包
    rs=socket.socket(socket.AF_INET,socket.SOCK_RAW,socket.IPPROTO_RAW)
    rs.setsockopt(socket.IPPROTO_IP, socket.IP_HDRINCL, 1)
    
    # 构造一个 seq=1000000 的包（远超正常窗口）
    for i in range(50):
        ip=struct.pack('!BBHHHBBH4s4s',0x45,0,100,0,0,64,6,0,
            socket.inet_aton(target),socket.inet_aton(target))
        tcp=struct.pack('!HHIIBBHHH',local_port,port,1000000+i*10000,1,
            0x50,0x18,65535,0,0)  # PSH+ACK
        rs.sendto(ip+tcp+'window-violation-data-payload-'+str(i).encode(),(target,0))
    
    rs.close()
    print('50 window violation 包已发送 ✓')
except Exception as e:
    print(f'连接失败: {e}')
    # 即使连接失败，也尝试直接发孤立包
    rs=socket.socket(socket.AF_INET,socket.SOCK_RAW,socket.IPPROTO_RAW)
    rs.setsockopt(socket.IPPROTO_IP, socket.IP_HDRINCL, 1)
    for i in range(100):
        ip=struct.pack('!BBHHHBBH4s4s',0x45,0,100,0,0,64,6,0,
            socket.inet_aton('10.0.7.'+str(i%250+1)),socket.inet_aton(target))
        tcp=struct.pack('!HHIIBBHHH',60000+i,port,500000+i,1,0x50,0x10,65535,0,0)
        rs.sendto(ip+tcp,(target,0))
    rs.close()
    print('100 ACK 包已发送（备用方案）')
" 2>&1 || true

    sleep 2

    # ---- Step 4: 验证 ----
    log_step "[4/4] 验证 window tracking 异常"
    local after_invalid
    after_invalid=$(docker exec "${CONTAINER_NAME}" awk 'NR>1{print $4;exit}' /proc/net/stat/nf_conntrack 2>/dev/null || echo "0")
    log_info "注入后 invalid 计数: ${after_invalid}"

    docker exec "${CONTAINER_NAME}" bash -c '
        echo "[conntrack 统计]"
        awk "NR>1 {printf \"invalid=%s  insert_failed=%s  drop=%s  early_drop=%s\\n\", \$4, \$8, \$9, \$10}" /proc/net/stat/nf_conntrack
        echo ""
        echo "[INVALID 条目]"
        conntrack -L --state INVALID 2>/dev/null | head -5 || echo "(无，INVALID 不计入条目表)"
    '

    record_fault_injection "${CONTAINER_NAME}" "E_tcp_window" \
        "{\"tcp_be_liberal\": 0, \"invalid_before\": \"${before_invalid}\", \"invalid_after\": \"${after_invalid}\"}" \
        "{\"keyword\": \"invalid\", \"detail\": \"TCP window violation 导致 nf_conntrack invalid 计数增长\"}"

    echo "  容器: ${CONTAINER_NAME}  IP: ${cip}"
    echo "诊断: docker exec ${CONTAINER_NAME} bash /scripts/01_collect_baseline.sh"
    echo "      docker exec ${CONTAINER_NAME} bash /scripts/branch_E_tcp_window.sh /tmp/netfilter_diag_*"
}

clean() { stop_fault_container "${CONTAINER_NAME}"; log_info "故障 E 清理完成"; }
main() { if [[ "${1:-}" == "--clean" ]]; then clean; else inject_fault; fi; }
main "$@"
