#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_C_close_wait.sh
# 用途：Socket FD 泄漏诊断（CLOSE_WAIT 堆积）— L3+L4 联合分析
# 使用：bash branch_C_close_wait.sh [target_pid]
# 参数：
#   $1  目标 PID（可选）
# =============================================================================

set -euo pipefail

TARGET_PID="${1:-}"

if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
  echo "用途：Socket FD 泄漏诊断（CLOSE_WAIT）"
  echo "使用：bash $0 [target_pid]"
  echo "  target_pid: 目标 PID（可选；不指定则全系统检测）"
  exit 0
fi

echo "=================================================================="
echo " 分支C：Socket FD 泄漏 (CLOSE_WAIT) —— L3+L4 联合分析"
echo "=================================================================="

# C1. 全局 CLOSE_WAIT 统计
echo ""
echo "【C1】全系统 CLOSE_WAIT 统计"
echo "------------------------------------------------------------------"
if ! command -v ss &>/dev/null; then
  echo "  ss 命令不可用，请安装 iproute2"
  exit 1
fi

cw_total=$(ss -Htn state close-wait 2>/dev/null | wc -l)
echo "  全系统 CLOSE_WAIT 总数: ${cw_total}"

# 按进程聚合
echo ""
echo "  按进程聚合（Top 5）："
ss -tnp state close-wait 2>/dev/null | grep -oP 'pid=\K\d+' | sort | uniq -c | sort -rn | head -5

# 按目标地址聚合
echo ""
echo "  按目标地址聚合（Top 5）："
ss -tnp state close-wait 2>/dev/null | awk '{print $4}' | sort | uniq -c | sort -rn | head -5

# C2. 目标进程分析
if [[ -n "$TARGET_PID" ]]; then
  echo ""
  echo "【C2】目标 PID ${TARGET_PID} CLOSE_WAIT 详情"
  echo "------------------------------------------------------------------"
  my_cw=$(ss -tnp state close-wait 2>/dev/null | grep -c "pid=${TARGET_PID}" || echo 0)
  echo "  该进程 CLOSE_WAIT 数: ${my_cw}"
  echo ""
  echo "  该进程 CLOSE_WAIT 列表："
  ss -tnp state close-wait 2>/dev/null | grep "pid=${TARGET_PID}" | head -20
fi

# C3. Socket FD 占比
echo ""
echo "【C3】目标进程 Socket FD 占比"
echo "------------------------------------------------------------------"
if [[ -n "$TARGET_PID" ]]; then
  total_fds=$(ls -1 "/proc/${TARGET_PID}/fd" 2>/dev/null | wc -l)
  sock_fds=$(ls -la "/proc/${TARGET_PID}/fd" 2>/dev/null | grep -c "socket:" || echo 0)
  sock_pct=$(awk "BEGIN {printf \"%.1f\", ${sock_fds} / ${total_fds} * 100}" 2>/dev/null || echo "N/A")
  echo "  总 FD: ${total_fds} | socket FD: ${sock_fds} (${sock_pct}%)"
fi

# C4. 根因分析指引
echo ""
echo "【C4】根因分析（L4 代码级）"
echo "------------------------------------------------------------------"
cat << 'GUIDE'
  CLOSE_WAIT 泄漏的常见根因：
    1. recv() 返回 0（EOF）后未调用 close()
       → 修复: 在 recv 返回 <= 0 时调用 shutdown/closesocket
    2. 连接池不归还连接
       → 修复: try-with-resources / using / defer 确保 close()
    3. HTTP keep-alive 未正确处理
       → 修复: 检查 Connection: close 头处理逻辑

  如果可执行 strace：
    strace -p <PID> -e trace=close -c
    → 对比 est_count 和 close_count，差异即为泄漏量

  使用 gdb 在 close() 断点：
    gdb -p <PID> -ex 'break close' -ex 'continue'
    → bt 查看调用栈
GUIDE

echo ""
echo "=================================================================="
echo " 分支C 诊断结论"
echo "=================================================================="
cat << 'CONCLUSION'
  全系统 CLOSE_WAIT：<N>
  目标进程 CLOSE_WAIT：<N>（占比 <P>%）
  Socket FD 占比：<P>%
  主要目标地址：<ip:port>
  strace 结果（如执行）：open/close 差值 <N>
  根因假设：<应用层调用 close() 时序不当 / 连接池管理缺陷>
  建议：
    - 立即：ss -K state close-wait src <local_ip> 强制清理
    - 短期：修复代码在 EOF 后补上 close()
    - 长期：监控 CLOSE_WAIT 趋势，设置告警
CONCLUSION
