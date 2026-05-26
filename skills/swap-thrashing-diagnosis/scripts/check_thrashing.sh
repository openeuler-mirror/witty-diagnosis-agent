#!/usr/bin/env bash
# =============================================================================
# 脚本：check_thrashing.sh
# 用途：独立 Swap Thrashing 检测脚本（可定时运行或按需排查）
# 使用：bash check_thrashing.sh [duration_seconds] [si_so_threshold]
# 示例：
#   bash check_thrashing.sh 30 500      # 检测30秒，阈值500 pages/s
#   bash check_thrashing.sh 10 1000     # 快速检测，阈值1000 pages/s
# =============================================================================

set -euo pipefail

echo "=================================================================="
echo " Swap Thrashing 检测器"
echo " 时间: $(date)"
echo "=================================================================="

# 参数
DURATION="${1:-10}"
THRESHOLD="${2:-500}"

echo "  检测时长: ${DURATION}s"
echo "  Thrashing 阈值: ${THRESHOLD} pages/s (si + so)"
echo ""

# --------------------------------------------------------------------------
# 检查依赖
# --------------------------------------------------------------------------
if ! command -v vmstat &>/dev/null; then
  echo "❌ vmstat 不可用，请安装 sysstat 或 procps 包"
  exit 1
fi

# --------------------------------------------------------------------------
# 样本采集
# --------------------------------------------------------------------------
echo "正在采集样本（${DURATION} 秒）..."
VMSTAT_OUT=$(LC_ALL=C vmstat 1 "${DURATION}" 2>/dev/null)

# 跳过标题行，取最后 N-2 行数据
SAMPLES=$(echo "$VMSTAT_OUT" | tail -n +3 | head -n -1 2>/dev/null || echo "$VMSTAT_OUT" | tail -n +3)

SAMPLE_COUNT=$(echo "$SAMPLES" | grep -c -E "^\\s*[0-9]" 2>/dev/null || echo 0)

if [ "$SAMPLE_COUNT" -lt 2 ]; then
  echo "❌ 样本不足（仅 ${SAMPLE_COUNT} 个有效样本）"
  echo "原始输出:"
  echo "$VMSTAT_OUT"
  exit 1
fi

echo "  有效样本数: ${SAMPLE_COUNT}"

# --------------------------------------------------------------------------
# 分析 thrashing 指标
# --------------------------------------------------------------------------
echo ""
echo "------------------------------------------------------------------"
echo " Thrashing 指标分析"
echo "------------------------------------------------------------------"
echo ""

# 计算各项指标
# 列: r,b,swpd,free,buff,cache,si,so,bi,bo,in,cs,us,sy,id,wa,st

SI_AVG=$(echo "$SAMPLES" | awk '{sum+=$7} END{printf "%.1f", sum/NR}')
SO_AVG=$(echo "$SAMPLES" | awk '{sum+=$8} END{printf "%.1f", sum/NR}')
SI_MAX=$(echo "$SAMPLES" | awk '{max=$7} {if($7>max) max=$7} END{print max}')
SO_MAX=$(echo "$SAMPLES" | awk '{max=$8} {if($8>max) max=$8} END{print max}')
BI_AVG=$(echo "$SAMPLES" | awk '{sum+=$9} END{printf "%.1f", sum/NR}')
BO_AVG=$(echo "$SAMPLES" | awk '{sum+=$10} END{printf "%.1f", sum/NR}')
WA_AVG=$(echo "$SAMPLES" | awk '{sum+=$16} END{printf "%.1f", sum/NR}')
ID_AVG=$(echo "$SAMPLES" | awk '{sum+=$15} END{printf "%.1f", sum/NR}')

TOTAL_AVG=$(echo "$SI_AVG + $SO_AVG" | bc 2>/dev/null || echo 0)
TOTAL_MAX=$(echo "$SI_MAX + $SO_MAX" | bc 2>/dev/null || echo 0)

SWPD=$(echo "$SAMPLES" | tail -1 | awk '{print $3}')
FREE=$(echo "$SAMPLES" | tail -1 | awk '{print $4}')
CACHE=$(echo "$SAMPLES" | tail -1 | awk '{print $6}')

echo "  ┌──────────────────────────────┬───────────┬──────────┐"
echo "  │ 指标                          │ 平均值     │ 最大值    │"
echo "  ├──────────────────────────────┼───────────┼──────────┤"
printf "  │ %-28s │ %-9s │ %-8s │\n" "si (swap in pages/s)"    "${SI_AVG}" "${SI_MAX}"
printf "  │ %-28s │ %-9s │ %-8s │\n" "so (swap out pages/s)"   "${SO_AVG}" "${SO_MAX}"
printf "  │ %-28s │ %-9s │ %-8s │\n" "si+so (total swap/s)"    "${TOTAL_AVG}" "${TOTAL_MAX}"
printf "  │ %-28s │ %-9s │ %-8s │\n" "bi (block in blk/s)"     "${BI_AVG}" ""
printf "  │ %-28s │ %-9s │ %-8s │\n" "bo (block out blk/s)"    "${BO_AVG}" ""
printf "  │ %-28s │ %-9s │ %-8s │\n" "wa (iowait %)"           "${WA_AVG}" ""
printf "  │ %-28s │ %-9s │ %-8s │\n" "id (idle %)"             "${ID_AVG}" ""
echo "  └──────────────────────────────┴───────────┴──────────┘"
echo ""
echo "  当前状态: swpd=${SWPD}KB  free=${FREE}KB  cache=${CACHE}KB"
echo ""

# --------------------------------------------------------------------------
# Thrashing 判定
# --------------------------------------------------------------------------
echo "------------------------------------------------------------------"
echo " 判定结果"
echo "------------------------------------------------------------------"

THRASHING_LEVEL=0

# 主要判定: si+so 速率
TOTAL_INT=$(echo "$TOTAL_AVG" | cut -d. -f1)
[ -z "$TOTAL_INT" ] && TOTAL_INT=0

if [ "$TOTAL_INT" -ge "$THRESHOLD" ]; then
  THRASHING_LEVEL=2
elif [ "$TOTAL_INT" -ge $(( THRESHOLD / 2 )) ]; then
  THRASHING_LEVEL=1
fi

# 辅助判定: iowait
WA_INT=$(echo "$WA_AVG" | cut -d. -f1)
[ -z "$WA_INT" ] && WA_INT=0

if [ "$WA_INT" -ge 30 ]; then
  THRASHING_LEVEL=$(( THRASHING_LEVEL + 1 ))
fi

# 输出判定
case $THRASHING_LEVEL in
  0)
    echo "  ✅ 未检测到 Swap Thrashing"
    echo "  si+so=${TOTAL_AVG} pages/s < ${THRESHOLD}（阈值）"
    echo "  iowait=${WA_AVG}%"
    echo ""
    echo "  系统 swap 活动正常"
    ;;
  1)
    echo "  🟡 轻度警告: 可能存在轻度 thrashing"
    echo "  si+so=${TOTAL_AVG} pages/s（阈值 ${THRESHOLD}）"
    echo "  iowait=${WA_AVG}%"
    echo ""
    echo "  建议: 进一步监控，确认趋势"
    echo "  watch -n 1 'vmstat 1 5 | tail -3'" 
    ;;
  2)
    echo "  🔴 Thrashing 检测到!"
    echo "  si+so=${TOTAL_AVG} pages/s >= ${THRESHOLD}（阈值）"
    echo "  iowait=${WA_AVG}%"
    echo ""
    echo "  建议立即处理:"
    echo "  1. 找出高 swap 占用进程"
    echo "     for f in /proc/[0-9]*/status; do"
    echo "       awk '/^Pid/{pid=\$2}/^Name/{name=\$2}/^VmSwap/{print pid,name,\$2}' \$f 2>/dev/null"
    echo "     done | sort -k3 -rn | head -10"
    echo "  2. 考虑以下紧急措施:"
    echo "     a) 降低 swappiness: sysctl -w vm.swappiness=10"
    echo "     b) 清理缓存: sync && echo 3 > /proc/sys/vm/drop_caches"
    echo "     c) 杀掉高内存占用进程"
    echo "  3. 运行完整诊断:"
    echo "     bash 01_baseline_info.sh"
    ;;
  3)
    echo "  🔴🔴 严重 Thrashing!"
    echo "  si+so=${TOTAL_AVG} pages/s >= ${THRESHOLD}（阈值）"
    echo "  iowait=${WA_AVG}% >= 30%（IO 瓶颈）"
    echo ""
    echo "  系统正经历严重 thrashing 和 IO 瓶颈"
    echo "  建议立即采取行动:"
    echo "  1. 降低 swappiness 到 1: sysctl -w vm.swappiness=1"
    echo "  2. OOM kill 高分进程: echo f > /proc/sysrq-trigger（警告: 会杀进程）"
    echo "  3. 增加内存或减少负载"
    echo "  4. 如有 zswap/zram，检查其健康状态"
    ;;
esac

echo ""
echo "------------------------------------------------------------------"
echo " 检测完成。时间: $(date)"
echo "=================================================================="
