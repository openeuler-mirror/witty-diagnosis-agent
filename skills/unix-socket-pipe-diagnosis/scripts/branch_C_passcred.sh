#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_C_passcred.sh
# 用途：SO_PASSCRED / SCM_RIGHTS 凭证传递诊断
# 使用：bash branch_C_passcred.sh <target_pid>
# 参数：
#   $1  目标 PID（必选）
# =============================================================================

set -euo pipefail

TARGET_PID="${1:-}"

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]] || [[ -z "$TARGET_PID" ]]; then
  echo "用途：SO_PASSCRED/SCM_RIGHTS 凭证传递诊断"
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
echo " 分支C：SO_PASSCRED / SCM_RIGHTS 凭证传递诊断"
echo " 目标 PID: ${TARGET_PID}"
echo "=================================================================="

# C1. ss -xp 查看 UDS 凭证状态
echo ""
echo "【C1】ss -xp：UDS 凭证状态"
echo "------------------------------------------------------------------"
if command -v ss &>/dev/null; then
  ss -xp 2>/dev/null | grep "pid=${TARGET_PID}" | tee "${OUT_DIR}/ss_xp.txt" || echo "  该进程无 UDS socket，或 ss 未输出凭证信息"
else
  echo "  ss 命令不可用"
fi

# C2. lsof -p PID | grep unix
echo ""
echo "【C2】lsof -p ${TARGET_PID}：Unix socket 信息"
echo "------------------------------------------------------------------"
if command -v lsof &>/dev/null; then
  lsof -p "${TARGET_PID}" 2>/dev/null | grep -i "unix" | tee "${OUT_DIR}/lsof_unix.txt" || echo "  该进程无 unix socket FD"
else
  echo "  lsof 不可用，使用 /proc 枚举"
  ls -la "/proc/${TARGET_PID}/fd" 2>/dev/null | grep "socket:" > "${OUT_DIR}/proc_socket_fds.txt" || true
  echo "  socket FD 列表已保存到 ${OUT_DIR}/proc_socket_fds.txt"
fi

# C3. 检查 socket SO_PASSCRED 选项
echo ""
echo "【C3】SO_PASSCRED 选项检查"
echo "------------------------------------------------------------------"
echo "  注: SO_PASSCRED 可通过 gdb 附加进程检查 sock->sk->sk_peer_cred，"
echo "  或通过 strace 观察 setsockopt 调用来判断。"
echo ""

# 尝试通过 lsof + ss 组合判断
if command -v lsof &>/dev/null; then
  lsof -p "${TARGET_PID}" 2>/dev/null | grep "unix" | awk '{print $9}' | while read -r fd; do
    if [[ -n "$fd" ]]; then
      # 检查是否为 abstract socket
      inode=$(lsof -p "${TARGET_PID}" 2>/dev/null | grep " $fd " | awk '{print $NF}' | grep -oP 'inode=\K\d+' || true)
      if [[ -n "$inode" ]]; then
        passcred=$(ss -xp 2>/dev/null | grep "${inode}" | grep -oP 'passcred=\K\d+' || echo "N/A")
        echo "  FD ${fd} (inode ${inode})  SO_PASSCRED=${passcred}"
      fi
    fi
  done
fi

# 无 gdb 时给出检查指引
cat << 'GUIDE'
  手动检查方法（需 root/gdb）：
    gdb -p <PID> -batch -ex "info os socket" 2>/dev/null | grep SO_PASSCRED
  或通过 socat 测试：
    socat UNIX-LISTEN:/tmp/test_cred.sock,so-passcred -
GUIDE

# C4. strace -e trace=sendmsg,recvmsg -p PID（警告性能影响）
echo ""
echo "【C4】strace 凭证传递追踪（仅提示，不自动执行）"
echo "------------------------------------------------------------------"
cat << 'WARN'
  ⚠ strace 对 sendmsg/recvmsg 的追踪有显著性能影响，默认不自动执行。
  如需手动执行：
    strace -e trace=sendmsg,recvmsg -p <PID> -o /tmp/uds_msg_trace.log
  重点关注：
    - sendmsg() 中 msg_control 是否包含 SCM_CREDENTIALS
    - recvmsg() 中 msg_controllen 是否非零（表示有凭证数据）
WARN

# C5. 结论
echo ""
echo "=================================================================="
echo " 分支C 诊断结论"
echo "=================================================================="

ss_xp_lines=$(wc -l < "${OUT_DIR}/ss_xp.txt" 2>/dev/null || true)
lsof_unix_lines=$(wc -l < "${OUT_DIR}/lsof_unix.txt" 2>/dev/null || true)

cat << EOF
  目标 PID: ${TARGET_PID}
  ss -xp 凭证条目: ${ss_xp_lines}
  lsof unix FD: ${lsof_unix_lines}

  判定: $( [[ $ss_xp_lines -eq 0 ]] && echo "⚠ 进程 UDS 无凭证传递活跃，若业务依赖 SCM_CREDENTIALS，建议："
  echo "    - 确认服务端已设置 SO_PASSCRED"
  echo "    - 确认客户端发送了 SCM_CREDENTIALS"
  echo "    - 检查 selinux / apparmor 是否阻止凭证传递" || echo "有凭证传递活动，需进一步分析传递内容" )
EOF
