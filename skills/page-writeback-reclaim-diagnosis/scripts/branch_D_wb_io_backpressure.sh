#!/bin/bash
# ==============================================================
# branch_D_wb_io_backpressure.sh
# 分支D：慢设备拖垮回写（IO 背压）
# 覆盖 BDI 逐设备回写统计、单设备 IO 性能、全局 vs 局部 dirty 限流
# 可选参数：device（如 sda）
# ==============================================================

set -e
export LANG=C
DEV="$1"

echo "=============================================================="
echo " 分支D：慢设备拖垮回写（IO 背压）诊断"
echo " 目标设备: ${DEV:-全部}"
echo "=============================================================="

# 1. BDI 逐设备回写统计
echo ""
echo "--- 1. BDI 逐设备回写统计 ---"
if [ -d /sys/devices/virtual/bdi ]; then
    for bdi in /sys/devices/virtual/bdi/*/; do
        dev_name=$(cat "${bdi}dev_name" 2>/dev/null || echo "unknown")
        if [ -n "$DEV" ] && ! echo "$dev_name" | grep -q "$DEV"; then
            continue
        fi
        echo "  [BDI: $dev_name]"
        f="nr_dirty_this_bf"
        echo "    $f: $(cat "${bdi}stats/$f" 2>/dev/null || echo N/A)"
        echo "    nr_writeback_this_bf: $(cat "${bdi}stats/nr_writeback_this_bf" 2>/dev/null || echo N/A)"
        echo "    bdi_dirty_limit: $(cat "${bdi}stats/bdi_dirty_limit" 2>/dev/null || echo N/A)"
        echo "    wb_throttled: $(cat "${bdi}stats/wb_throttled" 2>/dev/null || echo N/A)"
        echo "    avg_write_bandwidth: $(cat "${bdi}stats/avg_write_bandwidth" 2>/dev/null || echo N/A)"
        echo "    dirty_ratelimit: $(cat "${bdi}stats/dirty_ratelimit" 2>/dev/null || echo N/A)"
        echo "    avg_queue_size: $(cat "${bdi}stats/avg_queue_size" 2>/dev/null || echo N/A)"
        echo "    min_ratio: $(cat "${bdi}stats/min_ratio" 2>/dev/null || echo N/A)"
        echo "    max_ratio: $(cat "${bdi}stats/max_ratio" 2>/dev/null || echo N/A)"
    done
else
    echo "  BDI sysfs 不可访问"
fi

# 2. 全局 vs BDI dirty 对比
echo ""
echo "--- 2. 全局 vs BDI dirty 对比 ---"
global_dirty=$(awk '/^Dirty/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
echo "  全局 Dirty: ${global_dirty} kB"

if [ -d /sys/devices/virtual/bdi ]; then
    for bdi in /sys/devices/virtual/bdi/*/; do
        dev_name=$(cat "${bdi}dev_name" 2>/dev/null || echo "unknown")
        if [ -n "$DEV" ] && ! echo "$dev_name" | grep -q "$DEV"; then
            continue
        fi
        dirty_this=$(cat "${bdi}stats/nr_dirty_this_bf" 2>/dev/null || echo 0)
        limit=$(cat "${bdi}stats/bdi_dirty_limit" 2>/dev/null || echo 0)
        if [ "$limit" -gt 0 ] 2>/dev/null; then
            usage=$(echo "scale=1; $dirty_this * 100 / $limit" | bc 2>/dev/null)
            echo "  [$dev_name] nr_dirty_this_bf=$dirty_this, bdi_dirty_limit=$limit (${usage}% 已用)"
            if [ "$(echo "$usage > 90" | bc 2>/dev/null)" = "1" ]; then
                echo "    [警告] 该 BDI 脏页接近 dirty limit，IO 背压风险高！"
            fi
        fi
    done
fi

# 3. 对应块设备 IO 性能
echo ""
echo "--- 3. 块设备 IO 性能 ---"
if command -v iostat &>/dev/null; then
    if [ -n "$DEV" ]; then
        iostat -x "$DEV" 1 3 2>/dev/null || echo "iostat 不可用"
    else
        iostat -x 1 3 2>/dev/null | head -30 || echo "iostat 不可用"
    fi
else
    echo "iostat 未安装"
    # 回退到 /proc/diskstats
    if [ -n "$DEV" ]; then
        echo "/proc/diskstats:"
        grep " $DEV " /proc/diskstats 2>/dev/null || echo "设备 $DEV 未找到"
    fi
fi

# 4. 设备 IO 队列深度
echo ""
echo "--- 4. 设备 IO 队列状态 ---"
if [ -n "$DEV" ]; then
    for d in "$DEV" "${DEV%[0-9]}"; do
        inflight=$(cat /sys/block/$d/inflight 2>/dev/null || echo "N/A")
        [ "$inflight" != "N/A" ] && echo "  $d inflight: $inflight"
        ro=$(cat /sys/block/$d/ro 2>/dev/null || echo "N/A")
        [ "$ro" != "N/A" ] && echo "  $d read-only: $ro"
    done
else
    for d in /sys/block/*/inflight; do
        dev=$(echo "$d" | cut -d/ -f4)
        val=$(cat "$d" 2>/dev/null)
        echo "  $dev inflight: $val"
    done
fi

# 5. D 状态进程(wb 相关)
echo ""
echo "--- 5. 回写相关 D 状态进程 ---"
for pid in $(ps -eo pid,stat --no-headers 2>/dev/null | awk '$2 ~ /^D|Dl/ {print $1}'); do
    wchan=$(cat /proc/$pid/wchan 2>/dev/null || echo "N/A")
    stack=$(cat /proc/$pid/stack 2>/dev/null | head -15 || echo "N/A")
    if echo "$wchan$stack" | grep -qiE "writeback|wb_|bdi|backing_dev|throttle|wait_on_page"; then
        echo "  PID=$pid wchan=$wchan comm=$(cat /proc/$pid/comm 2>/dev/null)"
        echo "  Stack top: $(echo "$stack" | head -3)"
    fi
done

echo ""
echo "=============================================================="
echo " 分支D 诊断完成"
echo "=============================================================="
