#!/usr/bin/env bash
# =============================================================================
# 脚本：01_baseline_info.sh
# 用途：Unix Socket / Pipe 基线信息采集与分支推荐
# 使用：bash 01_baseline_info.sh [target_pid]
# 参数：
#   $1  目标 PID（可选；不提供则采集系统全局信息）
# =============================================================================

set -euo pipefail

TARGET_PID="${1:-}"

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  echo "用途：Unix Socket / Pipe 基线信息采集与分支推荐"
  echo "使用：bash $0 [target_pid]"
  echo ""
  echo "  target_pid: 目标 PID（可选）"
  echo ""
  echo "采集内容："
  echo "  L1 系统层：ss -xl、/proc/net/unix、/proc/sys/fs/pipe-max-size"
  echo "  L2 进程层（如有 PID）：lsof -p PID FD 类型分布、UDS/pipe 分类"
  echo "  分支推荐：基于检测结果推荐对应 branch_*.sh"
  exit 0
fi

OUT_DIR="/tmp/uds_pipe_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "${OUT_DIR}"
echo "诊断输出目录: ${OUT_DIR}"

# =============================================================================
# L1: 系统层 Unix Socket 信息
# =============================================================================
echo ""
echo "=================================================================="
echo " L1: 系统层 Unix Socket 信息"
echo "=================================================================="

# UDS listen socket 数量
if command -v ss &>/dev/null; then
  ss_xl_count=$(ss -Hxl 2>/dev/null | wc -l || true)
  ss_xa_count=$(ss -Hxa 2>/dev/null | wc -l || true)
  echo "  ss -xl (listen UDS): ${ss_xl_count}"
  echo "  ss -xa (all UDS):    ${ss_xa_count}"

  # 保存全量信息
  ss -xl > "${OUT_DIR}/ss_xl.txt" 2>/dev/null || true
  ss -xa > "${OUT_DIR}/ss_xa.txt" 2>/dev/null || true
else
  echo "  [跳过] ss 命令不可用，无法采集 UDS 信息"
fi

# /proc/net/unix
if [[ -f /proc/net/unix ]]; then
  echo ""
  echo "  /proc/net/unix socket 总数: $(wc -l < /proc/net/unix 2>/dev/null || true)"
  cp /proc/net/unix "${OUT_DIR}/proc_net_unix.txt" 2>/dev/null || true
else
  echo "  [跳过] /proc/net/unix 不存在"
fi

# pipe 系统限制
echo ""
echo "  pipe-max-size: $(cat /proc/sys/fs/pipe-max-size 2>/dev/null || echo 'N/A')"
echo "  pipe-user-pages-soft: $(cat /proc/sys/fs/pipe-user-pages-soft 2>/dev/null || echo 'N/A')"
echo "  pipe-user-pages-hard: $(cat /proc/sys/fs/pipe-user-pages-hard 2>/dev/null || echo 'N/A')"

# =============================================================================
# L2: 进程层信息（如有 PID）
# =============================================================================
echo ""
echo "=================================================================="
echo " L2: 进程层信息"
echo "=================================================================="

if [[ -n "$TARGET_PID" ]]; then
  if [[ ! -d "/proc/${TARGET_PID}" ]]; then
    echo "  [错误] PID ${TARGET_PID} 不存在"
    exit 1
  fi

  cmdline=$(cat "/proc/${TARGET_PID}/cmdline" 2>/dev/null | tr '\0' ' ' | head -c 80)
  echo "  目标 PID: ${TARGET_PID} (${cmdline:-unknown})"

  fd_count=$(ls -1 "/proc/${TARGET_PID}/fd" 2>/dev/null | wc -l)
  echo "  FD 总数: ${fd_count}"

  # FD 类型分布
  echo ""
  echo "  FD 类型分布（lsof）:"
  if command -v lsof &>/dev/null; then
    lsof -p "${TARGET_PID}" 2>/dev/null | awk '{print $5}' | sort | uniq -c | sort -rn | head -15
    # 保存完整输出
    lsof -p "${TARGET_PID}" > "${OUT_DIR}/lsof_pid.txt" 2>/dev/null || true
  else
    echo "    lsof 不可用"
  fi

  # UDS / pipe 专项分类
  echo ""
  echo "  UDS / pipe 专项分类:"
  if command -v lsof &>/dev/null; then
    uds_count=$(lsof -p "${TARGET_PID}" 2>/dev/null | grep -c "unix" || true)
    pipe_count=$(lsof -p "${TARGET_PID}" 2>/dev/null | grep -c "FIFO\|pipe" || true)
    anon_count=$(lsof -p "${TARGET_PID}" 2>/dev/null | grep -c "anon_inode" || true)
    echo "    unix socket: ${uds_count}"
    echo "    pipe/FIFO:   ${pipe_count}"
    echo "    anon_inode:  ${anon_count}"
  fi

  # 保存 FD 列表
  ls -la "/proc/${TARGET_PID}/fd" > "${OUT_DIR}/proc_fd_list.txt" 2>/dev/null || true
else
  echo "  未指定 PID，跳过进程层采集。"
  echo "  提示: 可指定 PID 进行深度分析: bash $0 <pid>"
fi

# =============================================================================
# 分支推荐
# =============================================================================
echo ""
echo "=================================================================="
echo " 分支推荐（基于已采集信息）"
echo "=================================================================="

MATCHED=0

# 分支A: Listen backlog 过满
if command -v ss &>/dev/null; then
  backlog_full=$(ss -xl 2>/dev/null | awk 'NR>1 {if ($5 > 0) print}' | wc -l)
  if [[ $backlog_full -gt 0 ]]; then
    echo "  ✓ 推荐: bash branch_A_uds_backlog.sh [PID]   (存在 ${backlog_full} 个非零 backlog 的 listen UDS)"
    MATCHED=$((MATCHED + 1))
  fi
fi

# 分支B: Abstract socket 双绑定
if command -v ss &>/dev/null; then
  abstract_count=$(ss -xl 2>/dev/null | grep -c '@' || true)
  if [[ $abstract_count -gt 0 ]]; then
    echo "  ✓ 推荐: bash branch_B_abstract_conflict.sh   (发现 ${abstract_count} 个 abstract UDS)"
    MATCHED=$((MATCHED + 1))
  fi
fi

# 分支D: Socket 文件权限异常
socket_files=$(find / -type s 2>/dev/null | wc -l)
if [[ $socket_files -gt 0 ]]; then
  echo "  ✓ 推荐: bash branch_D_socket_perms.sh          (发现 ${socket_files} 个 socket 文件)"
  MATCHED=$((MATCHED + 1))
fi

# 分支E: D 状态进程写管道阻塞
d_state_count=$(ps -eo stat 2>/dev/null | grep -c '^D' || true)
if [[ $d_state_count -gt 0 ]]; then
  echo "  ✓ 推荐: bash branch_E_pipe_buf.sh [PID]        (发现 ${d_state_count} 个 D 状态进程)"
  MATCHED=$((MATCHED + 1))
fi

# 分支G: anon_unix FD 持续增长
if [[ -n "$TARGET_PID" ]] && command -v lsof &>/dev/null; then
  anon_count=$(lsof -p "${TARGET_PID}" 2>/dev/null | grep -c "anon_inode" || true)
  if [[ $anon_count -gt 10 ]]; then
    echo "  ✓ 推荐: bash branch_G_socketpair.sh ${TARGET_PID}  (anon_inode FD ${anon_count} > 10)"
    MATCHED=$((MATCHED + 1))
  fi
fi

# 分支F: SIGPIPE 未处理（仅当有 PID 时）
if [[ -n "$TARGET_PID" ]]; then
  if [[ -r "/proc/${TARGET_PID}/status" ]]; then
    sigpipe_ign=$(grep "SigIgn" "/proc/${TARGET_PID}/status" 2>/dev/null | awk '{print $2}')
    if [[ -n "$sigpipe_ign" ]]; then
      # SIGPIPE = 13, bit = 12 (0-indexed)
      bit_val=$(( (16#${sigpipe_ign: -4:1} >> 0) & 1 )) 2>/dev/null || true
      # 简化检查
      echo "  ? 推荐: bash branch_F_sigpipe.sh ${TARGET_PID}          (检查 SIGPIPE 处理状态)"
      MATCHED=$((MATCHED + 1))
    fi
  fi
fi

if [[ $MATCHED -eq 0 ]]; then
  echo "  未匹配到特定分支，建议手动分析。"
fi

echo ""
echo "=================================================================="
echo " 基线信息采集完成。结果目录: ${OUT_DIR}"
echo " 按分支推荐执行对应的 branch_*.sh 脚本进入深度诊断。"
echo "=================================================================="
