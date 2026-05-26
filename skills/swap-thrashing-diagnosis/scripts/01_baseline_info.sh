#!/usr/bin/env bash
# =============================================================================
# 脚本：01_baseline_info.sh
# 用途：Swap Thrashing 与虚拟内存异常诊断 —— 基础信息收集与快速定性
# 使用：bash 01_baseline_info.sh [output_dir]
# 参数：
#   $1  输出目录（可选，默认 /tmp/swap_diag_<timestamp>）
# =============================================================================

set -euo pipefail

OUT_DIR="${1:-/tmp/swap_diag_$(date +%Y%m%d%H%M%S)}"
mkdir -p "${OUT_DIR}"

echo "=================================================================="
echo " Swap Thrashing 基础信息收集"
echo " 输出目录: ${OUT_DIR}"
echo " 时间: $(date)"
echo "=================================================================="

# --------------------------------------------------------------------------
# 1. 系统基础信息
# --------------------------------------------------------------------------
echo ""
echo "▶ [1/12] 系统基础信息 ..."

{
  echo "=== 主机名 ==="
  hostname 2>/dev/null || echo "N/A"
  echo ""
  echo "=== uname ==="
  uname -a 2>/dev/null || true
  echo ""
  echo "=== 内核配置 (swap 相关) ==="
  zcat /proc/config.gz 2>/dev/null | grep -E "CONFIG_SWAP|CONFIG_ZSWAP|CONFIG_ZRAM|CONFIG_MEMCG_SWAP|CONFIG_COMPACTION" || \
    grep -E "CONFIG_SWAP|CONFIG_ZSWAP|CONFIG_ZRAM|CONFIG_MEMCG_SWAP|CONFIG_COMPACTION" /boot/config-$(uname -r) 2>/dev/null || \
    echo "  [无法读取内核配置]"
} > "${OUT_DIR}/system_info.txt" 2>/dev/null
echo "  -> system_info.txt"

# --------------------------------------------------------------------------
# 2. 内存与 Swap 基本信息
# --------------------------------------------------------------------------
echo ""
echo "▶ [2/12] 内存与 Swap 基本信息 ..."

{
  echo "=== free -h ==="
  free -h 2>/dev/null || true
  echo ""
  echo "=== /proc/meminfo ==="
  cat /proc/meminfo 2>/dev/null || true
} > "${OUT_DIR}/meminfo.txt" 2>/dev/null

{
  echo "=== swapon --show ==="
  swapon --show 2>/dev/null || swapon -s 2>/dev/null || echo "No swap"
  echo ""
  echo "=== /proc/swaps ==="
  cat /proc/swaps 2>/dev/null || true
} > "${OUT_DIR}/swap_info.txt" 2>/dev/null
echo "  -> meminfo.txt, swap_info.txt"

# --------------------------------------------------------------------------
# 3. Swap 活动实时采样
# --------------------------------------------------------------------------
echo ""
echo "▶ [3/12] Swap 活动实时采样（10秒）..."

# 使用 vmstat 采样
LC_ALL=C vmstat 1 10 > "${OUT_DIR}/vmstat.txt" 2>/dev/null &
VMPID=$!

# 同时用 sar 采样（如果可用）
if command -v sar &>/dev/null; then
  sar -S 1 10 > "${OUT_DIR}/sar_swap.txt" 2>/dev/null &
  SARPID=$!
  sar -B 1 10 > "${OUT_DIR}/sar_paging.txt" 2>/dev/null &
  SARBPID=$!
fi

wait $VMPID 2>/dev/null || true
echo "  -> vmstat.txt"

# --------------------------------------------------------------------------
# 4. 内核 vmstat 统计
# --------------------------------------------------------------------------
echo ""
echo "▶ [4/12] 内核 VM 统计 ..."

cat /proc/vmstat > "${OUT_DIR}/vmstat_summary.txt" 2>/dev/null || true

# 提取关键 swap/thrashing 指标
{
  echo "=== 关键 VM 指标 ==="
  for key in pgscan_kswapd pgscan_direct pgsteal_kswapd pgsteal_direct \
             allocstall pgpgin pgpgout pswpin pswpout pgmajfault \
             compact_stall compact_fail oom_kill numa_hit numa_miss \
             numa_foreign numa_interleave numa_local numa_other; do
    val=$(grep -w "$key" /proc/vmstat 2>/dev/null | awk '{print $2}')
    [ -n "$val" ] && echo "  $key = $val"
  done
} > "${OUT_DIR}/vm_key_metrics.txt" 2>/dev/null
echo "  -> vmstat_summary.txt, vm_key_metrics.txt"

# --------------------------------------------------------------------------
# 5. 进程级内存/swap 占用
# --------------------------------------------------------------------------
echo ""
echo "▶ [5/12] 进程级内存/swap 占用分析 ..."

# Top 20 RSS 进程
{
  echo "=== Top 20 进程按 RSS 排序 ==="
  ps -eo pid,comm,rss,%mem --sort=-%mem --no-headers 2>/dev/null | head -20
} > "${OUT_DIR}/top_rss.txt" 2>/dev/null

# Top 20 Swap 占用进程
{
  echo "=== Top 20 进程按 Swap 占用排序 ==="
  for f in /proc/[0-9]*/status 2>/dev/null; do
    awk '
      /^Name/{name=$2}
      /^Pid/{pid=$2}
      /^VmSwap/{if ($2 ~ /^[0-9]+$/ && $2 > 0) print pid, name, $2}
    ' "$f" 2>/dev/null
  done | sort -k3 -rn | head -20
} > "${OUT_DIR}/top_swap.txt" 2>/dev/null

# OOM score 排序
{
  echo "=== Top 20 OOM score 进程 ==="
  for f in /proc/[0-9]*/oom_score; do
    pid=$(basename "$(dirname "$f")")
    name=$(cat "/proc/$pid/comm" 2>/dev/null)
    score=$(cat "$f" 2>/dev/null)
    [ -n "$score" ] && echo "$pid $name $score"
  done 2>/dev/null | sort -k3 -rn | head -20
} > "${OUT_DIR}/oom_scores.txt" 2>/dev/null

echo "  -> top_rss.txt, top_swap.txt, oom_scores.txt"

# --------------------------------------------------------------------------
# 6. 内核日志中的 swap/oom 相关记录
# --------------------------------------------------------------------------
echo ""
echo "▶ [6/12] 内核日志分析 ..."

{
  echo "=== Swap OOM 相关日志 ==="
  dmesg 2>/dev/null | grep -E "swap|oom|Out of memory|killed|allocation failure|page allocation" | tail -50

  echo ""
  echo "=== I/O 错误相关日志 ==="
  dmesg 2>/dev/null | grep -E "I/O error|sd.*:.*error|nvme.*error" | tail -20
} > "${OUT_DIR}/dmesg_swap.txt" 2>/dev/null
echo "  -> dmesg_swap.txt"

# --------------------------------------------------------------------------
# 7. zswap/zram 信息
# --------------------------------------------------------------------------
echo ""
echo "▶ [7/12] zswap/zram 信息 ..."

{
  echo "=== zswap debug (如果可用) ==="
  if [ -d /sys/kernel/debug/zswap ]; then
    for f in /sys/kernel/debug/zswap/*; do
      echo "$(basename $f): $(cat $f 2>/dev/null)"
    done
  else
    echo "  zswap debug 不可用"
  fi

  echo ""
  echo "=== zswap 参数 ==="
  if [ -d /sys/module/zswap/parameters ]; then
    for f in /sys/module/zswap/parameters/*; do
      echo "$(basename $f): $(cat $f 2>/dev/null)"
    done
  else
    echo "  zswap 未加载"
  fi

  echo ""
  echo "=== zram 信息 ==="
  if command -v zramctl &>/dev/null; then
    zramctl
  else
    echo "  zramctl 不可用"
  fi
  if [ -d /sys/block ]; then
    for d in /sys/block/zram*; do
      [ -d "$d" ] && echo "  $(basename $d): $(cat $d/mm_stat 2>/dev/null)"
    done 2>/dev/null
  fi
} > "${OUT_DIR}/zswap_zram.txt" 2>/dev/null
echo "  -> zswap_zram.txt"

# --------------------------------------------------------------------------
# 8. 内核参数
# --------------------------------------------------------------------------
echo ""
echo "▶ [8/12] 内核 Swap 相关参数 ..."

{
  echo "=== sysctl vm 参数 ==="
  sysctl vm.swappiness vm.min_free_kbytes vm.vfs_cache_pressure \
         vm.watermark_scale_factor vm.overcommit_memory vm.overcommit_ratio \
         vm.dirty_ratio vm.dirty_background_ratio vm.zone_reclaim_mode \
         vm.page-cluster 2>/dev/null

  echo ""
  echo "=== THP 配置 ==="
  cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || echo "N/A"
  cat /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || echo "N/A"

  echo ""
  echo "=== NUMA 信息 ==="
  numactl --hardware 2>/dev/null || echo "numactl 不可用"
} > "${OUT_DIR}/kernel_params.txt" 2>/dev/null
echo "  -> kernel_params.txt"

# --------------------------------------------------------------------------
# 9. 内存 PSI 压力
# --------------------------------------------------------------------------
echo ""
echo "▶ [9/12] PSI 内存/IO 压力 ..."

{
  echo "=== PSI memory ==="
  cat /proc/pressure/memory 2>/dev/null || echo "N/A"
  echo ""
  echo "=== PSI io ==="
  cat /proc/pressure/io 2>/dev/null || echo "N/A"
} > "${OUT_DIR}/psi.txt" 2>/dev/null
echo "  -> psi.txt"

# --------------------------------------------------------------------------
# 10. I/O 统计
# --------------------------------------------------------------------------
if command -v iostat &>/dev/null; then
  echo ""
  echo "▶ [10/12] I/O 统计（可能需等待）..."
  iostat -x 1 5 > "${OUT_DIR}/iostat.txt" 2>/dev/null &
  IOPID=$!
  wait $IOPID 2>/dev/null || true
  echo "  -> iostat.txt"
fi

# --------------------------------------------------------------------------
# 11. CPU 热点（kswapd）
# --------------------------------------------------------------------------
echo ""
echo "▶ [11/12] kswapd CPU 占用（如果需要更准确分析，使用 perf top）..."

{
  echo "=== kswapd/kworker 进程 ==="
  ps -eo pid,comm,%cpu,%mem,rss --sort=-%cpu 2>/dev/null | head -20 | grep -E "kswapd|kworker|ksoftirqd" || echo "  (未在 top 中找到)"
} > "${OUT_DIR}/cpu_hotspots.txt" 2>/dev/null
echo "  -> cpu_hotspots.txt"

# --------------------------------------------------------------------------
# 12. 分支决策与综合推荐
# --------------------------------------------------------------------------
echo ""
echo "▶ [12/12] 分支决策与综合推荐 ..."
echo "------------------------------------------------------------------"

# 收集关键指标用于分支判断
MEMINFO_FILE="${OUT_DIR}/meminfo.txt"
VMSTAT_FILE="${OUT_DIR}/vmstat_summary.txt"
VMSTAT_LIVE="${OUT_DIR}/vmstat.txt"
DMESG_FILE="${OUT_DIR}/dmesg_swap.txt"
SWAP_INFO="${OUT_DIR}/swap_info.txt"

# 提取 swap 总量和已用量
SWAP_TOTAL=$(awk '/^SwapTotal:/{print $2}' "${MEMINFO_FILE}" 2>/dev/null || echo 0)
SWAP_FREE=$(awk '/^SwapFree:/{print $2}' "${MEMINFO_FILE}" 2>/dev/null || echo 0)
SWAP_USED=$(( SWAP_TOTAL - SWAP_FREE ))
SWAP_USED_PCT=0
if [ "$SWAP_TOTAL" -gt 0 ]; then
  SWAP_USED_PCT=$(( SWAP_USED * 100 / SWAP_TOTAL ))
fi

# 提取 si/so 速率（从最后 5 秒 vmstat 平均值）
SI_RATE=$(tail -5 "${VMSTAT_LIVE}" 2>/dev/null | awk '{sum+=$7} END{printf "%d", sum/5}')
SO_RATE=$(tail -5 "${VMSTAT_LIVE}" 2>/dev/null | awk '{sum+=$8} END{printf "%d", sum/5}')
[ -z "$SI_RATE" ] && SI_RATE=0
[ -z "$SO_RATE" ] && SO_RATE=0

# 提取 pgscan/pgsteal
PGSCAN_K=$(grep -w "pgscan_kswapd" "${VMSTAT_FILE}" 2>/dev/null | awk '{print $2}' || echo 0)
PGSTEAL_K=$(grep -w "pgsteal_kswapd" "${VMSTAT_FILE}" 2>/dev/null | awk '{print $2}' || echo 0)
PGSCAN_D=$(grep -w "pgscan_direct" "${VMSTAT_FILE}" 2>/dev/null | awk '{print $2}' || echo 0)
PGSTEAL_D=$(grep -w "pgsteal_direct" "${VMSTAT_FILE}" 2>/dev/null | awk '{print $2}' || echo 0)
ALLOCSTALL=$(grep -w "allocstall" "${VMSTAT_FILE}" 2>/dev/null | awk '{print $2}' || echo 0)
OOM_KILL=$(grep -w "oom_kill" "${VMSTAT_FILE}" 2>/dev/null | awk '{print $2}' || echo 0)

SWAPPINESS=$(sysctl vm.swappiness 2>/dev/null | awk '{print $3}' || echo 60)
SWAP_DEV=$(awk '{if(NR>1) print $1}' "${SWAP_INFO}" 2>/dev/null | head -1)

# 检查 zswap/zram 是否启用
ZSWAP_ACTIVE=false
[ -d /sys/kernel/debug/zswap ] && ZSWAP_ACTIVE=true
ZRAM_ACTIVE=false
ls /sys/block/zram* &>/dev/null && ZRAM_ACTIVE=true

# 检查 swap 设备类型（是否为 SSD）
SWAP_IS_SSD=false
if [ -n "$SWAP_DEV" ] && [[ "$SWAP_DEV" == /dev/sd* ]] || [[ "$SWAP_DEV" == /dev/nvme* ]]; then
  SWAP_DEV_BASE=$(basename "$SWAP_DEV" | sed 's/[0-9]//g')
  ROT=$(cat "/sys/block/${SWAP_DEV_BASE}/queue/rotational" 2>/dev/null || echo 1)
  [ "$ROT" = "0" ] && SWAP_IS_SSD=true
fi

# 分支匹配（参考 SKILL.md Step 2 决策树）
{
  echo "=================================================================="
  echo " 综合诊断建议"
  echo "=================================================================="
  echo ""
  echo "【系统概要】"
  echo "  SwapTotal:     ${SWAP_TOTAL} kB"
  echo "  SwapFree:      ${SWAP_FREE} kB"
  echo "  SwapUsed:      ${SWAP_USED} kB (${SWAP_USED_PCT}%)"
  echo "  si 速率:       ${SI_RATE} pages/s"
  echo "  so 速率:       ${SO_RATE} pages/s"
  echo "  pgscan_kswapd: ${PGSCAN_K}"
  echo "  pgsteal_kswapd:${PGSTEAL_K}"
  echo "  pgscan_direct: ${PGSCAN_D}"
  echo "  pgsteal_direct:${PGSTEAL_D}"
  echo "  allocstall:    ${ALLOCSTALL}"
  echo "  oom_kill:      ${OOM_KILL}"
  echo "  swappiness:    ${SWAPPINESS}"
  echo "  swap device:   ${SWAP_DEV}"
  echo "  swap is SSD:   ${SWAP_IS_SSD}"
  echo "  zswap active:  ${ZSWAP_ACTIVE}"
  echo "  zram active:   ${ZRAM_ACTIVE}"
  echo ""

  echo "【分支推荐】"
  MATCHED=0

  # 分支A: Swap 耗尽
  if [ "$SWAP_USED_PCT" -ge 90 ]; then
    echo "  ✓ 分支A: Swap 空间耗尽 (使用率 ${SWAP_USED_PCT}% >= 90%)"
    echo "     → bash scripts/branch_A_swap_exhaustion.sh ${OUT_DIR}"
    MATCHED=1
  fi

  # 分支B: Thrashing
  TOTAL_SWAP_RATE=$(( SI_RATE + SO_RATE ))
  if [ "$TOTAL_SWAP_RATE" -ge 500 ]; then
    SEV="🟡"
    [ "$TOTAL_SWAP_RATE" -ge 1000 ] && SEV="🔴"
    echo "  ${SEV} 分支B: Swap Thrashing (si+so=${TOTAL_SWAP_RATE} pages/s >= 500)"
    echo "     → bash scripts/branch_B_thrashing.sh ${OUT_DIR}"
    MATCHED=1
  fi

  # 分支C: Swappiness 不当
  if [ "$SWAPPINESS" -gt 100 ] || [ "$SWAPPINESS" -lt 1 ] 2>/dev/null; then
    echo "  ✓ 分支C: Swappiness 配置不当 (当前值=${SWAPPINESS})"
    echo "     → bash scripts/branch_C_swappiness.sh ${OUT_DIR}"
    MATCHED=1
  fi

  # 分支D: Swap 设备损坏
  if grep -qE "I/O error|buffer I/O" "${DMESG_FILE}" 2>/dev/null; then
    echo "  ✓ 分支D: Swap 设备 I/O 错误"
    echo "     → bash scripts/branch_D_swap_corruption.sh ${OUT_DIR}"
    MATCHED=1
  fi

  # 分支E: SSD 磨损
  if [ "$SWAP_IS_SSD" = true ] && [ "$SWAP_USED_PCT" -ge 50 ]; then
    echo "  ✓ 分支E: Swap on SSD (SSD 设备 + swap 使用率 ${SWAP_USED_PCT}% >= 50%)"
    echo "     → bash scripts/branch_E_ssd_wear.sh ${OUT_DIR}"
    MATCHED=1
  fi

  # 分支F: kswapd CPU 高
  if [ "${PGSCAN_K}" -gt 0 ] && [ "${PGSTEAL_K}" -gt 0 ]; then
    if [ "$((PGSCAN_K - PGSTEAL_K))" -gt "$PGSTEAL_K" ] 2>/dev/null; then
      echo "  ✓ 分支F: kswapd CPU 占用高 (pgscan >> pgsteal, 无效扫描)"
      echo "     → bash scripts/branch_F_kswapd_high.sh ${OUT_DIR}"
      MATCHED=1
    fi
  fi

  # 分支G: zswap/zram 异常
  if [ "$ZSWAP_ACTIVE" = true ] || [ "$ZRAM_ACTIVE" = true ]; then
    echo "  ✓ 分支G: zswap/zram 配置检查"
    echo "     → bash scripts/branch_G_zswap_zram.sh ${OUT_DIR}"
    MATCHED=1
  fi

  if [ "$MATCHED" -eq 0 ]; then
    echo "  ✗ 未明确匹配到特定分支"
    echo "  建议执行通用诊断: bash scripts/02_diagnosis.sh ${OUT_DIR}"
  fi

  echo ""
  echo "【OOM 状态】"
  if [ "$OOM_KILL" -gt 0 ]; then
    echo "  🔴 系统发生过 OOM Killer 事件！次数: ${OOM_KILL}"
    echo "  查看: ${DMESG_FILE}"
  else
    echo "  ✓ 未检测到 OOM 事件"
  fi
  echo ""
  echo "【allocstall】"
  if [ "$ALLOCSTALL" -gt 0 ]; then
    echo "  🟡 存在内存分配 stall (次数: ${ALLOCSTALL})"
  else
    echo "  ✓ 无内存分配 stall"
  fi
  echo "=================================================================="
} > "${OUT_DIR}/branch_recommendation.txt" 2>/dev/null

cat "${OUT_DIR}/branch_recommendation.txt"

echo ""
echo "=================================================================="
echo " 基础信息收集完成"
echo " 所有输出文件: ${OUT_DIR}/"
echo " 分支推荐: ${OUT_DIR}/branch_recommendation.txt"
echo "=================================================================="
