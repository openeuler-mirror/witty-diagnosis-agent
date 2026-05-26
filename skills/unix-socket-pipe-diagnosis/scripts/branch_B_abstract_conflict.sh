#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_B_abstract_conflict.sh
# 用途：Abstract socket 冲突诊断
# 使用：bash branch_B_abstract_conflict.sh [abstract_address]
# 参数：
#   $1  abstract 地址关键字（可选；不指定则列出所有 abstract UDS）
# =============================================================================

set -euo pipefail

ABSTRACT_KEY="${1:-}"

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  echo "用途：Abstract socket 冲突诊断"
  echo "使用：bash $0 [abstract_address]"
  echo "  abstract_address: abstract 地址关键字（可选；不指定则全系统扫描）"
  exit 0
fi

OUT_DIR="/tmp/uds_pipe_diag_$(date +%Y%m%d%H%M%S)"
mkdir -p "${OUT_DIR}"
echo "诊断输出目录: ${OUT_DIR}"
echo ""

echo "=================================================================="
echo " 分支B：Abstract socket 冲突诊断"
echo "=================================================================="

# B1. ss -xl | grep @ 列出所有 abstract UDS
echo ""
echo "【B1】ss -xl：所有 abstract UDS listen socket"
echo "------------------------------------------------------------------"
if ! command -v ss &>/dev/null; then
  echo "  ss 命令不可用，请安装 iproute2"
  exit 1
fi

if [[ -n "$ABSTRACT_KEY" ]]; then
  ss -xl 2>/dev/null | grep "@" | grep -i "${ABSTRACT_KEY}" | tee "${OUT_DIR}/abstract_list.txt"
else
  ss -xl 2>/dev/null | grep "@" | tee "${OUT_DIR}/abstract_list.txt"
fi

abstract_total=$(wc -l < "${OUT_DIR}/abstract_list.txt" 2>/dev/null || true)
echo "  abstract UDS listen 总数: ${abstract_total}"

# B2. ss -xlp | grep @ 含进程信息
echo ""
echo "【B2】ss -xlp：abstract UDS 含进程绑定"
echo "------------------------------------------------------------------"
if [[ -n "$ABSTRACT_KEY" ]]; then
  ss -xlp 2>/dev/null | grep "@" | grep -i "${ABSTRACT_KEY}" | tee "${OUT_DIR}/abstract_list_p.txt"
else
  ss -xlp 2>/dev/null | grep "@" | tee "${OUT_DIR}/abstract_list_p.txt"
fi

# B3. lsof -U | grep ABSTRACT
echo ""
echo "【B3】lsof -U：abstract UDS 进程信息"
echo "------------------------------------------------------------------"
if command -v lsof &>/dev/null; then
  if [[ -n "$ABSTRACT_KEY" ]]; then
    lsof -U 2>/dev/null | grep -i "ABSTRACT\|${ABSTRACT_KEY}" | tee "${OUT_DIR}/lsof_abstract.txt" || true
  else
    lsof -U 2>/dev/null | tee "${OUT_DIR}/lsof_abstract.txt"
  fi
  lsof_abstract_count=$(wc -l < "${OUT_DIR}/lsof_abstract.txt" 2>/dev/null || true)
  echo "  lsof abstract UDS 条目数: ${lsof_abstract_count}"
else
  echo "  lsof 不可用，跳过"
fi

# B4. 检查重复绑定同一 abstract 地址
echo ""
echo "【B4】重复 abstract 地址检测"
echo "------------------------------------------------------------------"
awk 'NR>1 {
  # 提取 abstract 地址（带 @ 前缀的行）
  for (i=1; i<=NF; i++) {
    if ($i ~ /^@/) { print $i; break }
  }
}' "${OUT_DIR}/ss_xl.txt" 2>/dev/null | sort | uniq -c | sort -rn | while read -r count addr; do
  if [[ $count -gt 1 ]]; then
    echo "  ⚠ 冲突: ${addr} 被 ${count} 个 socket 绑定"
  fi
done | tee "${OUT_DIR}/abstract_conflicts.txt"

conflict_count=$(grep -c "⚠" "${OUT_DIR}/abstract_conflicts.txt" 2>/dev/null || true)

# 如果指定了地址关键字，检查该地址
if [[ -n "$ABSTRACT_KEY" ]]; then
  echo ""
  echo "  针对地址关键字 \"${ABSTRACT_KEY}\" 的绑定详情:"
  ss -xlp 2>/dev/null | grep "@" | grep -i "${ABSTRACT_KEY}" | while read -r line; do
    pid=$(echo "$line" | grep -oP 'pid=\K\d+' || echo "N/A")
    echo "    地址: $(echo "$line" | awk '{print $NF}')  进程PID: ${pid}"
  done
fi

# B5. 结论
echo ""
echo "=================================================================="
echo " 分支B 诊断结论"
echo "=================================================================="

if [[ $conflict_count -gt 0 ]]; then
  echo "  ⚠ 检测到 ${conflict_count} 个 abstract 地址冲突！"
  echo ""
  echo "  冲突地址列表:"
  awk '{print "    - " $2}' "${OUT_DIR}/abstract_conflicts.txt" 2>/dev/null
  echo ""
  echo "  根因：多个进程/线程绑定到同一 abstract socket 地址"
  echo "  建议："
  echo "    - 检查应用配置，确保 address 唯一"
  echo "    - 使用 namespce / PID 作为地址一部分"
  echo "    - 若需多进程监听，使用 SO_REUSEPORT"
else
  echo "  未检测到 abstract 地址冲突。"
fi
echo "  全系统 abstract UDS 总数: ${abstract_total}"
