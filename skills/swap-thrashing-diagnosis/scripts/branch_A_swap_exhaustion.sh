#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_A_swap_exhaustion.sh
# 用途：Swap 空间耗尽诊断 —— 现场指标轨道 + 内核语义轨道并行分析
# 使用：bash branch_A_swap_exhaustion.sh [output_dir]
# 参数：
#   $1  输出目录（来自 01_baseline_info.sh 的输出）
# =============================================================================

set -euo pipefail

OUT_DIR="${1:-/tmp/swap_diag_$(date +%Y%m%d%H%M%S)}"
mkdir -p "${OUT_DIR}"

echo "=================================================================="
echo " 分支A：Swap 空间耗尽 —— 双轨分析"
echo "=================================================================="

# --------------------------------------------------------------------------
# M1 系统态还原
# --------------------------------------------------------------------------
echo ""
echo "【M1】系统态还原 —— Swap 空间使用情况"
echo "------------------------------------------------------------------"

MEMINFO="${OUT_DIR}/meminfo.txt"
if [ -f "$MEMINFO" ]; then
  SWAP_TOTAL=$(awk '/^SwapTotal:/{print $2}' "$MEMINFO" || echo 0)
  SWAP_FREE=$(awk '/^SwapFree:/{print $2}' "$MEMINFO" || echo 0)
  SWAP_USED=$(( SWAP_TOTAL - SWAP_FREE ))
  echo "  SwapTotal: $SWAP_TOTAL kB"
  echo "  SwapFree:  $SWAP_FREE kB"
  echo "  SwapUsed:  $SWAP_USED kB"
  if [ "$SWAP_TOTAL" -gt 0 ]; then
    PCT=$(( SWAP_USED * 100 / SWAP_TOTAL ))
    echo "  使用率: ${PCT}%"
  fi
  echo ""
  grep -E "MemTotal|MemFree|MemAvailable|Cached|Dirty|Writeback|PageTables|Slab|VmallocUsed" "$MEMINFO" 2>/dev/null
fi

echo ""
echo "  ➤ 观察要点："
echo "    - Swap 使用率 > 90% → 已耗尽，需找原因"
echo "    - MemAvailable 是否充足 → 区分"swap 填满但内存有余" vs "整体紧张""
echo "    - Dirty + Writeback 是否很大 → 脏页占用导致文件页不可回收"
echo ""

# --------------------------------------------------------------------------
# M2 指标时序重建
# --------------------------------------------------------------------------
echo ""
echo "【M2】指标时序分析 —— Swap 使用趋势"
echo "------------------------------------------------------------------"

# 检查是否有 sar 历史日志
SAR_AVAIL=false
command -v sar &>/dev/null && SAR_AVAIL=true

if $SAR_AVAIL; then
  echo "  sar 历史日志（最近7天 swap 使用率）:"
  # 尝试各种 sar 日志路径
  for sa_file in /var/log/sysstat/sa[0-9]* /var/log/sa/sa[0-9]*; do
    if [ -f "$sa_file" ]; then
      echo "  --- $(basename $sa_file) ---"
      sar -S -f "$sa_file" 2>/dev/null | head -30
      echo ""
      break
    fi
  done
else
  echo "  sar 不可用，使用 /proc/meminfo 的 swap 变化..."
  echo "  （换页活动已在基线中收集，请查看 ${OUT_DIR}/vmstat.txt）"
fi

echo ""
echo "  ➤ 观察要点："
echo "    - SwapUsed 在哪个时间点开始快速上升？→ OOM 或 large process 启动时间"
echo "    - 对比 MemFree 的下降趋势 → 是内存持续泄漏还是突发分配"
echo ""

# --------------------------------------------------------------------------
# M3 进程级归因
# --------------------------------------------------------------------------
echo ""
echo "【M3】进程级归因 —— 找出 swap 占用者"
echo "------------------------------------------------------------------"

TOP_SWAP="${OUT_DIR}/top_swap.txt"
if [ -f "$TOP_SWAP" ]; then
  echo "  Top 20 swap 占用进程:"
  cat "$TOP_SWAP" 2>/dev/null || echo "    (无数据)"
fi

echo ""

# 手动收集实时数据
echo "  当前 swap 占用 TOP（实时）:"
for f in /proc/[0-9]*/status; do
  awk '
    /^Name/{name=$2}
    /^Pid/{pid=$2}
    /^VmSwap/{if ($2 ~ /^[0-9]+$/ && $2 > 0) print pid, name, $2}
  ' "$f" 2>/dev/null
done 2>/dev/null | sort -k3 -rn | head -10 || true

echo ""
echo "  ➤ 观察要点："
echo "    · 单个进程是否占用了不成比例的 swap → 内存泄漏"
echo "    · 多个进程共同占用 → 工作集过大"
echo "    · Java JVM / 数据库进程占用 → 检查 heap 大小"
echo ""

# --------------------------------------------------------------------------
# M4 独立归因
# --------------------------------------------------------------------------
echo ""
echo "【M4】现场指标轨道结论"
echo "------------------------------------------------------------------"
{
  SWAP_TOTAL=$(awk '/^SwapTotal:/{print $2}' "$MEMINFO" 2>/dev/null || echo 0)
  SWAP_FREE=$(awk '/^SwapFree:/{print $2}' "$MEMINFO" 2>/dev/null || echo 0)
  SWAP_USED=$(( SWAP_TOTAL - SWAP_FREE ))
  PCT=0
  [ "$SWAP_TOTAL" -gt 0 ] && PCT=$(( SWAP_USED * 100 / SWAP_TOTAL ))

  echo "  Swap 状态: 总量=${SWAP_TOTAL}kB 已用=${SWAP_USED}kB (${PCT}%)"
  echo "  活跃换页: 请查看基线 vmstat.txt"
  echo "  现场指标归因假设: "
  echo "    Swap 已耗尽，需要检查:"
  echo "    ① 总 swap 是否配置过小（建议 = RAM 的 0.5-2倍）"
  echo "    ② 是否有进程内存泄漏"
  echo "    ③ 是否 dirty_ratio 设置过高导致脏页堵塞"
  echo "    ④ 是否 overcommit 设置导致过度承诺"
} | tee -a "${OUT_DIR}/branch_A_metrics.txt"

# ==========================================================================
# ▶ 内核语义轨道（正向追踪）
# ==========================================================================
echo ""
echo "=================================================================="
echo " ▶ 内核语义轨道 —— 配置与源码分析指引"
echo "=================================================================="

echo ""
echo "【K1】Swap 配置验证"
echo "------------------------------------------------------------------"
echo "  执行以下命令检查 swap 相关配置:"
echo ""

# 收集关键参数
PARAMS="${OUT_DIR}/kernel_params.txt"
if [ -f "$PARAMS" ]; then
  echo "  --- 关键 swap 参数 ---"
  grep -E "swappiness|overcommit|watermark|dirty" "$PARAMS" 2>/dev/null || true
fi
echo ""

echo "【K2】内核语义分析 —— 源码路径参考"
echo "------------------------------------------------------------------"
cat << 'SRCGUIDE'
  Swap 耗尽在源码中有多种可能:

  ├── 场景A: 总 swap 太小
  │    ├── 检查: mkswap / swapon 时的交换空间大小
  │    └── 源码: mm/swapfile.c :: get_swap_page()
  │       → 当 swap_info[type].highest_bit 耗尽时返回 -1
  │
  ├── 场景B: 应用内存泄漏 → 匿名页大量增加
  │    ├── 检查: 进程 RSS 持续增长
  │    ├── 修复: 修复应用内存泄漏
  │    └── 源码: mm/vmscan.c :: shrink_lruvec()
  │       → 匿名页比例高 → shrink_list 选择匿名页回收
  │
  ├── 场景C: 脏页太多导致文件页不可回收，被迫 swap out
  │    ├── 检查: /proc/meminfo 的 Dirty / Writeback
  │    ├── 调整: 降低 dirty_ratio / dirty_background_ratio
  │    └── 源码: mm/page-writeback.c :: balance_dirty_pages()
  │       → 脏页量超过 dirty_ratio 时写回线程阻塞
  │
  └── 场景D: overcommit 过度承诺
       ├── 检查: vm.overcommit_memory=1（总是允许）
       ├── 调整: 改为 2（禁止 overcommit）或调整 ratio
       └── 源码: mm/mmap.c :: __vm_enough_memory()
          → overcommit=1 时不做任何检查

  根因帧判断: 
    - 如果 Swap 耗尽时 MemAvailable 仍充足 → swap 配置问题
    - 如果 Swap 和 Mem 都耗尽 → 工作集 > 物理内存
    - 如果只看到 swap 增长但 RSS 未同步增长 → 可能有共享库/内存映射被 swap out
SRCGUIDE

echo ""
echo "【反事实验证】"
echo "------------------------------------------------------------------"
echo "  用配置调整假设正向推演，确认与现象一致:"
echo "  □ 增加 swap 大小后问题解决 → 配置问题"
echo "  □ 恢复内存泄漏进程后 swap 稳定 → 应用问题"
echo "  □ 调整 dirty_ratio 后 swap 减少 → 脏页问题"
echo ""

# --------------------------------------------------------------------------
# 结论输出
# --------------------------------------------------------------------------
echo ""
echo "=================================================================="
echo " ▶ 最终结论"
echo "=================================================================="
cat << 'CONCLUSION'

  故障模式: Swap 空间耗尽
  处理建议:
    【紧急缓解】
      1. 释放 swap: swapoff -a && swapon -a（需确保内存足够）
      2. 或临时增加 swap: dd if=/dev/zero of=/tmp/swap bs=1M count=2048
         chmod 600 /tmp/swap && mkswap /tmp/swap && swapon /tmp/swap
      3. 或 OOM 调整: echo f > /proc/sysrq-trigger (OOM kill 高分进程)
    
    【根因修复】
      1. 若总 swap 过小: 增加 swap 分区/文件大小
      2. 若应用泄漏: 修复内存泄漏 / 限制进程内存
      3. 若脏页问题: 调低 dirty_ratio (建议 5-10)
      4. 若 overcommit: 改为 2 并设合理 ratio
    
    【验证建议】
      - 修复后观察 24h swap 使用率趋势
      - 配合基线脚本 01_baseline_info.sh 复检
CONCLUSION
