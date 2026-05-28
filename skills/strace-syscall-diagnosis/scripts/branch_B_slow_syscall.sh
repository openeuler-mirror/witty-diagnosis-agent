#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_B_slow_syscall.sh
# 用途：慢 Syscall 定位 — 双轨分析
# 使用：bash branch_B_slow_syscall.sh [output_dir]
# 参数：
#   $1  输出目录（来自 01_baseline_info.sh 的输出）
# =============================================================================

set -euo pipefail

OUT_DIR="${1:-/tmp/syscall_diag_$(date +%Y%m%d%H%M%S)}"

echo "=================================================================="
echo " 分支B：慢 Syscall 定位 —— 双轨分析"
echo "=================================================================="

# --------------------------------------------------------------------------
# T1 - 按耗时排序 Top-N
# --------------------------------------------------------------------------
echo ""
echo "【T1】慢 syscall Top-N（按耗时降序）"
echo "------------------------------------------------------------------"

STDERR="${OUT_DIR}/strace_all.txt"
SUMMARY="${OUT_DIR}/strace_summary.txt"

# 从 strace -c 输出提取慢 syscall
if [ -f "$SUMMARY" ]; then
  echo "  --- strace -c 统计（按耗时占比排序）---"
  grep -E "^[0-9]|syscall" "$SUMMARY" 2>/dev/null | head -20 || true
fi

echo ""

# 从 strace -T 提取具体慢调用
if [ -f "$STDERR" ]; then
  echo "  --- 具体慢调用（ > 100ms）---"
  grep -E "<0\.[1-9][0-9][0-9]" "$STDERR" 2>/dev/null | sort -t'<' -k2 -rn | head -20 || echo "    (未检测到 > 100ms 的调用)"
  echo ""
  echo "  --- 具体慢调用（ > 10ms）---"
  grep -E "<0\.0[1-9]" "$STDERR" 2>/dev/null | sort -t'<' -k2 -rn | head -10 || echo "    (未检测到 > 10ms 的调用)"
fi

echo ""

# --------------------------------------------------------------------------
# T2 - futex 分析
# --------------------------------------------------------------------------
echo ""
echo "【T2】futex 阻塞分析"
echo "------------------------------------------------------------------"
if [ -f "$STDERR" ]; then
  FUTEX_LINES=$(grep "futex" "$STDERR" 2>/dev/null || true)
  FUTEX_COUNT=$(echo "$FUTEX_LINES" | wc -l)
  FUTEX_WAIT=$(echo "$FUTEX_LINES" | grep "FUTEX_WAIT" | wc -l || echo 0)
  FUTEX_WAKE=$(echo "$FUTEX_LINES" | grep "FUTEX_WAKE" | wc -l || echo 0)

  echo "  futex 总调用: ${FUTEX_COUNT}"
  echo "  FUTEX_WAIT:   ${FUTEX_WAIT}"
  echo "  FUTEX_WAKE:   ${FUTEX_WAKE}"

  # 找出耗时最长的 futex
  echo ""
  echo "  最慢 futex Top 5:"
  echo "$FUTEX_LINES" | sort -t'<' -k2 -rn 2>/dev/null | head -5 || echo "    (无)"
fi

echo ""

# --------------------------------------------------------------------------
# T3 - epoll/IO 分析
# --------------------------------------------------------------------------
echo ""
echo "【T3】epoll/IO 阻塞分析"
echo "------------------------------------------------------------------"
if [ -f "$STDERR" ]; then
  EPOLL_LINES=$(grep -E "epoll_wait|epoll_pwait" "$STDERR" 2>/dev/null || true)
  READ_LINES=$(grep -E "^read\(" "$STDERR" 2>/dev/null || true)
  WRITE_LINES=$(grep -E "^write\(" "$STDERR" 2>/dev/null || true)

  EPOLL_COUNT=$(echo "$EPOLL_LINES" | wc -l)
  READ_COUNT=$(echo "$READ_LINES" | wc -l)
  WRITE_COUNT=$(echo "$WRITE_LINES" | wc -l)

  echo "  epoll_wait 调用: ${EPOLL_COUNT} 次"
  echo "  read 调用:      ${READ_COUNT} 次"
  echo "  write 调用:     ${WRITE_COUNT} 次"

  # epoll 超时比例
  EPOLL_TIMEOUT=$(echo "$EPOLL_LINES" | grep "= 0" | wc -l || echo 0)
  if [ "$EPOLL_COUNT" -gt 0 ]; then
    TIMEOUT_PCT=$(( EPOLL_TIMEOUT * 100 / EPOLL_COUNT ))
    echo "  epoll_wait 超时返回: ${EPOLL_TIMEOUT}/${EPOLL_COUNT} (${TIMEOUT_PCT}%)"
    [ "$TIMEOUT_PCT" -gt 80 ] && echo "  ⚠ epoll 频繁超时，可能事件等待不足"
  fi
fi

echo ""

# --------------------------------------------------------------------------
# T4 - 独立归因
# --------------------------------------------------------------------------
echo ""
echo "【T4】调用轨迹轨道结论"
echo "------------------------------------------------------------------"
{
  echo "  慢 syscall 类型: futex/epoll/read/write 耗时分析已完成"
  echo "  调用轨迹归因假设: 见上述耗时分布"
} | tee -a "${OUT_DIR}/branch_B_metrics.txt"

# ==========================================================================
# ▶ 内核语义轨道
# ==========================================================================
echo ""
echo "=================================================================="
echo " ▶ 内核语义轨道 —— 慢 Syscall 根因分析"
echo "=================================================================="

echo ""
echo "【K1】慢 syscall 根因定位指引"
echo "------------------------------------------------------------------"
cat << 'SRCGUIDE'
  futex 耗时:
    · 检查锁持有者: cat /proc/<PID>/stack
    · 分析锁竞争: perf record -e sched:sched_switch -p <PID> -- sleep 5
    · 锁持有时间 vs 调度延迟（futex 等待包括调度延迟）
  
  epoll_wait 耗时:
    · 检查超时参数: strace 输出中的 timeout 值
    · ET 模式下检查是否漏读: 确认 read 循环读完所有数据
    · 检查 fd 是否就绪: /proc/<PID>/fdinfo/<epoll_fd>

  read/write 耗时:
    · 磁盘 IO: iostat -x 1; iotop -oP
    · 网络 IO: ss -ti; netstat -s
    · 检查缓存命中率: sar -B 1 (pgpgin/pgpgout)

  open 耗时:
    · 目录层级深度（每级需要权限检查）
    · 文件系统类型（网络 fs 延迟高）
    · 目录下文件数量（线性扫描）
SRCGUIDE

echo ""
echo "【K2】反事实验证"
echo "------------------------------------------------------------------"
echo "  □ 推演的耗时模式 == strace 中的耗时分布?"
echo "  □ 根因判断（锁竞争/IO瓶颈/调度延迟）与实际一致?"
echo ""

echo "=================================================================="
echo " ▶ 最终结论"
echo "=================================================================="
cat << 'CONCLUSION'

  故障模式: 慢 Syscall
  处理建议:
    futex 慢:
      · 减小锁粒度（fine-grained locking）
      · 使用读写锁替代互斥锁（读多写少场景）
      · 考虑无锁数据结构
    
    epoll 慢:
      · 调整超时参数
      · 检查 edge-triggered 事件处理完整性
      · 增加 worker 线程
    
    read/write 慢:
      · 使用异步 IO（io_uring / aio）
      · 调整 IO 调度策略
      · 升级存储硬件
    
    【验证建议】
      - 调整后重新运行 strace -T -c 确认耗时下降
CONCLUSION
