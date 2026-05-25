#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_F_sigpipe.sh
# 用途：SIGPIPE 信号诊断
# 使用：bash branch_F_sigpipe.sh <target_pid>
# 参数：
#   $1  目标 PID（必选）
# =============================================================================

set -euo pipefail

TARGET_PID="${1:-}"

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]] || [[ -z "$TARGET_PID" ]]; then
  echo "用途：SIGPIPE 信号诊断"
  echo "使用：bash $0 <target_pid>"
  echo "  target_pid: 目标进程 PID（必选）"
  exit 0
fi

if [[ ! -d "/proc/${TARGET_PID}" ]]; then
  echo "[错误] PID ${TARGET_PID} 不存在"
  exit 1
fi

OUT_DIR="/tmp/uds_pipe_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "${OUT_DIR}"
echo "诊断输出目录: ${OUT_DIR}"
echo ""

echo "=================================================================="
echo " 分支F：SIGPIPE 信号诊断"
echo " 目标 PID: ${TARGET_PID}"
echo "=================================================================="

# F1. cat /proc/PID/status | grep -E "SigIgn|SigCgt"
echo ""
echo "【F1】进程信号处理状态"
echo "------------------------------------------------------------------"
if [[ -r "/proc/${TARGET_PID}/status" ]]; then
  grep -E "SigIgn|SigCgt|SigBlk" "/proc/${TARGET_PID}/status" | tee "${OUT_DIR}/signal_status.txt"
else
  echo "  /proc/${TARGET_PID}/status 不可读"
  exit 1
fi

# F2. 解析 SIGPIPE(13) 位掩码
echo ""
echo "【F2】SIGPIPE(13) 位掩码解析"
echo "------------------------------------------------------------------"
# SIGPIPE=13, bit index = 12 (0-based)
# 位掩码是 16 进制大端表示，需要从右往左数 bit

sigign_hex=$(grep "SigIgn" "/proc/${TARGET_PID}/status" 2>/dev/null | awk '{print $2}' || echo "0")
sigcgt_hex=$(grep "SigCgt" "/proc/${TARGET_PID}/status" 2>/dev/null | awk '{print $2}' || echo "0")

echo "  SigIgn (16 进制): ${sigign_hex}"
echo "  SigCgt (16 进制): ${sigcgt_hex}"

# 将 16 进制转换为 10 进制，检查 SIGPIPE(13) bit
# bit position for SIGPIPE = 13 - 1 = 12
# 在掩码中，bit 0 对应 SIG1，bit 12 对应 SIG13
sigign_dec=$((16#${sigign_hex} 2>/dev/null || true))
sigcgt_dec=$((16#${sigcgt_hex} 2>/dev/null || true))

sigpipe_ignored=$(( (sigign_dec >> 12) & 1 ))
sigpipe_caught=$(( (sigcgt_dec >> 12) & 1 ))

echo ""
if [[ $sigpipe_ignored -eq 1 ]]; then
  echo "  ➜ SIGPIPE 被 IGNORE（忽略）—— 写入已关闭管道时 write() 返回 EPIPE 而非终止进程"
elif [[ $sigpipe_caught -eq 1 ]]; then
  echo "  ➜ SIGPIPE 被 CATCH（捕获）—— 进程注册了信号处理函数"
else
  echo "  ➜ SIGPIPE 使用默认处理（终止进程）"
fi

# F3. grep SIGPIPE 在 status 中
echo ""
echo "【F3】/proc/${TARGET_PID}/status 信号详情"
echo "------------------------------------------------------------------"
grep -E "SigPnd|ShdPnd|SigBlk|SigIgn|SigCgt" "/proc/${TARGET_PID}/status" 2>/dev/null | tee "${OUT_DIR}/signal_details.txt"

# F4. dmesg | grep SIGPIPE
echo ""
echo "【F4】dmesg SIGPIPE 事件"
echo "------------------------------------------------------------------"
if dmesg 2>/dev/null | grep -i "SIGPIPE" 2>/dev/null; then
  dmesg 2>/dev/null | grep -i "SIGPIPE" | tail -10 | tee "${OUT_DIR}/dmesg_sigpipe.txt"
else
  echo "  内核日志中无 SIGPIPE 相关记录"
fi

# F5. 检查写目标是否已关闭（pipe/socket 对端）
echo ""
echo "【F5】写目标对端状态检查（pipe|socket 对端是否已关闭）"
echo "------------------------------------------------------------------"
# 检查进程的 pipe FD，看对端是否关闭
pipe_count=0
if ls "/proc/${TARGET_PID}/fd/" &>/dev/null; then
  for fdlink in "/proc/${TARGET_PID}/fd/"*; do
    target=$(readlink "$fdlink" 2>/dev/null || true)
    if [[ "$target" == "pipe:"* ]]; then
      pipe_count=$((pipe_count + 1))
      # 通过 lsof 查看 pipe 两端进程
      if command -v lsof &>/dev/null; then
        inode=$(echo "$target" | grep -oP '\[?\K\d+' || true)
        if [[ -n "$inode" ]]; then
          pipe_endpoints=$(lsof 2>/dev/null | grep "pipe" | grep "${inode}" | awk '{print $1, $2}' | sort -u || true)
          endpoint_count=$(echo "$pipe_endpoints" | wc -l)
          if [[ $endpoint_count -lt 2 ]]; then
            echo "  ⚠ pipe inode ${inode}: 仅 ${endpoint_count} 端活跃，对端可能已关闭"
          fi
        fi
      fi
    elif [[ "$target" == "socket:"* ]]; then
      # socket 对端检测
      socket_count=$((socket_count + 1))
    fi
  done
fi
echo "  pipe FD 数: ${pipe_count}"
echo "  socket FD 数: ${socket_count:-0}"

# F6. 结论
echo ""
echo "=================================================================="
echo " 分支F 诊断结论"
echo "=================================================================="

if [[ $sigpipe_ignored -eq 1 ]]; then
  sigpipe_status="IGNORED（忽略）"
  risk="低（进程忽略 SIGPIPE，写入关闭管道时得到 EPIPE）"
elif [[ $sigpipe_caught -eq 1 ]]; then
  sigpipe_status="CAUGHT（捕获）"
  risk="中（进程自行处理 SIGPIPE，需检查处理逻辑是否正确）"
else
  sigpipe_status="DEFAULT（默认终止）"
  risk="高（收到 SIGPIPE 时进程默认终止，可能导致非预期退出）"
fi

cat << EOF
  目标 PID: ${TARGET_PID}
  SIGPIPE 状态: ${sigpipe_status}
  风险评估: ${risk}

  建议:
$( if [[ $sigpipe_ignored -eq 1 ]]; then
  echo "    - 进程忽略 SIGPIPE，write() 返回 EPIPE，需在代码中正确处理 EPIPE"
elif [[ $sigpipe_caught -eq 1 ]]; then
  echo "    - 检查 SIGPIPE handler 实现是否正确"
  echo "    - 避免在 handler 中做复杂操作（信号不安全）"
else
  echo "    - 若进程预期会写入已关闭管道/socket，建议忽略 SIGPIPE"
  echo "    - signal(SIGPIPE, SIG_IGN) 或 sigaction() 设置"
  echo "    - 否则，收到 SIGPIPE 时进程将终止（默认行为）"
fi )
EOF
