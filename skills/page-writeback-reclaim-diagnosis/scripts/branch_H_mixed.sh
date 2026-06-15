#!/bin/bash
# ==============================================================
# branch_H_mixed.sh
# 分支H：混合/复杂场景
# 覆盖同时出现多个故障模式的情况
# 执行全部 A-G 分支的简化版检测，输出汇总对比
# ==============================================================

set -e
export LANG=C

echo "=============================================================="
echo " 分支H：混合/复杂回写-回收场景诊断"
echo "=============================================================="

TMP=$(mktemp -d)

# --- 采集所有分支的关键指标到临时文件 ---
echo ""
echo "--- [H1] 多维度指标总览 ---"

# 1. 脏页和回写
cat /proc/meminfo 2>/dev/null > "$TMP/meminfo.txt"
awk '/nr_dirty|nr_writeback|nr_pageout|workingset_|pgscan|pgsteal|pgfault|pgmajfault/' /proc/vmstat 2>/dev/null > "$TMP/vmstat_reclaim.txt"

# 2. 回收效率（10s 增量）
awk '$1 ~ /pgscan|pgsteal|pgrefill|pgoutrun|allocstall|workingset/' /proc/vmstat 2>/dev/null > "$TMP/vmstat_t1.txt"
sleep 10
awk '$1 ~ /pgscan|pgsteal|pgrefill|pgoutrun|allocstall|workingset/' /proc/vmstat 2>/dev/null > "$TMP/vmstat_t2.txt"

# 3. BDI
find /sys/devices/virtual/bdi -name "nr_dirty_this_bf" -exec cat {} \; 2>/dev/null > "$TMP/bdi_dirty.txt"
find /sys/devices/virtual/bdi -name "wb_throttled" -exec cat {} \; 2>/dev/null > "$TMP/bdi_throttled.txt"

# 4. zone 水位
grep -E "Node|zone|free |min |low |high " /proc/zoneinfo 2>/dev/null > "$TMP/zoneinfo.txt"

# 5. 参数
for p in dirty_ratio dirty_background_ratio min_free_kbytes vfs_cache_pressure swappiness watermark_scale_factor; do
    echo "$p=$(cat /proc/sys/vm/$p 2>/dev/null || echo N/A)" >> "$TMP/params.txt"
done

# 6. D 状态进程
ps -eo pid,stat,wchan:32,comm --no-headers 2>/dev/null | awk '$2 ~ /^D/ {print}' > "$TMP/dstate.txt"

# --- 输出汇总诊断 ---
echo ""
echo "========== H2: 故障模式汇总诊断 =========="

# H2-a: 脏页回写异常
echo ""
echo "--- [H2-a] 脏页回写异常检查 ---"
total=$(awk '/MemTotal/{print $2}' "$TMP/meminfo.txt")
dirty=$(awk '/^Dirty/{print $2}' "$TMP/meminfo.txt")
wback=$(awk '/^Writeback/{print $2}' "$TMP/meminfo.txt")
d_ratio=$(awk -F= '/dirty_ratio/{print $2}' "$TMP/params.txt")
limit=$(( total * d_ratio / 100 ))
echo "  Dirty=${dirty}kB limit=${limit}kB(${d_ratio}%) Writeback=${wback}kB"
if [ "$dirty" -gt "$limit" ] 2>/dev/null; then
    echo "  [A] 脏页超过 dirty_ratio 阈值!"
fi
if [ "$wback" -gt 0 ] 2>/dev/null; then
    echo "  [A] 当前有 ${wback}kB 正在回写"
fi

# H2-b: 回收压力
echo ""
echo "--- [H2-b] 回收压力检查 ---"
while read -r name val1; do
    val2=$(awk -v n="$name" '$1 == n {print $2}' "$TMP/vmstat_t2.txt")
    diff=$((val2 - val1))
    echo "  $name: Δ=+$diff/10s"
done < "$TMP/vmstat_t1.txt"

# H2-c: Page cache 抖动
echo ""
echo "--- [H2-c] Page cache 抖动检查 ---"
refault_t1=$(awk '/workingset_refault/{print $2}' "$TMP/vmstat_t1.txt" 2>/dev/null || echo 0)
refault_t2=$(awk '/workingset_refault/{print $2}' "$TMP/vmstat_t2.txt" 2>/dev/null || echo 0)
refault_delta=$((refault_t2 - refault_t1))
echo "  workingset_refault: Δ=+${refault_delta}/10s ($(( refault_delta / 10 ))/s)"
if [ "$refault_delta" -gt 10000 ] 2>/dev/null; then
    echo "  [C] Refault 速率 > 1000/s，page cache 正在剧烈抖动！"
fi

# H2-d: IO 背压
echo ""
echo "--- [H2-d] IO 背压检查 ---"
throttled_sum=$(paste -sd+ "$TMP/bdi_throttled.txt" 2>/dev/null | bc 2>/dev/null || echo 0)
echo "  wb_throttled 总和: $throttled_sum"

# H2-e: 水位不足
echo ""
echo "--- [H2-e] 水位不足检查 ---"
awk '
  /^Node/ { node = $0 }
  /zone/  { zone = $2 }
  /free / {
    free=$2; getline; min=$2
    if (free < min) printf "  [E] %s zone=%s: free=%d < min=%d\n", node, zone, free, min
  }
' "$TMP/zoneinfo.txt" 2>/dev/null || echo "  [E] 所有 zone free >= min"

# H2-f: vfs_cache_pressure
echo ""
echo "--- [H2-f] vfs_cache_pressure 检查 ---"
pressure=$(awk -F= '/vfs_cache_pressure/{print $2}' "$TMP/params.txt")
echo "  vfs_cache_pressure=$pressure"
if [ "$pressure" = "0" ] || [ "$pressure" -gt 500 ] 2>/dev/null; then
    echo "  [G] 极端值，需关注 slab 回收行为"
fi

# H2-g: mmap writeback
echo ""
echo "--- [H2-g] mmap writeback 检查 ---"
grep -E "mkwrite|msync|page_mkwrite|fput" "$TMP/dstate.txt" 2>/dev/null | head -5 || echo "  无相关 D 状态进程"

# H3: 综合诊断建议
echo ""
echo "========== H3: 综合诊断建议 =========="
echo "  基于以上多维度指标综合分析。"
echo "  建议优先级：回写异常 > 回收压力 > 参数误配。"
echo "  如多个模式同时触发，回溯时间线确定因果链。"
echo ""

# 清理
rm -rf "$TMP"

echo "=============================================================="
echo " 分支H 诊断完成"
echo "=============================================================="
