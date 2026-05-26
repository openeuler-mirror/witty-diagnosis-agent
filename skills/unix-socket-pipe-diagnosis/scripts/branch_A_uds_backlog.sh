#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_A_uds_backlog.sh
# 用途：UDS listen backlog 满诊断
# 使用：bash branch_A_uds_backlog.sh [target_pid]
# 参数：
#   $1  目标 PID（可选；不指定则全系统扫描）
# =============================================================================

set -euo pipefail

TARGET_PID="${1:-}"

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  echo "用途：UDS listen backlog 满诊断"
  echo "使用：bash $0 [target_pid]"
  echo "  target_pid: 目标 PID（可选；不指定则全系统检测）"
  exit 0
fi

OUT_DIR="/tmp/uds_pipe_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "${OUT_DIR}"
echo "诊断输出目录: ${OUT_DIR}"
echo ""

echo "=================================================================="
echo " 分支A：UDS listen backlog 满诊断"
echo "=================================================================="

# A1. 列出所有 UDS listen socket 和 backlog 值
echo ""
echo "【A1】ss -xl：所有 UDS listen socket 及 backlog"
echo "------------------------------------------------------------------"
if ! command -v ss &>/dev/null; then
  echo "  ss 命令不可用，请安装 iproute2"
  exit 1
fi

ss -xl 2>/dev/null | tee "${OUT_DIR}/ss_xl.txt"
echo ""
echo "  backlog 列说明：Recv-Q = 当前待 accept 连接数，Send-Q = backlog 上限"

# A2. ss -xlp 含进程信息
echo ""
echo "【A2】ss -xlp：UDS listen socket 含进程绑定"
echo "------------------------------------------------------------------"
ss -xlp 2>/dev/null | tee "${OUT_DIR}/ss_xlp.txt"

# A3. ss -x 连接状态分布统计
echo ""
echo "【A3】ss -x：UDS 连接状态分布"
echo "------------------------------------------------------------------"
ss -x 2>/dev/null | awk 'NR>1 {print $2}' | sort | uniq -c | sort -rn | tee "${OUT_DIR}/ss_x_state_dist.txt"
echo ""

# A4. 判断哪些 socket backlog 已满或接近满
echo ""
echo "【A4】backlog 饱和度判定"
echo "------------------------------------------------------------------"
ss -xl 2>/dev/null | awk 'NR>1 {
  recvq=$3
  backlog=$4
  path=$5
  if (backlog+0 > 0) {
    pct = (recvq / backlog) * 100
    if (pct >= 80) {
      printf "  ⚠ 严重: %-40s Recv-Q=%-6d backlog=%-6d (%.0f%%)\n", path, recvq, backlog, pct
    } else if (pct >= 50) {
      printf "  !  告警: %-40s Recv-Q=%-6d backlog=%-6d (%.0f%%)\n", path, recvq, backlog, pct
    } else {
      printf "  OK:      %-40s Recv-Q=%-6d backlog=%-6d (%.0f%%)\n", path, recvq, backlog, pct
    }
  }
}' | tee "${OUT_DIR}/backlog_analysis.txt"

# A5. 结论
echo ""
echo "=================================================================="
echo " 分支A 诊断结论"
echo "=================================================================="

critical_count=$(grep -c '⚠' "${OUT_DIR}/backlog_analysis.txt" 2>/dev/null || true)
warn_count=$(grep -c '!' "${OUT_DIR}/backlog_analysis.txt" 2>/dev/null || true)

cat << EOF
  UDS listen socket 总数: $(ss -xl 2>/dev/null | wc -l)
  backlog 严重（>=80%）: ${critical_count}
  backlog 告警（>=50%）: ${warn_count}

  结论: $( [[ $critical_count -gt 0 ]] && echo "⚠ 检测到 backlog 满或接近满的 UDS listen socket，建议："
  echo "    - 增大 backlog：在 listen() 调用中增加 backlog 参数"
  echo "    - 加速 accept：检查 accept 循环是否被阻塞或效率不足"
  echo "    - 多 worker：考虑使用 SO_REUSEPORT 多进程分担" || echo "UDS listen backlog 正常" )
EOF
