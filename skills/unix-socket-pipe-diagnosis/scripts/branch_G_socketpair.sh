#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_G_socketpair.sh
# 用途：socketpair 泄漏诊断
# 使用：bash branch_G_socketpair.sh <target_pid> [--full]
# 参数：
#   $1  目标 PID（必选）
#   $2  --full  执行完整诊断（含 strace 系统调用追踪）
# =============================================================================

set -euo pipefail

TARGET_PID="${1:-}"
FULL_MODE=false
[[ "${2:-}" == "--full" ]] && FULL_MODE=true

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]] || [[ -z "$TARGET_PID" ]]; then
  echo "用途：socketpair 泄漏诊断"
  echo "使用：bash $0 <target_pid> [--full]"
  echo "  target_pid: 目标 PID（必选）"
  echo "  --full:      执行完整诊断（含 strace 系统调用追踪，有性能影响）"
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
echo " 分支G：socketpair 泄漏诊断"
echo " 目标 PID: ${TARGET_PID}"
echo "=================================================================="

# G1. lsof -p PID | grep -E "unix|anon_inode" 统计
echo ""
echo "【G1】unix/anon_inode FD 统计（lsof）"
echo "------------------------------------------------------------------"
if command -v lsof &>/dev/null; then
  lsof -p "${TARGET_PID}" 2>/dev/null | grep -E "unix|anon_inode" | tee "${OUT_DIR}/lsof_unix_anon.txt"
  uds_count=$(lsof -p "${TARGET_PID}" 2>/dev/null | grep -c "unix" || true)
  anon_count=$(lsof -p "${TARGET_PID}" 2>/dev/null | grep -c "anon_inode" || true)
  echo ""
  echo "  unix socket FD:     ${uds_count}"
  echo "  anon_inode FD:      ${anon_count}"
  echo "  合计:               $(( uds_count + anon_count ))"
else
  echo "  lsof 不可用，使用 /proc 枚举"
  ls -la "/proc/${TARGET_PID}/fd" 2>/dev/null | tee "${OUT_DIR}/proc_fd_all.txt"
  uds_count=$(grep -c "socket:" < "${OUT_DIR}/proc_fd_all.txt" 2>/dev/null || true)
  anon_count=$(grep -c "anon_inode" < "${OUT_DIR}/proc_fd_all.txt" 2>/dev/null || true)
  echo "  socket FD: ${uds_count} | anon_inode FD: ${anon_count}"
fi

# G2. lsof -p PID | awk '{print $5}' | sort | uniq -c
echo ""
echo "【G2】FD 类型分布（按类型统计）"
echo "------------------------------------------------------------------"
if command -v lsof &>/dev/null; then
  lsof -p "${TARGET_PID}" 2>/dev/null | awk '{print $5}' | sort | uniq -c | sort -rn | tee "${OUT_DIR}/fd_type_dist.txt"
else
  # 从 /proc 推断
  for fdlink in "/proc/${TARGET_PID}/fd/"*; do
    target=$(readlink "$fdlink" 2>/dev/null || echo "?")
    case "$target" in
      socket:*)       echo "socket" ;;
      pipe:*)         echo "pipe" ;;
      anon_inode:*)   echo "${target#anon_inode:}" ;;
      /dev/*)         echo "device" ;;
      *)              echo "file/other" ;;
    esac
  done 2>/dev/null | sort | uniq -c | sort -rn | tee "${OUT_DIR}/fd_type_dist.txt"
fi

# G3. anon_unix 类型 FD 计数
echo ""
echo "【G3】anon_unix FD 专项计数"
echo "------------------------------------------------------------------"
if command -v lsof &>/dev/null; then
  anon_unix_count=$(lsof -p "${TARGET_PID}" 2>/dev/null | awk '{print $5, $9}' | grep -c "unix\|anon" || true)
  echo "  anon_unix/socketpair 相关 FD: ${anon_unix_count}"
else
  anon_unix_count=$anon_count
  echo "  anon_inode FD: ${anon_unix_count}（含 socketpair）"
fi

# G4. 采样 3 次（间隔 5s）看增长趋势
echo ""
echo "【G4】FD 增长趋势采样（3 次 × 间隔 5s）"
echo "------------------------------------------------------------------"
echo "  采样时间点  |  总FD  |  unix  |  anon_inode  |  pipe"
echo "  -----------------------------------------------------"

sampled_data=()
for i in 1 2 3; do
  if command -v lsof &>/dev/null; then
    total=$(lsof -p "${TARGET_PID}" 2>/dev/null | wc -l)
    u=$(lsof -p "${TARGET_PID}" 2>/dev/null | grep -c "unix" || true)
    a=$(lsof -p "${TARGET_PID}" 2>/dev/null | grep -c "anon_inode" || true)
    p=$(lsof -p "${TARGET_PID}" 2>/dev/null | grep -c "FIFO\|pipe" || true)
  else
    total=$(ls -1 "/proc/${TARGET_PID}/fd" 2>/dev/null | wc -l)
    u=$(grep -c "socket:" "/proc/${TARGET_PID}/fd" 2>/dev/null || true)
    a=$(grep -c "anon_inode" "/proc/${TARGET_PID}/fd" 2>/dev/null || true)
    p=$(grep -c "pipe:" "/proc/${TARGET_PID}/fd" 2>/dev/null || true)
  fi
  echo "  ${ts}     |  ${total}   |  ${u}     |  ${a}          |  ${p}"
  sampled_data+=("${total},${u},${a},${p}")
  if [[ $i -lt 3 ]]; then sleep 5; fi
done 2>&1 | tee "${OUT_DIR}/fd_trend.txt"

# 分析趋势
if [[ ${#sampled_data[@]} -ge 3 ]]; then
  first_total=$(echo "${sampled_data[0]}" | cut -d',' -f1)
  last_total=$(echo "${sampled_data[2]}" | cut -d',' -f1)
  diff=$(( last_total - first_total ))
  first_anon=$(echo "${sampled_data[0]}" | cut -d',' -f3)
  last_anon=$(echo "${sampled_data[2]}" | cut -d',' -f3)
  anon_diff=$(( last_anon - first_anon ))

  echo ""
  if [[ $diff -gt 0 ]]; then
    echo "  趋势: FD 总量增长 ${diff}（10s 内），"
    if [[ $anon_diff -gt 0 ]]; then
      echo "  其中 anon_inode 增长 ${anon_diff} —— 疑似 socketpair 泄漏"
    fi
  elif [[ $diff -eq 0 ]]; then
    echo "  趋势: FD 数量稳定（10s 内无增长）"
  else
    echo "  趋势: FD 数量减少 ${diff}（10s 内），整体正常"
  fi
fi

# G5. strace（仅 --full 模式）
echo ""
echo "【G5】strace 系统调用追踪"
echo "------------------------------------------------------------------"
if $FULL_MODE && command -v strace &>/dev/null; then
  echo "  ⚠ strace 执行中（5 秒采样），可能有轻微性能影响..."
  timeout 5 strace -p "${TARGET_PID}" -e trace=socketpair,close -c 2>&1 | tee "${OUT_DIR}/strace_trace.txt" || true
  echo ""
  echo "  完整追踪建议: strace -p ${TARGET_PID} -e trace=socketpair,close -o ${OUT_DIR}/strace_full.log"
elif $FULL_MODE; then
  echo "  strace 不可用，跳过系统调用追踪"
else
  echo "  跳过 strace（未指定 --full）"
  echo "  如需追踪: bash $0 ${TARGET_PID} --full"
fi

# G6. 结论
echo ""
echo "=================================================================="
echo " 分支G 诊断结论"
echo "=================================================================="

total_fd=$(ls -1 "/proc/${TARGET_PID}/fd" 2>/dev/null | wc -l || echo "?")
anon_fd="${anon_unix_count:-?}"

if [[ ${#sampled_data[@]} -ge 3 ]]; then
  trend_msg="FD 变化: ${diff:+$diff/10s}"
  if [[ $anon_diff -gt 2 ]]; then
    leak_verdict="⚠ 疑似活跃的 socketpair 泄漏（anon_inode 10s 内增长 ${anon_diff}）"
  elif [[ $diff -gt 5 ]]; then
    leak_verdict="! FD 总量增长较快，需进一步观察"
  elif [[ $total_fd -gt 50 ]] && [[ ${anon_fd:-0} -gt $(( total_fd / 2 )) ]]; then
    leak_verdict="⚠ 大量 unix socket FD 存在（${anon_fd}/${total_fd}），疑似已完成泄漏"
  else
    leak_verdict="FD 数量稳定，无泄漏迹象"
  fi
else
  if [[ $total_fd -gt 50 ]] && [[ ${anon_fd:-0} -gt $(( total_fd / 2 )) ]]; then
    leak_verdict="❓ 采样数据不足，但存在大量 unix socket FD（${anon_fd}/${total_fd}），疑似已完成泄漏"
  else
    leak_verdict="采样数据不足，无法判断趋势"
  fi
fi

cat << EOF
  目标 PID: ${TARGET_PID}
  FD 总数: ${total_fd}
  anon_inode/unix FD: ${anon_fd}
  ${trend_msg:-趋势: 参见采样数据}

  判定: ${leak_verdict}

  建议:
    - 若确认泄漏: 检查代码中 socketpair() 创建的 fd 是否在分支路径中未 close()
    - 使用 strace -e trace=socketpair,close -p ${TARGET_PID} 追踪 syscall
    - 考虑使用 RAII / defer 确保 close() 在异常路径也被调用
EOF
