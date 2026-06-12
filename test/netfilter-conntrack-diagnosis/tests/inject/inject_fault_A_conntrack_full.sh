#!/usr/bin/env bash
# =============================================================================
# 故障注入 A: nf_conntrack 表满溢出
# 分支对应: branch_A_conntrack_full.sh
# 注入方式: 使用 --network host + 挂载 /proc/sys 降低 nf_conntrack_max 并发起大量连接
# 验证方式: dmesg 应出现 "table full, dropping packet" 关键字
# 注意: 需要宿主机的 root 权限来修改 nf_conntrack_max（通过挂载路径写入）
# =============================================================================
# 使用:
#   bash inject_fault_A_conntrack_full.sh          # 注入故障
#   bash inject_fault_A_conntrack_full.sh --clean  # 清理
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

readonly FAULT_NAME="conntrack_full"
readonly CONTAINER_NAME="netfilter-fault-${FAULT_NAME}"
readonly LISTEN_PORT=18888

# =============================================================================
# 注入故障
# =============================================================================
inject_fault() {
    print_banner "故障注入 A: nf_conntrack 表满溢出"

    check_docker
    build_base_image

    # 停止旧容器（如果有）
    stop_fault_container "${CONTAINER_NAME}"

    # ---- Step 0: 启动容器（host网络 + 挂载 /proc/sys 以写入 nf_conntrack_max）----
    log_step "[0/4] 启动特权容器（host网络 + /proc/sys 挂载）"
    log_warn "分支 A 需要修改宿主机的 nf_conntrack_max，将在注入后自动恢复"

    docker run -d --privileged \
        --name "${CONTAINER_NAME}" \
        --hostname "${CONTAINER_NAME}" \
        --network host \
        -v /proc/sys/net/netfilter/:/host-sys:rw \
        --security-opt apparmor=unconfined \
        "${NETFILTER_IMAGE}" 2>&1
    sleep 2
    wait_container_ready "${CONTAINER_NAME}"

    log_info "容器启动成功"

    # ---- Step 1: 大幅降低 conntrack_max ----
    log_step "[1/4] 降低 nf_conntrack_max 到 4096（正常值 262144）"
    local original_max
    original_max=$(docker exec "${CONTAINER_NAME}" cat /host-sys/nf_conntrack_max 2>/dev/null || echo "262144")
    log_info "原始 nf_conntrack_max=${original_max}"

    # 通过挂载的 /host-sys 路径写入（该路径映射到宿主机的 /proc/sys/net/netfilter/）
    docker exec "${CONTAINER_NAME}" bash -c "
        echo '写入 nf_conntrack_max=4096 ...'
        echo 4096 > /host-sys/nf_conntrack_max 2>&1 && echo 'OK' || echo 'FAILED'
        echo 2048 > /host-sys/nf_conntrack_buckets 2>/dev/null || true
        # 缩短超时，使条目迅速填满
        sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=30 >/dev/null 2>&1 || true
        sysctl -w net.netfilter.nf_conntrack_tcp_timeout_time_wait=10 >/dev/null 2>&1 || true
        sysctl -w net.netfilter.nf_conntrack_udp_timeout=10 >/dev/null 2>&1 || true
        echo '当前 nf_conntrack_max='\$(cat /host-sys/nf_conntrack_max)
    "
    log_info "conntrack_max 已降至 4096"

    # ---- Step 2: 启动 Python 服务 ----
    log_step "[2/4] 启动 Python TCP 服务（端口 ${LISTEN_PORT}）"
    docker exec -d "${CONTAINER_NAME}" python3 -c "
import socket, threading
def handle(c): c.close()
s=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1)
s.bind(('0.0.0.0',${LISTEN_PORT}))
s.listen(5000)
while True:
    c,_=s.accept()
    threading.Thread(target=handle,args=(c,)).start()
" 2>/dev/null &
    sleep 2

    # ---- Step 3: 使用 Python 大量 TCP 连接洪水 ----
    log_step "[3/4] 发起大量 TCP 连接填满 conntrack 表（max=4096）"
    log_info "发送 20000 个快速连接..."

    docker exec "${CONTAINER_NAME}" python3 -c "
import socket, threading, time

ok=fail=0
def flood(i):
    global ok,fail
    try:
        s=socket.socket(socket.AF_INET,socket.SOCK_STREAM)
        s.settimeout(0.3)
        s.connect(('127.0.0.1',${LISTEN_PORT}))
        s.close()
        ok+=1
    except:
        fail+=1

# 批次发送，每批 500 个
for batch in range(40):
    threads=[]
    for i in range(500):
        t=threading.Thread(target=flood,args=(batch*500+i,))
        t.start()
        threads.append(t)
    for t in threads: t.join()
    time.sleep(0.1)
    cur = open('/proc/sys/net/netfilter/nf_conntrack_count').read().strip()
    print(f'批次{batch+1}: ok={ok} fail={fail} conntrack={cur}')

print(f'最终: ok={ok} fail={fail}')
" 2>&1 || true

    sleep 3

    # ---- Step 4: 验证故障注入效果 ----
    log_step "[4/4] 验证故障注入效果"

    docker exec "${CONTAINER_NAME}" bash -c '
        echo "[conntrack 状态]"
        echo "  使用率: $(cat /proc/sys/net/netfilter/nf_conntrack_count 2>/dev/null || echo 0) / $(cat /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || echo 0)"
        if [ -f /proc/net/stat/nf_conntrack ]; then
            echo "  insert_failed=$(awk "NR>1 {print \$8}" /proc/net/stat/nf_conntrack)"
            echo "  drop=$(awk "NR>1 {print \$9}" /proc/net/stat/nf_conntrack)"
            echo "  early_drop=$(awk "NR>1 {print \$10}" /proc/net/stat/nf_conntrack)"
        fi
        echo "[dmesg 表满告警]:"
        dmesg 2>/dev/null | grep -i "table full\|dropping packet" | tail -5 || echo "  (无 dmesg 告警)"
    '

    # 获取计数用于记录
    local drop_c early_drop_c insert_failed_c
    drop_c=$(docker exec "${CONTAINER_NAME}" bash -c 'awk "NR>1{print \$9}" /proc/net/stat/nf_conntrack 2>/dev/null' || echo "0")
    early_drop_c=$(docker exec "${CONTAINER_NAME}" bash -c 'awk "NR>1{print \$10}" /proc/net/stat/nf_conntrack 2>/dev/null' || echo "0")
    insert_failed_c=$(docker exec "${CONTAINER_NAME}" bash -c 'awk "NR>1{print \$8}" /proc/net/stat/nf_conntrack 2>/dev/null' || echo "0")

    record_fault_injection \
        "${CONTAINER_NAME}" \
        "A_conntrack_full" \
        "{\"original_max\": ${original_max}, \"reduced_max\": 4096, \"drop\": \"${drop_c}\", \"early_drop\": \"${early_drop_c}\", \"insert_failed\": \"${insert_failed_c}\"}" \
        "{\"keyword\": \"table full\", \"detail\": \"dmesg 应出现 nf_conntrack: table full, dropping packet\"}"

    echo ""
    echo "================================================================"
    echo "  故障注入 A 完成!"
    echo "  容器名称: ${CONTAINER_NAME}"
    echo "  注意: 宿主机 nf_conntrack_max 已被临时降低到 4096"
    echo "        运行 cleanup_all.sh 或 inject_fault_A --clean 恢复"
    echo "================================================================"
    echo ""
    echo "诊断命令:"
    echo "  docker exec ${CONTAINER_NAME} bash /scripts/01_collect_baseline.sh"
    echo "  docker exec ${CONTAINER_NAME} bash /scripts/branch_A_conntrack_full.sh /tmp/netfilter_diag_*"
    echo ""
}

# =============================================================================
# 清理：恢复宿主机的 nf_conntrack_max
# =============================================================================
clean() {
    log_step "恢复宿主机 nf_conntrack_max..."

    # 如果容器还在运行，通过挂载路径恢复
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        local saved_max
        saved_max=$(docker exec "${CONTAINER_NAME}" cat /host-sys/nf_conntrack_max 2>/dev/null || echo "262144")
        # 恢复为 262144（默认值）
        docker exec "${CONTAINER_NAME}" bash -c "echo 262144 > /host-sys/nf_conntrack_max" 2>/dev/null || true
        log_info "已恢复 nf_conntrack_max=262144"
    fi

    stop_fault_container "${CONTAINER_NAME}"
    log_info "故障 A 清理完成"
}

main() {
    if [[ "${1:-}" == "--clean" ]]; then
        clean
    else
        inject_fault
    fi
}

main "$@"
