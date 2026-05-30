#!/usr/bin/env bash
# ================================================================
# inject_loop.sh - 注入持续运行的故障（供 agent 自动诊断用）
#
# 与 inject.sh 区别：
#   inject.sh      → 跑固定次数后退出，strace日志自带
#   inject_loop.sh → 故障持续运行(--loop)，agent可attach strace诊断
#
# 典型测试流程：
#   终端1: ./inject_loop.sh a eacces     # 持续注入EACCES
#   终端2: PID=$(docker inspect ... --format '{{.State.Pid}}')
#          bash 01_baseline_info.sh $PID 15
#
# 用法: ./inject_loop.sh <branch> <mode>
# ================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

usage() {
    echo "Usage: $0 <branch> <mode>"
    echo ""
    echo "启动一个持续运行故障的容器，PID=1为故障程序本身"
    echo "agent 诊断时直接 attach 到这个 PID 即可"
    echo ""
    echo "Branches & Modes:"
    echo "  a - eacces | enoent | eagain | enomem | all"
    echo "  b - futex | slowio | slowopen | all"
    echo "  c - mallocfreq | callpath | all"
    echo "  d - fd_leak | mmap_leak | all"
    echo "  e - econnrefused | econnreset | epipe | eaddrinuse | all"
    echo "  f - eintr | sigpipe | all"
    echo "  g - fork_storm | execve_fail | zombie | all"
    echo ""
    echo "Examples:"
    echo "  ./inject_loop.sh a eacces"
    echo "  ./inject_loop.sh b futex"
    echo ""
    echo "诊断完成后清理:"
    echo "  ./cleanup_loop.sh <branch>"
    exit 1
}

get_binary() {
    case "$1" in a|A) echo "branch_a_errors" ;; b|B) echo "branch_b_slow" ;;
        c|C) echo "branch_c_library" ;; d|D) echo "branch_d_leak" ;;
        e|E) echo "branch_e_network" ;; f|F) echo "branch_f_signal" ;;
        g|G) echo "branch_g_lifecycle" ;; *) echo "" ;; esac
}

if [ $# -lt 2 ]; then usage; fi

BRANCH="$1"; MODE="$2"
BINARY=$(get_binary "${BRANCH}")
if [ -z "$BINARY" ]; then print_error "Unknown branch"; usage; fi

check_prereqs
ensure_image

CNAME="strace-fi-loop-${BRANCH}-${MODE}-$(date +%s)"
OUTPATH=$(output_path "loop_${BRANCH}" "${MODE}")
mkdir -p "${OUTPATH}"

print_header "持续注入故障: Branch ${BRANCH} - ${MODE}"
print_info "容器名称: ${CNAME}"
print_info "故障程序 PID=1（容器主进程），agent 直接 attach"

# 运行故障程序（--loop模式），PID=1就是故障进程
docker run -d --name "${CNAME}" \
    --cap-add=SYS_PTRACE \
    --cap-add=NET_ADMIN \
    --cap-add=SYS_ADMIN \
    --security-opt seccomp=unconfined \
    -v "${OUTPATH}:/output" \
    "${DOCKER_IMAGE}" \
    "/usr/local/bin/${BINARY} --loop ${MODE}"

sleep 2
CONTAINER_PID=$(docker inspect "${CNAME}" --format '{{.State.Pid}}')
echo "${CNAME}" > "${OUTPATH}/container_name.txt"
echo "${BINARY} --loop ${MODE}" > "${OUTPATH}/fault_info.txt"
echo "PID=${CONTAINER_PID}" > "${OUTPATH}/container_pid.txt"

print_info ""
print_info "========================================"
echo -e "  ${GREEN}容器已启动${NC}"
echo -e "  故障:     ${BINARY} --loop ${MODE}"
echo -e "  容器PID:  ${CONTAINER_PID}"
echo -e "  容器名:   ${CNAME}"
print_info "========================================"
print_info ""
print_info "运行 agent 诊断:"
echo ""
echo "  cd /home/win11/.config/opencode/skills/strace-syscall-diagnosis/scripts"
echo "  bash 01_baseline_info.sh ${CONTAINER_PID} 15"
echo ""
print_info "诊断完成后清理:"
echo "  ./cleanup_loop.sh ${BRANCH} ${MODE}"
