#!/usr/bin/env bash
# =============================================================================
# 统一环境清理脚本
# 用途: 清理所有故障注入容器和网络，恢复宿主机 netfilter 参数
# =============================================================================
# 使用:
#   bash cleanup_all.sh          # 清理所有故障容器和网络
#   bash cleanup_all.sh --force  # 强制清理（包括基础镜像）
#   bash cleanup_all.sh --help   # 显示帮助
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# 颜色
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

echo -e "${BLUE}================================================================"
echo " Netfilter / conntrack 故障注入测试 — 环境清理"
echo -e "================================================================${NC}"
echo ""

# =============================================================================
# 阶段1: 停止并删除所有故障注入容器
# =============================================================================
cleanup_containers() {
    echo -e "${YELLOW}[阶段 1/5]${NC} 停止并删除所有故障注入容器..."

    local fault_containers=(
        "netfilter-fault-conntrack_full"
        "netfilter-fault-rule_mishit"
        "netfilter-fault-nat_mapping"
        "netfilter-fault-nat_mapping-client"
        "netfilter-fault-nat_mapping-server"
        "netfilter-fault-ct_state_drop"
        "netfilter-fault-tcp_window"
        "netfilter-fault-ct_timeout"
        "netfilter-fault-helper_alg"
        "netfilter-fault-ipset"
    )

    local found=0

    # 在删除容器前，先通过 /host-sys 恢复 nf_conntrack_max（分支A）
    local a_container="netfilter-fault-conntrack_full"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${a_container}$"; then
        echo -e "  ${YELLOW}恢复 nf_conntrack_max（通过 ${a_container} 的 /host-sys）${NC}"
        docker exec "${a_container}" bash -c 'echo 262144 > /host-sys/nf_conntrack_max' 2>/dev/null &&             echo -e "  ${GREEN}已恢复 nf_conntrack_max=262144${NC}" ||             echo -e "  ${RED}恢复失败${NC}"
    fi

    for cname in "${fault_containers[@]}"; do
        if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${cname}$"; then
            echo -e "  ${RED}删除${NC} ${cname}"
            docker rm -f "${cname}" 2>/dev/null && ((found++)) || true
        fi
    done

    if [[ ${found} -eq 0 ]]; then
        echo "  (无故障注入容器需要清理)"
    else
        echo -e "  ${GREEN}已删除 ${found} 个容器${NC}"
    fi
}

# =============================================================================
# 阶段2: 清理测试网络
# =============================================================================
cleanup_network() {
    echo -e "${YELLOW}[阶段 2/5]${NC} 清理测试网络..."

    local network_name="netfilter-test-bridge"
    if docker network ls --format '{{.Name}}' 2>/dev/null | grep -q "^${network_name}$"; then
        # 检查是否还有容器连接到此网络
        local attached
        attached=$(docker network inspect "${network_name}" --format '{{len .Containers}}' 2>/dev/null || echo "0")
        if [[ "${attached}" -gt 0 ]]; then
            echo -e "  ${YELLOW}网络 ${network_name} 仍有 ${attached} 个容器连接，跳过删除${NC}"
            echo "  请先确保所有容器已删除"
        else
            docker network rm "${network_name}" 2>/dev/null && \
                echo -e "  ${GREEN}已删除网络 ${network_name}${NC}" || \
                echo -e "  ${RED}删除网络 ${network_name} 失败${NC}"
        fi
    else
        echo "  (无测试网络需要清理)"
    fi
}

# =============================================================================
# 阶段3: 恢复宿主机 netfilter 内核参数
# =============================================================================
cleanup_sysctl() {
    echo -e "${YELLOW}[阶段 3/5]${NC} 恢复宿主机 netfilter 内核参数..."

    local restored=0

    # 分支A的特殊情况: 如果容器还活着，通过 /host-sys 恢复
    local a_container="netfilter-fault-conntrack_full"
    if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${a_container}$"; then
        echo -e "  ${YELLOW}通过容器 ${a_container} 恢复 nf_conntrack_max${NC}"
        docker exec "${a_container}" bash -c 'echo 262144 > /host-sys/nf_conntrack_max' 2>/dev/null || true
        ((restored++))
fi





    # 检查 conntrack_max 是否被测试脚本改过
    if [[ -f /proc/sys/net/netfilter/nf_conntrack_max ]]; then
        local current_max
        current_max=$(cat /proc/sys/net/netfilter/nf_conntrack_max)
        if [[ "${current_max}" -lt 262144 ]]; then
            echo -e "  ${YELLOW}恢复 nf_conntrack_max: ${current_max} → 262144${NC}"
            echo 262144 > /proc/sys/net/netfilter/nf_conntrack_max 2>/dev/null || \
                echo -e "  ${RED}恢复失败（需要 root 权限）${NC}"
            ((restored++))
        else
            echo "  nf_conntrack_max = ${current_max} (正常)"
        fi
    fi

    # 检查 nf_conntrack_buckets
    if [[ -f /proc/sys/net/netfilter/nf_conntrack_buckets ]]; then
        local current_buckets
        current_buckets=$(cat /proc/sys/net/netfilter/nf_conntrack_buckets)
        if [[ "${current_buckets}" -lt 16384 ]]; then
            echo -e "  ${YELLOW}恢复 nf_conntrack_buckets: ${current_buckets} → 65536${NC}"
            echo 65536 > /proc/sys/net/netfilter/nf_conntrack_buckets 2>/dev/null || \
                echo -e "  ${RED}恢复失败（需要 root 权限）${NC}"
            ((restored++))
        else
            echo "  nf_conntrack_buckets = ${current_buckets} (正常)"
        fi
    fi

    # 恢复 tcp_be_liberal
    if [[ -f /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal ]]; then
        local current_liberal
        current_liberal=$(cat /proc/sys/net/netfilter/nf_conntrack_tcp_be_liberal)
        if [[ "${current_liberal}" -ne 0 ]]; then
            echo -e "  ${YELLOW}恢复 nf_conntrack_tcp_be_liberal: ${current_liberal} → 0${NC}"
            sysctl -w net.netfilter.nf_conntrack_tcp_be_liberal=0 >/dev/null 2>&1 || true
            ((restored++))
        fi
    fi

    # 恢复 nf_conntrack_helper
    if [[ -f /proc/sys/net/netfilter/nf_conntrack_helper ]]; then
        local current_helper
        current_helper=$(cat /proc/sys/net/netfilter/nf_conntrack_helper)
        if [[ "${current_helper}" -ne 0 ]]; then
            echo -e "  ${YELLOW}恢复 nf_conntrack_helper: ${current_helper} → 0${NC}"
            sysctl -w net.netfilter.nf_conntrack_helper=0 >/dev/null 2>&1 || true
            ((restored++))
        fi
    fi

    if [[ ${restored} -eq 0 ]]; then
        echo "  (宿主机 netfilter 参数正常，无需恢复)"
    fi
}

# =============================================================================
# 阶段4: 清理临时文件
# =============================================================================
cleanup_temp_files() {
    echo -e "${YELLOW}[阶段 4/5]${NC} 清理临时文件..."

    local cleaned=0

    # 清理故障注入记录文件
    local record_files
    record_files=$(ls /tmp/netfilter_test_*.json 2>/dev/null || true)
    if [[ -n "${record_files}" ]]; then
        rm -f /tmp/netfilter_test_*.json
        echo "  ${record_files}" | wc -l | xargs -I{} echo "  已清理 {} 个故障注入记录文件"
        ((cleaned++))
    fi

    # 清理诊断输出目录
    local diag_dirs
    diag_dirs=$(ls -d /tmp/netfilter_diag_* 2>/dev/null || true)
    if [[ -n "${diag_dirs}" ]]; then
        rm -rf /tmp/netfilter_diag_*
        echo "  已清理诊断输出目录"
        ((cleaned++))
    fi

    if [[ ${cleaned} -eq 0 ]]; then
        echo "  (无临时文件需要清理)"
    fi
}

# =============================================================================
# 阶段5: 清理 Docker 镜像（可选）
# =============================================================================
cleanup_image() {
    echo -e "${YELLOW}[阶段 5/5]${NC} 清理 Docker 镜像..."

    local image_name="netfilter-test:latest"
    if docker image ls --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -q "^${image_name}$"; then
        echo -e "  ${YELLOW}删除镜像 ${image_name}${NC}"
        docker rmi "${image_name}" 2>/dev/null && \
            echo -e "  ${GREEN}已删除${NC}" || \
            echo -e "  ${RED}删除失败（可能被其他容器引用）${NC}"
    else
        echo "  (无基础镜像需要清理)"
    fi
}

# =============================================================================
# 主流程
# =============================================================================
main() {
    local force_clean=false

    case "${1:-}" in
        --help|-h)
            echo "用法: bash cleanup_all.sh [选项]"
            echo ""
            echo "选项:"
            echo "  --force   强制清理（包括基础 Docker 镜像）"
            echo "  --help    显示此帮助"
            echo ""
            echo "默认行为: 清理容器、网络、系统参数、临时文件"
            echo "使用 --force 额外清理基础 Docker 镜像"
            exit 0
            ;;
        --force)
            force_clean=true
            ;;
    esac

    # 检查 Docker 是否可用
    if ! docker ps &>/dev/null; then
        echo -e "${RED}[WARN] Docker 不可用，跳过容器和网络清理${NC}"
    fi

    cleanup_containers
    echo ""

    if docker ps &>/dev/null; then
        cleanup_network
        echo ""
    fi

    cleanup_sysctl
    echo ""

    cleanup_temp_files
    echo ""

    if [[ "${force_clean}" == true ]] && docker ps &>/dev/null; then
        cleanup_image
        echo ""
    fi

    # 最后检查是否有残留
    echo -e "${BLUE}================================================================"
    echo " 清理完成检查"
    echo -e "================================================================${NC}"

    local remaining
    remaining=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep "^netfilter-fault-" || true)
    if [[ -n "${remaining}" ]]; then
        echo -e "${YELLOW}  尚有残留容器:${NC}"
        echo "${remaining}" | sed 's/^/    /'
    else
        echo -e "${GREEN}  所有故障注入容器已清理${NC}"
    fi

    echo ""
    echo -e "${GREEN}环境清理完成${NC}"
}

main "$@"
