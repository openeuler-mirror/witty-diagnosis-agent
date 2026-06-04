# 内存泄漏诊断命令与工具参考

## 1. 用户态诊断命令

| 命令 | 用途 | 示例 |
|------|------|------|
| `top` / `htop` | 实时查看进程内存占用 | `top -p <pid>` |
| `ps aux --sort=-%mem` | 按内存占用排序进程 | `ps aux --sort=-%mem \| head -20` |
| `pmap -x <pid>` | 查看进程内存映射详情 | `pmap -x <pid>` |
| `cat /proc/<pid>/status` | 查看进程 VmRSS/VmPeak/VmSize | `grep Vm /proc/<pid>/status` |
| `cat /proc/<pid>/smaps` | 查看进程详细内存区域统计 | `cat /proc/<pid>/smaps` |
| `cat /proc/<pid>/smaps_rollup` | smaps 汇总（Linux 4.14+） | `cat /proc/<pid>/smaps_rollup` |
| `grep Anon /proc/<pid>/smaps` | 查看匿名页变化 | `grep Anon /proc/<pid>/smaps \| awk '{sum+=$2} END{print sum " kB"}'` |
| `valgrind --tool=memcheck` | 内存泄漏检测 | `valgrind --tool=memcheck --leak-check=full ./program` |
| `valgrind --tool=massif` | 堆内存分析 | `valgrind --tool=massif --massif-out-file=massif.out ./program` |
| `ms_print massif.out` | 可视化 massif 输出 | `ms_print massif.out \| head -50` |
| `gperftools` heap profiler | 堆内存 profiling | `CPUPROFILE=heap.prof HEAPPROFILE=heap ./program` |
| `pprof` | 分析 heap profile | `pprof --text ./program heap.prof` |
| `lsof -p <pid>` | 查看进程打开的文件描述符 | `lsof -p <pid> \| wc -l` |
| `strace -e trace=mmap,brk <pid>` | 追踪内存分配 syscall | `strace -p <pid> -e trace=mmap,brk -o /tmp/mmap.log` |

## 2. 内核态诊断命令

| 命令 | 用途 | 示例 |
|------|------|------|
| `slabtop` | 实时查看 slab 缓存使用 | `slabtop -o` |
| `cat /proc/slabinfo` | 查看 slab 分配器状态 | `cat /proc/slabinfo \| head -20` |
| `cat /proc/meminfo` | 查看系统内存整体使用 | `grep -E "Slab|SUnreclaim|Vmalloc|PageTables" /proc/meminfo` |
| `cat /proc/vmallocinfo` | 查看 vmalloc 分配情况 | `cat /proc/vmallocinfo \| head -30` |
| `kmemleak` | 内核内存泄漏检测 | `echo scan > /sys/kernel/debug/kmemleak; cat /sys/kernel/debug/kmemleak` |
| `cat /proc/meminfo \| grep Vmalloc` | 查看 vmalloc 使用 | `grep Vmalloc /proc/meminfo` |
| `cat /proc/zoneinfo` | 查看内存区详情 | `cat /proc/zoneinfo \| grep -E "Node|min|low|high"` |
| `cat /proc/pagetypeinfo` | 查看页类型分布 | `cat /proc/pagetypeinfo \| head -20` |
| `echo m > /proc/sysrq-trigger` | 导出内存分配信息 | `echo m > /proc/sysrq-trigger`（需 root） |

## 3. Memcg 诊断命令

| 命令 | 用途 | 示例 |
|------|------|------|
| `cat /sys/fs/cgroup/memory/memory.usage_in_bytes` | 查看 cgroup 内存使用 | `cat /sys/fs/cgroup/<group>/memory.usage_in_bytes` |
| `cat /sys/fs/cgroup/memory/memory.stat` | 查看 cgroup 内存统计 | `cat /sys/fs/cgroup/<group>/memory.stat \| head -20` |
| `cat /sys/fs/cgroup/memory/memory.kmem.usage_in_bytes` | 查看内核内存使用 | `cat /sys/fs/cgroup/<group>/memory.kmem.usage_in_bytes` |

## 4. 其他诊断工具

| 工具 | 用途 | 示例 |
|------|------|------|
| `perf mem` | 内存访问 profiling | `perf mem record -a sleep 10` |
| `numactl --hardware` | 查看 NUMA 内存配置 | `numactl --hardware` |
| `free -h` | 系统内存总览 | `free -h` |
| `sar -r` | 历史内存使用趋势 | `sar -r -f /var/log/sa/saNN` |
| `bcc/funccount` | 追踪内存分配函数 | `funccount 'c:kmalloc*' -d 10` |
