#!/bin/bash
# ==============================================================
# branch_C_page_cache_thrash.sh
# 分支C：Page cache 反复回收抖动
# 覆盖 workingset_refault、workingset_activate、pgmajfault、
# refault 距离分析、page cache 命中率推断
# ==============================================================

set -e
export LANG=C

echo "=============================================================="
echo " 分支C：Page cache 反复回收抖动诊断"
echo "=============================================================="

# 1. workingset / refault 指标快照
echo ""
echo "--- 1. workingset & refault 关键指标 ---"
awk '$1 ~ /^pgfault|^pgmajfault|^pgrefill|workingset_|^pswpin|^pswpout|allocstall|nr_inactive_anon|nr_active_anon|nr_inactive_file|nr_active_file' /proc/vmstat 2>/dev/null

# 2. 5s 增量采样的 refault 趋势
echo ""
echo "--- 2. Refault 5s 增量采样 ---"
awk '$1 ~ /workingset_|pgmajfault|pgfault/' /proc/vmstat > /tmp/vmstat_thrash_t1
sleep 5
awk '$1 ~ /workingset_|pgmajfault|pgfault/' /proc/vmstat > /tmp/vmstat_thrash_t2

while read -r name val1; do
    val2=$(awk -v n="$name" '$1 == n {print $2}' /tmp/vmstat_thrash_t2)
    diff=$((val2 - val1))
    rate=$(echo "scale=0; $diff/5" | bc 2>/dev/null)
    echo "  $name: $val1 → $val2 (Δ=${diff}/5s = ${rate}/s)"
done < /tmp/vmstat_thrash_t1
rm -f /tmp/vmstat_thrash_t1 /tmp/vmstat_thrash_t2

# 3. page cache 命中率估计
echo ""
echo "--- 3. Page cache 命中率估计 ---"
pgfault=$(awk '/^pgfault/{print $2}' /proc/vmstat 2>/dev/null || echo 0)
pgmajfault=$(awk '/^pgmajfault/{print $2}' /proc/vmstat 2>/dev/null || echo 0)

if [ "$pgfault" -gt 0 ] 2>/dev/null; then
    maj_ratio=$(echo "scale=2; $pgmajfault * 100 / $pgfault" | bc 2>/dev/null)
    echo "  pgfault=$pgfault, pgmajfault=$pgmajfault"
    echo "  pgmajfault/pgfault=${maj_ratio}% (major fault 占比)"
    if [ "$(echo "$maj_ratio > 10" | bc 2>/dev/null)" = "1" ]; then
        echo "  [警告] major fault 占比 > 10%，page cache 命中率低"
    else
        echo "  [正常] major fault 占比在合理范围"
    fi
else
    echo "  无法计算（pgfault=0）"
fi

# 4. refault 距离 — 通过 lru 列表大小估计
echo ""
echo "--- 4. Refault 距离估计 ---"
inactive_file=$(awk '/nr_inactive_file/{print $2}' /proc/vmstat 2>/dev/null || echo 0)
active_file=$(awk '/nr_active_file/{print $2}' /proc/vmstat 2>/dev/null || echo 0)
total_file_pages=$((inactive_file + active_file))
echo "  nr_inactive_file: $inactive_file"
echo "  nr_active_file: $active_file"
echo "  total_file_pages (估算): $total_file_pages"

# 如果 refault 增长快且 inactive 小 → 抖动
refault=$(awk '/workingset_refault/{print $2}' /proc/vmstat 2>/dev/null || echo 0)
activate=$(awk '/workingset_activate/{print $2}' /proc/vmstat 2>/dev/null || echo 0)
if [ "$refault" -gt 0 ] && [ "$inactive_file" -gt 0 ] 2>/dev/null; then
    refault_rate=$(echo "scale=2; $refault / $inactive_file" | bc 2>/dev/null)
    echo "  refault/inactive_file=${refault_rate}x (累计率)"
fi
if [ "$activate" -gt 0 ] && [ "$refault" -gt 0 ] 2>/dev/null; then
    act_ratio=$(echo "scale=2; $activate * 100 / $refault" | bc 2>/dev/null)
    echo "  workingset_activate/workingset_refault=${act_ratio}% (激活/refault)"
fi

# 5. 文件端缓存占用
echo ""
echo "--- 5. meminfo 缓存相关 ---"
grep -E "^(Cached|Active|Inactive|Mapped|Shmem|Slab|SReclaimable|KReclaimable|Buffers|SwapCached)" /proc/meminfo 2>/dev/null

# 6. swap 活动（swappiness 的影响）
echo ""
echo "--- 6. Swap 活动 ---"
echo "swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null)"
echo "pswpin=$(awk '/^pswpin/{print $2}' /proc/vmstat 2>/dev/null || echo 0)"
echo "pswpout=$(awk '/^pswpout/{print $2}' /proc/vmstat 2>/dev/null || echo 0)"
echo "SwapTotal: $(awk '/SwapTotal/{print $2}' /proc/meminfo 2>/dev/null) kB"
echo "SwapFree: $(awk '/SwapFree/{print $2}' /proc/meminfo 2>/dev/null) kB"
echo "SwapCached: $(awk '/SwapCached/{print $2}' /proc/meminfo 2>/dev/null) kB"

# 7. dmesg 中 thrash 相关
echo ""
echo "--- 7. 内核日志 thrash / reclaim 相关 ---"
dmesg 2>/dev/null | grep -iE "workingset|refault|thrash|page cache|truncate" | tail -10 || echo "（无相关记录）"

echo ""
echo "=============================================================="
echo " 分支C 诊断完成"
echo "=============================================================="
