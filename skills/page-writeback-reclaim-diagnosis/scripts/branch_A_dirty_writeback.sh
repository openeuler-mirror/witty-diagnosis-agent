#!/bin/bash
# ==============================================================
# branch_A_dirty_writeback.sh
# 分支A：脏页回写异常
# 覆盖 dirty_ratio/dirty_bytes 阈值、writeback throttling、
# balance_dirty_pages 节流检测
# ==============================================================

set -e
export LANG=C

echo "=============================================================="
echo " 分支A：脏页回写异常诊断"
echo "=============================================================="

# 1. 脏页总量与阈值关系
echo ""
echo "--- 1. 脏页阈值快照 ---"
echo "dirty_ratio=$(cat /proc/sys/vm/dirty_ratio 2>/dev/null)%"
echo "dirty_background_ratio=$(cat /proc/sys/vm/dirty_background_ratio 2>/dev/null)%"
echo "dirty_bytes=$(cat /proc/sys/vm/dirty_bytes 2>/dev/null)"
echo "dirty_background_bytes=$(cat /proc/sys/vm/dirty_background_bytes 2>/dev/null)"
echo "dirty_expire_centisecs=$(cat /proc/sys/vm/dirty_expire_centisecs 2>/dev/null)"
echo "dirty_writeback_centisecs=$(cat /proc/sys/vm/dirty_writeback_centisecs 2>/dev/null)"

# 2. /proc/meminfo 脏页相关
echo ""
echo "--- 2. meminfo 脏页相关 ---"
grep -E "^(Dirty|Writeback|WritebackTmp|NFS_Unstable|Cached|MemTotal|MemFree|AnonPages)" /proc/meminfo 2>/dev/null

# 3. /proc/vmstat 脏页指标
echo ""
echo "--- 3. vmstat 脏页相关 ---"
awk '$1 ~ /nr_dirty|nr_writeback|nr_pageout|nr_dirtied|nr_written|nr_foll_pin_acquired/' /proc/vmstat 2>/dev/null

# 4. BDI 脏页统计
echo ""
echo "--- 4. BDI 脏页/回写统计 ---"
if [ -d /sys/devices/virtual/bdi ]; then
    for bdi in /sys/devices/virtual/bdi/*/; do
        dev=$(cat "${bdi}dev_name" 2>/dev/null || echo "unknown")
        echo "  [$dev]"
        for f in nr_dirty_this_bf nr_writeback_this_bf bdi_dirty_limit \
                 wb_throttled dirty_ratelimit avg_write_bandwidth \
                 dirty_poll_interval min_ratio max_ratio; do
            val=$(cat "${bdi}stats/$f" 2>/dev/null || echo "N/A")
            echo "    $f: $val"
        done
    done
fi

# 5. 计算脏页阈值水位
echo ""
echo "--- 5. 脏页阈值水位计算 ---"
mem_total=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null)
dirty=$(awk '/^Dirty/{print $2}' /proc/meminfo 2>/dev/null)
writeback=$(awk '/^Writeback/{print $2}' /proc/meminfo 2>/dev/null)
dirty_rat=$(cat /proc/sys/vm/dirty_ratio 2>/dev/null || echo 0)
dirty_bg=$(cat /proc/sys/vm/dirty_background_ratio 2>/dev/null || echo 0)

# dirty_ratio 阈值（以 kB 计）
dirty_limit_kb=$(( mem_total * dirty_rat / 100 ))
dirty_bg_kb=$(( mem_total * dirty_bg / 100 ))

echo "  MemTotal: ${mem_total} kB"
echo "  dirty_limit (计算): ${dirty_limit_kb} kB (${dirty_rat}% of MemTotal)"
echo "  dirty_background (计算): ${dirty_bg_kb} kB (${dirty_bg}% of MemTotal)"
echo "  Dirty: ${dirty} kB"
echo "  Writeback: ${writeback} kB"

if [ "$dirty" -gt "$dirty_limit_kb" ] 2>/dev/null; then
    echo "  [警告] Dirty(${dirty}) > dirty_limit(${dirty_limit_kb})，已触发全局限流！"
elif [ "$dirty" -gt "$dirty_bg_kb" ] 2>/dev/null; then
    echo "  [信息] Dirty(${dirty}) > dirty_background(${dirty_bg_kb})，后台回写应已触发"
else
    echo "  [正常] Dirty 低于后台阈值"
fi

if [ "$writeback" -gt 0 ] 2>/dev/null; then
    echo "  [信息] Writeback=${writeback} kB，回写正在进行中"
fi

# 6. D 状态进程（balance_dirty_pages）
echo ""
echo "--- 6. D 状态进程检查（balance_dirty_pages / 回写相关） ---"
ps -eo pid,ppid,stat,wchan:32,comm --no-headers 2>/dev/null | awk '$3 ~ /^D/ {print}' | head -30
echo ""
for pid in $(ps -eo pid,stat --no-headers 2>/dev/null | awk '$2 ~ /^D/ {print $1}'); do
    wchan=$(cat /proc/$pid/wchan 2>/dev/null || echo "N/A")
    stack=$(cat /proc/$pid/stack 2>/dev/null | head -15 || echo "N/A")
    if echo "$wchan$stack" | grep -qiE "dirty|writeback|balance|throttle|wb_"; then
        echo "  PID=$pid wchan=$wchan comm=$(cat /proc/$pid/comm 2>/dev/null)"
        echo "  Stack: $stack" | head -5
        echo ""
    fi
done

# 7. 回写日志检查
echo ""
echo "--- 7. 内核日志回写相关 ---"
dmesg 2>/dev/null | grep -iE "balance_dirty_pages|dirty_limit|writeback_throttle|throttle_on_writeback" | tail -10 || echo "（无相关日志）"

echo ""
echo "=============================================================="
echo " 分支A 诊断完成"
echo "=============================================================="
