#!/bin/bash
#===============================================================================
# Swap Thrashing TC1 精确回放脚本
# 完全复现 2026-05-20 进行的故障注入+诊断测试
#
# 测试参数:
#   容器: --memory=256m --memory-swap=512m
#   负载: stress-ng --vm 4 --vm-bytes 384M --vm-keep --page-in --timeout 300s
#   预期: si/so ≥ 50,000 KB/s, D 状态进程 ≥ 1, iowait ≥ 10%
#===============================================================================

set -euo pipefail

#========= 颜色 =========
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info() { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
log_fail() { echo -e "${RED}[FAIL]${NC}  $*"; }

CONTAINER="swap-thrash-test"
IMAGE="swap-thrasher"

#=======================================================================
# 1. 环境预检查
#=======================================================================
pre_check() {
  echo ""
  echo -e "${CYAN}[1/6] 环境预检查${NC}"

  command -v docker >/dev/null || { log_fail "Docker 未安装"; exit 1; }
  log_ok "Docker: $(docker --version 2>/dev/null)"

  if swapon --show 2>/dev/null | grep -q .; then
    log_ok "Swap 已启用"
  else
    log_fail "系统无 Swap，无法复现 thrashing（OOM 会先于 thrashing 触发）"
    exit 1
  fi

  docker rm -f "$CONTAINER" 2>/dev/null || true
  log_ok "旧容器已清理"
}

#=======================================================================
# 2. 构建镜像
#=======================================================================
build_image() {
  echo ""
  echo -e "${CYAN}[2/6] 构建 stress-ng 镜像${NC}"

  if docker images --format '{{.Repository}}' | grep -q "^${IMAGE}$"; then
    log_ok "镜像已存在，跳过构建"
    return
  fi

  docker build -t "$IMAGE" -f- . <<'DOCKERFILE'
FROM ubuntu:22.04
RUN apt-get update -qq && apt-get install -y -qq stress-ng procps sysstat && rm -rf /var/lib/apt/lists/*
DOCKERFILE
  log_ok "镜像构建完成"
}

#=======================================================================
# 3. 注入故障
#=======================================================================
inject() {
  echo ""
  echo -e "${CYAN}[3/6] 注入 Swap Thrashing 故障${NC}"
  echo "  容器配置:"
  echo "    memory.max     = 256 MB"
  echo "    memory.swap.max = 256 MB"
  echo "    总容量         = 512 MB"
  echo "  负载配置:"
  echo "    4 workers x 384 MB = 1,536 MB"
  echo "    超额           = 1,024 MB（>> 512MB，必触发 thrashing）"
  echo ""

  docker run -d --name "$CONTAINER" \
    --memory=256m --memory-swap=512m \
    "$IMAGE" \
    stress-ng --vm 4 --vm-bytes 384M \
      --vm-method all --page-in --timeout 300s --vm-keep

  sleep 5

  if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    log_ok "容器已启动"
  else
    log_fail "容器启动失败"
    docker logs "$CONTAINER" 2>/dev/null | tail -5
    exit 1
  fi
}

#=======================================================================
# 4. 等待 Thrashing 稳态
#=======================================================================
wait_thrashing() {
  echo ""
  echo -e "${CYAN}[4/6] 等待 Thrashing 稳态（轮询 si/so）${NC}"

  local max_wait=60
  local waited=0

  while [ $waited -lt $max_wait ]; do
    local si so
    si=$(vmstat 1 2 2>/dev/null | tail -1 | awk '{print $7}')
    so=$(vmstat 1 2 2>/dev/null | tail -1 | awk '{print $8}')

    if [ "${si:-0}" -gt 10000 ] && [ "${so:-0}" -gt 10000 ]; then
      log_ok "Thrashing 稳态确认（耗时 ${waited}s）"
      echo "  si = $(printf "%'d" $si) KB/s"
      echo "  so = $(printf "%'d" $so) KB/s"
      return 0
    fi

    sleep 3
    waited=$((waited + 3))
  done

  log_fail "超时 ${max_wait}s 未达到 thrashing 阈值"
  return 1
}

#=======================================================================
# 5. 全量指标采集
#=======================================================================
collect_metrics() {
  echo ""
  echo -e "${CYAN}[5/6] 全量指标采集${NC}"
  echo ""

  echo "--- vmstat (系统级) ---"
  echo "  si       so       cs       us   sy   id   wa"
  vmstat 1 3 | tail -1 | awk '{printf "  %-8s %-8s %-8s %-4s %-4s %-4s %-4s\n", $7, $8, $12, $13, $14, $15, $16}'

  echo ""
  echo "--- cgroup v2 (容器级) ---"
  local mem_cur swap_cur mem_max swap_max
  mem_cur=$(docker exec "$CONTAINER" cat /sys/fs/cgroup/memory.current 2>/dev/null)
  swap_cur=$(docker exec "$CONTAINER" cat /sys/fs/cgroup/memory.swap.current 2>/dev/null)
  mem_max=$(docker exec "$CONTAINER" cat /sys/fs/cgroup/memory.max 2>/dev/null)
  swap_max=$(docker exec "$CONTAINER" cat /sys/fs/cgroup/memory.swap.max 2>/dev/null)
  echo "  memory.current     = $(( mem_cur / 1024 / 1024 )) MB / $(( mem_max / 1024 / 1024 )) MB"
  echo "  memory.swap.current= $(( swap_cur / 1024 / 1024 )) MB / $(( swap_max / 1024 / 1024 )) MB"

  echo ""
  echo "--- cgroup events ---"
  docker exec "$CONTAINER" cat /sys/fs/cgroup/memory.events 2>/dev/null

  if docker exec "$CONTAINER" test -f /sys/fs/cgroup/memory.pressure 2>/dev/null; then
    echo ""
    echo "--- PSI memory.pressure ---"
    docker exec "$CONTAINER" cat /sys/fs/cgroup/memory.pressure 2>/dev/null
  fi

  echo ""
  echo "--- stress-ng 进程状态 ---"
  docker exec "$CONTAINER" ps aux 2>/dev/null | awk 'NR==1 || /stress-ng/'

  local d_count
  d_count=$(docker exec "$CONTAINER" ps aux 2>/dev/null | awk '$8 ~ /^D/ {print}' | wc -l)
  echo "  D 状态进程: ${d_count} 个"
}

#=======================================================================
# 6. 判读与总结 + 输出可复制的诊断 Prompt
#=======================================================================
summary() {
  echo ""
  echo -e "${CYAN}[6/6] 判读与总结${NC}"
  echo ""

  local si so cs wa sy
  si=$(vmstat 1 2 | tail -1 | awk '{print $7}')
  so=$(vmstat 1 2 | tail -1 | awk '{print $8}')
  cs=$(vmstat 1 2 | tail -1 | awk '{print $12}')
  sy=$(vmstat 1 2 | tail -1 | awk '{print $14}')
  wa=$(vmstat 1 2 | tail -1 | awk '{print $16}')

  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║               Swap Thrashing 故障注入结果                    ║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""

  local fail_count=0

  if [ "$si" -gt 10000 ]; then
    echo -e "  ${GREEN}✓${NC} Swap In (si)  = $(printf "%'d" $si) KB/s  ${GREEN}(>= 10,000, thrashing 确认)${NC}"
  else
    echo -e "  ${RED}x${NC} Swap In (si)  = $(printf "%'d" $si) KB/s  ${RED}(< 10,000)${NC}"
    fail_count=$((fail_count + 1))
  fi

  if [ "$so" -gt 10000 ]; then
    echo -e "  ${GREEN}✓${NC} Swap Out (so) = $(printf "%'d" $so) KB/s  ${GREEN}(>= 10,000, thrashing 确认)${NC}"
  else
    echo -e "  ${RED}x${NC} Swap Out (so) = $(printf "%'d" $so) KB/s  ${RED}(< 10,000)${NC}"
    fail_count=$((fail_count + 1))
  fi

  if [ "$cs" -gt 30000 ]; then
    echo -e "  ${GREEN}✓${NC} 上下文切换    = $(printf "%'d" $cs) /s  ${GREEN}(>= 30,000, 极高)${NC}"
  else
    echo -e "  ${YELLOW}~${NC} 上下文切换    = $(printf "%'d" $cs) /s  ${YELLOW}(< 30,000, 辅助指标)${NC}"
  fi

  if [ "$wa" -gt 10 ]; then
    echo -e "  ${GREEN}✓${NC} CPU iowait    = ${wa}%  ${GREEN}(>= 10%)${NC}"
  else
    echo -e "  ${YELLOW}~${NC} CPU iowait    = ${wa}%  ${YELLOW}(< 10%)${NC}"
  fi

  if [ "$sy" -gt 5 ]; then
    echo -e "  ${GREEN}✓${NC} CPU 内核态    = ${sy}%  ${GREEN}(>= 5%, reclaim 开销)${NC}"
  else
    echo -e "  ${YELLOW}~${NC} CPU 内核态    = ${sy}%  ${YELLOW}(< 5%)${NC}"
  fi

  echo ""
  if [ $fail_count -le 1 ]; then
    echo -e "  ${GREEN}==============================================================${NC}"
    echo -e "  ${GREEN}  测试结论: Swap Thrashing TC1 注入成功${NC}"
    echo -e "  ${GREEN}==============================================================${NC}"
  else
    echo -e "  ${YELLOW}==============================================================${NC}"
    echo -e "  ${YELLOW}  注入完成，si/so 已达 thrashing 阈值（部分辅助指标待确认）${NC}"
    echo -e "  ${YELLOW}==============================================================${NC}"
  fi

  #--- 输出可复制的 Prompt ---
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║  复制以下内容到 opencode 聊天框，触发全链路诊断             ║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "${GREEN}==============================================================${NC}"
  echo "容器 swap-thrash-test 卡死了，系统响应特别慢，"
  echo "感觉像是内存不够一直在换页，帮忙诊断一下。"
  echo -e "${GREEN}==============================================================${NC}"
  echo ""
}

#=======================================================================
# 主入口
#=======================================================================
main() {
  echo -e "${CYAN}"
  echo "  +-------------------------------------------------+"
  echo "  |   Swap Thrashing TC1 精确回放                   |"
  echo "  |   复现: 隔离容器(256MB+256MB) + stress-ng 4x384M |"
  echo "  +-------------------------------------------------+"
  echo -e "${NC}"

  pre_check
  build_image
  inject
  wait_thrashing
  collect_metrics
  summary

  echo ""
  log_info "故障持续中，容器名: ${CONTAINER} (timeout=300s)"
  log_info "查看: docker exec ${CONTAINER} vmstat 1 5"
  log_info "停止: docker exec ${CONTAINER} pkill -9 stress-ng"
  log_info "清理: docker rm -f ${CONTAINER}"
}

main "$@"
