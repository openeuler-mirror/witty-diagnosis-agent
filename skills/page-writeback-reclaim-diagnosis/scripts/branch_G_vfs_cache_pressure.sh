#!/bin/bash
# ==============================================================
# branch_G_vfs_cache_pressure.sh
# 分支G：vfs_cache_pressure 误配
# 覆盖 slab 回收状态、dentry/inode 缓存占用、
# vfs_cache_pressure 合理性评估
# ==============================================================

set -e
export LANG=C

echo "=============================================================="
echo " 分支G：vfs_cache_pressure 误配诊断"
echo "=============================================================="

# 1. 基本参数
echo ""
echo "--- 1. 回收参数 ---"
echo "  vfs_cache_pressure=$(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null || echo N/A)"
echo "  swappiness=$(cat /proc/sys/vm/swappiness 2>/dev/null || echo N/A)"
echo "  zone_reclaim_mode=$(cat /proc/sys/vm/zone_reclaim_mode 2>/dev/null || echo N/A)"

# 2. slab 状态
echo ""
echo "--- 2. Slab 内存状态 ---"
grep -E "^(Slab|SReclaimable|SUnreclaim|KReclaimable)" /proc/meminfo 2>/dev/null

slab_total=$(awk '/^Slab/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
sreclaimable=$(awk '/^SReclaimable/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
sunreclaim=$(awk '/^SUnreclaim/{print $2}' /proc/meminfo 2>/dev/null || echo 0)
mem_total=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 1)

echo "  Slab/MemTotal: $(echo "scale=2; $slab_total * 100 / $mem_total" | bc 2>/dev/null)%"
echo "  SReclaimable/Slab: $(echo "scale=1; $sreclaimable * 100 / $slab_total" | bc 2>/dev/null)%"
echo "  SUnreclaim/Slab: $(echo "scale=1; $sunreclaim * 100 / $slab_total" | bc 2>/dev/null)%"

# 3. slabinfo 详细（dentry / inode / file 等）
echo ""
echo "--- 3. Slab 详细（dentry/inode/file 等）---"
if [ -f /proc/slabinfo ]; then
    echo "  dentry: $(awk '$1 == "dentry" {printf "objects=%d, size=%d kB", $2, $2*$4/1024}' /proc/slabinfo 2>/dev/null)"
    echo "  filp: $(awk '$1 == "filp" {printf "objects=%d, size=%d kB", $2, $2*$4/1024}' /proc/slabinfo 2>/dev/null)"
    echo "  inode_cache: $(awk '$1 == "inode_cache" {printf "objects=%d, size=%d kB", $2, $2*$4/1024}' /proc/slabinfo 2>/dev/null)"
    echo "  buffer_head: $(awk '$1 == "buffer_head" {printf "objects=%d, size=%d kB", $2, $2*$4/1024}' /proc/slabinfo 2>/dev/null)"
    echo "  vm_area_struct: $(awk '$1 == "vm_area_struct" {printf "objects=%d, size=%d kB", $2, $2*$4/1024}' /proc/slabinfo 2>/dev/null)"
    echo "  mm_struct: $(awk '$1 == "mm_struct" {printf "objects=%d, size=%d kB", $2, $2*$4/1024}' /proc/slabinfo 2>/dev/null)"
else
    echo "  /proc/slabinfo 不可用"
fi

# 4. dentry / inode 统计（如果可用）
echo ""
echo "--- 4. VFS 缓存统计 ---"
for f in nr_dentry nr_inode nr_unused; do
    val=$(cat /proc/sys/fs/$f 2>/dev/null || echo "N/A")
    echo "  $f: $val"
done

# 5. 诊断 vfs_cache_pressure 的合理范围
echo ""
echo "--- 5. vfs_cache_pressure 合理性评估 ---"
pressure=$(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null || echo 100)
sreclaimable_ratio=$(echo "scale=2; $sreclaimable * 100 / $mem_total" | bc 2>/dev/null)

if [ "$pressure" -eq 0 ] 2>/dev/null; then
    echo "  [警告] vfs_cache_pressure=0: slab 永不回收，容易内存泄漏"
elif [ "$pressure" -gt 0 ] 2>/dev/null && [ "$pressure" -le 50 ]; then
    echo "  [信息] vfs_cache_pressure=${pressure} < 100: slab 回收相对保守"
elif [ "$pressure" -eq 100 ] 2>/dev/null; then
    echo "  [正常] vfs_cache_pressure=100: 默认平衡值"
elif [ "$pressure" -gt 100 ] 2>/dev/null && [ "$pressure" -le 500 ]; then
    echo "  [信息] vfs_cache_pressure=${pressure} > 100: slab 回收偏激进"
elif [ "$pressure" -gt 500 ] 2>/dev/null; then
    echo "  [警告] vfs_cache_pressure=${pressure} >> 100: slab 回收极端激进"
fi

if [ "$(echo "$sreclaimable_ratio > 30" | bc 2>/dev/null)" = "1" ] && [ "$pressure" -lt 100 ] 2>/dev/null; then
    echo "  [建议] SReclaimable=${sreclaimable_ratio}% 占比高，可适度提高 vfs_cache_pressure"
fi

if [ "$(echo "$sreclaimable_ratio < 3" | bc 2>/dev/null)" = "1" ] && [ "$pressure" -gt 100 ] 2>/dev/null; then
    echo "  [信息] SReclaimable 低且 vfs_cache_pressure 高，回收主要是 reclaim 引起的"
fi

# 6. slaptop 首部
echo ""
echo "--- 6. slab 占用 TOP ---"
slabtop -s c -o 2>/dev/null | head -12 || echo "slabtop 不可用"

echo ""
echo "=============================================================="
echo " 分支G 诊断完成"
echo "=============================================================="
