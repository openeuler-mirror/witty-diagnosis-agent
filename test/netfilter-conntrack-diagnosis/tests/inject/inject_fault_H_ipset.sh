#!/usr/bin/env bash
# =============================================================================
# 故障注入 H: ipset 匹配失效
# 分支对应: branch_H_ipset.sh
# 注入方式: 创建 ipset 列表并与 iptables 规则配合，模拟匹配失效
# 验证方式: ipset 条目计数与预期不符 / 规则命中异常
# 参考 skill: ipset 匹配计数不为零但预期不应匹配/应匹配但计数为零
# =============================================================================
# 使用:
#   bash inject_fault_H_ipset.sh          # 注入故障
#   bash inject_fault_H_ipset.sh --clean  # 清理
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

readonly FAULT_NAME="ipset"
readonly CONTAINER_NAME="netfilter-fault-${FAULT_NAME}"

# =============================================================================
# 注入故障
# =============================================================================
inject_fault() {
    print_banner "故障注入 H: ipset 匹配失效"

    check_docker
    build_base_image
    ensure_test_network

    # 启动容器
    start_fault_container "${CONTAINER_NAME}"
    wait_container_ready "${CONTAINER_NAME}"

    local cip
    cip=$(get_container_ip "${CONTAINER_NAME}")
    log_info "容器 IP: ${cip}"

    # ---- Step 1: 创建 ipset 列表 ----
    log_step "[1/4] 创建 ipset 列表"

    docker exec "${CONTAINER_NAME}" bash -c '
        # 清理已有 ipset
        ipset flush 2>/dev/null || true
        for s in $(ipset list -n 2>/dev/null); do ipset destroy $s 2>/dev/null || true; done

        # ---- 创建3个 ipset 列表 ----

        # 1) 白名单 IP 列表（hash:ip）
        ipset create whitelist hash:ip maxelem 65536
        ipset add whitelist 192.168.1.1
        ipset add whitelist 10.0.0.1
        ipset add whitelist 172.16.0.1
        echo "[whitelist] 已创建，包含 3 个 IP"

        # 2) ⚠️ 黑名单列表（hash:net）- 但类型与规则预期不匹配（模拟类型不匹配）
        #    规则用了 match-set blacklist src（但 blacklist 是 hash:net 类型，src 需要 hash:ip）
        ipset create blacklist hash:net maxelem 65536
        ipset add blacklist 10.0.0.0/8
        ipset add blacklist 192.168.0.0/16
        echo "[blacklist] 已创建，包含 2 个网段"

        # 3) ⚠️ 端口列表 - 超时相关的匹配失效
        ipset create app_ports bitmap:port range 0-65535
        ipset add app_ports 8080
        ipset add app_ports 8443
        ipset add app_ports 9090
        echo "[app_ports] 已创建，包含 3 个端口"

        echo ""
        echo "[当前 ipset 列表]"
        ipset list
    '

    # ---- Step 2: 配置使用 ipset 的 iptables 规则 ----
    log_step "[2/4] 配置引用 ipset 的 iptables 规则"

    docker exec "${CONTAINER_NAME}" bash -c '
        iptables -F
        iptables -t nat -F

        # iptables 规则使用 ipset

        # ⚠️ 规则1: 本应使用 whitelist 放行，但因为 ipset 名拼写错误（whitelist -> whitelist）
        # 实际上是正确的，但此处模拟一个情况: 规则使用了错误的 ipset 名称
        # 实际上这个规则是正确的，但后面测试时发来的源 IP 不在 whitelist 中

        # 规则2: 正确的黑名单拦截
        # 预期: 来自 10.0.0.0/8 的流量被 DROP
        # 但！由于 ipset 类型是 hash:net，而规则中用了 src 参数（对 hash:net 应使用 src 或 dst 都可以）
        # 这个实际上是正确的...

        # ⚠️ 真正的问题: 规则3 引用 app_ports（bitmap:port）但匹配方向错误
        # bitmap:port 只能匹配 dst port，如果规则中指定 src 则是错误的

        iptables -A INPUT -i lo -j ACCEPT

        # 白名单放行（来自 whitelist 的 IP 放行）
        iptables -A INPUT -m set --match-set whitelist src -j ACCEPT
        echo "[规则1] whitelist src ACCEPT"

        # 黑名单拦截
        iptables -A INPUT -m set --match-set blacklist src -j DROP
        echo "[规则2] blacklist src DROP"

        # ⚠️ 故障规则: bitmap:port 类型用 src 匹配（预期不会生效）
        iptables -A INPUT -m set --match-set app_ports src -j DROP
        echo "[规则3 - 故障] app_ports src DROP（类型不匹配，此规则不会生效）"

        # 正确的端口匹配（作为对比）
        iptables -A INPUT -m set --match-set app_ports dst -j DROP
        echo "[规则4 - 正确] app_ports dst DROP"

        # 默认 ACCEPT
        iptables -P INPUT ACCEPT

        echo ""
        echo "[iptables 规则（含 ipset 引用）]"
        iptables -L -n -v --line-numbers
    '

    # ---- Step 3: 发送流量触发 ipset 匹配 ----
    log_step "[3/4] 发送流量触发 ipset 匹配"

    # 发送来自黑名单网段的流量
    log_info "发送来自黑名单网段 (10.99.99.99) 的流量..."
    docker exec "${CONTAINER_NAME}" bash -c '
        # 用 Python 构造来自黑名单 IP 的请求
        python3 -c "
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.bind((\"10.99.99.99\", 0))  # 尝试绑定黑名单 IP（需要在容器内添加此 IP）
" 2>/dev/null || true

        # 添加虚拟 IP 到 lo
        ip addr add 10.99.99.99/32 dev lo 2>/dev/null || true
        ip addr add 192.168.10.10/32 dev lo 2>/dev/null || true
        ip addr add 172.16.0.99/32 dev lo 2>/dev/null || true

        # 从这些 IP 发送请求触发匹配
        curl -s --connect-timeout 1 http://10.99.99.99:8080/ 2>/dev/null || true
        curl -s --connect-timeout 1 http://192.168.10.10:80/ 2>/dev/null || true
    ' 2>&1 || true

    # 发送匹配白名单的流量
    log_info "发送匹配白名单的流量..."
    docker exec "${CONTAINER_NAME}" bash -c '
        ip addr add 192.168.1.1/32 dev lo 2>/dev/null || true
        # 启动一个简单服务再请求
    ' 2>&1 || true

    # 发送匹配 app_ports 端口的流量
    log_info "发送到 app_ports 端口 (8080) 的流量..."
    docker exec -d "${CONTAINER_NAME}" bash -c '
        while true; do nc -lk -p 8080 -e echo "app" 2>/dev/null; sleep 0.1; done
    ' 2>/dev/null || true
    sleep 0.5
    docker exec "${CONTAINER_NAME}" bash -c '
        for i in $(seq 1 30); do
            timeout 0.3 curl -s http://127.0.0.1:8080/ 2>/dev/null || true
        done
        echo "端口 8080 请求完成"
    ' 2>&1

    sleep 1

    # ---- Step 4: 验证 ipset 匹配失效 ----
    log_step "[4/4] 验证 ipset 匹配异常"
    docker exec "${CONTAINER_NAME}" bash -c '
        echo "[ipset 条目与命中计数]"
        ipset list | grep -E "^Name|^Type|^Members|packets|bytes" -A1

        echo ""
        echo "[iptables 规则命中计数]"
        iptables -L INPUT -n -v --line-numbers

        echo ""
        echo "[ipset 匹配异常分析]"
        echo "  ⚠️ 规则3 (app_ports src): bitmap:port 类型不支持 src 匹配"
        echo "     → 预期: pkts=0（故障规则未生效）"
        echo "  ✅ 规则4 (app_ports dst): 正确的端口匹配方式"
        echo "     → 预期: pkts>0（正常生效）"
        echo "  ✅ 规则2 (blacklist src): hash:net 支持 src 匹配"
        echo "     → 预期: pkts>0（黑名单生效）"
    '

    # 获取规则命中计数
    local rule3_pkts rule4_pkts rule2_pkts
    rule3_pkts=$(docker exec "${CONTAINER_NAME}" bash -c "iptables -L INPUT -n -v --line-numbers 2>/dev/null | grep 'app_ports src' | awk '{print \$1}'" || echo "0")
    rule4_pkts=$(docker exec "${CONTAINER_NAME}" bash -c "iptables -L INPUT -n -v --line-numbers 2>/dev/null | grep 'app_ports dst' | awk '{print \$1}'" || echo "0")
    rule2_pkts=$(docker exec "${CONTAINER_NAME}" bash -c "iptables -L INPUT -n -v --line-numbers 2>/dev/null | grep 'blacklist' | awk '{print \$1}'" || echo "0")

    record_fault_injection \
        "${CONTAINER_NAME}" \
        "H_ipset" \
        "{\"rule3_app_ports_src_pkts\": \"${rule3_pkts}\", \"rule4_app_ports_dst_pkts\": \"${rule4_pkts}\", \"rule2_blacklist_pkts\": \"${rule2_pkts}\", \"fault_type\": \"ipset类型与规则不匹配\"}" \
        "{\"keyword\": \"ipset\", \"detail\": \"ipset bitmap:port 类型被 src 规则引用导致匹配失效\"}"

    echo ""
    echo "================================================================"
    echo "  故障注入 H 完成!"
    echo "  容器名称: ${CONTAINER_NAME}"
    echo "  容器 IP:  ${cip}"
    echo "================================================================"
    echo ""
    echo "诊断命令示例:"
    echo "  docker exec ${CONTAINER_NAME} bash /scripts/01_collect_baseline.sh"
    echo "  docker exec ${CONTAINER_NAME} bash /scripts/branch_H_ipset.sh /tmp/netfilter_diag_*"
    echo ""
}

clean() {
    stop_fault_container "${CONTAINER_NAME}"
    log_info "故障 H 清理完成"
}

main() {
    if [[ "${1:-}" == "--clean" ]]; then
        clean
    else
        inject_fault
    fi
}

main "$@"
