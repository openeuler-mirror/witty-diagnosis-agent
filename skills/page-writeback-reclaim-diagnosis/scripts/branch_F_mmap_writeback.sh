#!/bin/bash
# ==============================================================
# branch_F_mmap_writeback.sh
# 分支F：mmap writeback 停顿
# 覆盖 msync/munmap/fput 卡顿、page_mkwrite 等待、
# 文件映射脏页检测
# ==============================================================

set -e
export LANG=C

echo "=============================================================="
echo " 分支F：mmap writeback 停顿诊断"
echo "=============================================================="

# 1. D 状态进程—写回/映射相关
echo ""
echo "--- 1. mmap/writeback 相关 D 状态进程 ---"
for pid in $(ps -eo pid,stat --no-headers 2>/dev/null | awk '$2 ~ /^D/ {print $1}'); do
    wchan=$(cat /proc/$pid/wchan 2>/dev/null || echo "N/A")
    stack=$(cat /proc/$pid/stack 2>/dev/null | head -25 || echo "N/A")
    if echo "$wchan$stack" | grep -qiE "mkwrite|page_mkwrite|msync|munmap|fput|writeback_page|wait_on_page|fault|filemap|do_wp_page"; then
        echo "  PID=$pid wchan=$wchan"
        echo "  comm=$(cat /proc/$pid/comm 2>/dev/null)"
        echo "  Stack:"
        echo "$stack" | head -10
        echo ""
    fi
done

# 2. 进程内存映射情况（Dirty RSS）
echo ""
echo "--- 2. 进程文件映射脏页统计 ---"
if command -v pmap &>/dev/null; then
    for pid in $(ps -eo pid,stat --no-headers 2>/dev/null | awk '$2 ~ /^D/ {print $1}' | head -5); do
        comm=$(cat /proc/$pid/comm 2>/dev/null)
        echo "  PID=$pid ($comm) 映射汇总:"
        pmap -x "$pid" 2>/dev/null | tail -3 || echo "    pmap 不可用"
    done
else
    echo "  pmap 不可用"
fi

# 3. /proc/smaps 检查各进程的 dirty 映射
echo ""
echo "--- 3. 进程 smaps dirty 文件映射 ---"
for pid in $(ps -eo pid,stat --no-headers 2>/dev/null | awk '$2 ~ /^D/ {print $1}' | head -3); do
    comm=$(cat /proc/$pid/comm 2>/dev/null)
    echo "  PID=$pid ($comm):"
    smaps_file="/proc/$pid/smaps"
    if [ -r "$smaps_file" ]; then
        awk '
          /^[0-9a-f]+-[0-9a-f]+ / { path = $NF }
          /Rss:/    { rss = $2 }
          /Dirty:/  { dirty = $2 }
          /VmFlags:/ { if (path ~ /^\/|\[vma\]/ && dirty > 0)
                         printf "    %s Rss=%s Dirty=%s\n", path, rss, dirty }
        ' "$smaps_file" 2>/dev/null | head -10
    fi
done

# 4. 脏页总量与文件映射关系
echo ""
echo "--- 4. 脏页构成 ---"
grep -E "^(Dirty|AnonPages|Cached|Mapped|Writeback)" /proc/meminfo 2>/dev/null

# 5. 内核日志映射/回写相关
echo ""
echo "--- 5. 内核日志 mmap/writeback 相关 ---"
dmesg 2>/dev/null | grep -iE "mmap|page_mkwrite|msync|writeback_page|fput" | tail -10 || echo "（无相关日志）"

# 6. slab 中与文件映射/VMA 相关
echo ""
echo "--- 6. VMA / 文件映射 slab 占用 ---"
slabtop -s c -o 2>/dev/null | grep -iE "vm_area|mm_struct|file|dentry|inode" | head -5 || echo "slabtop 不可用"

echo ""
echo "=============================================================="
echo " 分支F 诊断完成"
echo "=============================================================="
