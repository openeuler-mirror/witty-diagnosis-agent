#!/bin/bash
#===============================================================================
# Swap Thrashing 测试环境清理脚本
# 清理：测试容器、测试镜像、诊断报告（可选）
# 用法：
#   ./test_swap_thrashing_cleanup.sh              # 只清理容器
#   ./test_swap_thrashing_cleanup.sh --all        # 清理容器 + 镜像 + 报告
#   ./test_swap_thrashing_cleanup.sh --report     # 只清理报告
#===============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'
log_info() { echo -e "  ${CYAN}[INFO]${NC} $*"; }
log_ok()   { echo -e "  ${GREEN}[OK]${NC}   $*"; }
log_warn() { echo -e "  ${YELLOW}[WARN]${NC} $*"; }

CONTAINER_PREFIX="st-test"
CONTAINER_NAMES=("swap-thrash-test" "swap-thrash-demo")
IMAGE_NAME="swap-thrasher"
REPORT_DIRS=(
  "/home/win11/.witty-diagnosis-agent/kuafu"
  "/home/win11/.witty-diagnosis-agent/dayu/report"
  "/home/win11/.witty-diagnosis-agent/dayu/plans"
  "/home/win11/.witty-diagnosis-agent/baize/reports"
  "/home/win11/.witty-diagnosis-agent/fuxi"
  "/home/win11/.witty-diagnosis-agent/nuwa/solutions"
  "/home/win11/.witty-diagnosis-agent/nuwa/knowledge"
)

clean_containers() {
  echo ""
  log_info "清理测试容器..."

  # 清理指定名称的容器
  for name in "${CONTAINER_NAMES[@]}"; do
    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${name}$"; then
      docker rm -f "$name" >/dev/null 2>&1
      log_ok "容器 ${name} 已删除"
    fi
  done

  # 清理测试套件容器 (st-test-tc*)
  for container in $(docker ps -a --format '{{.Names}}' 2>/dev/null | grep "^${CONTAINER_PREFIX}-tc"); do
    docker rm -f "$container" >/dev/null 2>&1
    log_ok "容器 ${container} 已删除"
  done
}

clean_image() {
  echo ""
  log_info "清理测试镜像..."

  if docker images --format '{{.Repository}}' 2>/dev/null | grep -q "^${IMAGE_NAME}$"; then
    docker rmi -f "${IMAGE_NAME}" >/dev/null 2>&1
    log_ok "镜像 ${IMAGE_NAME} 已删除"
  else
    log_info "无测试镜像残留"
  fi
}

clean_reports() {
  echo ""
  log_info "清理诊断报告文件..."

  local cleaned=0
  for dir in "${REPORT_DIRS[@]}"; do
    if [ -d "$dir" ]; then
      # 只清理本次测试产生的文件（含 swap-thrash/st-test 关键词的文件）
      local count
      count=$(find "$dir" -name "*swap*thrash*" -o -name "*st-test*" -o -name "*thrash*" 2>/dev/null | wc -l)
      if [ "$count" -gt 0 ]; then
        find "$dir" -name "*swap*thrash*" -o -name "*st-test*" -o -name "*thrash*" -exec rm -f {} \; 2>/dev/null
        log_ok "${dir}: 清理了 ${count} 个文件"
        cleaned=$((cleaned + count))
      fi
    fi
  done

  if [ "$cleaned" -eq 0 ]; then
    log_info "无诊断报告残留"
  else
    log_info "共清理 ${cleaned} 个报告文件"
  fi
}

clean_all() {
  clean_containers
  clean_image
  clean_reports
}

status_check() {
  echo ""
  log_info "清理后状态检查："

  local containers
  containers=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E "(swap-thrash|${CONTAINER_PREFIX}-tc)" | wc -l)
  if [ "$containers" -eq 0 ]; then
    log_ok "容器: 无残留"
  else
    log_warn "容器: ${containers} 个残留"
  fi

  if docker images --format '{{.Repository}}' 2>/dev/null | grep -q "^${IMAGE_NAME}$"; then
    log_warn "镜像: ${IMAGE_NAME} 仍存在"
  else
    log_ok "镜像: 无残留"
  fi

  local reports
  reports=$(find "${REPORT_DIRS[@]}" -name "*swap*thrash*" -o -name "*thrash*" 2>/dev/null | wc -l)
  if [ "$reports" -eq 0 ]; then
    log_ok "报告文件: 无残留"
  else
    log_warn "报告文件: ${reports} 个残留（可用 --all 清理）"
  fi
}

#===============================================================================
# 主入口
#===============================================================================
main() {
  local mode="container"

  for arg in "$@"; do
    case $arg in
      --all)    mode="all" ;;
      --report) mode="report" ;;
      --status) mode="status" ;;
      --help)
        echo "用法: $0 [选项]"
        echo "  （无参数）  只清理测试容器"
        echo "  --all       清理容器 + 镜像 + 诊断报告"
        echo "  --report    只清理诊断报告"
        echo "  --status    检查残留状态（不清理）"
        exit 0
        ;;
    esac
  done

  echo -e "${CYAN}"
  echo "  +---------------------------------------------+"
  echo "  |   Swap Thrashing 测试环境清理                 |"
  echo "  +---------------------------------------------+"
  echo -e "${NC}"

  case $mode in
    container) clean_containers ;;
    all)       clean_all ;;
    report)    clean_reports ;;
    status)    status_check ;;
  esac

  if [ "$mode" != "status" ]; then
    status_check
  fi

  echo ""
  log_info "清理完成"
}

main "$@"
