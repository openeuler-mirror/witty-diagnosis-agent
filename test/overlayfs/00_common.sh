#!/usr/bin/env bash
# =============================================================================
# 脚本：00_common.sh
# 用途：OverlayFS 故障注入框架 —— 公共函数与容器管理
# 说明：本脚本为故障注入测试套件的公共库，提供统一的容器生命周期管理、
#       依赖检查、overlay 挂载辅助等基础能力。
#       所有故障注入通过 Docker 容器隔离执行，防止对宿主机造成影响。
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# 全局配置
# ─────────────────────────────────────────────────────────────────────────────
FIOVERLAY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "${FIOVERLAY_DIR}/.." && pwd)"
OUTPUT_DIR="/tmp/overlayfs_fault_test"

# 容器镜像配置
FIOVERLAY_IMAGE="ubuntu:22.04"
CONTAINER_PREFIX="overlayfs-fault"

# 容器内工作目录
CONTAINER_WORKDIR="/workspace"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ─────────────────────────────────────────────────────────────────────────────
# 通用工具函数
# ─────────────────────────────────────────────────────────────────────────────

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
header()  { echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo -e "${BLUE} $*${NC}"; echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; }

# ─────────────────────────────────────────────────────────────────────────────
# 依赖检查
# ─────────────────────────────────────────────────────────────────────────────

check_dependencies() {
    local missing=0

    if ! command -v docker &>/dev/null; then
        error "Docker 未安装。故障注入要求 Docker 环境进行容器隔离。"
        error "请安装 Docker: https://docs.docker.com/engine/install/"
        missing=1
    fi

    # 检查 docker 是否可正常执行
    if ! docker info &>/dev/null; then
        error "Docker 守护进程未运行或当前用户无权限访问。"
        error "请确认: sudo systemctl start docker 且当前用户有 socket 权限。"
        missing=1
    fi

    if [[ "${missing}" -eq 1 ]]; then
        exit 1
    fi

    info "Docker 环境就绪"
}

# ─────────────────────────────────────────────────────────────────────────────
# 容器管理
# ─────────────────────────────────────────────────────────────────────────────

# 获取容器的唯一标签名
_get_container_name() {
    local branch="$1"
    echo "${CONTAINER_PREFIX}-${branch}"
}

# 构建隔离测试容器镜像
# 基础镜像 + 安装 overlay 测试所需工具集
build_container_image() {
    local branch="$1"
    local container_name
    container_name="$(_get_container_name "${branch}")"

    header "构建隔离测试容器: ${container_name}"

    # 创建临时 Dockerfile
    local dockerfile
    dockerfile="$(mktemp)"
    cat > "${dockerfile}" << 'DOCKERFILE'
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# 安装 overlay 测试和相关诊断工具
RUN apt-get update && apt-get install -y --no-install-recommends \
    # 核心 overlay 工具
    attr \
    # 文件系统工具
    e2fsprogs \
    xfsprogs \
    # 性能分析
    strace \
    lsof \
    iotop \
    sysstat \
    time \
    # 文件监控
    inotify-tools \
    # 通用工具
    curl \
    jq \
    util-linux \
    coreutils \
    findutils \
    mount \
    && rm -rf /var/lib/apt/lists/*

# 容器需要特权模式来挂载 overlay 和 loop 设备，在 run 时动态添加 --privileged

WORKDIR /workspace

CMD ["/bin/bash"]
DOCKERFILE

    # 构建镜像（带进度信息）
    docker build -t "overlayfs-fault-base:latest" -f "${dockerfile}" . 2>&1 | tail -5 || {
        error "基础镜像构建失败"
        rm -f "${dockerfile}"
        return 1
    }

    rm -f "${dockerfile}"
    info "基础镜像构建完成: overlayfs-fault-base:latest"
    return 0
}

# 创建并启动隔离容器
# 返回: 容器 ID
start_container() {
    local branch="$1"
    local container_name
    container_name="$(_get_container_name "${branch}")"

    header "启动隔离容器: ${container_name}"

    # 检查是否已有同名容器在运行
    if docker ps --format '{{.Names}}' | grep -q "^${container_name}$"; then
        info "容器 ${container_name} 已在运行，复用"
        echo "${container_name}"
        return 0
    fi

    # 如果有停止的同名容器，先删除
    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        info "移除已存在的容器 ${container_name}"
        docker rm -f "${container_name}" >/dev/null 2>&1 || true
    fi

    # 创建新容器
    # --privileged: 需要挂载 overlay、loop 设备、创建文件系统等
    # --cap-add SYS_ADMIN: 需要 mount 系统调用（替代 --privileged 的最小权限）
    # --security-opt apparmor:unconfined: 避免 AppArmor 限制 mount
    docker run -d \
        --name "${container_name}" \
        --privileged \
        --security-opt apparmor:unconfined \
        --security-opt seccomp:unconfined \
        -v /lib/modules:/lib/modules:ro \
        -w "${CONTAINER_WORKDIR}" \
        overlayfs-fault-base:latest \
        /bin/bash -c "tail -f /dev/null" 2>&1 || {

        error "容器启动失败"
        return 1
    }

    info "容器 ${container_name} 已启动"
    echo "${container_name}"
}

# 进入容器执行命令
exec_in_container() {
    local container_name="$1"
    shift
    docker exec -i "${container_name}" bash -c "$*" 2>&1
}

# 停止并清理容器
stop_container() {
    local branch="$1"
    local container_name
    container_name="$(_get_container_name "${branch}")"

    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        info "停止并移除容器: ${container_name}"
        docker rm -f "${container_name}" >/dev/null 2>&1 || true
        info "已清理"
    else
        info "容器 ${container_name} 不存在，跳过"
    fi
}

# 智能等待（用于测试间的同步）
_wait_seconds() {
    local seconds="${1:-2}"
    for i in $(seq "${seconds}"); do
        sleep 1
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Overlay 测试环境辅助函数（在容器内执行）
# ─────────────────────────────────────────────────────────────────────────────

# 在容器内创建标准的 overlay 测试目录结构
# 参数: $1 - 基础路径（默认 /tmp/overlay_test）
setup_test_dirs() {
    local base="${1:-/tmp/overlay_test}"
    cat << BASH
mkdir -p "${base}"/{lower,upper,work,merged}
echo "Hello from lower (layer 0)" > "${base}/lower/hello.txt"
echo "lower-only content" > "${base}/lower/lower_only.txt"
BASH
}

# 在容器内创建多层 lowerdir 结构
setup_multi_lower_dirs() {
    local base="${1:-/tmp/overlay_test}"
    local layers="${2:-3}"
    cat << BASH
for i in \$(seq 0 \$((layers-1))); do
  mkdir -p "${base}/lower\${i}"
  echo "from lower layer \${i}" > "${base}/lower\${i}/layer_info.txt"
done
BASH
}

# 挂载一个标准的 overlay
mount_overlay() {
    local base="${1:-/tmp/overlay_test}"
    local extra_opts="${2:-}"
    local mount_point="${base}/merged"

    local cmd="mount -t overlay overlay"
    cmd+=" -o lowerdir=${base}/lower,upperdir=${base}/upper,workdir=${base}/work"
    [[ -n "${extra_opts}" ]] && cmd+=",${extra_opts}"
    cmd+=" ${mount_point}"

    echo "${cmd} 2>&1 || echo 'MOUNT_FAILED'"
}

# ─────────────────────────────────────────────────────────────────────────────
# 测试验证与报告
# ─────────────────────────────────────────────────────────────────────────────

# 记录测试结果并生成报告片段
record_result() {
    local branch="$1"
    local test_name="$2"
    local status="$3"  # PASS / FAIL
    local detail="$4"

    mkdir -p "${OUTPUT_DIR}"
    echo "[${status}] ${branch} | ${test_name} | ${detail}" >> "${OUTPUT_DIR}/results.log"

    if [[ "${status}" == "PASS" ]]; then
        info "[${branch}] ${test_name}: ✓ ${detail}"
    else
        error "[${branch}] ${test_name}: ✗ ${detail}"
    fi
}

# 生成 Markdown 测试报告
generate_report() {
    local output_file="${OUTPUT_DIR}/fault_injection_report.md"

    header "生成测试报告: ${output_file}"

    local total=0
    local passed=0
    local failed=0

    while IFS='|' read -r status rest; do
        total=$((total + 1))
        case "${status}" in
            *PASS*) passed=$((passed + 1)) ;;
            *FAIL*) failed=$((failed + 1)) ;;
        esac
    done < "${OUTPUT_DIR}/results.log" 2>/dev/null || true

    [[ "${total}" -eq 0 ]] && total=1

    cat > "${output_file}" << REPORT
# OverlayFS 故障注入测试报告

**生成时间**: $(date)
**宿主机内核**: $(uname -r)
**Docker 版本**: $(docker --version 2>/dev/null || echo 'N/A')

## 测试汇总

| 指标 | 值 |
|------|-----|
| 总计用例 | ${total} |
| 通过 | ${passed} |
| 失败 | ${failed} |
| 通过率 | $((passed * 100 / total))% |

## 详细结果

| 分支 | 测试名称 | 状态 | 详情 |
|------|---------|------|------|
REPORT

    while IFS='|' read -r status branch test_name detail; do
        # 去除空格
        status_clean=$(echo "${status}" | xargs)
        branch_clean=$(echo "${branch}" | xargs)
        test_clean=$(echo "${test_name}" | xargs)
        detail_clean=$(echo "${detail}" | xargs)
        echo "| ${branch_clean} | ${test_clean} | ${status_clean} | ${detail_clean} |" >> "${output_file}"
    done < <(sed 's/^\[\(.*\)\] \(.*\) | \(.*\) | \(.*\)$/\1|\2|\3|\4/' "${OUTPUT_DIR}/results.log" 2>/dev/null) || true

    echo "" >> "${output_file}"
    echo "---" >> "${output_file}"
    echo "_报告由 overlayfs 故障注入框架自动生成_" >> "${output_file}"

    info "测试报告已生成: ${output_file}"
    echo "${output_file}"
}

# ─────────────────────────────────────────────────────────────────────────────
# 主流程
# ─────────────────────────────────────────────────────────────────────────────

# 当本脚本被 source 而非直接执行时，不运行任何逻辑
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "这是 OverlayFS 故障注入框架的公共库脚本。"
    echo "请勿直接运行，应通过各分支注入脚本 source 引用。"
    echo ""
    echo "用法示例："
    echo "  source 00_common.sh"
    echo "  check_dependencies"
    echo '  CONTAINER=$(start_container "branch_A")'
    echo "  exec_in_container \${CONTAINER} 'mount | grep overlay'"
    echo "  stop_container \"branch_A\""
fi
