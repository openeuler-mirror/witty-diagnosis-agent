#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_F_kswapd_high.sh
# 用途：kswapd CPU 占用过高诊断
# 使用：bash branch_F_kswapd_high.sh [output_dir]
# 参数：
#   $1  输出目录（来自 01_baseline_info.sh 的输出）
# =============================================================================

set -euo pipefail

OUT_DIR="${1:-/tmp/swap_diag_$(date +%Y%m%d%H%M%S)}"

echo "=================================================================="
echo " 分支F：kswapd CPU 占用过高 —— 双轨分析"
echo "=================================================================="

# --------------------------------------------------------------------------
# M1 kswapd CPU 占用确认
# --------------------------------------------------------------------------
echo ""
echo "【M1】kswapd CPU 与内存状态确认"
echo "------------------------------------------------------------------"

echo "  kswapd 进程状态:"
if command -v pidstat &>/dev/null; then
  pidstat -u -p $(pgrep -d',' -u0 kswapd 2>/dev/null || echo 0) 1 5 2>/dev/null | head -10 || echo "  kswapd 未运行或不可用"
else
  ps -eo pid,comm,%cpu,%mem,rss --sort=-%cpu 2>/dev/null | grep -E "kswapd|PID" | head -5 || echo "  kswapd 未在进程中"
fi

echo ""

# 内存概览
MEMINFO="${OUT_DIR}/meminfo.txt"
if [ -f "$MEMINFO" ]; then
  echo "  内存概览:"
  awk '/^MemTotal:/{mt=$2} /^MemFree:/{mf=$2} /^MemAvailable:/{ma=$2} /^Dirty:/{d=$2} /^Writeback:/{w=$2} END{printf "    MemTotal=%d kB MemFree=%d kB MemAvailable=%d kB Dirty=%d kB Writeback=%d kB\n", mt, mf, ma, d, w}' "$MEMINFO" 2>/dev/null
fi

echo ""

# --------------------------------------------------------------------------
# M2 无效扫描分析
# --------------------------------------------------------------------------
echo ""
echo "【M2】扫描效率分析（无效扫描检测）"
echo "------------------------------------------------------------------"

VM_KEY="${OUT_DIR}/vm_key_metrics.txt"
if [ -f "$VM_KEY" ]; then
  PGSCAN_K=$(grep -w "pgscan_kswapd" "$VM_KEY" | awk '{print $2}' || echo 0)
  PGSTEAL_K=$(grep -w "pgsteal_kswapd" "$VM_KEY" | awk '{print $2}' || echo 0)

  echo "  kswapd 扫描页数 (pgscan_kswapd):  ${PGSCAN_K}"
  echo "  kswapd 回收页数 (pgsteal_kswapd): ${PGSTEAL_K}"

  if [ "$PGSCAN_K" -gt 0 ] && [ "$PGSTEAL_K" -gt 0 ]; then
    EFFICIENCY=$(( PGSTEAL_K * 100 / PGSCAN_K ))
    echo "  回收效率: ${EFFICIENCY}%"
    if [ "$EFFICIENCY" -lt 20 ]; then
      echo ""
      echo "  ▓▓ 严重无效扫描: 回收效率 < 20% → kswapd 在空转！"
      echo "  可能原因:"
      echo "    · LRU 链表被大量不可回收页占据（脏页/unevictable 页）"
      echo "    · 内存碎片化严重（需要 compact 但 compact 也失败）"
      echo "    · 水位线设置过高（min_free_kbytes 太大）"
      echo "    · 脏页回写堵塞（dirty_ratio 过小或 IO 性能不足）"
    elif [ "$EFFICIENCY" -lt 50 ]; then
      echo "  ░░ 低效扫描: ${EFFICIENCY}% → 需要检查具体原因"
    else
      echo "  ✓ 扫描效率正常（> 50%）"
    fi
  fi

  echo ""
  ALLOCSTALL=$(grep -w "allocstall" "$VM_KEY" | awk '{print $2}' || echo 0)
  echo "  allocstall（分配阻塞）: ${ALLOCSTALL}"
  if [ "$ALLOCSTALL" -gt 0 ]; then
    echo "  ⚠ 存在内存分配阻塞 → 可能有进程在 direct reclaim 中睡眠"
  fi
fi

echo ""

# --------------------------------------------------------------------------
# M3 水位线分析
# --------------------------------------------------------------------------
echo ""
echo "【M3】水位线配置分析"
echo "------------------------------------------------------------------"

PARAMS="${OUT_DIR}/kernel_params.txt"
if [ -f "$PARAMS" ]; then
  echo "  水位线参数:"
  grep -E "min_free_kbytes|watermark_scale_factor" "$PARAMS" 2>/dev/null || echo "    未找到（请查看 kernel_params.txt）"
fi

echo ""
WATERMARK=$(awk 'NR==1{print $2}' /proc/zoneinfo 2>/dev/null | head -1 || echo "N/A")
echo "  /proc/zoneinfo: 请查看 zone 级别的水位线详情"
echo "    cat /proc/zoneinfo | grep -E 'Node|zone|min|low|high|scanned'"

echo ""

# --------------------------------------------------------------------------
# M4 内核语义分析
# --------------------------------------------------------------------------
echo ""
echo "【M4】内核语义分析 —— kswapd 高 CPU 源码路径"
echo "------------------------------------------------------------------"
cat << 'SRCGUIDE'
  kswapd 高 CPU 的常见根因:

  ▸ 场景1: 无效扫描（LRU 被不可回收页阻塞）
    · LRU 链表上大量脏页正在写回、unevictable 页、tempfs 文件页
    · 检查: /proc/meminfo 的 Dirty / Writeback / Unevictable
    · 源码: mm/vmscan.c :: shrink_page_list()
      → 页不可回收时跳过（PageWriteback / PageDirty 但没 IO 完成）
  
  ▸ 场景2: 内存碎片化（high-order 分配频繁失败）
    · /proc/buddyinfo 显示只有 order-0 空闲页块
    · 源码: mm/page_alloc.c :: __alloc_pages_slowpath()
      → __alloc_pages_may_compact() 尝试 compaction
      → compaction 失败 → 继续唤醒 kswapd 回收
  
  ▸ 场景3: 水位线过高
    · min_free_kbytes 设得太大（> 5% 总内存）
    · 源码: mm/page_alloc.c :: init_per_zone_wmark_min()
      → watermark[min] = min_free_kbytes / num_zones
      → 水位线高 → 频繁唤醒 kswapd
  
  ▸ 场景4: THP 导致频繁 compaction
    · 透明大页尝试 promotion 触发 compaction
    · 源码: mm/khugepaged.c / mm/compaction.c
    · 检查: /proc/vmstat 中 compact_* 计数
SRCGUIDE

echo ""
echo "【根因排查与修复】"
echo "------------------------------------------------------------------"

echo "  ▸ 无效扫描修复:"
echo "    降低 dirty 比例: sysctl -w vm.dirty_ratio=5"
echo "    禁用 THP defrag: echo never > /sys/kernel/mm/transparent_hugepage/defrag"
echo ""
echo "  ▸ 碎片化修复:"
echo "    定时 defrag: echo 1 > /proc/sys/vm/compact_memory"
echo "    减少 THP 使用: echo never > /sys/kernel/mm/transparent_hugepage/enabled"
echo ""
echo "  ▸ 水位线调整:"
echo "    降低 min_free_kbytes: sysctl -w vm.min_free_kbytes=$(awk '/MemTotal/{print int($2*0.003)}' /proc/meminfo)"
echo "    （默认约 0.04%，建议不低于 0.3%）"
echo ""
echo "  ▸ 降低 kswapd 唤醒频率:"
echo "    sysctl -w vm.watermark_scale_factor=50  # 增大 low-high 间隙"

echo ""
echo "=================================================================="
echo " ▶ 最终结论"
echo "=================================================================="
cat << 'CONCLUSION'

  故障模式: kswapd CPU 占用过高
  常见根因分类:
    □ 无效扫描（LRU 阻塞） → 降低 dirty_ratio、检查写回性能
    □ 碎片化（high-order 分配失败） → compact_memory、禁用 THP
    □ 水位线过高（频繁唤醒） → 降低 min_free_kbytes
    □ 脏页回写瓶颈 → 增加 IO 带宽或调整 dirty 比例
  
  处理建议:
    【紧急缓解】
      echo 1 > /proc/sys/vm/compact_memory  # 立即压缩内存
      echo 3 > /proc/sys/vm/drop_caches      # 清理缓存（谨慎）
    
    【配置优化】
      1. 调整 swappiness 和 dirty_ratio
      2. 考虑禁用 THP defrag
      3. 合理设置 min_free_kbytes
      4. 检查 IO 存储性能是否成为瓶颈
    
    【源码级修复】（如有源码）
      - 检查 mm/vmscan.c 中 scan_control.priority 是否降得太快
      - 检查 kswapd 唤醒逻辑 (wake_all_kswapds)
CONCLUSION
