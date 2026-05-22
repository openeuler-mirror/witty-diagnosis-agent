#!/usr/bin/env bash
# =============================================================================
# 脚本：branch_B_thrashing.sh
# 用途：Swap Thrashing（换页抖动）诊断 —— 现场指标轨道 + 内核语义轨道
# 使用：bash branch_B_thrashing.sh [output_dir]
# 参数：
#   $1  输出目录（来自 01_baseline_info.sh 的输出）
# =============================================================================

set -euo pipefail

OUT_DIR="${1:-/tmp/swap_diag_$(date +%Y%m%d%H%M%S)}"
mkdir -p "${OUT_DIR}"

echo "=================================================================="
echo " 分支B：Swap Thrashing —— 双轨分析"
echo "=================================================================="

# --------------------------------------------------------------------------
# M1 系统态还原
# --------------------------------------------------------------------------
echo ""
echo "【M1】系统态还原 —— SI/SO 活动与 CPU/iowait"
echo "------------------------------------------------------------------"

VMSTAT_LIVE="${OUT_DIR}/vmstat.txt"
if [ -f "$VMSTAT_LIVE" ]; then
  echo "  vmstat 采样（关注 si, so, wa, b 列）:"
  echo "  procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----"
  echo "   r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st"
  cat "$VMSTAT_LIVE" 2>/dev/null

  echo ""
  # 提取平均值
  echo "  汇总分析:"
  SI_AVG=$(tail -5 "$VMSTAT_LIVE" 2>/dev/null | awk '{sum+=$7} END{printf "%.0f", sum/NR}')
  SO_AVG=$(tail -5 "$VMSTAT_LIVE" 2>/dev/null | awk '{sum+=$8} END{printf "%.0f", sum/NR}')
  BI_AVG=$(tail -5 "$VMSTAT_LIVE" 2>/dev/null | awk '{sum+=$9} END{printf "%.0f", sum/NR}')
  WA_AVG=$(tail -5 "$VMSTAT_LIVE" 2>/dev/null | awk '{sum+=$16} END{printf "%.0f", sum/NR}')
  echo "    si (swap in):  ${SI_AVG} pages/s"
  echo "    so (swap out): ${SO_AVG} pages/s"
  echo "    bi (block in): ${BI_AVG} blocks/s"
  echo "    wa (iowait):   ${WA_AVG}%"

  TOTAL_SWAP=$(( SI_AVG + SO_AVG ))
  if [ "$TOTAL_SWAP" -ge 1000 ]; then
    echo ""
    echo "  ██ 严重 Thrashing 判定 ██"
    echo "  si+so=${TOTAL_SWAP} pages/s（>= 1000）→ 系统正经历严重换页抖动"
    echo "  建议立即检查:"
    echo "    · 工作集(WS) > 物理内存(RAM)？"
    echo "    · 是否有进程内存泄漏？"
    echo "    · 是否大量进程同时启动/释放？"
  elif [ "$TOTAL_SWAP" -ge 500 ]; then
    echo ""
    echo "  ▓▓ 中度 Thrashing 判定 ▓▓"
    echo "  si+so=${TOTAL_SWAP} pages/s（>= 500）→ 系统可能正在经历换页抖动"
  else
    echo ""
    echo "  ░░ 低强度换页活动 ░░"
    echo "  si+so=${TOTAL_SWAP} pages/s（< 500）→ 当前并非严重 thrashing"
  fi
fi

# I/O 统计交叉验证
IOSTAT_FILE="${OUT_DIR}/iostat.txt"
if [ -f "$IOSTAT_FILE" ]; then
  echo ""
  echo "  交叉验证 I/O 统计（bidi/busy 与 swap 的关联）:"
  grep -E "Device|sd[a-z]|nvme" "$IOSTAT_FILE" 2>/dev/null | head -10 || true
fi

echo ""

# --------------------------------------------------------------------------
# M2 时序重建（PSI + vmstat 趋势）
# --------------------------------------------------------------------------
echo ""
echo "【M2】PSI 内存压力分析"
echo "------------------------------------------------------------------"

PSI_FILE="${OUT_DIR}/psi.txt"
if [ -f "$PSI_FILE" ]; then
  cat "$PSI_FILE" 2>/dev/null
  echo ""
  echo "  ➤ PSI 解读:"
  echo "    · avg10 > 0.5 → 过去 10 秒 50%+ 时间在 stall"
  echo "    · full > some → 说明至少一个 CPU 完全被 stall 占满"
  echo "    · memory full 高 + io some 高 → 典型 thrashing 信号"
fi

echo ""

# --------------------------------------------------------------------------
# M3 进程级归因
# --------------------------------------------------------------------------
echo ""
echo "【M3】进程级归因 —— 谁在消耗/触发换页"
echo "------------------------------------------------------------------"

TOP_RSS="${OUT_DIR}/top_rss.txt"
TOP_SWAP="${OUT_DIR}/top_swap.txt"

echo "  RSS Top 10（内存消耗者）:"
if [ -f "$TOP_RSS" ]; then
  head -10 "$TOP_RSS" 2>/dev/null || true
fi

echo ""
echo "  Swap Top 10（swap 空间占用者，最可能触发 thrashing）:"
if [ -f "$TOP_SWAP" ]; then
  head -10 "$TOP_SWAP" 2>/dev/null || true
fi

echo ""
echo "  ➤ 观察要点:"
echo "    · swap 占用大的进程是否同时 RSS 也大？→ 该进程正在被频繁换入换出"
echo "    · 多个进程 RSS 总和接近/超过物理内存 → 工作集过大"
echo ""

# 计算总 RSS 与 RAM 的比对
echo "  RSS vs RAM 总览:"
TOTAL_RSS=0
for f in /proc/[0-9]*/status; do
  rss=$(awk '/^VmRSS/{print $2}' "$f" 2>/dev/null || echo 0)
  TOTAL_RSS=$(( TOTAL_RSS + rss ))
done 2>/dev/null || true
MEM_TOTAL=$(awk '/^MemTotal:/{print $2}' "${OUT_DIR}/meminfo.txt" 2>/dev/null || echo 0)
echo "    总 RSS (估算): ${TOTAL_RSS} kB"
echo "    物理内存:      ${MEM_TOTAL} kB"
if [ "$MEM_TOTAL" -gt 0 ]; then
  PCT=$(( TOTAL_RSS * 100 / MEM_TOTAL ))
  echo "    RSS/内存占比:  ${PCT}%"
  if [ "$PCT" -ge 90 ]; then
    echo "    ◆ RSS 已接近物理内存上限 → 工作集 > RAM，thrashing 根因确认"
  fi
fi

echo ""

# --------------------------------------------------------------------------
# M4 —— 现场指标归因总结
# --------------------------------------------------------------------------
echo ""
echo "【M4】现场指标轨道结论"
echo "------------------------------------------------------------------"

{
  SI_AVG=$(tail -5 "$VMSTAT_LIVE" 2>/dev/null | awk '{sum+=$7} END{printf "%.0f", sum/NR}')
  SO_AVG=$(tail -5 "$VMSTAT_LIVE" 2>/dev/null | awk '{sum+=$8} END{printf "%.0f", sum/NR}')
  TOTAL_SWAP=$(( SI_AVG + SO_AVG ))

  echo "  Swap 活动: si=${SI_AVG:-0} pages/s  so=${SO_AVG:-0} pages/s"
  echo "  合成速率: ${TOTAL_SWAP:-0} pages/s"
  echo "  RSS/内存占用比: ${PCT:-0}%"
  echo "  现场指标归因假设:"
  if [ "$TOTAL_SWAP" -ge 1000 ]; then
    echo "    Thrashing 严重。RSS ${PCT:-0}% 接近/超过物理内存容量"
    echo "    → 系统工作集超过物理内存，需要增加内存或减少负载"
  elif [ "$TOTAL_SWAP" -ge 500 ]; then
    echo "    中度 thrashing。需要进一步确认根因（工作集过大/脏页阻塞/碎片化）"
  else
    echo "    非典型 thrashing 模式。需结合其他指标综合判断"
  fi
} | tee -a "${OUT_DIR}/branch_B_metrics.txt"

# ==========================================================================
# ▶ 内核语义轨道
# ==========================================================================
echo ""
echo "=================================================================="
echo " ▶ 内核语义轨道 —— 源码级 Thrashing 分析"
echo "=================================================================="

echo ""
echo "【K1】内核关键计数检查"
echo "------------------------------------------------------------------"

VM_KEY="${OUT_DIR}/vm_key_metrics.txt"
if [ -f "$VM_KEY" ]; then
  echo "  --- 关键 vmstat 计数器 ---"
  cat "$VM_KEY" 2>/dev/null
fi

echo ""
echo "  ➤ 解读:"
echo "  · pgscan_kswapd >> pgsteal_kswapd → kswapd 在无效扫描"
echo "  · pgscan_direct > 0 → 进程直接回收（严重延迟）"
echo "  · allocstall > 0 → 内存分配阻塞（最严重）"
echo "  · pgmajfault 高 → swap in 导致主缺页"
echo ""

echo "【K2】内核语义分析 —— Thrashing 源码路径参考"
echo "------------------------------------------------------------------"
cat << 'SRCGUIDE'
  Thrashing 的完整内核因果链:

  ┌── 触发条件 ─────────────────────────────────────────────────┐
  │  进程工作集总和 > 物理内存容量                                │
  │  或 dirty_ratio 过大 → 文件页不可回收 → 被迫 swap out 匿名页   │
  │  或 NUMA 节点失衡 → 单节点超限                                │
  └─────────────────────────────────────────────────────────────┘
       ↓
  ┌── 内核行为 ─────────────────────────────────────────────────┐
  │  ① 分配器水位线检查 → zone_watermark_ok() 失败               │
  │     mm/page_alloc.c                                          │
  │  ② 唤醒 kswapd → wake_all_kswapds()                         │
  │     mm/vmscan.c :: balance_pgdat() → shrink_node()           │
  │  ③ shrink_lruvec() 选择回收目标                              │
  │     - 匿名页/文件页比例由 swappiness 控制                      │
  │  ④ swap_writepage() → 匿名页换出 → 回写至 swap 设备          │
  │  ⑤ 缺页时 do_swap_page() → swap_readpage() → 从 swap 读入   │
  └─────────────────────────────────────────────────────────────┘
       ↓
  ┌── 异常指标 ─────────────────────────────────────────────────┐
  │  si ≈ so → 频繁换入换出（thrashing 的典型特征）               │
  │  CPU iowait 高 → swap 设备 IO 成为瓶颈                        │
  │  pgmajfault 高 → 每次缺页都需要磁盘 IO                         │
  └─────────────────────────────────────────────────────────────┘
       ↓
  ┌── 系统表现 ─────────────────────────────────────────────────┐
  │  进程大量 D 状态（等待 IO）                                    │
  │  系统响应极慢，负载高但吞吐低                                   │
  │  最终可能 OOM Killer 触发                                      │
  └─────────────────────────────────────────────────────────────┘

  根因帧判定:
    · 如果 Total RSS > RAM → 根因是"工作集过大"
    · 如果 Dirty 占比高 → 根因是"脏页阻塞"
    · 如果 NUMA 节点差异大 → 根因是"NUMA 失衡"
    · 如果以上都不是 → 检查 direct reclaim 触发源 (allocstall)
SRCGUIDE

echo ""
echo "【K3】内核参数调整建议"
echo "------------------------------------------------------------------"
cat << 'ADVICE'
  根据 thrashing 类型，调整以下参数:

  ▸ 工作集过大:
    · 增加物理内存（最直接）
    · 减少运行进程数
    · 检查应用内存泄漏
  
  ▸ 脏页阻塞:
    sysctl -w vm.dirty_ratio=5
    sysctl -w vm.dirty_background_ratio=2
  
  ▸ kswapd 无效扫描:
    sysctl -w vm.swappiness=10   # 减少 swap 倾向
    sysctl -w vm.vfs_cache_pressure=200  # 积极回收 VFS 缓存
  
  ▸ NUMA 失衡:
    sysctl -w vm.zone_reclaim_mode=0  # 允许跨节点分配
    # 或对进程使用: numactl --interleave=all <command>
  
  ▸ 透明大页致 compaction:
    echo never > /sys/kernel/mm/transparent_hugepage/defrag
ADVICE

echo ""
echo "【反事实验证】"
echo "------------------------------------------------------------------"
echo "  用以上假设正向推演，确认与现场指标一致:"
echo "  □ 工作集分析: 进程 RSS 总和 > RAM？"
echo "  □ 脏页分析: /proc/meminfo Dirty 占比高？"
echo "  □ NUMA 分析: 一个节点在 swap，其他空闲？"
echo "  □ 配置调整后: thrashing 缓解？"
echo ""

# --------------------------------------------------------------------------
# 最终输出
# --------------------------------------------------------------------------
echo ""
echo "=================================================================="
echo " ▶ 最终结论"
echo "=================================================================="
cat << 'CONCLUSION'

  故障模式: Swap Thrashing
  置信度判断:
    · si+so > 1000 pages/s → 高置信度 thrashing
    · si+so 500-1000 但 PSI memory > 0.5 → 中高置信度
  
  处理建议:
    【紧急缓解】
      1. 排查高 swap 占用进程并 kill/重启（临时）
      2. OOM kill 高分进程: sysctl -w vm.oom_kill_allocating_task=1; echo f > /proc/sysrq-trigger
      3. 降低 swappiness: sysctl -w vm.swappiness=1（减少匿名页换出）
      4. 清理 page cache: sync && echo 3 > /proc/sys/vm/drop_caches
      5. 关闭 THP defrag: echo never > /sys/kernel/mm/transparent_hugepage/defrag

    【根本修复】
      1. 增加物理内存
      2. 优化应用内存使用（减少工作集）
      3. 调大 dirty_ratio/dirty_background_ratio（如果脏页是瓶颈）
      4. 使用 zram/zswap 减轻 swap 设备 IO 压力
      5. 合理规划 NUMA 内存分配

    【验证建议】
      - 调整后持续监控 si/so 速率 10 分钟
      - 使用 check_thrashing.sh 脚本定期检测
CONCLUSION
