#!/bin/bash
# ==============================================================
# branch_B_reclaim_pressure.sh
# 分支B：kswapd / direct reclaim 高 CPU
# 覆盖 pgscan/pgsteal 分析、回收效率评估、压缩/迁移压力
# ==============================================================

set -e
export LANG=C

echo "=============================================================="
echo " 分支B：kswapd / direct reclaim 高 CPU 诊断"
echo "=============================================================="

# 1. 回收指标快照
echo ""
echo "--- 1. vmstat 回收相关指标 ---"
awk '$1 ~ /pgscan|pgsteal|pgrefill|pgoutrun|pgdeactivate|pgskip|allocstall|compact_|kswapd_|direct_/' /proc/vmstat 2>/dev/null

# 2. 两次采样计算增量
echo ""
echo "--- 2. 5s 增量采样 ---"
T1=$(mktemp)
T2=$(mktemp)
awk '$1 ~ /pgscan|pgsteal|pgrefill|pgoutrun|allocstall/' /proc/vmstat > "$T1"
sleep 5
awk '$1 ~ /pgscan|pgsteal|pgrefill|pgoutrun|allocstall/' /proc/vmstat > "$T2"

while read -r name val1; do
    val2=$(awk -v n="$name" '$1 == n {print $2}' "$T2")
    diff=$((val2 - val1))
    echo "  $name: $val1 → $val2 (Δ=${diff}/5s = $(echo "scale=0; $diff/5" | bc 2>/dev/null)/s)"
done < "$T1"
rm -f "$T1" "$T2"

# 3. 回收效率评估
echo ""
echo "--- 3. 回收效率评估 ---"
scan_k=$(awk '/pgscan_kswapd/{print $2}' /proc/vmstat 2>/dev/null || echo 0)
scan_d=$(awk '/pgscan_direct/{print $2}' /proc/vmstat 2>/dev/null || echo 0)
steal_k=$(awk '/pgsteal_kswapd/{print $2}' /proc/vmstat 2>/dev/null || echo 0)
steal_d=$(awk '/pgsteal_direct/{print $2}' /proc/vmstat 2>/dev/null || echo 0)
throttle=$(awk '/pgscan_direct_throttle/{print $2}' /proc/vmstat 2>/dev/null || echo 0)
scan_total=$((scan_k + scan_d))
steal_total=$((steal_k + steal_d))

echo "  pgscan_kswapd: $scan_k"
echo "  pgscan_direct: $scan_d"
echo "  pgsteal_kswapd: $steal_k"
echo "  pgsteal_direct: $steal_d"
echo "  pgscan_direct_throttle: $throttle"
echo "  scan_total: $scan_total  steal_total: $steal_total"

if [ "$scan_total" -gt 0 ] 2>/dev/null; then
    eff=$(echo "scale=2; $steal_total * 100 / $scan_total" | bc 2>/dev/null)
    echo "  回收效率 (pgsteal/pgscan): ${eff}%"
else
    echo "  回收效率: N/A（无扫描活动）"
fi

if [ "$throttle" -gt 0 ] 2>/dev/null; then
    echo "  [严重] pgscan_direct_throttle=$throttle — 直接回收被限流！"
fi
if [ "$scan_d" -gt "$scan_k" ] 2>/dev/null; then
    echo "  [信息] direct reclaim 主导回收"
else
    echo "  [信息] kswapd 主导回收"
fi

# 4. kswapd CPU 占用
echo ""
echo "--- 4. kswapd CPU 占用 ---"
if pgrep -x kswapd0 >/dev/null 2>&1; then
    kspid=$(pgrep -x kswapd0)
    echo "  kswapd0 PID: $kspid"
    top -b -n1 -p "$kspid" 2>/dev/null | tail -2 || echo "  top 不可用"
    # kswapd 运行时间/状态
    echo "  kswapd 状态: $(cat /proc/$kspid/stat 2>/dev/null | awk '{print $3}')"
    echo "  kswapd CPU: $(ps -p $kspid -o %cpu --no-headers 2>/dev/null)%"
else
    echo "  kswapd0 不在运行"
fi

# 5. zoneinfo 水位与回收信号
echo ""
echo "--- 5. zone 水位与回收信号 ---"
grep -E "Node|zone|free |min |low |high |present|scanned|reclaim" /proc/zoneinfo 2>/dev/null | head -60

# 6. 内存碎片 / compation 压力
echo ""
echo "--- 6. 内存碎片/压缩 ---"
echo "compact_migrate_scanned: $(awk '/compact_migrate_scanned/{print $2}' /proc/vmstat 2>/dev/null || echo 0)"
echo "compact_free_scanned: $(awk '/compact_free_scanned/{print $2}' /proc/vmstat 2>/dev/null || echo 0)"
echo "compact_isolated: $(awk '/compact_isolated/{print $2}' /proc/vmstat 2>/dev/null || echo 0)"
echo "compact_stall: $(awk '/compact_stall/{print $2}' /proc/vmstat 2>/dev/null || echo 0)"
echo "compact_fail: $(awk '/compact_fail/{print $2}' /proc/vmstat 2>/dev/null || echo 0)"
echo "compact_success: $(awk '/compact_success/{print $2}' /proc/vmstat 2>/dev/null || echo 0)"
extfrag=$(cat /sys/kernel/debug/extfrag/extfrag_index 2>/dev/null | head -5 || echo "N/A")
echo "extfrag_index: $extfrag"

# 7. 内存分配失败日志
echo ""
echo "--- 7. allocation failure / OOM ---"
dmesg 2>/dev/null | grep -iE "allocation failure|page allocation failure" | tail -10 || echo "（无记录）"
dmesg 2>/dev/null | grep -iE "oom|out of memory|killed process" | tail -10 || echo "（无 OOM 记录）"

echo ""
echo "=============================================================="
echo " 分支B 诊断完成"
echo "=============================================================="
