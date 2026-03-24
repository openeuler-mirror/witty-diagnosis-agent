# 系统级 OOM 分析参考手册

## 适用场景
- 整机 OOM（系统变慢、无响应、大量进程被杀死）
- OOM killer 主动触发
- 系统可用内存持续下降到 0

---

## A1. 快速确认 OOM 事件

### 从日志确认 OOM killer 触发
```bash
# 有故障时间点时（优先使用）
journalctl -k --since="FAULT_TIME -30min" --until="FAULT_TIME +10min" \
    | grep -E "Out of memory|oom_kill"

# 无时间点时
dmesg -T | grep -E "Out of memory|oom_kill" | tail -20
grep "Out of memory" /var/log/messages | tail -20
```

### OOM kill 事件完整信息解析
```
[  234.567890] Out of memory: Kill process 12345 (java) score 856 or sacrifice child
[  234.567891] Killed process 12345 (java) total-vm:4194304kB, anon-rss:3145728kB, file-rss:65536kB, shmem-rss:0kB
```

**字段解析**：
| 字段 | 含义 | 诊断意义 |
|------|------|----------|
| `score` | OOM 分数（0-1000）| 分数高 = 更可能被杀 |
| `total-vm` | 虚拟内存大小 | 反映进程申请上限 |
| `anon-rss` | 匿名页驻留内存 | 主要内存消耗（堆/栈） |
| `file-rss` | 文件映射驻留内存 | mmap 文件 |
| `shmem-rss` | 共享内存驻留 | 共享内存使用 |

---

## A2. 分析系统内存分布

### 确认内存去向
```bash
# 执行并分析输出
cat /proc/meminfo

# 关键诊断公式
# 用户态内存 = AnonPages + Cached + Buffers + Shmem
# 内核态内存 = Slab + PageTables + KernelStack + VmallocUsed
# 未归因内存 = MemTotal - MemFree - 用户态 - 内核态  (>500MB 需警惕)
```

### meminfo 异常判断规则

| 条件 | 可能场景 |
|------|----------|
| `AnonPages` 持续增大 | 用户态进程内存泄漏 |
| `Slab` > MemTotal 的 20% | slab 内存泄漏（dentry/inode/proc） |
| `Shmem` > MemTotal 的 10% | tmpfs 大文件或内存泄漏 |
| `MemTotal << 物理内存` | kdump/crashkernel 预留过大 |
| `MemTotal - MemFree >> AnonPages + Cached + Slab` | 内核模块内存泄漏 |

---

## A3. 用户态内存泄漏分析

### 3.1 定位泄漏进程

```bash
# 按内存使用排序
ps aux --sort=-%mem | head -20

# 查看进程内存增长历史（如果有监控）
# 如果有 atop 历史记录
atop -r /var/log/atop/atop_YYYYMMDD -b FAULT_TIME -i 5 2>/dev/null | grep "MEM\|PRC"

# 检查进程 maps（了解内存分布）
PID=<目标PID>
cat /proc/$PID/smaps_rollup
```

### 3.2 判断是否为内存泄漏

**内存泄漏特征**：
- RSS/RES 单调递增，不随负载降低而下降
- Heap 段持续增大（smaps 中 `[heap]` 段的 Rss 一直增大）
- `/proc/PID/status` 中 `VmRSS` 线性增长

**正常内存增长特征**：
- 内存使用随负载变化（高峰后会回落）
- 有明显的业务触发原因（数据量增大/并发增加）

### 3.3 内存泄漏进一步确认

```bash
# 检查进程 fd 泄漏（fd 泄漏可能导致内存泄漏）
ls /proc/$PID/fd | wc -l
cat /proc/sys/fs/file-nr

# 检查 mmap 匿名段数量（大量碎片化 mmap 是泄漏信号）
grep -c "^[0-9a-f]" /proc/$PID/maps

# 对比 heap 大小 vs 实际 RSS（差距大说明内存碎片化）
grep "\[heap\]" /proc/$PID/maps
```

---

## A4. OOM Score 分析

OOM killer 选择被杀进程的逻辑：

```
oom_score = (进程实际内存占用/总内存) * 1000
           + oom_score_adj 调整值
           - CAP_SYS_ADMIN 特权加分
```

### 调整 OOM 优先级
```bash
# 保护关键进程（-1000 = 永不被杀）
echo -1000 > /proc/<PID>/oom_score_adj

# 让某进程优先被杀（适用于后台任务）
echo 500 > /proc/<PID>/oom_score_adj
```

---

## A5. 内存回收失败分析

```bash
# 检查 kswapd 活跃度
vmstat 1 10 | awk '{print $7,$8,$9,$10}'   # si,so,bi,bo

# 高 si/so（swap in/out）= 内存压力大
# 高 bi（block in）= 从磁盘读取（page cache 失效）

# 检查内存分配失败
dmesg | grep -E "page allocation failure|__alloc_pages_nodemask"

# 检查内存规整
cat /proc/vmstat | grep compact
```

---

## A6. 系统级 OOM 分析检查清单

```
诊断阶段：
□ 确认 OOM killer 触发时间（与故障时间点对比）
□ 确认被杀进程及其 OOM score
□ 分析 OOM 前 /proc/meminfo 状态（如有历史监控）
□ 确认内存主要去向（anon/cache/slab/shmem）
□ 检查 SWAP 使用情况和配置
□ 检查 vm.overcommit_memory 配置

根因判断：
□ 是否有单个进程异常占用大量内存？
□ Slab/Shmem 是否异常高？
□ 是否有内核态内存泄漏迹象？
□ 内存使用是否与业务量相关？

修复方向：
□ 临时：释放 page cache（echo 3 > /proc/sys/vm/drop_caches）
□ 临时：增加 SWAP
□ 永久：修复内存泄漏 / 优化内存使用 / 增加物理内存
□ 预防：配置内存监控告警、配置 cgroup 限制
```
