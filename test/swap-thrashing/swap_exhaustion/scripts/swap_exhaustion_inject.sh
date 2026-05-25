#!/bin/bash
#===============================================================================
# Swap Thrashing 分支A — Swap 空间耗尽 故障注入脚本
# 故障特征: swap 使用率 > 90%, memory.swap.events.max 触发, 但 si/so 不高
# 注入方式: 容器 memory=128m, swap=32m (总量160m), 分配 200MB → swap 迅速耗尽
# 预期结果: swap.max 事件触发, 容器可能 OOM killed (Exit 137)
#===============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
log_info() { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
log_fail() { echo -e "${RED}[FAIL]${NC}  $*"; }

CONTAINER="swap-thrash-branchA"
IMAGE="swap-thrasher"

pre_check() {
  echo -e "${CYAN}[1/5] 环境预检查${NC}"
  command -v docker >/dev/null || { log_fail "Docker 未安装"; exit 1; }
  log_ok "Docker: $(docker --version 2>/dev/null)"
  docker rm -f "$CONTAINER" 2>/dev/null || true
  log_ok "旧容器已清理"
}

build_image() {
  echo -e "${CYAN}[2/5] 构建镜像${NC}"
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

inject() {
  echo -e "${CYAN}[3/5] 注入 Swap 空间耗尽故障${NC}"
  echo "  容器配置:"
  echo "    memory.max     = 128 MB"
  echo "    memory.swap.max = 32 MB  (总量 160MB)"
  echo "  负载: 2 workers × 100MB = 200MB >> 160MB 总量"
  echo "  预期: swap 迅速耗尽, 触发 swap.max 事件"
  echo ""

  docker run -d --name "$CONTAINER" \
    --memory=128m --memory-swap=160m \
    "$IMAGE" \
    stress-ng --vm 2 --vm-bytes 100M --timeout 120s

  sleep 3

  if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    log_ok "容器已启动"
  else
    log_fail "容器启动失败"
    exit 1
  fi
}

wait_and_collect() {
  echo -e "${CYAN}[4/5] 采集故障证据${NC}"
  
  local max_wait=30
  local waited=0
  while [ $waited -lt $max_wait ]; do
    if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
      log_info "容器已退出, 收集退出信息"
      break
    fi
    sleep 3
    waited=$((waited + 3))
  done

  echo ""
  echo "--- 容器状态 ---"
  docker ps -a --filter "name=${CONTAINER}" --format '{{.Names}} {{.Status}} {{.ExitCode}}'

  # 如果容器还在运行, 采集 cgroup 指标
  if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    echo ""
    echo "--- cgroup memory.events ---"
    docker exec "$CONTAINER" cat /sys/fs/cgroup/memory.events 2>/dev/null || echo "无法读取"
    
    echo ""
    echo "--- cgroup swap ---"
    docker exec "$CONTAINER" cat /sys/fs/cgroup/memory.swap.current 2>/dev/null || echo "无法读取"
    docker exec "$CONTAINER" cat /sys/fs/cgroup/memory.swap.events 2>/dev/null || echo "无法读取"
    
    echo ""
    echo "--- 进程状态 ---"
    docker exec "$CONTAINER" ps aux 2>/dev/null | awk 'NR==1 || /stress-ng/'
  fi

  # 宿主机 swap 指标
  echo ""
  echo "--- 宿主机 swap 状态 ---"
  free -h | grep -i swap
  echo "si/so: $(vmstat 1 2 | tail -1 | awk '{print $7" "$8}') pages/s"
}

summary() {
  echo -e "${CYAN}[5/5] 判读与输出${NC}"

  local exit_code
  exit_code=$(docker inspect "$CONTAINER" --format '{{.State.ExitCode}}' 2>/dev/null || echo "running")
  
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║           分支A — Swap 空间耗尽 注入结果                    ║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo "  容器退出码: $exit_code"
  echo "  预期特征:"
  echo "    - swap.max 事件 > 0 (或容器因 OOM 退出)"
  echo "    - si/so 较低 (< 10,000 pages/s)"
  echo "    - 非 thrashing (没有双向对等换页)"
  echo ""

  # 输出 prompt
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║  复制以下内容到 opencode 聊天框, 触发全链路诊断             ║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
  echo ""
  echo -e "${GREEN}==============================================================${NC}"
  echo "容器 swap-thrash-branchA 运行异常, 容器已退出,"
  echo "怀疑是 swap 空间不够用导致的, 帮忙诊断一下原因。"
  echo -e "${GREEN}==============================================================${NC}"
  echo ""
}

main() {
  echo -e "${CYAN}"
  echo "  +-------------------------------------------------+"
  echo "  |   分支A: Swap 空间耗尽故障注入                    |"
  echo "  |   参数: 容器(128MB+32MB) + stress-ng 2x100MB     |"
  echo "  +-------------------------------------------------+"
  echo -e "${NC}"

  pre_check
  build_image
  inject
  wait_and_collect
  summary

  log_info "容器名: ${CONTAINER}"
  log_info "清理: docker rm -f ${CONTAINER}"
  log_info "或运行: ./swap_thrashing_cleanup.sh"
}

main "$@"
