#!/usr/bin/env bash
# =============================================================================
# 故障注入 B: iptables 规则误命中 DROP
# 分支对应: branch_B_rule_mishit.sh
# 注入方式: 在 Docker 容器内添加 iptables DROP 规则，然后发送匹配流量
# 验证方式: iptables DROP 规则 pkts > 0
# 参考 skill: iptables/nftables 有 DROP/REJECT 规则且 pkts > 0
# =============================================================================
# 使用:
#   bash inject_fault_B_rule_mishit.sh          # 注入故障
#   bash inject_fault_B_rule_mishit.sh --clean  # 清理
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

readonly FAULT_NAME="rule_mishit"
readonly CONTAINER_NAME="netfilter-fault-${FAULT_NAME}"
readonly BLOCKED_PORT=9999
readonly ALLOWED_PORT=9998

# =============================================================================
# 注入故障
# =============================================================================
inject_fault() {
    print_banner "故障注入 B: iptables 规则误命中 DROP"

    check_docker
    build_base_image
    ensure_test_network

    # 启动服务容器（模拟业务服务器）
    start_fault_container "${CONTAINER_NAME}"
    wait_container_ready "${CONTAINER_NAME}"

    local cip
    cip=$(get_container_ip "${CONTAINER_NAME}")
    log_info "容器 IP: ${cip}"

    # ---- Step 1: 设置 iptables 规则 ----
    log_step "[1/4] 配置 iptables DROP 规则（模拟规则误命中）"

    # 清理已有规则
    docker exec "${CONTAINER_NAME}" bash -c 'iptables -F; iptables -t nat -F; iptables -t mangle -F'

    # 创建两个规则:
    #   规则1: 允许特定端口 (ACCEPT)
    #   规则2: 意外地将某个管理端口范围也 DROP 掉（模拟误配置）
    docker exec "${CONTAINER_NAME}" bash -c "
        # 放行必要流量（SSH-like）
        iptables -A INPUT -i lo -j ACCEPT
        iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

        # 允许特定服务端口
        iptables -A INPUT -p tcp --dport ${ALLOWED_PORT} -j ACCEPT

        # ⚠️ 误配置: 将 ${BLOCKED_PORT} 端口 DROP（本应只限制管理网段）
        # 正常应该: -s 管理网段 -j DROP
        # 误配置为: 所有源都 DROP
        iptables -A INPUT -p tcp --dport ${BLOCKED_PORT} -j DROP

        # 再加一条看起来正常但不小心的误配置
        # 对 10000-10010 范围全部 DROP（模拟某次变更中误将服务端口列入黑名单）
        iptables -A INPUT -p tcp --dport 10000:10010 -j DROP

        # 默认策略
        iptables -P INPUT ACCEPT
        iptables -P FORWARD ACCEPT
        iptables -P OUTPUT ACCEPT

        echo '[iptables 规则配置完成]'
        iptables -L -n -v --line-numbers
    "

    # ---- Step 2: 启动受害者服务 ----
    log_step "[2/4] 启动被误拦截的服务（端口 ${BLOCKED_PORT}）"
    docker exec -d "${CONTAINER_NAME}" bash -c "
        while true; do
            nc -lk -p ${BLOCKED_PORT} -e echo 'service-on-blocked-port' 2>/dev/null
            sleep 0.1
        done
    " 2>/dev/null || true

    docker exec -d "${CONTAINER_NAME}" bash -c "
        while true; do
            nc -lk -p ${ALLOWED_PORT} -e echo 'service-on-allowed-port' 2>/dev/null
            sleep 0.1
        done
    " 2>/dev/null || true

    sleep 1

    # ---- Step 3: 发送流量触发 DROP 规则 ----
    log_step "[3/4] 发送流量触发 DROP 规则命中计数"

    # 发送流量到被拦截端口（触发 DROP）
    log_info "发送请求到被拦截端口 ${BLOCKED_PORT}..."
    docker exec "${CONTAINER_NAME}" bash -c "
        for i in \$(seq 1 50); do
            timeout 0.5 curl -s http://127.0.0.1:${BLOCKED_PORT}/ 2>/dev/null || true
        done
        echo '请求到端口 ${BLOCKED_PORT} 完成'
    " 2>&1

    # 发送流量到被拦截端口范围
    log_info "发送请求到拦截端口范围 10000-10010..."
    docker exec "${CONTAINER_NAME}" bash -c "
        for port in \$(seq 10000 10005); do
            timeout 0.5 curl -s http://127.0.0.1:\${port}/ 2>/dev/null || true
        done
        echo '请求到端口范围完成'
    " 2>&1

    # 发送少量正常流量到允许端口
    log_info "发送正常流量到端口 ${ALLOWED_PORT}"
    docker exec "${CONTAINER_NAME}" bash -c "
        for i in \$(seq 1 5); do
            timeout 0.5 curl -s http://127.0.0.1:${ALLOWED_PORT}/ 2>/dev/null || true
        done
        echo '正常请求完成'
    " 2>&1

    sleep 1

    # ---- Step 4: 验证故障注入效果 ----
    log_step "[4/4] 验证故障注入效果"
    docker exec "${CONTAINER_NAME}" bash -c '
        echo "[iptables 命中计数]"
        iptables -L INPUT -n -v --line-numbers 2>/dev/null | head -20

        echo ""
        echo "[DROP 规则 pkts 检查]"
        iptables -L INPUT -n -v --line-numbers 2>/dev/null | awk '\''/DROP/ {if ($1 ~ /^[0-9]+$/ && $1 > 0) print "  ✅ pkt计数=" $1 " " $0; else if ($1 ~ /^[0-9]+$/) print "  ❌ pkt计数=" $1 " " $0}'\''
    '

    # 获取规则命中计数用于记录
    local drop_pkts
    drop_pkts=$(docker exec "${CONTAINER_NAME}" bash -c "iptables -L INPUT -n -v --line-numbers 2>/dev/null | awk '/dpt:${BLOCKED_PORT}/ {print \$1}'" || echo "0")

    record_fault_injection \
        "${CONTAINER_NAME}" \
        "B_rule_mishit" \
        "{\"blocked_port\": ${BLOCKED_PORT}, \"drop_pkts\": \"${drop_pkts}\", \"rules\": \"INPUT chain DROP on port ${BLOCKED_PORT} and 10000-10010\"}" \
        "{\"keyword\": \"DROP\", \"detail\": \"iptables filter 表 INPUT 链中 DROP 规则 pkts > 0\"}"

    echo ""
    echo "================================================================"
    echo "  故障注入 B 完成!"
    echo "  容器名称: ${CONTAINER_NAME}"
    echo "  容器 IP:  ${cip}"
    echo "  被拦截端口: ${BLOCKED_PORT}, 10000-10010"
    echo "================================================================"
    echo ""
    echo "诊断命令示例:"
    echo "  docker exec ${CONTAINER_NAME} bash /scripts/01_collect_baseline.sh"
    echo "  docker exec ${CONTAINER_NAME} bash /scripts/branch_B_rule_mishit.sh /tmp/netfilter_diag_*"
    echo ""
}

# =============================================================================
# 清理
# =============================================================================
clean() {
    stop_fault_container "${CONTAINER_NAME}"
    log_info "故障 B 清理完成"
}

main() {
    if [[ "${1:-}" == "--clean" ]]; then
        clean
    else
        inject_fault
    fi
}

main "$@"
