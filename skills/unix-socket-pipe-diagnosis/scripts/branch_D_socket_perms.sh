#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_D_socket_perms.sh
# 用途：Socket 文件权限诊断
# 使用：bash branch_D_socket_perms.sh [socket_path]
# 参数：
#   $1  socket 文件路径（可选；不指定则全系统扫描）
# =============================================================================

set -euo pipefail

SOCKET_PATH="${1:-}"

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  echo "用途：Socket 文件权限诊断"
  echo "使用：bash $0 [socket_path]"
  echo "  socket_path: socket 文件路径（可选；不指定则全系统扫描）"
  exit 0
fi

OUT_DIR="/tmp/uds_pipe_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "${OUT_DIR}"
echo "诊断输出目录: ${OUT_DIR}"
echo ""

echo "=================================================================="
echo " 分支D：Socket 文件权限诊断"
echo "=================================================================="

# D1. 列出 socket 文件
echo ""
echo "【D1】socket 文件列表"
echo "------------------------------------------------------------------"
if [[ -n "$SOCKET_PATH" ]]; then
  if [[ -S "$SOCKET_PATH" ]]; then
    echo "  ${SOCKET_PATH}"
    echo "${SOCKET_PATH}" > "${OUT_DIR}/socket_files.txt"
  else
    echo "  [错误] 路径不存在或不是 socket 文件: ${SOCKET_PATH}"
    exit 1
  fi
else
  echo "  全系统扫描中（可能需要 root 权限）..."
  find / -type s 2>/dev/null | tee "${OUT_DIR}/socket_files.txt"
  socket_total=$(wc -l < "${OUT_DIR}/socket_files.txt" 2>/dev/null || true)
  echo ""
  echo "  socket 文件总数: ${socket_total}"
fi

# D2. ls -la 检查各 socket 权限
echo ""
echo "【D2】socket 文件权限详情"
echo "------------------------------------------------------------------"
while read -r sock; do
  ls -la "$sock" 2>/dev/null
done < "${OUT_DIR}/socket_files.txt" | tee "${OUT_DIR}/socket_perms.txt"

# D3. stat 检查 owner/group
echo ""
echo "【D3】socket 文件 owner/group"
echo "------------------------------------------------------------------"
while read -r sock; do
  stat_output=$(stat -c '%a %U:%G %n' "$sock" 2>/dev/null || true)
  if [[ -n "$stat_output" ]]; then
    echo "  ${stat_output}"
  fi
done < "${OUT_DIR}/socket_files.txt" | tee "${OUT_DIR}/socket_stat.txt"

# D4. getfacl（若可用）
echo ""
echo "【D4】ACL 权限检查（getfacl）"
echo "------------------------------------------------------------------"
if command -v getfacl &>/dev/null; then
  while read -r sock; do
    echo "  --- ${sock} ---"
    getfacl "$sock" 2>/dev/null | sed 's/^/  /'
  done < "${OUT_DIR}/socket_files.txt" | tee "${OUT_DIR}/socket_acl.txt"
else
  echo "  getfacl 不可用，跳过 ACL 检查"
fi

# D5. 权限合规性判定
echo ""
echo "【D5】权限合规性判定"
echo "------------------------------------------------------------------"
echo "  合规标准（推荐）:"
echo "    权限 <= 0777（避免 setuid/setgid/sticky）"
echo "    不应为 other 可写（除非明确需要）"
echo "    owner 应匹配运行服务的用户"
echo ""

while IFS= read -r sock; do
  if [[ -n "$sock" ]]; then
    perm=$(stat -c '%a' "$sock" 2>/dev/null || echo "0000")
    owner=$(stat -c '%U' "$sock" 2>/dev/null || echo "?")
    world_writable=$(( 10#${perm} & 0002 ))
    owner_readable=$(( 10#${perm} & 0400 ))
    if [[ $world_writable -ne 0 ]]; then
      echo "  ⚠ ${sock} 权限 ${perm} 对其他用户可写（不安全）"
    elif [[ $owner_readable -eq 0 ]] && { [[ $perm = 0000 ]] || [[ $perm = 0 ]]; }; then
      echo "  ⚠ ${sock} 权限 ${perm} 完全无权限（无法连接或通信）"
    elif [[ $owner_readable -eq 0 ]]; then
      echo "  ⚠ ${sock} 权限 ${perm} owner 无读写权（可能过于严格）"
    else
      echo "  OK ${sock} 权限 ${perm} 所有者 ${owner}"
    fi
  fi
done < "${OUT_DIR}/socket_files.txt" > "${OUT_DIR}/perm_audit_raw.txt"
cat "${OUT_DIR}/perm_audit_raw.txt" | tee "${OUT_DIR}/perm_audit.txt"

# D6. 结论
echo ""
echo "=================================================================="
echo " 分支D 诊断结论"
echo "=================================================================="

socket_count=$(wc -l < "${OUT_DIR}/socket_files.txt" 2>/dev/null || true)
warn_count=$(grep -c "⚠" "${OUT_DIR}/perm_audit.txt" 2>/dev/null || true)

cat << EOF
  扫描 socket 文件数: ${socket_count}
  权限不合规数: ${warn_count}

  结论: $( [[ $warn_count -gt 0 ]] && echo "⚠ ${warn_count} 个 socket 文件权限不安全，建议："
  echo "    - 使用 chmod 收紧权限（如 0660）"
  echo "    - 使用 chown 设置正确的 owner/group"
  echo "    - 检查 umask 设置" || echo "所有 socket 文件权限合规" )
EOF
