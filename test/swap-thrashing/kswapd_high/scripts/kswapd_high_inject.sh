#!/bin/bash
#===============================================================================
# Swap Thrashing 分支F — kswapd 后台回收 真实故障注入脚本
#
# 原理: 容器不加 --memory 限制, 使用 stress-ng 持续占用 70% 宿主机内存
#       触发全局 kswapd 回收 (pgscan_kswapd=100%, pgscan_direct=0)
#       容器退出后自动恢复
#
# 用法:
#   ./swap_thrashing_inject_branchF.sh
#===============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info() { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
log_fail() { echo -e "${RED}[FAIL]${NC}  $*"; }

CONTAINER="swap-thrash-branchF"
IMAGE="swap-thrasher"
TOTAL_MB=$(free -m | awk '/^Mem:/{print $2}')

pre_check() {
  echo -e "${CYAN}[1/5] 环境预检查${NC}"
  command -v docker >/dev/null || { log_fail "Docker 未安装"; exit 1; }
  log_ok "Docker: $(docker --version 2>/dev/null)"
  docker rm -f "$CONTAINER" 2>/dev/null || true
  log_ok "旧容器已清理"
  log_info "宿主机内存: ${TOTAL_MB} MB"
}

build_image() {
  echo -e "${CYAN}[2/5] 构建镜像${NC}"
  if docker images --format '{{.Repository}}' | grep -q "^${IMAGE}$"; then
    log_ok "镜像已存在"
    return
  fi
  docker build -t "$IMAGE" -f- . <<'DOCKERFILE'
FROM ubuntu:22.04
RUN apt-get update -qq && apt-get install -y -qq stress-ng procps sysbench && rm -rf /var/lib/apt/lists/*
DOCKERFILE
  log_ok "镜像构建完成"
}

inject() {
  echo -e "${CYAN}[3/5] 注入 kswapd 后台回收压力${NC}"
  echo "  容器: 无 --memory 限制 → stress-ng 直接竞争宿主机内存"
  echo "  stress-ng --vm 2 --vm-bytes 70% --page-in --vm-keep"
  echo "  预期: pgscan_kswapd >> pgscan_direct"
  echo ""

  docker run -d --name "$CONTAINER" \
    "$IMAGE" \
    stress-ng --vm 2 --vm-bytes 70% --vm-keep --page-in --timeout 180s

  sleep 8

  if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    log_ok "容器已启动"
  else
    log_fail "容器启动失败"
    docker logs "$CONTAINER" 2>/dev/null | tail -5
    exit 1
  fi
}

collect() {
  echo -e "${CYAN}[4/5] 采集故障证据${NC}"
  sleep 20

  echo ""
  echo "--- vmstat (系统级) ---"
  echo "  si       so       cs       us   sy   id   wa"
  vmstat 1 5 | tail -1 | awk '{printf "  %-8s %-8s %-8s %-4s %-4s %-4s %-4s\n", $7, $8, $12, $13, $14, $15, $16}'

  echo ""
  echo "--- /proc/vmstat (reclaim 路径) ---"
  for key in pgscan_kswapd pgscan_direct pgsteal_kswapd pgsteal_direct \
             workingset_refault_anon pgrotated kswapd_low_wmark_hit_quickly; do
    grep "$key" /proc/vmstat 2>/dev/null | awk "{printf \"  %s\\n\", \$0}"
  done

  echo ""
  echo "--- 内存概况 ---"
  free -h

  echo ""
  echo "--- D 状态进程 ---"
  local d_count
  d_count=$(ps aux 2>/dev/null | awk '$8 ~ /^D/ {print}' | wc -l)
  log_info "D 状态进程: ${d_count} 个"
}

summary() {
  echo -e "${CYAN}[5/5] 判读与输出${NC}"

  local kswapd_val direct_val
  kswapd_val=$(grep pgscan_kswapd /proc/vmstat 2>/dev/null | awk '{print $2}')
  direct_val=$(grep pgscan_direct /proc/vmstat 2>/dev/null | awk '{print $2}')

  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║       分支F — kswapd 后台回收 真实注入结果                 ║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo "  pgscan_kswapd = ${kswapd_val:-N/A}"
  echo "  pgscan_direct = ${direct_val:-N/A}"
  echo "  kswapd 占比   = $(echo "scale=1; ${kswapd_val:-0} * 100 / (${kswapd_val:-0} + ${direct_val:-1})" | bc 2>/dev/null)%"
  echo "  预期: kswapd 主导回收 (区别于分支B的 direct reclaim)"
  echo ""

  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║  复制以下内容到 opencode 聊天框, 触发全链路诊断             ║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "${GREEN}==============================================================${NC}"
  echo "容器 swap-thrash-branchF 运行后宿主机 CPU 升高了,"
  echo "感觉内核一直在做内存回收, 看看是不是 kswapd 压力太大了。"
  echo -e "${GREEN}==============================================================${NC}"
  echo ""
}

main() {
  echo -e "${CYAN}"
  echo "  +-------------------------------------------------+"
  echo "  |   分支F: kswapd 后台回收 (stress-ng 真实注入)    |"
  echo "  |   无 memory 限制 + stress-ng 70% 内存           |"
  echo "  +-------------------------------------------------+"
  echo -e "${NC}"

  pre_check
  build_image
  inject
  collect
  summary

  log_info "容器名: ${CONTAINER}"
  log_info "清理: ./swap_thrashing_cleanup_branchF.sh"
}

main "$@"
