#!/usr/bin/env bash
# =============================================================================
# 故障注入 C: NAT/SNAT/DNAT 映射异常
# 分支对应: branch_C_nat_mapping.sh
# 注入方式: 配置 DNAT 指向 dummy 接口错误地址 + SNAT 错误源地址
# 验证方式: conntrack NAT entry 与预期地址不符
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

readonly FAULT_NAME="nat_mapping"
readonly CONTAINER_NAME="netfilter-fault-${FAULT_NAME}"
readonly WRONG_DNAT_IP="172.29.0.199"

inject_fault() {
    print_banner "故障注入 C: NAT/SNAT/DNAT 映射异常"
    check_docker && build_base_image && ensure_test_network
    start_fault_container "${CONTAINER_NAME}"
    wait_container_ready "${CONTAINER_NAME}"
    local cip; cip=$(get_container_ip "${CONTAINER_NAME}")
    log_info "容器 IP: ${cip}"

    log_step "[1/5] 配置网络（IP转发 + dummy 接口）"
    docker exec "${CONTAINER_NAME}" bash -c "
        echo 1 > /proc/sys/net/ipv4/ip_forward
        iptables -F; iptables -t nat -F
        ip link add dummy0 type dummy 2>/dev/null || true
        ip addr add ${WRONG_DNAT_IP}/32 dev dummy0 2>/dev/null || true
        ip link set dummy0 up
        # 在 dummy IP 上启动服务
        python3 -c \"
import socket
s=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
s.bind(('${WRONG_DNAT_IP}',80))
s.listen(5)
while True:
    c,_=s.accept()
    c.send(b'HTTP/1.1 200 OK\r\n\r\nFake Backend\n')
    c.close()
\" &
        echo 'dummy0 就绪: ${WRONG_DNAT_IP}:80'
    " 2>/dev/null || true
    sleep 1

    log_step "[2/5] 配置异常的 NAT 规则"
    docker exec "${CONTAINER_NAME}" bash -c "
        # DNAT 端口 20000 → 映射到错误的内部 IP
        iptables -t nat -A PREROUTING -p tcp --dport 20000 -j DNAT --to-destination ${WRONG_DNAT_IP}:80
        # SNAT 源地址错误
        iptables -t nat -A POSTROUTING -j SNAT --to-source 10.0.0.99
        iptables -A FORWARD -j ACCEPT
        iptables -t nat -L -n -v --line-numbers
    "

    log_step "[3/5] 发送流量触发 NAT"
    docker exec "${CONTAINER_NAME}" bash -c '
        timeout 1 curl -s http://127.0.0.1:20000/ 2>/dev/null || true
        curl -s http://1.1.1.1 --connect-timeout 2 2>/dev/null || true
        echo "流量触发完成"
    ' 2>&1 || true
    sleep 2

    log_step "[4/5] 验证 NAT 映射"
    docker exec "${CONTAINER_NAME}" bash -c '
        echo "[conntrack NAT 条目]"
        conntrack -L -n 2>/dev/null | head -20
        echo ""
        echo "[NAT 规则命中]"
        iptables -t nat -L -n -v --line-numbers
    '

    local dnat_snat
    dnat_snat=$(docker exec "${CONTAINER_NAME}" bash -c 'conntrack -L -n 2>/dev/null | grep -c "DNAT\|SNAT"' 2>/dev/null || echo "0")
    record_fault_injection "${CONTAINER_NAME}" "C_nat_mapping" \
        "{\"dnat\":\"→${WRONG_DNAT_IP}:80\",\"snat\":\"→10.0.0.99\",\"nat_entries\":${dnat_snat}}" \
        "{\"keyword\":\"DNAT\",\"detail\":\"NAT 转换地址与预期不符\"}"

    echo ""
    echo "================================================================"
    echo "  故障注入 C 完成!  容器: ${CONTAINER_NAME}  IP: ${cip}"
    echo "================================================================"
}

clean() { stop_fault_container "${CONTAINER_NAME}"; log_info "故障 C 清理完成"; }
main() { if [[ "${1:-}" == "--clean" ]]; then clean; else inject_fault; fi; }
main "$@"
