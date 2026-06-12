#!/usr/bin/env bash
# =============================================================================
# 故障注入 G: helper/ALG 协议辅助模块故障
# 分支对应: branch_G_helper_alg.sh
# 注入方式: 不加载 nf_conntrack_ftp 模块，尝试 FTP PASV 模式触发 ALG 故障
# 验证方式: FTP 数据通道无法建立 / helper 模块未加载
# 参考 skill: FTP/SIP/TFTP 等协议 ALG 异常
# =============================================================================
# 使用:
#   bash inject_fault_G_helper_alg.sh          # 注入故障
#   bash inject_fault_G_helper_alg.sh --clean  # 清理
# =============================================================================

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

readonly FAULT_NAME="helper_alg"
readonly CONTAINER_NAME="netfilter-fault-${FAULT_NAME}"
readonly FTP_PORT=2121

# =============================================================================
# 注入故障
# =============================================================================
inject_fault() {
    print_banner "故障注入 G: helper/ALG 协议辅助模块故障"

    check_docker
    build_base_image
    ensure_test_network

    # 启动容器
    start_fault_container "${CONTAINER_NAME}"
    wait_container_ready "${CONTAINER_NAME}"

    local cip
    cip=$(get_container_ip "${CONTAINER_NAME}")
    log_info "容器 IP: ${cip}"

    # ---- Step 1: 确认 nf_conntrack_helper=0 且不加载 FTP helper ----
    log_step "[1/4] 确保 nf_conntrack_helper=0 且无 FTP helper 模块"

    docker exec "${CONTAINER_NAME}" bash -c '
        # 确保 helper 自动分配关闭（模拟安全加固后的系统）
        sysctl -w net.netfilter.nf_conntrack_helper=0
        echo "nf_conntrack_helper = $(cat /proc/sys/net/netfilter/nf_conntrack_helper)"

        # 卸载 FTP helper（如果已加载）
        modprobe -r nf_conntrack_ftp 2>/dev/null || true

        echo ""
        echo "[已加载的 nf_conntrack 模块]"
        lsmod | grep -E "nf_conntrack|nf_ct" || echo "  (仅核心模块)"
    '

    # ---- Step 2: 设置 iptables 规则并启动 FTP 服务 ----
    log_step "[2/4] 启动 FTP 服务并配置 iptables 规则"

    # 配置 iptables 规则（允许 FTP 控制通道，但未加载 helper 导致数据通道无法通过）
    docker exec "${CONTAINER_NAME}" bash -c '
        iptables -F
        iptables -t nat -F

        # 允许已建立的连接
        iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
        iptables -A INPUT -i lo -j ACCEPT

        # 放行 FTP 控制端口
        iptables -A INPUT -p tcp --dport 2121 -j ACCEPT
        iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
        iptables -A OUTPUT -p tcp --sport 2121 -j ACCEPT

        # FORWARD 链默认 ACCEPT
        iptables -P FORWARD ACCEPT

        echo "[iptables 规则]"
        iptables -L -n -v
    '

    # 用 Python 启动一个简单的模拟 FTP 服务（模拟 PASV 模式）
    log_info "启动模拟 FTP 服务（PASV 模式，端口 ${FTP_PORT}）..."
    docker exec -d "${CONTAINER_NAME}" python3 /dev/stdin << 'PYFTP' 2>&1 || true
import socket
import threading
import sys

CONTROL_PORT = 2121
# 数据通道端口范围（FTP PASV 模式通常使用随机高位端口）
DATA_PORTS = list(range(30000, 30010))

def handle_ftp_client(conn, addr):
    """模拟一个简单的 FTP 服务器，PASV 模式下数据端口不会被 helper 识别"""
    print(f"[FTP] 控制连接来自 {addr}")
    try:
        conn.sendall(b"220 FakeFTP ready\r\n")
        while True:
            data = conn.recv(1024)
            if not data:
                break
            cmd = data.decode().strip().upper()
            print(f"[FTP] 收到命令: {cmd}")

            if cmd.startswith("USER"):
                conn.sendall(b"331 Username ok, need password\r\n")
            elif cmd.startswith("PASS"):
                conn.sendall(b"230 Login successful\r\n")
            elif cmd == "TYPE I":
                conn.sendall(b"200 Type set to I\r\n")
            elif cmd.startswith("PASV"):
                # PASV 模式: 返回一个数据端口地址
                # 这里使用一个高位端口，但 nf_conntrack_ftp 未加载，
                # conntrack 不会自动创建 EXPECTED 条目
                data_port = 30001
                p1 = data_port // 256
                p2 = data_port % 256
                # 返回 127.0.0.1,port
                resp = f"227 Entering Passive Mode (127,0,0,1,{p1},{p2})\r\n"
                conn.sendall(resp.encode())
                print(f"[FTP] PASV 响应: {resp.strip()}")
            elif cmd.startswith("RETR"):
                conn.sendall(b"150 Opening data connection\r\n")
                # 由于 helper 未加载，数据通道的 conntrack 条目不会自动创建
                # 数据连接会失败或被防火墙拦截
                conn.sendall(b"426 Connection closed; transfer aborted\r\n")
            elif cmd.startswith("QUIT"):
                conn.sendall(b"221 Goodbye\r\n")
                break
            else:
                conn.sendall(b"500 Unknown command\r\n")
    except Exception as e:
        print(f"[FTP] 错误: {e}")
    finally:
        conn.close()
    print(f"[FTP] 控制连接关闭 {addr}")

def main():
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(('0.0.0.0', CONTROL_PORT))
    srv.listen(5)
    print(f"[FTP] 模拟 FTP 服务启动在端口 {CONTROL_PORT}")
    while True:
        conn, addr = srv.accept()
        t = threading.Thread(target=handle_ftp_client, args=(conn, addr))
        t.daemon = True
        t.start()

if __name__ == "__main__":
    main()
PYFTP

    sleep 2

    # ---- Step 3: 模拟 FTP 客户端连接触发 ALG 问题 ----
    log_step "[3/4] 模拟 FTP 客户端连接，触发 ALG 问题"

    # 使用 Python 编写 FTP 客户端进行 PASV 模式连接
    docker exec "${CONTAINER_NAME}" python3 /dev/stdin << 'PYCLI' 2>&1 || true
import socket
import time

print("[FTP 客户端] 连接模拟 FTP 服务...")

# 连接 FTP 控制通道
ctrl = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
ctrl.settimeout(5)
try:
    ctrl.connect(('127.0.0.1', 2121))
    print(f"[FTP 客户端] 控制连接建立成功")

    # 接收欢迎消息
    resp = ctrl.recv(1024)
    print(f"  <- {resp.decode().strip()}")

    # 登录
    ctrl.sendall(b"USER test\r\n")
    resp = ctrl.recv(1024)
    print(f"  <- {resp.decode().strip()}")

    ctrl.sendall(b"PASS test\r\n")
    resp = ctrl.recv(1024)
    print(f"  <- {resp.decode().strip()}")

    # PASV 模式
    ctrl.sendall(b"PASV\r\n")
    resp = ctrl.recv(1024)
    print(f"  <- {resp.decode().strip()}")

    # 尝试连接数据通道
    time.sleep(0.5)
    print("[FTP 客户端] 尝试连接数据通道 127.0.0.1:30001...")
    data = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    data.settimeout(3)
    try:
        data.connect(('127.0.0.1', 30001))
        print("  ✅ 数据通道连接成功（应为失败，因为 helper 未加载）")
        data.close()
    except Exception as e:
        print(f"  ❌ 数据通道连接失败: {e}")
        print("     （预期行为: nf_conntrack_ftp 未加载，数据通道被拦截）")

    # 退出
    ctrl.sendall(b"QUIT\r\n")
    resp = ctrl.recv(1024)
    print(f"  <- {resp.decode().strip()}")

except Exception as e:
    print(f"[FTP 客户端] 错误: {e}")
finally:
    ctrl.close()

print("[FTP 客户端] 测试完成")
PYCLI

    # ---- Step 4: 验证 ALG 故障 ----
    log_step "[4/4] 验证 helper/ALG 故障"
    docker exec "${CONTAINER_NAME}" bash -c '
        echo "[已加载 helper 模块]"
        lsmod | grep -E "nf_conntrack_ftp|nf_conntrack_sip|nf_conntrack_tftp|nf_ct" | sort \
            || echo "  (无 ALG helper 模块加载)"

        echo ""
        echo "[nf_conntrack_helper 状态]"
        cat /proc/sys/net/netfilter/nf_conntrack_helper 2>/dev/null \
            && echo " (0=helper 自动分配关闭)" \
            || echo "  N/A"

        echo ""
        echo "[conntrack 中 EXPECTED/RELATED 条目]"
        conntrack -L 2>/dev/null | grep -E "EXPECTED|RELATED" | head -10 || echo "  (无 EXPECTED/RELATED 条目 - 预期行为)"

        echo ""
        echo "[FTP 相关 conntrack 条目]"
        conntrack -L -p tcp 2>/dev/null | grep ":2121" | head -5 || echo "  (无 FTP 相关条目)"

        if command -v conntrack &>/dev/null; then
            echo ""
            echo "[conntrack 总条目数]"
            conntrack -C
        fi
    '

    record_fault_injection \
        "${CONTAINER_NAME}" \
        "G_helper_alg" \
        "{\"nf_conntrack_helper\": 0, \"helpers_loaded\": [], \"ftp_module\": \"not loaded\"}" \
        "{\"keyword\": \"helper\", \"detail\": \"nf_conntrack_ftp 未加载，FTP PASV 数据通道无法建立\"}"

    echo ""
    echo "================================================================"
    echo "  故障注入 G 完成!"
    echo "  容器名称: ${CONTAINER_NAME}"
    echo "  容器 IP:  ${cip}"
    echo "  模拟协议: FTP (PASV 模式)"
    echo "================================================================"
    echo ""
    echo "诊断命令示例:"
    echo "  docker exec ${CONTAINER_NAME} bash /scripts/01_collect_baseline.sh"
    echo "  docker exec ${CONTAINER_NAME} bash /scripts/branch_G_helper_alg.sh /tmp/netfilter_diag_*"
    echo ""
}

clean() {
    stop_fault_container "${CONTAINER_NAME}"
    log_info "故障 G 清理完成"
}

main() {
    if [[ "${1:-}" == "--clean" ]]; then
        clean
    else
        inject_fault
    fi
}

main "$@"
