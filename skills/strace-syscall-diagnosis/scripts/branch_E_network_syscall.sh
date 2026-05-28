#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_E_network_syscall.sh
# 用途：网络 Syscall 异常诊断 — 双轨分析
# 使用：bash branch_E_network_syscall.sh [output_dir]
# 参数：
#   $1  输出目录（来自 01_baseline_info.sh 的输出）
# =============================================================================

set -euo pipefail

OUT_DIR="${1:-/tmp/syscall_diag_$(date +%Y%m%d%H%M%S)}"

echo "=================================================================="
echo " 分支E：网络 Syscall 异常 —— 双轨分析"
echo "=================================================================="

BASELINE_TARGET="${OUT_DIR}/process_status.txt"
STDERR="${OUT_DIR}/strace_all.txt"
TARGET_PID=$(grep "^Pid:" "$BASELINE_TARGET" 2>/dev/null | awk '{print $2}' || echo "")

# --------------------------------------------------------------------------
# T1 - 网络 syscall 分布
# --------------------------------------------------------------------------
echo ""
echo "【T1】网络 syscall 分布统计"
echo "------------------------------------------------------------------"
if [ -f "$STDERR" ]; then
  echo "  网络相关 syscall 统计:"
  grep -E "^connect\b|^socket\b|^bind\b|^listen\b|^accept\b|^send\b|^recv\b|^sendto\b|^recvfrom\b|^read\(" "$STDERR" 2>/dev/null | \
    awk '{print $1}' | sort | uniq -c | sort -rn | head -15 || echo "    (无)"
  echo ""
  echo "  网络错误码统计:"
  grep -E "ECONNREFUSED|ECONNRESET|ETIMEDOUT|EHOSTUNREACH|ENETUNREACH|EADDRINUSE" "$STDERR" 2>/dev/null | \
    grep -oP "(E[A-Z_]+)" | sort | uniq -c | sort -rn | head -10 || echo "    (无网络错误)"
fi
echo ""

# --------------------------------------------------------------------------
# T2 - connect/accept 异常
# --------------------------------------------------------------------------
echo ""
echo "【T2】connect/accept 异常分析"
echo "------------------------------------------------------------------"
if [ -f "$STDERR" ]; then
  CONNECT_LINES=$(grep "^connect\b" "$STDERR" 2>/dev/null | head -20 || true)
  ACCEPT_LINES=$(grep "^accept\b" "$STDERR" 2>/dev/null | head -20 || true)

  echo "  connect 调用:"
  echo "${CONNECT_LINES}" | while read line; do
    [ -n "$line" ] && echo "    $line"
  done
  echo ""
  echo "  accept 调用:"
  echo "${ACCEPT_LINES}" | while read line; do
    [ -n "$line" ] && echo "    $line"
  done
fi

echo ""

# --------------------------------------------------------------------------
# T3 - 网络 I/O 耗时
# --------------------------------------------------------------------------
echo ""
echo "【T3】网络 I/O 耗时分析"
echo "------------------------------------------------------------------"
if [ -f "$STDERR" ]; then
  echo "  慢 read/write/send/recv（> 100ms）:"
  grep -E "^read|^write|^send|^recv|^sendto|^recvfrom" "$STDERR" 2>/dev/null | \
    grep -E "<0\.[1-9][0-9][0-9]" | sort -t'<' -k2 -rn | head -10 || echo "    (无)"
fi

echo ""

# --------------------------------------------------------------------------
# T4 - Socket 状态（ss）
# --------------------------------------------------------------------------
echo ""
echo "【T4】Socket 状态快照（ss）"
echo "------------------------------------------------------------------"
echo "  进程 socket 统计:"
ss -tapn 2>/dev/null | grep "pid=${TARGET_PID}" 2>/dev/null | sed 's/^/    /' || \
ss -tapn 2>/dev/null | head -20 | sed 's/^/    /' || true

echo ""

echo "【T5】调用轨迹轨道结论"
echo "------------------------------------------------------------------"
{
  echo "  网络 syscall 错误码分布已统计"
  echo "  调用轨迹归因假设: 网络通信异常定位"
} | tee -a "${OUT_DIR}/branch_E_metrics.txt"

# ==========================================================================
echo ""
echo "=================================================================="
echo " ▶ 内核语义轨道"
echo "=================================================================="
cat << 'SRCGUIDE'
  connect ECONNREFUSED:
    · 对端端口未监听: ss -tlnp | grep <port>
    · 防火墙拦截: iptables -L -n; nft list ruleset
    · 连接队列满: ss -lnt | grep Recv-Q

  connect ETIMEDOUT:
    · 对端网络不可达: ping/traceroute
    · 防火墙丢弃 SYN: tcpdump -i any host <target>
    · conntrack 表满: sysctl net.netfilter.nf_conntrack_count

  ECONNRESET/EPIPE:
    · 对端异常关闭: 检查对端进程日志
    · 保活机制: sysctl net.ipv4.tcp_keepalive_*

  EADDRINUSE:
    · 端口被占用: ss -tlnp | grep <port>
    · TIME_WAIT 过多: sysctl net.ipv4.tcp_tw_reuse
SRCGUIDE

echo ""
echo "=================================================================="
echo " ▶ 最终结论"
echo "=================================================================="
cat << 'CONCLUSION'

  故障模式: 网络 Syscall 异常
  处理建议:
    · ECONNREFUSED → 确认服务端口监听状态
    · ETIMEDOUT → 检查网络连通性和防火墙
    · ECONNRESET → 检查对端保活和应用稳定性
    · EADDRINUSE → 检查端口占用和 TIME_WAIT 优化
    · 慢 I/O → 检查带宽和延迟
    
    【验证】
      - 调整后 ss -tapn 确认连接状态正常
      - strace 确认错误码消失
CONCLUSION
