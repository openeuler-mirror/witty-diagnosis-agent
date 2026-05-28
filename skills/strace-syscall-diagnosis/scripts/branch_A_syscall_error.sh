#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_A_syscall_error.sh
# 用途：Syscall 错误码模式识别 — 双轨分析
# 使用：bash branch_A_syscall_error.sh [output_dir]
# 参数：
#   $1  输出目录（来自 01_baseline_info.sh 的输出）
# =============================================================================

set -euo pipefail

OUT_DIR="${1:-/tmp/syscall_diag_$(date +%Y%m%d%H%M%S)}"

echo "=================================================================="
echo " 分支A：Syscall 错误码模式识别 —— 双轨分析"
echo "=================================================================="

# --------------------------------------------------------------------------
# T1 - 错误码分布
# --------------------------------------------------------------------------
echo ""
echo "【T1】错误码分布统计"
echo "------------------------------------------------------------------"

STDERR="${OUT_DIR}/strace_all.txt"
SUMMARY="${OUT_DIR}/strace_summary.txt"

if [ -f "$STDERR" ]; then
  echo "  所有错误码频次:"
  grep -oP "E[A-Z_]+" "$STDERR" 2>/dev/null | sort | uniq -c | sort -rn | head -15 || true
fi

echo ""

# 错误码分类解读
echo "  错误码解读:"
for err in EACCES EPERM ENOENT EAGAIN ENOMEM EBADF EINVAL ECONNREFUSED ETIMEDOUT EPIPE; do
  count=$(grep -c "$err" "$STDERR" 2>/dev/null || echo 0)
  [ "$count" -gt 0 ] && echo "    $err: ${count} 次"
done

echo ""

# --------------------------------------------------------------------------
# T2 - 错误时序分析
# --------------------------------------------------------------------------
echo ""
echo "【T2】错误时序分析"
echo "------------------------------------------------------------------"
if [ -f "$STDERR" ]; then
  echo "  各错误首次出现和末次出现（截取）:"
  for err in EACCES EPERM ENOENT EAGAIN ENOMEM EBADF; do
    first=$(grep -m1 "$err" "$STDERR" 2>/dev/null | awk '{print $1}' || true)
    last=$(grep "$err" "$STDERR" 2>/dev/null | tail -1 | awk '{print $1}' || true)
    count=$(grep -c "$err" "$STDERR" 2>/dev/null || echo 0)
    [ -n "$first" ] && echo "    $err: 共${count}次, 首次=${first}, 末次=${last}"
  done
fi

echo ""
echo "  ➤ 观察要点:"
echo "    · 错误集中在某个时间窗口 → 特定操作触发的"
echo "    · 错误持续存在 → 资源/配置长期问题"
echo "    · 错误频率增长 → 泄漏/恶化趋势"
echo ""

# --------------------------------------------------------------------------
# T3 - 错误上下文
# --------------------------------------------------------------------------
echo ""
echo "【T3】错误上下文（参数 + 调用场景）"
echo "------------------------------------------------------------------"
if [ -f "$STDERR" ]; then
  echo "  EACCES/EPERM 上下文:"
  grep "EACCES\|EPERM" "$STDERR" 2>/dev/null | head -10 || echo "    (无)"
  echo ""
  echo "  ENOENT 上下文:"
  grep "ENOENT" "$STDERR" 2>/dev/null | head -10 || echo "    (无)"
  echo ""
  echo "  ENOMEM 上下文:"
  grep "ENOMEM" "$STDERR" 2>/dev/null | head -10 || echo "    (无)"
fi

echo ""

# --------------------------------------------------------------------------
# T4 - 独立归因
# --------------------------------------------------------------------------
echo ""
echo "【T4】调用轨迹轨道结论"
echo "------------------------------------------------------------------"
{
  ERROR_COUNT=$(grep -cP "E[A-Z_]+" "${STDERR}" 2>/dev/null || echo 0)
  TOP_ERR=$(grep -oP "E[A-Z_]+" "${STDERR}" 2>/dev/null | sort | uniq -c | sort -rn | head -3 | awk '{print $2 "(" $1 "次)"}' | paste -sd, || echo "N/A")

  echo "  总错误数: ${ERROR_COUNT}"
  echo "  主要错误: ${TOP_ERR}"
  echo "  调用轨迹归因假设: 进程在执行 ${TOP_ERR} 时频繁失败，需检查对应资源和配置"
} | tee -a "${OUT_DIR}/branch_A_metrics.txt"

# ==========================================================================
# ▶ 内核语义轨道
# ==========================================================================
echo ""
echo "=================================================================="
echo " ▶ 内核语义轨道 —— 错误码根因分析"
echo "=================================================================="

echo ""
echo "【S1】常见错误排查指引"
echo "------------------------------------------------------------------"
cat << 'SRCGUIDE'
  EACCES/EPERM:
    · 文件权限: ls -la <path>
    · SELinux: getenforce; audit2why -a
    · Capabilities: getcap <binary>; cat /proc/<PID>/status | grep CapEff
  
  ENOENT:
    · 路径完整性: 每级目录用 ls 确认
    · 符号链接: readlink -f <path>
    · 库依赖: ldd <binary> | grep "not found"
    · 挂载点: mount | grep <path_component>

  EAGAIN/EWOULDBLOCK:
    · 重试间隔: strace -e trace=read,poll,epoll -p <PID>
    · 非阻塞 vs 阻塞: 检查 fd 创建时 O_NONBLOCK 标志
  
  ENOMEM:
    · 系统内存: free -h; cat /proc/meminfo
    · cgroup: cat /proc/<PID>/cgroup
    · overcommit: sysctl vm.overcommit_memory
    · max_map_count: sysctl vm.max_map_count
SRCGUIDE

echo ""
echo "【S2】反事实验证"
echo "------------------------------------------------------------------"
echo "  用根因假设正向推演:"
echo "  □ 推演的错误码 == strace 中的 errno?"
echo "  □ 推演的调用路径 == strace 中的 syscall 序列?"
echo "  □ 修复建议实施后错误消失?"
echo ""

echo "=================================================================="
echo " ▶ 最终结论"
echo "=================================================================="
cat << 'CONCLUSION'

  故障模式: Syscall 错误码模式
  处理建议:
    【根据错误码类型处理】
    · EACCES/EPERM → 修复权限/SELinux/capability
    · ENOENT → 补充依赖文件/修复路径
    · EAGAIN → 检查非阻塞重试策略
    · ENOMEM → 增加内存/调整 cgroup/检查泄漏
    
    【验证建议】
      - 修复后重新运行 strace -c 确认错误率下降
      - 使用 check_syscall.sh 定期巡检
CONCLUSION
