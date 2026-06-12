#!/usr/bin/env bash
# =============================================================================
# 故障注入 F: conntrack timeout 超时问题
# 分支对应: branch_F_ct_timeout.sh
# 注入方式: 设极短超时 + 降低 nf_conntrack_max + 大量连接 → early_drop 增长
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

readonly FAULT_NAME="ct_timeout"
readonly CONTAINER_NAME="netfilter-fault-${FAULT_NAME}"
readonly SERVICE_PORT=5555

inject_fault() {
    print_banner "故障注入 F: conntrack timeout 超时问题"
    check_docker && build_base_image && ensure_test_network
    start_fault_container "${CONTAINER_NAME}"
    wait_container_ready "${CONTAINER_NAME}"
    local cip; cip=$(get_container_ip "${CONTAINER_NAME}")
    log_info "容器 IP: ${cip}"

    # ---- Step 1: 设极短 timeout ----
    log_step "[1/5] 设置 conntrack timeout 为极短值"
    docker exec "${CONTAINER_NAME}" bash -c '
        echo "[修改前]"
        echo "established=$(cat /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established)"
        sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=10 >/dev/null 2>&1
        sysctl -w net.netfilter.nf_conntrack_tcp_timeout_time_wait=5 >/dev/null 2>&1
        sysctl -w net.netfilter.nf_conntrack_udp_timeout=5 >/dev/null 2>&1
        echo "[修改后]"
        echo "established=$(cat /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established)"
        echo "time_wait=$(cat /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_time_wait)"
        echo "udp_timeout=$(cat /proc/sys/net/netfilter/nf_conntrack_udp_timeout)"
    '

    # ---- Step 2: 启动服务 ----
    log_step "[2/5] 启动 TCP 服务"
    docker exec -d "${CONTAINER_NAME}" python3 -c "
import socket, threading
s=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
s.bind(('0.0.0.0',${SERVICE_PORT}))
s.listen(50)
def h(c): c.close()
while True:
    c,_=s.accept()
    threading.Thread(target=h,args=(c,)).start()
" 2>/dev/null &
    sleep 1

    # ---- Step 3: 建立连接后空闲等待超时 ----
    log_step "[3/5] 建立 50 个连接并空闲等待超时"
    docker exec "${CONTAINER_NAME}" python3 -c "
import socket, time
for i in range(50):
    try:
        s=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
        s.settimeout(30)
        s.connect(('${cip}',${SERVICE_PORT}))
        time.sleep(0.05)
    except: pass
print('50 连接已建立，等待 conntrack 超时...')
" 2>&1 || true

    echo "  等待 15 秒..."
    sleep 15

    # ---- Step 4: 额外增加 conntrack 压力 ----
    log_step "[4/5] 大量连接填充 conntrack（模拟超时 + 表满压力）"
    docker exec "${CONTAINER_NAME}" python3 -c "
import socket, threading, time
ok=fail=0
def f(i):
    global ok,fail
    try:
        s=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
        s.settimeout(0.3)
        s.connect(('${cip}',${SERVICE_PORT}))
        s.close(); ok+=1
    except: fail+=1
for batch in range(20):
    ts=[]
    for i in range(500):
        t=threading.Thread(target=f,args=(i,))
        t.start(); ts.append(t)
    for t in ts: t.join()
    time.sleep(0.05)
print(f'ok={ok} fail={fail}')
" 2>&1 || true

    sleep 3

    # ---- Step 5: 验证 ----
    log_step "[5/5] 验证 timeout 效果"
    docker exec "${CONTAINER_NAME}" bash -c '
        echo "[conntrack 状态]"
        echo "条目数: $(conntrack -C 2>/dev/null)"
        echo "timeout 参数:"
        sysctl -a 2>/dev/null | grep "conntrack.*timeout" | grep -E "established|time_wait|udp_timeout[^_]"
    '

    record_fault_injection "${CONTAINER_NAME}" "F_ct_timeout" \
        "{\"tcp_established\": 10, \"tcp_time_wait\": 5, \"udp_timeout\": 5}" \
        "{\"keyword\": \"timeout\", \"detail\": \"conntrack timeout 配置远短于推荐值\"}"

    echo "  容器: ${CONTAINER_NAME}  IP: ${cip}"
    echo "诊断: docker exec ${CONTAINER_NAME} bash /scripts/01_collect_baseline.sh"
    echo "      docker exec ${CONTAINER_NAME} bash /scripts/branch_F_ct_timeout.sh /tmp/netfilter_diag_*"
}

clean() { stop_fault_container "${CONTAINER_NAME}"; log_info "故障 F 清理完成"; }
main() { if [[ "${1:-}" == "--clean" ]]; then clean; else inject_fault; fi; }
main "$@"
