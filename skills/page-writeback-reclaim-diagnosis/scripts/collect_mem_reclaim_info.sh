#!/bin/bash
# ==============================================================
# collect_mem_reclaim_info.sh
# 页缓存/脏页回写/内存回收 全量基线信息采集脚本
# 输出按 Section A~J 组织，供后续分支决策使用
# ==============================================================

set -e
export LANG=C
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
NODE=$(uname -n)

echo "=============================================================="
echo " 页缓存/脏页回写/内存回收 基线信息采集"
echo " 时间: $TIMESTAMP"
echo " 主机: $NODE"
echo "=============================================================="

# ----------------------------------------------------------------
# Section A: 系统概要
# ----------------------------------------------------------------
echo ""
echo "========== [Section A] 系统概要 =========="
echo "Kernel: $(uname -r 2>/dev/null)"
echo "OS: $(cat /etc/os-release 2>/dev/null | head -3 | tr '\n' ' ')"
echo "Arch: $(uname -m 2>/dev/null)"
echo "CPU: $(nproc 2>/dev/null) cores"
total_gb=$(awk '/MemTotal/{printf "%.1f", $2/1024/1024}' /proc/meminfo 2>/dev/null)
echo "MemTotal: ${total_gb} GB"
swap_gb=$(awk '/SwapTotal/{printf "%.1f", $2/1024/1024}' /proc/meminfo 2>/dev/null)
echo "SwapTotal: ${swap_gb} GB"
uptime

# ----------------------------------------------------------------
# Section B: /proc/meminfo 完整快照
# ----------------------------------------------------------------
echo ""
echo "========== [Section B] /proc/meminfo 完整快照 =========="
cat /proc/meminfo 2>/dev/null

# ----------------------------------------------------------------
# Section C: /proc/vmstat 快照（含增量采样 5s×2）
# ----------------------------------------------------------------
echo ""
echo "========== [Section C] /proc/vmstat =========="
echo "--- 首次采样 ---"
cat /proc/vmstat 2>/dev/null

echo ""
echo "--- 等待 5s 二次采样 ---"
sleep 5
echo "--- 二次采样 ---"
cat /proc/vmstat 2>/dev/null

# 计算关键增量指标（脏页、回收、refault）
echo ""
echo "--- 关键增量指标（两次采样差值，每秒均值） ---"
declare -A V1 V2
for kv in pgfault pgmajfault pgscan_kswapd pgscan_direct pgsteal_kswapd pgsteal_direct \
          pgrefill pgoutrun pgdeactivate pgskip pswpin pswpout \
          nr_dirty nr_writeback nr_pageout \
          workingset_refault workingset_activate workingset_restore \
          allocstall_dma allocstall_dma32 allocstall_normal allocstall_movabled; do
    v1=$(awk -v k="$kv" '$1 == k {print $2}' vmstat_t1.txt 2>/dev/null || echo 0)
    v2=$(awk -v k="$kv" '$1 == k {print $2}' vmstat_t2.txt 2>/dev/null || echo 0)
    diff=$((v2 - v1))
    echo "  $kv: $v1 → $v2 (Δ=${diff}/5s = $(echo "scale=0; $diff/5" | bc 2>/dev/null)/s)"
done

# ----------------------------------------------------------------
# Section D: /proc/zoneinfo（水位状态）
# ----------------------------------------------------------------
echo ""
echo "========== [Section D] /proc/zoneinfo =========="
grep -E "Node|zone|free |min |low |high |scanned|reclaim|present|spanned|protection" /proc/zoneinfo 2>/dev/null | head -120

# ----------------------------------------------------------------
# Section E: BDI 逐设备回写统计
# ----------------------------------------------------------------
echo ""
echo "========== [Section E] BDI 逐设备回写统计 =========="
if [ -d /sys/devices/virtual/bdi ]; then
    for bdi in /sys/devices/virtual/bdi/*/; do
        bdi_name=$(cat "${bdi}dev_name" 2>/dev/null || echo "unknown")
        echo "--- BDI: $bdi_name ---"
        for f in nr_dirty_this_bf nr_writeback_this_bf nr_dirty_threshold bdi_dirty_limit \
                 wb_throttled min_ratio max_ratio dirty_ratelimit dirty_poll_interval \
                 avg_queue_size avg_write_bandwidth; do
            val=$(cat "${bdi}stats/$f" 2>/dev/null || echo "N/A")
            echo "  $f: $val"
        done
    done
else
    echo "BDI sysfs 不可访问"
fi

# ----------------------------------------------------------------
# Section F: 内核回写参数
# ----------------------------------------------------------------
echo ""
echo "========== [Section F] 内核回写参数 =========="
for p in dirty_ratio dirty_background_ratio dirty_expire_centisecs \
         dirty_writeback_centisecs dirty_background_bytes dirty_bytes \
         dirtytime_expire_seconds block_dump; do
    val=$(cat "/proc/sys/vm/$p" 2>/dev/null || echo "N/A")
    echo "  vm.$p = $val"
done

# ----------------------------------------------------------------
# Section G: 回收参数
# ----------------------------------------------------------------
echo ""
echo "========== [Section G] 回收参数 =========="
for p in min_free_kbytes watermark_scale_factor watermark_boost_factor \
         vfs_cache_pressure swappiness zone_reclaim_mode \
         page-cluster drop_caches extfrag_threshold \
         dirty_ratio; do
    val=$(cat "/proc/sys/vm/$p" 2>/dev/null || echo "N/A")
    echo "  vm.$p = $val"
done

# 额外：NR_FREE_PAGES / min_free_kbytes 比值估算
free_kb=$(awk '/MemFree/{print $2}' /proc/meminfo 2>/dev/null)
min_kb=$(cat /proc/sys/vm/min_free_kbytes 2>/dev/null || echo 0)
if [ "$min_kb" -gt 0 ] 2>/dev/null; then
    ratio=$(echo "scale=2; $free_kb / $min_kb" | bc 2>/dev/null)
    echo "  MemFree/min_free_kbytes = ${ratio}x"
fi

# ----------------------------------------------------------------
# Section H: kswapd / reclaim CPU 使用率
# ----------------------------------------------------------------
echo ""
echo "========== [Section H] kswapd / reclaim CPU =========="
# kswapd 进程是否存在
if pgrep -x kswapd0 >/dev/null 2>&1; then
    echo "kswapd0 PID: $(pgrep -x kswapd0)"
    # 简单 CPU 快照
    top -b -n1 -p $(pgrep -x kswapd0) 2>/dev/null | tail -2 || echo "top 不可用"
else
    echo "kswapd0 不在运行中（可能未启动或名不同）"
    pgrep kswapd 2>/dev/null && echo "kswapd PID: $(pgrep -x kswapd)" || echo "无 kswapd 进程"
fi

# 系统 CPU 占用概览
echo ""
top -b -n1 | head -5 2>/dev/null || echo "top 不可用"

# 软中断 / 系统 CPU 时间
echo ""
awk '/^cpu / {print "  CPU: user="$2" nice="$3" sys="$4" idle="$5" iowait="$6" irq="$7" softirq="$8}' /proc/stat 2>/dev/null || echo "/proc/stat 不可用"

# ----------------------------------------------------------------
# Section I: D 状态进程及 wchan
# ----------------------------------------------------------------
echo ""
echo "========== [Section I] D 状态进程及 wchan =========="
# 使用 ps 列出 D 状态进程
ps -eo pid,ppid,stat,wchan:32,comm,user --no-headers 2>/dev/null | awk '$3 ~ /^D/ {print}' | head -60 || echo "无 D 状态进程"

# 检查特殊回写/reclaim路径
echo ""
echo "--- 在 balance_dirty_pages / pageout / wait_on_page_writeback 的进程 ---"
for pid in $(ps -eo pid,stat --no-headers 2>/dev/null | awk '$2 ~ /^D/ {print $1}'); do
    wchan=$(cat /proc/$pid/wchan 2>/dev/null || echo "N/A")
    stack=$(cat /proc/$pid/stack 2>/dev/null | head -20 || echo "N/A")
    if echo "$wchan$stack" | grep -qiE "dirty|writeback|pageout|reclaim|wait_on_page|throttle"; then
        echo ""
        echo "  PID=$pid wchan=$wchan comm=$(cat /proc/$pid/comm 2>/dev/null)"
        echo "  Stack: $stack" | head -8
    fi
done

# ----------------------------------------------------------------
# Section J: 内核日志
# ----------------------------------------------------------------
echo ""
echo "========== [Section J] 内核日志 =========="
# OOM
echo "--- OOM 相关 ---"
dmesg 2>/dev/null | grep -iE "oom|out of memory|killed process" | tail -20 || echo "（无 OOM 记录）"

# allocation failure
echo ""
echo "--- allocation failure 相关 ---"
dmesg 2>/dev/null | grep -iE "allocation failure|page allocation" | tail -20 || echo "（无 allocation failure 记录）"

# blocked task（回收/回写相关的 hung task）
echo ""
echo "--- hung task / blocked 相关 ---"
dmesg 2>/dev/null | grep -iE "blocked for|hung_task|task.*blocked|watchdog" | grep -iE "dirty|writeback|reclaim|page" | tail -20 || echo "（无相关记录）"

# 其它回写/回收相关
echo ""
echo "--- 回写/回收通用相关 ---"
dmesg 2>/dev/null | grep -iE "writeback|dirty_|reclaim|kswapd|pageout" | tail -20 || echo "（无相关记录）"

echo ""
echo "=============================================================="
echo " 基线信息采集完成"
echo "=============================================================="
