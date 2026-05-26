#!/bin/bash
#===============================================================================
# Swap Thrashing 分支C — Swappiness=100 真实故障注入脚本
#
# 原理: 通过 privileged 容器设置宿主机 swappiness=100, 然后启动混合负载
#       (文件缓存+匿名页), swappiness=100 导致内核在文件缓存充足时优先换出
#       匿名页, 产生 si>0 so=0 的轻度换页特征
#       完成后自动恢复 swappiness=60
#
# 用法:
#   ./swap_thrashing_inject_branchC.sh
#===============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info() { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
log_fail() { echo -e "${RED}[FAIL]${NC}  $*"; }

CONTAINER="swap-thrash-branchC"
IMAGE="swap-thrasher"

# 记录初始 swappiness
CURRENT_SWAP=$(cat /proc/sys/vm/swappiness)

set_swappiness() {
  local val=$1
  docker run --rm --privileged ubuntu:22.04 sysctl -w "vm.swappiness=$val" > /dev/null 2>&1
}

cleanup_host() {
  set_swappiness "$CURRENT_SWAP"
  log_info "swappiness 已恢复为: $(cat /proc/sys/vm/swappiness)"
}

pre_check() {
  echo -e "${CYAN}[1/6] 环境预检查${NC}"
  command -v docker >/dev/null || { log_fail "Docker 未安装"; exit 1; }
  log_ok "Docker: $(docker --version 2>/dev/null)"
  docker rm -f "$CONTAINER" 2>/dev/null || true
  log_ok "旧容器已清理"
  log_info "当前 swappiness: $CURRENT_SWAP (将设为 100 再恢复)"
}

build_image() {
  echo -e "${CYAN}[2/6] 构建镜像${NC}"
  if docker images --format '{{.Repository}}' | grep -q "^${IMAGE}$"; then
    log_ok "镜像已存在"
    return
  fi
  docker build -t "$IMAGE" -f- . <<'DOCKERFILE'
FROM ubuntu:22.04
RUN apt-get update -qq && apt-get install -y -qq stress-ng procps && rm -rf /var/lib/apt/lists/*
DOCKERFILE
  log_ok "镜像构建完成"
}

set_swappiness_100() {
  echo -e "${CYAN}[3/6] 设置 swappiness=100${NC}"
  log_info "当前: $CURRENT_SWAP → 设为 100"
  set_swappiness 100
  log_ok "swappiness = $(cat /proc/sys/vm/swappiness)"
}

inject() {
  echo -e "${CYAN}[4/6] 注入混合负载 (文件缓存 + 匿名页)${NC}"
  echo "  容器配置:"
  echo "    memory.max      = 256 MB"
  echo "    memory.swap.max = 256 MB (总量 512MB)"
  echo "  负载: dd 180MB 文件缓存 + stress-ng 1×200M 匿名页"
  echo "  swappiness=100: 优先换出匿名页而非回收文件缓存"
  echo ""

  docker run -d --name "$CONTAINER" \
    --memory=256m --memory-swap=512m \
    "$IMAGE" \
    bash -c '
dd if=/dev/zero of=/tmp/f bs=1M count=180 2>/dev/null
while true; do cat /tmp/f > /dev/null 2>&1; done &
stress-ng --vm 1 --vm-bytes 200M --vm-keep --page-in --timeout 120s
' 2>/dev/null

  sleep 5

  if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    log_ok "容器已启动"
  else
    log_fail "容器启动失败"
    cleanup_host
    exit 1
  fi
}

collect() {
  echo -e "${CYAN}[5/6] 采集故障证据${NC}"
  sleep 15

  echo ""
  echo "--- vmstat (系统级) ---"
  echo "  si       so       cs       us   sy   id   wa"
  vmstat 1 5 | tail -1 | awk '{printf "  %-8s %-8s %-8s %-4s %-4s %-4s %-4s\n", $7, $8, $12, $13, $14, $15, $16}'

  echo ""
  echo "--- 容器 cgroup ---"
  if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    local mem_cur swap_cur
    mem_cur=$(docker exec "$CONTAINER" cat /sys/fs/cgroup/memory.current 2>/dev/null)
    swap_cur=$(docker exec "$CONTAINER" cat /sys/fs/cgroup/memory.swap.current 2>/dev/null)
    echo "  memory: $(( mem_cur / 1024 / 1024 )) MB / 256 MB"
    echo "  swap:   $(( swap_cur / 1024 / 1024 )) MB / 256 MB"
    echo ""
    echo "--- memory.events ---"
    docker exec "$CONTAINER" cat /sys/fs/cgroup/memory.events 2>/dev/null
  fi

  echo ""
  echo "--- 进程状态 ---"
  docker exec "$CONTAINER" ps aux 2>/dev/null | awk 'NR==1 || /stress-ng/'
  local d_count
  d_count=$(docker exec "$CONTAINER" ps aux 2>/dev/null | awk '$8 ~ /^D/ {print}' | wc -l)
  echo "  D 状态进程: ${d_count} 个"
}

summary() {
  echo -e "${CYAN}[6/6] 判读与输出${NC}"

  local si so
  si=$(vmstat 1 2 | tail -1 | awk '{print $7}')
  so=$(vmstat 1 2 | tail -1 | awk '{print $8}')

  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║       分支C — Swappiness=100 真实注入结果                  ║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo "  swappiness=100 $(cat /proc/sys/vm/swappiness | grep -q 100 && echo '(已生效)' || echo '(待验证)')"
  echo "  si/so: ${si}/${so} pages/s"
  echo "  预期特征:"
  echo "    ● swappiness=100 使内核优先换出匿名页"
  echo "    ● 文件缓存充足时仍触发 swap 换入 (si > 0)"
  echo "    ● 非双向 thrashing (区别于分支B)"
  echo ""

  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║  复制以下内容到 opencode 聊天框, 触发全链路诊断             ║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "${GREEN}==============================================================${NC}"
  echo "容器 swap-thrash-branchC 运行后感觉系统在用 swap,"
  echo "但没到卡死的程度, 帮忙看一下 swap 使用是否正常,"
  echo "是不是 swappiness 设置有问题导致的。"
  echo -e "${GREEN}==============================================================${NC}"
  echo ""
}

main() {
  echo -e "${CYAN}"
  echo "  +-------------------------------------------------+"
  echo "  |   分支C: Swappiness=100 真实故障注入              |"
  echo "  |   容器(256MB+256MB swappiness=100) + 混合负载    |"
  echo "  +-------------------------------------------------+"
  echo -e "${NC}"

  # 确保退出时恢复 swappiness
  trap cleanup_host EXIT

  pre_check
  build_image
  set_swappiness_100
  inject
  collect
  summary

  log_info "容器名: ${CONTAINER}"
  log_info "清理: docker rm -f ${CONTAINER}"
}

main "$@"
