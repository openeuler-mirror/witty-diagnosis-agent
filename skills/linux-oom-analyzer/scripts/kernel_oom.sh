#!/bin/bash
# ============================================================
# 路径D：内核态 OOM 专项诊断脚本
# 覆盖子场景：D1(kdump预留) D2(内核模块) D3(Shmem/tmpfs) D4(Slab膨胀)
#
# 用法:
#   bash kernel_oom.sh -S <开始时间> [-E <结束时间>]
#
# 示例:
#   bash kernel_oom.sh -S "2024-01-15 14:00:00" -E "2024-01-15 15:00:00"
#
# 输出结构：
#   [SUMMARY]  自动摘要 + D1~D4 自动分类诊断（模型优先阅读）
#   [DETAIL]   原始详细数据（摘要存疑时补充查阅）
# ============================================================

START_TIME=""; END_TIME=""

while getopts ":S:E:h" opt; do
    case $opt in
        S) START_TIME="$OPTARG" ;; E) END_TIME="$OPTARG" ;;
        h) sed -n '3,10p' "$0" | sed 's/^# \{0,2\}//'; exit 0 ;;
        :) echo "错误: -$OPTARG 需要参数值"; exit 1 ;;
    esac
done

if [ -n "$START_TIME" ] && [ -z "$END_TIME" ]; then
    START_TS=$(date -d "$START_TIME" +%s 2>/dev/null)
    END_TIME=$(date -d "@$((START_TS+3600))" '+%Y-%m-%d %H:%M:%S')
fi

OUTPUT_DIR="/tmp/oom_kern_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTPUT_DIR"
exec > >(tee "$OUTPUT_DIR/kernel_oom.log") 2>&1

HAS_JOURNAL=$(which journalctl 2>/dev/null)

section() { echo ""; echo "###############################################"; echo "# $1"; echo "###############################################"; }
banner()  { echo ""; echo "╔══════════════════════════════════════════════╗"; printf "║  %-44s║\n" "$1"; echo "╚══════════════════════════════════════════════╝"; }
cmd_info() {
    echo ""
    echo "  ▶ 命令 : $1"
    echo "  ▶ 用途 : $2"
    echo "  ▶ 输出 : $3"
    echo ""
}

# 预计算内存归因（后续各节复用）
eval $(awk '
/MemTotal/        {printf "MEM_TOTAL=%d\n",    $2}
/MemFree/         {printf "MEM_FREE=%d\n",     $2}
/MemAvailable/    {printf "MEM_AVAIL=%d\n",    $2}
/^Buffers/        {printf "MEM_BUF=%d\n",      $2}
/^Cached/         {printf "MEM_CACHE=%d\n",    $2}
/^Slab:/          {printf "MEM_SLAB=%d\n",     $2}
/SReclaimable/    {printf "MEM_SREC=%d\n",     $2}
/SUnreclaim/      {printf "MEM_SUNREC=%d\n",   $2}
/^Shmem:/         {printf "MEM_SHMEM=%d\n",    $2}
/AnonPages/       {printf "MEM_ANON=%d\n",     $2}
/PageTables/      {printf "MEM_PT=%d\n",       $2}
/VmallocUsed/     {printf "MEM_VMALLOC=%d\n",  $2}
/KernelStack/     {printf "MEM_KSTACK=%d\n",   $2}
/HugePages_Total/ {printf "MEM_HPTOTAL=%d\n",  $2}
/Hugepagesize/    {printf "MEM_HPSIZE=%d\n",   $2}
' /proc/meminfo)

MEM_HUGEPAGES=$(( MEM_HPTOTAL * MEM_HPSIZE ))
MEM_ACCOUNTED=$(( MEM_ANON + MEM_CACHE + MEM_SLAB + MEM_SHMEM + MEM_BUF + MEM_PT + MEM_KSTACK + MEM_VMALLOC + MEM_HUGEPAGES ))
MEM_USED=$(( MEM_TOTAL - MEM_FREE ))
MEM_UNACCOUNTED=$(( MEM_USED - MEM_ACCOUNTED ))

# ================================================================
# [SUMMARY] 自动摘要 + D1~D4 自动分类诊断
# ================================================================
banner "[SUMMARY] 路径D 内核态OOM 自动摘要 — 模型优先阅读此节"
echo "分析时段: ${START_TIME:-全量} ~ ${END_TIME:-全量}"
echo ""

# ── S1: 内存归因精确计算 ─────────────────────────────────────
echo "━━━ S1. 内存归因精确计算 ━━━"
cmd_info \
    "awk 解析 /proc/meminfo，计算 已归因合计 和 未归因内存" \
    "未归因 = (MemTotal-MemFree) - (所有已知内存类型之和)；正常情况下应接近0，偏高说明有内核内存分配未被标准计数器追踪" \
    "逐项列出各内存类型MB值；最后给出未归因内存大小及诊断标记（>512MB = ⚠️ 疑似内核模块泄漏）"
printf "  %-30s %8d MB\n"  "MemTotal:"                $((MEM_TOTAL/1024))
printf "  %-30s %8d MB\n"  "MemFree:"                 $((MEM_FREE/1024))
printf "  %-30s %8d MB\n"  "已用(MemTotal-MemFree):"  $((MEM_USED/1024))
echo "  归因项目:"
printf "    %-28s %8d MB\n"  "AnonPages（进程匿名内存）:"  $((MEM_ANON/1024))
printf "    %-28s %8d MB\n"  "PageCache（文件缓存）:"       $((MEM_CACHE/1024))
printf "    %-28s %8d MB\n"  "Slab（内核slab缓存）:"        $((MEM_SLAB/1024))
printf "    %-28s %8d MB\n"  "Shmem（tmpfs/共享内存）:"     $((MEM_SHMEM/1024))
printf "    %-28s %8d MB\n"  "Buffers:"                     $((MEM_BUF/1024))
printf "    %-28s %8d MB\n"  "PageTables:"                  $((MEM_PT/1024))
printf "    %-28s %8d MB\n"  "KernelStack:"                 $((MEM_KSTACK/1024))
printf "    %-28s %8d MB\n"  "VmallocUsed:"                 $((MEM_VMALLOC/1024))
printf "    %-28s %8d MB\n"  "HugePages:"                   $((MEM_HUGEPAGES/1024))
echo "  ─────────────────────────────────────────────"
printf "  %-30s %8d MB\n"  "已归因合计:"              $((MEM_ACCOUNTED/1024))
printf "  %-30s %8d MB  %s\n" "【未归因内存】:"       $((MEM_UNACCOUNTED/1024)) \
    "$([ $MEM_UNACCOUNTED -gt $((512*1024)) ] && echo '⚠️  >512MB，疑似内核模块泄漏' || echo '✅ 正常')"

# ── S2: D1~D4 子场景自动诊断 ─────────────────────────────────
echo ""
echo "━━━ S2. 子场景自动诊断（D1~D4）━━━"
echo ""

# D1 ─────────────────────────────────────────────────────────
echo "  ── [D1] crashkernel/kdump 内存预留诊断 ──"
cmd_info \
    "cat /proc/cmdline | grep crashkernel  +  awk /proc/iomem 计算 Crash kernel 区域大小" \
    "检查启动参数中 crashkernel 预留量，预留过大会导致 MemTotal 远小于物理内存" \
    "crashkernel 参数值（如 crashkernel=512M）；/proc/iomem 中 Crash kernel 实际占用 MB"
CMDLINE_CK=$(cat /proc/cmdline | grep -oE 'crashkernel=[^ ]+')
IOMEM_CK_MB=$(awk '/Crash kernel/{
    split($1,a,"-"); start=strtonum("0x"a[1]); end=strtonum("0x"a[2])
    sum+=(end-start+1)} END{printf "%d",sum/1024/1024}' /proc/iomem 2>/dev/null)
if [ -n "$CMDLINE_CK" ]; then
    echo "    crashkernel 参数: $CMDLINE_CK"
    echo "    /proc/iomem 预留: ${IOMEM_CK_MB:-?} MB"
    echo "    MemTotal:         $((MEM_TOTAL/1024)) MB"
    [ "${IOMEM_CK_MB:-0}" -gt 256 ] 2>/dev/null && \
        echo "    ⚠️  预留 > 256MB，若内存紧张可考虑减小（如改为 crashkernel=128M）" || \
        echo "    ✅ crashkernel 预留量正常"
else
    echo "    ✅ 未配置 crashkernel（无 kdump 内存预留）"
fi

echo ""
echo "  ── [D2] 内核模块异常内存占用诊断 ──"
cmd_info \
    "cat /proc/vmallocinfo | awk 按调用者统计 vmalloc 内存  +  lsmod 过滤非标准模块" \
    "vmalloc 是内核模块分配大块内存的主要方式；按调用者（模块名/函数名）统计哪个模块分配了最多 vmalloc 内存" \
    "vmalloc 主要消耗者列表（>10MB）；非发行版原生模块列表（路径不在标准 kernel 目录下）"
echo "    未归因内存: $((MEM_UNACCOUNTED/1024)) MB"
echo "    vmalloc 主要消耗者（>10MB）:"
awk 'NF>4{size=$2; caller=$NF; sum[caller]+=size}
     END{for(c in sum) if(sum[c]>10485760) printf "      %8.1fMB  %s\n",sum[c]/1024/1024,c}' \
    /proc/vmallocinfo 2>/dev/null | sort -rn | head -10
echo "    非发行版原生模块:"
lsmod | awk 'NR>1{print $1}' | while read mod; do
    fname=$(modinfo "$mod" 2>/dev/null | awk '/^filename/{print $2}')
    [ -z "$fname" ] && continue
    echo "$fname" | grep -qE "/kernel/(drivers|net|fs|crypto|sound|block|lib|arch|mm|security)" && continue
    sz=$(lsmod | awk -v m="$mod" '$1==m{print $2}')
    printf "      %-25s  %s\n" "$mod(${sz}B)" "$fname"
done | head -10

echo ""
echo "  ── [D3] Shmem/tmpfs 异常诊断 ──"
cmd_info \
    "grep Shmem /proc/meminfo  +  df -h | grep tmpfs  +  find /dev/shm /run -size +10M" \
    "Shmem 包含 tmpfs 中的文件和匿名 MAP_SHARED 映射；偏高说明 tmpfs 有大文件或共享内存未释放" \
    "Shmem 占比；各 tmpfs 挂载点已用空间；/dev/shm 和 /run 下大于10MB的文件列表（含进程占用者）"
SHMEM_PCT=$(awk "BEGIN{printf \"%.1f\", $MEM_SHMEM*100/$MEM_TOTAL}")
printf "    Shmem: %d MB（占总内存 %s%%）  " $((MEM_SHMEM/1024)) "$SHMEM_PCT"
[ "$(awk "BEGIN{print ($MEM_SHMEM > $MEM_TOTAL*0.10) ? 1 : 0}")" = "1" ] && \
    echo "⚠️  超过10%，需排查" || echo "✅ 正常"
echo "    tmpfs 挂载点占用:"
df -h 2>/dev/null | awk '/tmpfs/{printf "      %-30s %6s used / %6s total\n",$6,$3,$2}'
echo "    /dev/shm 大文件（>10MB）:"
find /dev/shm /run -type f -size +10M 2>/dev/null -ls \
    | sort -k7 -rn | head -10 | awk '{printf "      %8.1fMB  %s\n",$7/1024/1024,$NF}' \
    || echo "      （无）"

echo ""
echo "  ── [D4] Slab 内存异常诊断 ──"
cmd_info \
    "awk 解析 /proc/slabinfo，提取 dentry/inode/proc_inode/sock 各对象内存占用" \
    "Slab 偏高时判断是哪类内核对象导致的，不同对象对应不同触发行为" \
    "各关键 slab 对象 MB 数值 + 自动诊断标记：dentry偏高=目录遍历; proc_inode偏高=大量fork; sock偏高=连接未关闭"
SLAB_PCT=$(awk "BEGIN{printf \"%.1f\", $MEM_SLAB*100/$MEM_TOTAL}")
printf "    Slab 总量: %d MB（占 %s%%）  " $((MEM_SLAB/1024)) "$SLAB_PCT"
[ "$(awk "BEGIN{print ($MEM_SLAB > $MEM_TOTAL*0.15)?1:0}")" = "1" ] && \
    echo "⚠️  超过15%" || echo "✅ 正常"
printf "    SUnreclaim: %d MB（不可回收部分）\n" $((MEM_SUNREC/1024))
echo ""
echo "    关键 slab 对象诊断:"
while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    mb=$(echo "$line" | awk '{print $NF}' | sed 's/MB//')
    case "$name" in
        dentry)           hint="偏高原因：大量目录遍历（如 find /）或频繁创建删除文件" ;;
        inode_cache)      hint="偏高原因：大量文件 inode 缓存，可能与 dentry 同步偏高" ;;
        proc_inode_cache) hint="偏高原因：大量进程/线程创建（fork 密集型应用）" ;;
        sock_inode_cache) hint="偏高原因：大量 socket 未关闭（高并发网络连接泄漏）" ;;
        *) hint="" ;;
    esac
    warn=""
    [ "$(awk "BEGIN{print ($mb+0>500)?1:0}" 2>/dev/null)" = "1" ] && warn="⚠️ "
    printf "    %-32s %7.1fMB  %s%s\n" "$name" "$mb" "$warn" "$hint"
done < <(awk 'NR>2 && /^(dentry|inode_cache|proc_inode_cache|sock_inode_cache|kmalloc|task_struct)/{
    printf "%s %s %.1fMB\n", $1, $2, $3*$4/1024/1024
}' /proc/slabinfo 2>/dev/null | sort -k3 -rn | head -10)

# ── S3: 内存碎片化评估 ───────────────────────────────────────
echo ""
echo "━━━ S3. 内存碎片化评估 ━━━"
cmd_info \
    "cat /proc/buddyinfo" \
    "展示每个 NUMA 节点每个 zone 中各 order（2^N × 4KB）的空闲内存块数量" \
    "order 0=4KB order 1=8KB ... order 10=4MB；高阶（>=8）数量为0时，大内存分配会失败触发 OOM，即使总空闲内存充足"
awk '
BEGIN {
    printf "  %-8s %-12s", "Node", "Zone"
    for(i=0;i<=10;i++) printf " %6s","ord"i
    printf "\n  %-8s %-12s","----","----"
    for(i=0;i<=10;i++) printf " %6s","------"
    printf "\n"
}
{
    printf "  %-8s %-12s", $2, $4
    for(i=5;i<=NF;i++) printf " %6s",$i
    printf "\n"
    # 检查高阶碎片
    if($NF+0==0 && $(NF-1)+0==0 && $(NF-2)+0==0)
        printf "    ⚠️  %s/%s: 无高阶(>=8)空闲页，内存碎片化严重！大内存分配将失败\n",$2,$4
}' /proc/buddyinfo 2>/dev/null

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "[SUMMARY END] 以下为原始详细数据"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ================================================================
# [DETAIL] 原始详细数据
# ================================================================
section "[DETAIL-D1] /proc/iomem 内存区域分布"
cmd_info "cat /proc/iomem | grep -E 'System RAM|Crash kernel|Reserved'" \
    "显示物理内存地址空间的完整分配情况，包括可用 RAM 和各类预留区域" \
    "System RAM 的地址范围可计算实际物理内存总量；Crash kernel 区域即 kdump 预留区"
cat /proc/iomem 2>/dev/null | grep -E "System RAM|Crash kernel|Reserved|ACPI"
echo ""
echo "--- /proc/cmdline（内核启动参数）---"
cmd_info "cat /proc/cmdline" \
    "获取内核启动时的完整命令行参数" \
    "包含 crashkernel/mem/memmap 等内存相关参数；是判断 D1 场景的直接证据"
cat /proc/cmdline

section "[DETAIL-D2] vmalloc 详细分配（按大小排序 Top 30）"
cmd_info "sort -k2 -rn /proc/vmallocinfo | head -30" \
    "获取最大的 vmalloc 分配记录，每行包含地址范围、大小、标志位和分配者（模块/函数）" \
    "第2列为字节数；最后一列为分配调用栈顶（如模块名+偏移）；异常大的单次分配需重点关注"
sort -k2 -rn /proc/vmallocinfo 2>/dev/null | head -30

echo ""
section "[DETAIL-D2] 内核模块完整列表（按大小排序）"
cmd_info "lsmod | sort -k2 -rn" \
    "获取所有已加载内核模块及其内存占用" \
    "第1列=模块名, 第2列=内存大小(字节), 第3列=引用计数；大模块（>10MB）需结合 vmalloc 分析是否存在泄漏"
lsmod | sort -k2 -rn | head -40

section "[DETAIL-D3] tmpfs 和 /dev/shm 详细内容"
cmd_info "mount | grep tmpfs  +  find /tmp /dev/shm /run -type f -size +1M" \
    "枚举所有 tmpfs 挂载点并查找大文件，定位 Shmem 内存的具体来源" \
    "tmpfs 挂载点列表；超过 1MB 的文件路径和大小，用于找到占用 Shmem 的具体文件"
mount | grep tmpfs
echo ""
echo "--- /dev/shm 内容 ---"
ls -lah /dev/shm 2>/dev/null
echo ""
echo "--- /tmp 大文件（>1MB）---"
find /tmp -type f -size +1M 2>/dev/null -ls | sort -k7 -rn | head -20
echo ""
echo "--- /run 大文件（>1MB）---"
find /run -type f -size +1M 2>/dev/null -ls | sort -k7 -rn | head -20

section "[DETAIL-D4] /proc/slabinfo 全量（内存 Top 40）"
cmd_info "awk 计算 /proc/slabinfo（对象数 × 单个大小），按内存排序" \
    "slab 分配器管理内核中频繁分配释放的固定大小对象（inode/dentry/socket等）" \
    "32列数据：对象名/活跃对象数/总对象数/对象大小/每slab对象数/每slab页数 + 统计；关注总内存(MB)列"
awk 'NR>2{printf "%-32s objs=%-8d size=%-6dB total=%8.1fMB\n",
    $1,$3,$4,$3*$4/1024/1024}' /proc/slabinfo 2>/dev/null | sort -k5 -rn | head -40
cp /proc/slabinfo "$OUTPUT_DIR/slabinfo.txt" 2>/dev/null

section "[DETAIL-D4] 内存回收相关内核参数"
cmd_info "sysctl -a | grep vm.(vfs_cache_pressure|swappiness|zone_reclaim_mode)" \
    "读取影响 slab 回收积极性的内核参数" \
    "vfs_cache_pressure=100(默认)；值越大内核越积极回收 dentry/inode 缓存；值为0则完全不回收（slab会无限增长）"
sysctl -a 2>/dev/null | grep -E \
    "vm\.(vfs_cache_pressure|min_free_kbytes|zone_reclaim_mode|swappiness|drop_caches)"

section "[DETAIL] 时间段内内核态相关日志"
cmd_info \
    "journalctl --since/--until -k | grep 'slab|vmalloc|page allocation|kswapd|oom'" \
    "从内核日志中提取与内存子系统（分配失败/slab/vmalloc/回收）相关的消息" \
    "page allocation failure 是内存分配失败的直接日志；Call Trace 中的 slab/vmalloc 路径提供精确的代码层面证据"
[ -n "$START_TIME" ] && [ -n "$HAS_JOURNAL" ] && \
    journalctl --since="$START_TIME" --until="$END_TIME" -k --no-pager 2>/dev/null \
        | grep -iE "slab|vmalloc|kmalloc|page allocation|kswapd|memory|oom" | head -200
dmesg -T 2>/dev/null | grep -iE "slab|vmalloc|page allocation failure|kswapd|oom" | tail -100

section "收集完成"
cp /proc/meminfo "$OUTPUT_DIR/meminfo.txt"
cat /proc/vmstat > "$OUTPUT_DIR/vmstat.txt" 2>/dev/null
cat /proc/buddyinfo > "$OUTPUT_DIR/buddyinfo.txt" 2>/dev/null
tar czf "${OUTPUT_DIR}.tar.gz" -C /tmp "$(basename $OUTPUT_DIR)/" 2>/dev/null
echo "📦 打包文件: ${OUTPUT_DIR}.tar.gz"
