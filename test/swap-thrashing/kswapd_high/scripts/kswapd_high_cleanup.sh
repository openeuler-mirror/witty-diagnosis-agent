#!/bin/bash
#===============================================================================
# 清理 分支F — kswapd 后台回收 测试环境
# 清理: 容器 swap-thrash-branchF
# 用法:
#   ./swap_thrashing_cleanup_branchF.sh
#===============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info() { echo -e "  ${CYAN}[INFO]${NC} $*"; }
log_ok()   { echo -e "  ${GREEN}[OK]${NC}   $*"; }

CONTAINER="swap-thrash-branchF"

clean_container() {
  if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER}$"; then
    docker rm -f "$CONTAINER" >/dev/null 2>&1
    log_ok "容器 ${CONTAINER} 已删除"
  else
    log_info "无残留容器"
  fi
}

main() {
  echo -e "${CYAN}"
  echo "  +---------------------------------------------+"
  echo "  |   清理 分支F: kswapd 后台回收                 |"
  echo "  +---------------------------------------------+"
  echo -e "${NC}"
  clean_container
  log_info "清理完成"
}

main "$@"
