# Linux Swap 相关命令速查手册

## 基础信息采集

| 命令 | 用途 | 示例 |
|------|------|------|
| `free -h` | 内存与 swap 总量/已用/可用 | `free -h` |
| `swapon --show` | 显示 swap 设备/文件列表及优先级 | `swapon --show` |
| `swapon -s` | 旧式 swap 设备显示 | `swapon -s` |
| `cat /proc/swaps` | swap 设备/文件详情（优先级、类型） | `cat /proc/swaps` |
| `cat /proc/meminfo` | 完整内存与 swap 统计（含 page tables、slab、dirty 等） | `cat /proc/meminfo` |
| `cat /proc/vmstat` | 虚拟内存内核统计（pgscan/pgsteal/allocstall/oom 等） | `cat /proc/vmstat` |
| `cat /proc/zoneinfo` | NUMA 节点/zone 水位线详情 | `cat /proc/zoneinfo` |
| `cat /proc/buddyinfo` | 伙伴系统空闲页块信息（碎片化检测） | `cat /proc/buddyinfo` |
| `lsmod \| grep zswap` | 检查 zswap 模块是否加载 | `lsmod \| grep zswap` |
| `lsmod \| grep zram` | 检查 zram 模块是否加载 | `lsmod \| grep zram` |

## Swap 活动实时监控

| 命令 | 用途 | 示例 |
|------|------|------|
| `sar -S 1 5` | swap 活动统计（si/so）每 1 秒 5 次 | `sar -S 1 5` |
| `sar -W 1 5` | swap si/so 汇总速率（KB/s） | `sar -W 1 5` |
| `sar -B 1 5` | 页统计（pgpgin/pgpgout/fault/si/so） | `sar -B 1 5` |
| `sar -r 1 5` | 内存与 swap 使用率 | `sar -r 1 5` |
| `sar -q 1 5` | 运行队列、系统负载 | `sar -q 1 5` |
| `vmstat 1 10` | 完整虚拟内存统计（procs/memory/swap/io/system/cpu） | `vmstat 1 10` |
| `vmstat -s` | 从启动至今的虚拟内存统计汇总 | `vmstat -s` |
| `vmstat -m` | slab 分配器统计 | `vmstat -m` |
| `atop -a 1 5` | 进程级内存+swap 占用实时视图 | `atop -a 1 5` |
| `dstat --swap --mem --io 1 10` | swap/mem/io 联合监控 | `dstat --swap --mem --io 1 10` |

## 进程级 Swap 占用分析

| 命令 | 用途 | 示例 |
|------|------|------|
| `cat /proc/<PID>/status \| grep -E "VmSwap\|VmRSS\|VmSize"` | 进程的 swap 占用 | `for p in /proc/[0-9]*/status; do awk '/VmSwap/{s+=$2} END{print s}' "$p" 2>/dev/null; done` |
| `ps aux --sort=-%mem \| head -20` | 按内存占用排序进程 | `ps aux --sort=-%mem \| head -20` |
| `top -o %MEM` | 交互式内存排序 | `top -o %MEM` |
| `htop -s PERCENT_MEM` | htop 内存排序 | `htop -s PERCENT_MEM` |
| `smem -t -k` | 更准确的进程内存占用（PSS/USS） | `smem -t -k` |
| `for f in /proc/*/status; do awk '/^Pid/{pid=$2}/^Name/{name=$2}/^VmSwap/{print pid,name,$2}' $f 2>/dev/null; done` | 所有进程 swap 占用列表 | `for f in /proc/*/status; do awk '/^Pid/{pid=$2}/^Name/{name=$2}/^VmSwap/{print pid,name,$2}' $f 2>/dev/null; done` |

## 内核行为诊断

| 命令 | 用途 | 示例 |
|------|------|------|
| `dmesg \| grep -E "swap\|oom\|Out of memory\|killed" \| tail -50` | 内核 swap/OOM 相关日志 | `dmesg \| grep -E "swap\|oom\|Out of memory\|killed" \| tail -50` |
| `dmesg \| grep -E "allocation\|page fault\|kswapd\|direct reclaim" \| tail -30` | 内核内存分配延迟日志 | `dmesg \| grep -E "allocation\|page fault\|kswapd\|direct reclaim" \| tail -30` |
| `perf top -k 1` | 内核热点函数实时分析 | `perf top -k 1` |
| `perf stat -e page-faults,minor-faults,major-faults -a -- sleep 10` | 缺页统计（大/小缺页） | `perf stat -e page-faults,minor-faults,major-faults -a -- sleep 10` |
| `perf record -e vmscan:mm_vmscan_kswapd_wake -a -- sleep 30` | kswapd 唤醒追踪 | `perf record -e vmscan:mm_vmscan_kswapd_wake -a -- sleep 30` |
| `perf record -e vmscan:mm_vmscan_direct_reclaim_begin -a -- sleep 30` | direct reclaim 追踪 | `perf record -e vmscan:mm_vmscan_direct_reclaim_begin -a -- sleep 30` |
| `perf record -e syscalls:sys_enter_mmap,syscalls:sys_enter_mprotect -a -- sleep 30` | 内存映射系统调用追踪 | `perf record -e syscalls:sys_enter_mmap,syscalls:sys_enter_mprotect -a -- sleep 30` |

## zswap/zram 专用命令

| 命令 | 用途 | 示例 |
|------|------|------|
| `cat /sys/kernel/debug/zswap/*` | zswap 调试统计（压缩比、reject 原因等） | `cat /sys/kernel/debug/zswap/*` |
| `cat /sys/module/zswap/parameters/*` | zswap 内核参数 | `cat /sys/module/zswap/parameters/*` |
| `zramctl` | zram 设备详情 | `zramctl` |
| `cat /sys/block/zram0/mm_stat` | zram 内存统计（orig_size/compr_size/mem_used） | `cat /sys/block/zram0/mm_stat` |
| `cat /sys/block/zram0/io_stat` | zram I/O 统计 | `cat /sys/block/zram0/io_stat` |
| `cat /sys/block/zram0/comp_algorithm` | zram 压缩算法 | `cat /sys/block/zram0/comp_algorithm` |
| `cat /sys/block/zram0/backing_dev` | zram 后备设备（如果有） | `cat /sys/block/zram0/backing_dev` |

## Swap 设备 I/O 监控

| 命令 | 用途 | 示例 |
|------|------|------|
| `iostat -x 1 5 \| grep -E "Device\|sd[a-z]\|nvme"` | 设备级 I/O 统计（含 await/svctm） | `iostat -x 1 5 \| grep -E "Device\|sd[a-z]\|nvme"` |
| `iotop -oP` | 进程级 I/O 实时排序 | `iotop -oP` |
| `biosnoop` | 块设备 I/O 延迟（需要 bcc 工具集） | `biosnoop` |
| `cat /sys/block/sdX/stat` | 设备块设备统计（I/O 合并、等待、延迟） | `cat /sys/block/sda/stat` |

## Swap 配置操作

| 命令 | 用途 | 示例 |
|------|------|------|
| `sysctl vm.swappiness` | 查看当前 swappiness | `sysctl vm.swappiness` |
| `sysctl vm.swappiness=10` | 临时设置 swappiness | `sysctl -w vm.swappiness=10` |
| `sysctl vm.vfs_cache_pressure` | 查看 dentry/inode cache 回收倾向 | `sysctl vm.vfs_cache_pressure` |
| `sysctl vm.min_free_kbytes` | 查看最小空闲内存阈值 | `sysctl vm.min_free_kbytes` |
| `sysctl vm.watermark_scale_factor` | 查看水位线缩放因子 | `sysctl vm.watermark_scale_factor` |
| `sysctl vm.overcommit_memory` | 查看内存 overcommit 策略 | `sysctl vm.overcommit_memory` |
| `sysctl vm.overcommit_ratio` | 查看 overcommit 比例 | `sysctl vm.overcommit_ratio` |
| `sysctl vm.dirty_ratio` | 查看脏页比例 | `sysctl vm.dirty_ratio` |
| `sysctl vm.dirty_background_ratio` | 查看脏页后台回写阈值 | `sysctl vm.dirty_background_ratio` |
| `cat /proc/sys/vm/zone_reclaim_mode` | 查看 NUMA zone reclaim 模式 | `cat /proc/sys/vm/zone_reclaim_mode` |

## cgroup 内存控制

| 命令 | 用途 | 示例 |
|------|------|------|
| `cat /sys/fs/cgroup/memory/memory.usage_in_bytes` | cgroup 内存使用 | `cat /sys/fs/cgroup/memory/memory.usage_in_bytes` |
| `cat /sys/fs/cgroup/memory/memory.limit_in_bytes` | cgroup 内存限制 | `cat /sys/fs/cgroup/memory/memory.limit_in_bytes` |
| `cat /sys/fs/cgroup/memory/memory.memsw.usage_in_bytes` | cgroup 内存+swap 使用 | `cat /sys/fs/cgroup/memory/memory.memsw.usage_in_bytes` |
| `cat /sys/fs/cgroup/memory/memory.memsw.limit_in_bytes` | cgroup 内存+swap 限制 | `cat /sys/fs/cgroup/memory/memory.memsw.limit_in_bytes` |
| `cat /sys/fs/cgroup/memory/memory.stat` | cgroup 内存详细统计（rss/cache/swap/pgmajfault） | `cat /sys/fs/cgroup/memory/memory.stat` |
| `cat /sys/fs/cgroup/memory/memory.pressure_level` | cgroup 内存压力等级 | `cat /sys/fs/cgroup/memory/memory.pressure_level` |
| `cat /proc/pressure/memory` | PSI（Pressure Stall Information）内存压力 | `cat /proc/pressure/memory` |
| `cat /proc/pressure/io` | PSI IO 压力 | `cat /proc/pressure/io` |

## OOM 调试

| 命令 | 用途 | 示例 |
|------|------|------|
| `cat /proc/<PID>/oom_score` | 进程 OOM 分数 | `cat /proc/1123/oom_score` |
| `cat /proc/<PID>/oom_score_adj` | 进程 OOM 分数调整 | `cat /proc/1123/oom_score_adj` |
| `cat /proc/<PID>/oom_adj` | 旧式 OOM 调整 | `cat /proc/1123/oom_adj` |
| `dmesg \| grep -B5 "Out of memory"` | OOM 击杀前日志上下文 | `dmesg \| grep -B5 "Out of memory"` |

## 历史数据采集（sar 日志）

| 命令 | 用途 | 示例 |
|------|------|------|
| `sar -S -f /var/log/sa/saXX` | 历史 swap 活动 | `sar -S -f /var/log/sa/sa12` |
| `sar -r -f /var/log/sa/saXX` | 历史内存使用率 | `sar -r -f /var/log/sa/sa12` |
| `sar -B -f /var/log/sa/saXX` | 历史分页活动 | `sar -B -f /var/log/sa/sa12` |
| `sa1` | 手动触发 sar 数据采集 | `sa1 10 60`（每 10 秒 60 次） |

## eBPF 高级诊断（bcc/bpftrace）

| 命令 | 用途 | 示例 |
|------|------|------|
| `trace 'vmscan:kswapd_wake'` | 追踪 kswapd 唤醒事件 | `trace 'vmscan:kswapd_wake'` |
| `trace 'vmscan:mm_vmscan_kswapd_wake'` | kswapd 唤醒详情 | `trace 'vmscan:mm_vmscan_kswapd_wake'` |
| `argdist -H 't:vmscan:mm_vmscan_kswapd_scan:nr_scanned'` | kswapd 每次唤醒扫描页数直方图 | `argdist -H 't:vmscan:mm_vmscan_kswapd_scan:nr_scanned'` |
| `bpftrace -e 'kprobe:kswapd { @[comm] = count(); }'` | 追踪 kswapd 运行频次 | `bpftrace -e 'kprobe:kswapd { @[comm] = count(); }'` |
| `oomkill` | 追踪 OOM killer 事件 | `oomkill` |
| `swapin` | 追踪 swap in 事件（进程级） | `swapin` |
| `memleak` | 检测内核/用户态内存泄漏 | `memleak -p <PID>` |

## 典型分析模式

### 快速确认 swap 状态
```
free -h
swapon --show
cat /proc/meminfo | grep -E "Swap|Dirty|Writeback"
vmstat 1 5
```

### 定位 kswapd 高 CPU
```
perf top -k 1
pidstat -p $(pgrep -u0 kswapd) 1 10
cat /proc/vmstat | grep -E "pgscan|pgsteal|allocstall"
```

### 检测 thrashing
```
vmstat 1 10                          # 关注 si/so 列
sar -W 1 10                          # swap in/out 速率
sar -B 1 10                          # 缺页和 swap 统计
cat /proc/vmstat | grep -E "pswp"

# 如果 si/so > 1000 pages/s 持续多个周期，极可能 thrashing
```

### 分析谁在换页
```
# 找出 swap 占用 TOP 进程
for f in /proc/[0-9]*/status; do
  awk '/^VmSwap|^Name|^Pid/{printf "%s ", $2} END{print ""}' "$f" 2>/dev/null
done | sort -k3 -rn | head -20

# 分析进程系统调用热点
perf top -p <PID>
```
