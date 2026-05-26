#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_E_pipe_buf.sh
# 用途：管道缓冲区满诊断
# 使用：bash branch_E_pipe_buf.sh [target_pid]
# 参数：
#   $1  目标 PID（可选；不指定则全系统检测 pipe 写阻塞）
# =============================================================================

set -euo pipefail

TARGET_PID="${1:-}"

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  echo "用途：管道缓冲区满诊断"
  echo "使用：bash $0 [target_pid]"
  echo "  target_pid: 目标 PID（可选；不指定则全系统检测 pipe 写阻塞）"
  exit 0
fi

OUT_DIR="/tmp/uds_pipe_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "${OUT_DIR}"
echo "诊断输出目录: ${OUT_DIR}"
echo ""

echo "=================================================================="
echo " 分支E：管道缓冲区满诊断"
echo "=================================================================="

# E1. pipe 系统限制
echo ""
echo "【E1】pipe 系统限制参数"
echo "------------------------------------------------------------------"
echo "  pipe-max-size:       $(cat /proc/sys/fs/pipe-max-size 2>/dev/null || echo 'N/A')"
echo "  pipe-user-pages-soft: $(cat /proc/sys/fs/pipe-user-pages-soft 2>/dev/null || echo 'N/A')"
echo "  pipe-user-pages-hard: $(cat /proc/sys/fs/pipe-user-pages-hard 2>/dev/null || echo 'N/A')"

# 保存到输出目录
cat /proc/sys/fs/pipe-max-size > "${OUT_DIR}/pipe_max_size.txt" 2>/dev/null || true
cat /proc/sys/fs/pipe-user-pages-soft > "${OUT_DIR}/pipe_user_pages_soft.txt" 2>/dev/null || true
cat /proc/sys/fs/pipe-user-pages-hard > "${OUT_DIR}/pipe_user_pages_hard.txt" 2>/dev/null || true

# E2. 保留备查
echo ""
echo "【E2】pipe-user-pages 限制值"
echo "------------------------------------------------------------------"
echo "  soft: $(cat /proc/sys/fs/pipe-user-pages-soft 2>/dev/null || echo 'N/A')"
echo "  hard: $(cat /proc/sys/fs/pipe-user-pages-hard 2>/dev/null || echo 'N/A')"

# E3. 识别 pipe FD
echo ""
echo "【E3】pipe FD 识别"
echo "------------------------------------------------------------------"
if [[ -n "$TARGET_PID" ]]; then
  if [[ ! -d "/proc/${TARGET_PID}" ]]; then
    echo "  [错误] PID ${TARGET_PID} 不存在"
    exit 1
  fi
  echo "  目标 PID ${TARGET_PID} 的 pipe FD:"
  ls -la "/proc/${TARGET_PID}/fd/" 2>/dev/null | grep "pipe:" | tee "${OUT_DIR}/pipe_fds.txt"
  pipe_fd_count=$(wc -l < "${OUT_DIR}/pipe_fds.txt" 2>/dev/null || true)
  echo "  pipe FD 总数: ${pipe_fd_count}"
else
  echo "  未指定 PID，跳过单个进程 pipe FD 识别"
fi

# E4. 获取 pipe buffer size
echo ""
echo "【E4】pipe buffer 大小"
echo "------------------------------------------------------------------"
if [[ -n "$TARGET_PID" ]] && command -v python3 &>/dev/null; then
  ls -la "/proc/${TARGET_PID}/fd/" 2>/dev/null | grep "pipe:" | while read -r line; do
    fd=$(echo "$line" | awk '{print $9}' | sed 's/://')
    if [[ -n "$fd" ]]; then
      pipe_sz=$(python3 -c "
import fcntl, os, sys
try:
    # F_GETPIPE_SZ = 1032 (on Linux)
    fd = int('${fd}')
    pid_path = f'/proc/${TARGET_PID}/fd/{fd}'
    # 通过 /proc/pid/fd/N 获取真实 fd 号
    real_fd = os.open(pid_path, os.O_RDONLY)
    sz = fcntl.fcntl(real_fd, 1032)
    os.close(real_fd)
    print(sz)
except Exception as e:
    print(f'error: {e}')
" 2>/dev/null || echo "N/A")
      echo "  FD ${fd} pipe buffer size: ${pipe_sz} bytes"
    fi
  done | tee "${OUT_DIR}/pipe_buffer_sizes.txt"
elif [[ -n "$TARGET_PID" ]]; then
  echo "  python3 不可用，无法获取 F_GETPIPE_SZ"
  echo "  可通过 /proc/${TARGET_PID}/fdinfo/ 查看部分信息"
  ls -la "/proc/${TARGET_PID}/fd/" 2>/dev/null | grep "pipe:" | while read -r line; do
    fd=$(echo "$line" | awk '{print $9}' | sed 's/://')
    if [[ -f "/proc/${TARGET_PID}/fdinfo/${fd}" ]]; then
      echo "  FD ${fd} fdinfo: $(cat "/proc/${TARGET_PID}/fdinfo/${fd}" 2>/dev/null | head -3)"
    fi
  done | tee "${OUT_DIR}/pipe_buffer_sizes.txt"
fi

# E5. 查找 pipe 写阻塞进程（D 状态或 S 状态 + pipe_write wchan）
echo ""
echo "【E5】pipe 写阻塞进程检测"
echo "------------------------------------------------------------------"
if command -v ps &>/dev/null; then
  # 先找所有 D 状态进程
  ps -eo pid,stat,wchan:32,comm 2>/dev/null | grep '^ *[0-9]\+ D' > "${OUT_DIR}/all_blocked_procs.txt" || true
  # 再找所有 wchan 包含 pipe 的进程（无论状态）
  ps -eo pid,stat,wchan:32,comm 2>/dev/null | grep -i 'pipe' >> "${OUT_DIR}/all_blocked_procs.txt" || true
  # 去重
  sort -u "${OUT_DIR}/all_blocked_procs.txt" -o "${OUT_DIR}/all_blocked_procs.txt" 2>/dev/null || true

  # 挑出 pipe 相关阻塞
  grep -E 'pipe_wait|pipe_write|pipe_read' "${OUT_DIR}/all_blocked_procs.txt" 2>/dev/null > "${OUT_DIR}/pipe_blocked_procs.txt" || true
  pipe_count=$(wc -l < "${OUT_DIR}/pipe_blocked_procs.txt" 2>/dev/null || true)
  echo "  pipe 阻塞进程数: ${pipe_count}"
fi

# E6. pipe 阻塞详情
echo ""
echo "【E6】pipe 阻塞详情"
echo "------------------------------------------------------------------"
while IFS= read -r line; do
  p_pid=$(echo "$line" | awk '{print $1}')
  if [[ -n "$p_pid" ]] && [[ -f "/proc/${p_pid}/wchan" ]]; then
    wchan=$(cat "/proc/${p_pid}/wchan" 2>/dev/null || echo "?")
    pstat=$(echo "$line" | awk '{print $2}')
    echo "  ⚠ PID ${p_pid} (状态 ${pstat}) 阻塞在: ${wchan} —— 疑似 pipe 写阻塞"
  fi
done < "${OUT_DIR}/pipe_blocked_procs.txt" 2>/dev/null | tee "${OUT_DIR}/pipe_wait_check.txt"

# E7. 结论
echo ""
echo "=================================================================="
echo " 分支E 诊断结论"
echo "=================================================================="

pipe_blocked=$(wc -l < "${OUT_DIR}/pipe_wait_check.txt" 2>/dev/null || true)

cat << EOF
  pipe-max-size: $(cat /proc/sys/fs/pipe-max-size 2>/dev/null || echo 'N/A')
  pipe 阻塞进程数: ${pipe_blocked}

  结论: $( [[ ${pipe_blocked} -gt 0 ]] && echo "⚠ 检测到 pipe 写阻塞进程，建议："
  echo "    - 增大 pipe-max-size: echo N > /proc/sys/fs/pipe-max-size"
  echo "    - 检查读端进程是否已退出或处理过慢"
  echo "    - 考虑使用 socketpair 替代 pipe" || echo "无 pipe 写阻塞迹象" )
EOF
