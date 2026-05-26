#!/bin/bash
#===============================================================================
# 清理 分支C — Swappiness=100 测试环境
# 清理: 容器 swap-thrash-branchC + 恢复 swappiness
# 用法:
#   ./swap_thrashing_cleanup_branchC.sh
#===============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info() { echo -e "  ${CYAN}[INFO]${NC} $*"; }
log_ok()   { echo -e "  ${GREEN}[OK]${NC}   $*"; }

CONTAINER="swap-thrash-branchC"

clean_container() {
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER}$"; then
    docker rm -f "$CONTAINER" >/dev/null 2>&1
    log_ok "容器 ${CONTAINER} 已删除"
  else
    log_info "无残留容器"
  fi
}

restore_swappiness() {
  local current
  current=$(cat /proc/sys/vm/swappiness 2>/dev/null)
  if [ "$current" != "60" ]; then
    docker run --rm --privileged ubuntu:22.04 sysctl -w vm.swappiness=60 > /dev/null 2>&1
    log_ok "swappiness 已恢复: $(cat /proc/sys/vm/swappiness)"
  else
    log_info "swappiness 已是 60（默认值）"
  fi
}

main() {
  echo -e "${CYAN}"
  echo "  +---------------------------------------------+"
  echo "  |   清理 分支C: Swappiness=100                  |"
  echo "  +---------------------------------------------+"
  echo -e "${NC}"
  clean_container
  restore_swappiness
  log_info "清理完成"
}

main "$@"
