#!/usr/bin/env bash
# diag_full.sh — 全量诊断（调用所有模块）
# 用途：故障类别未知时，一次性采集所有关键信息
# 使用：bash diag_full.sh [container_name_or_id]
# 输出：控制台 + /tmp/docker_diag_<timestamp>.txt

CONTAINER=""
KEYWORD=""
START_TIME=""
END_TIME=""

show_help() {
  echo "Usage: $(basename $0) [options]"
  echo "Options:"
  echo "  -c, --container <name>  Container name or ID (optional)"
  echo "  -k, --keyword <word>    Keyword to filter logs (optional)"
  echo "  -s, --start-time <time> Start time for logs (e.g. \"2023-10-01 12:00:00\", \"1 hour ago\")"
  echo "  -e, --end-time <time>   End time for logs (e.g. \"2023-10-01 13:00:00\")"
  echo "  -h, --help              Show this help message"
  exit 0
}

while [[ "$#" -gt 0 ]]; do
  case $1 in
    -c|--container) CONTAINER="$2"; shift 2 ;;
    -k|--keyword) KEYWORD="$2"; shift 2 ;;
    -s|--start-time) START_TIME="$2"; shift 2 ;;
    -e|--end-time) END_TIME="$2"; shift 2 ;;
    -h|--help) show_help ;;
    *) CONTAINER="$1"; shift ;; # Fallback for old positional arg
  esac
done
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
OUTFILE="/tmp/docker_diag_${TIMESTAMP}.txt"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SEP="========================================"

echo "全量诊断开始: $(date)"
echo "容器: ${CONTAINER:-'未指定'}"
echo "输出文件: $OUTFILE"
echo ""

run_module() {
  local name="$1"
  local script="$2"
  echo -e "\n\n${SEP}\n## 模块: ${name}\n${SEP}"
  if [ -f "$script" ]; then
    bash "$script" "$CONTAINER" 2>&1
  else
    echo "脚本不存在: $script"
  fi
}

{
  echo "========================================"
  echo "Docker 全量故障诊断报告"
  echo "时间: $(date)"
  echo "主机: $(hostname)"
  echo "容器: ${CONTAINER:-'未指定'}"
  echo "========================================"

  run_module "内核/系统调用" "${SCRIPT_DIR}/diag_kernel.sh"
  run_module "资源限制" "${SCRIPT_DIR}/diag_resource.sh"
  run_module "文件系统/存储" "${SCRIPT_DIR}/diag_storage.sh"
  run_module "网络" "${SCRIPT_DIR}/diag_network.sh"
  run_module "权限/安全" "${SCRIPT_DIR}/diag_security.sh"
  run_module "日志/时间" "${SCRIPT_DIR}/diag_logtime.sh"

  echo ""
  echo "${SEP}"
  echo "全量诊断完成: $(date)"
  echo "${SEP}"
} 2>&1 | tee "$OUTFILE"

echo ""
echo "诊断报告已保存至: $OUTFILE"
echo "文件大小: $(du -sh $OUTFILE | cut -f1)"
