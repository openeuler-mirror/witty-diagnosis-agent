# 内核态 OOM 分析参考手册

## 适用场景
- meminfo 中内存去向不明（total >> anon + cache + slab）
- Slab 内存异常增高
- Shmem/tmpfs 占用异常
- crashkernel 预留导致可用内存不足
- 内核模块内存泄漏

---

## D1. total 内存不足（kdump/crashkernel 预留）

### 诊断方法
```bash
# 检查实际物理内存与 MemTotal 的差异
dmidecode -t 17 2>/dev/null | grep "Size:" | grep -v "No Module"
# 或
lshw -class memory 2>/dev/null | grep size

# 检查 MemTotal
grep MemTotal /proc/meminfo

# 差异超过 512MB 需检查预留
dmesg | grep -E "crashkernel|reserved|BIOS-e820|ACPI"

# 查看 crashkernel 参数
cat /proc/cmdline | grep -o "crashkernel=[^ ]*"

# 查看内存区域分布
cat /proc/iomem | grep -E "System RAM|Crash kernel"
```

### 常见 crashkernel 配置
```bash
# 过大的预留（触发此场景）
crashkernel=512M        # 固定预留 512MB
crashkernel=2G-:256M    # >2G内存时预留256MB

# 合理调整
crashkernel=128M        # 对于多数场景足够

# 修改方法（GRUB）
vim /etc/default/grub
# 修改 GRUB_CMDLINE_LINUX 中的 crashkernel 参数
grub2-mkconfig -o /boot/grub2/grub.cfg
# 重启生效
```

---

## D2. 内核模块异常内存占用

### 诊断方法
```bash
# 计算未归因内存
python3 << 'EOF'
data = {}
with open('/proc/meminfo') as f:
    for line in f:
        k, v = line.split(':')
        data[k.strip()] = int(v.split()[0])

total = data['MemTotal']
free = data['MemFree']
accounted = (data.get('AnonPages', 0) + data.get('Cached', 0) + 
             data.get('Buffers', 0) + data.get('Slab', 0) + 
             data.get('Shmem', 0) + data.get('PageTables', 0) +
             data.get('KernelStack', 0) + data.get('VmallocUsed', 0))

unaccounted = total - free - accounted
print(f"Total:        {total//1024:8d} MB")
print(f"Accounted:    {accounted//1024:8d} MB")
print(f"Unaccounted:  {unaccounted//1024:8d} MB  {'⚠️ 异常' if unaccounted > 512*1024 else '正常'}")
EOF

# 检查非标准模块
lsmod | awk 'NR>1 {print $1}' | xargs -I{} sh -c \
    'echo -n "{}: "; modinfo {} 2>/dev/null | grep "^filename" | grep -v "/lib/modules"' 2>/dev/null

# 检查 vmalloc 使用（内核模块常用 vmalloc）
cat /proc/vmallocinfo | awk '{sum += $2} END {print "vmalloc total:", sum/1024/1024, "MB"}'
cat /proc/vmallocinfo | sort -k2 -rn | head -20
```

### 异常模块排查
```bash
# 列出所有非内核原生模块（第三方驱动、监控agent等）
lsmod | awk 'NR>1' | while read mod size used; do
    vendor=$(modinfo $mod 2>/dev/null | grep "^signer\|^author" | head -1)
    echo "$mod ($size bytes): $vendor"
done | grep -v "Linux\|kernel.org" | sort -k2 -t'(' -rn

# 逐一卸载可疑模块并观察内存变化（谨慎操作）
# rmmod <suspicious_module>
# grep MemFree /proc/meminfo
```

---

## D3. Shmem/tmpfs 异常分析

### 诊断方法
```bash
# 检查 Shmem 大小
grep Shmem /proc/meminfo

# 定位占用 tmpfs 的大文件
df -h | grep tmpfs
lsof +D /dev/shm 2>/dev/null | head -30
lsof +D /tmp 2>/dev/null | sort -k7 -rn | head -20
lsof +D /run 2>/dev/null | sort -k7 -rn | head -20

# 查找所有 tmpfs 挂载点
mount | grep tmpfs

# 找出大文件
find /dev/shm /tmp /run -type f -size +100M 2>/dev/null -ls | sort -k7 -rn | head

# 检查 POSIX 共享内存
ls -lh /dev/shm/

# 检查匿名 tmpfs（mmap(MAP_ANONYMOUS|MAP_SHARED)）
# 这类内存在 /proc/PID/maps 中体现为匿名 mmap 但计入 Shmem
for pid in $(ls /proc | grep '^[0-9]*$'); do
    shmem=$(grep -c "^[0-9a-f].* rw-s " /proc/$pid/maps 2>/dev/null || echo 0)
    if [ "$shmem" -gt 10 ] 2>/dev/null; then
        comm=$(cat /proc/$pid/comm 2>/dev/null)
        echo "PID $pid ($comm): $shmem shared mappings"
    fi
done
```

### 修复建议
- 大文件从 tmpfs 迁移到磁盘
- 检查是否有程序在 `/dev/shm` 或 `/tmp` 写入大量数据
- 调整 tmpfs 大小限制：`mount -o remount,size=1G /dev/shm`

---

## D4. Slab 内存异常分析

### D4.1 确认 Slab 异常

```bash
# 检查 slab 总量
grep -E "^Slab:|^SReclaimable:|^SUnreclaim:" /proc/meminfo

# 正常阈值：Slab < MemTotal * 10%
# 告警阈值：Slab > MemTotal * 20%

# 找出最大的 slab 对象
slabtop -o 2>/dev/null | head -30
# 或
sort -k3 -rn /proc/slabinfo | head -20
```

### D4.2 常见 slab 泄漏场景

#### 场景1：dentry cache 暴涨

**触发条件**：`find /` 全盘扫描 / 大量文件创建删除 / 容器频繁创建销毁

```bash
# 检查 dentry cache 大小
grep "^dentry" /proc/slabinfo | \
    awk '{printf "dentry cache: %d objects, %.1f MB\n", $2, $2*$4/1024/1024}'

# 检查谁在触发大量目录访问
strace -p <suspicious_pid> -e trace=getdents,openat 2>&1 | head -50

# 清理 dentry cache（会影响性能，谨慎）
echo 2 > /proc/sys/vm/drop_caches  # 清理 dentry+inode cache
```

#### 场景2：inode cache 暴涨（proc_inode_cache）

**触发条件**：大量创建进程/线程（fork 密集型应用）

```bash
# 检查 proc inode cache
grep "proc_inode_cache\|inode_cache" /proc/slabinfo | \
    awk '{printf "%-30s objects=%d, size=%d, total=%.1fMB\n", $1, $2, $4, $2*$4/1024/1024}'

# 检查进程创建速率
vmstat 1 5 | awk '{print "forks/s:", $12}'
# 或
sar -c 1 5 2>/dev/null

# 确认谁在大量 fork
perf stat -e sched:sched_process_fork -a sleep 5 2>/dev/null
```

#### 场景3：sock 相关 slab 暴涨

**触发条件**：高并发网络连接，连接未正确关闭

```bash
# 检查 socket 相关 slab
grep -E "^sock|^TCP|^UDP|^inet_peer" /proc/slabinfo | \
    awk '{if ($2 > 1000) printf "%-30s objects=%d, total=%.1fMB\n", $1, $2, $2*$4/1024/1024}'

# 统计连接状态
ss -s
netstat -s 2>/dev/null | grep -E "failed|overflow|retransmit"

# 检查 TIME_WAIT 连接
ss -ant | grep TIME-WAIT | wc -l
```

### D4.3 Slab 泄漏确认方法

```bash
# 监控 slab 变化（每5秒采样一次）
while true; do
    echo "=== $(date) ==="
    grep -E "^dentry|^inode_cache|proc_inode" /proc/slabinfo | \
        awk '{printf "%-30s %10d objects\n", $1, $2}'
    sleep 5
done

# 如果 slab 对象数量单调递增且不回落，确认为 slab 泄漏
```

---

## D5. NUMA 内存不均衡

```bash
# 检查 NUMA 节点内存
numastat -m 2>/dev/null

# 检查 NUMA 内存分配策略
numactl --show 2>/dev/null

# 检查各 NUMA 节点的可用内存
cat /proc/buddyinfo

# 内存不均衡可能导致某个 NUMA 节点 OOM 但整体内存充足
dmesg | grep -E "NUMA|node [0-9].*out of memory"
```

---

## 内核态 OOM 分析检查清单

```
D1 kdump预留：
□ MemTotal 是否显著小于物理内存？
□ crashkernel 参数是否合理？

D2 内核模块：
□ 未归因内存是否 > 500MB？
□ 是否有非标准第三方内核模块？
□ vmalloc 使用是否异常？

D3 Shmem：
□ Shmem 是否 > MemTotal 的 10%？
□ tmpfs 挂载点是否有异常大文件？
□ 是否有进程使用大量 MAP_SHARED 匿名映射？

D4 Slab：
□ Slab 是否 > MemTotal 的 15%？
□ 哪个 slab 对象占用最多？
□ slab 对象数量是否单调递增？
□ 是否有 find/fork 密集操作？
```
