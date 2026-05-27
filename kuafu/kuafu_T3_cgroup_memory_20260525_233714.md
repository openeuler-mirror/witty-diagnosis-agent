# T3: 容器 cgroup memory 限制竞争风险诊断

**诊断时间**: 2026-05-25 23:37:14 UTC
**目标容器**: pcr-pc (ID: 72f623c16761)
**诊断类型**: 只读 (read-only)
**内核**: 6.6.87.2-microsoft-standard-WSL2

---

## 1. cgroup 内存基本信息

### 1.1 cgroup 版本与控制器

```
cgroup v2 已启用
控制器: cpuset cpu io memory hugetlb pids rdma
```

### 1.2 内存限制配置

| 配置项 | 值 | 状态 |
|--------|-----|------|
| `memory.max` | `max` | ❌ 无限制 |
| `memory.swap.max` | `max` | ❌ 无限制 |
| `HostConfig.Memory` | `0` | ❌ 未设置 |
| `HostConfig.MemorySwap` | `0` | ❌ 未设置 |
| `HostConfig.MemoryReservation` | `0` | ❌ 未设置 |
| `HostConfig.MemorySwappiness` | `null` | ❌ 未设置 |
| `HostConfig.OomKillDisable` | `null` | ❌ 未设置 |
| `CgroupParent` | 空字符串 | 使用默认 cgroup |
| `CgroupnsMode` | `private` | 私有 cgroup 命名空间 |

**关键结论：容器 pcr-pc 未设置任何 cgroup 内存限制，可使用宿主机全部可用内存。**

---

## 2. 当前内存使用详情

### 2.1 cgroup memory.stat 完整数据

| 指标 | 值 (bytes) | 值 (可读) | 占比 |
|------|-----------|----------|------|
| **memory.current** | 6,072,467,456 | **~5.66 GB** | 100% |
| ├─ file (Page Cache) | 5,905,629,184 | **~5.50 GB** | **97.3%** |
| ├─ anon (匿名内存) | 192,512 | ~188 KB | 0.0% |
| ├─ kernel_stack | 16,384 | ~16 KB | 0.0% |
| ├─ pagetables | 73,728 | ~72 KB | 0.0% |
| ├─ slab_reclaimable | 197,646,880 | ~188.5 MB | 3.3% |
| ├─ slab_unreclaimable | 303,512 | ~296 KB | 0.0% |
| ├─ percpu | 6,048 | ~6 KB | 0.0% |
| └─ sock | 0 | 0 | 0.0% |

### 2.2 Page Cache 详细分布

| 指标 | 值 (bytes) |
|------|-----------|
| file (总) | 5,905,629,184 |
| ├─ inactive_file | 5,893,242,880 |
| ├─ active_file | 12,386,304 |
| ├─ file_mapped | 32,768 |
| ├─ file_dirty | 0 |
| └─ file_writeback | 0 |

### 2.3 Docker stats 对比

```
CONTAINER   NAME     CPU %   MEM USAGE / LIMIT     MEM %
72f623c167  pcr-pc   0.00%   171.7MiB / 15.25GiB   1.10%
```

> ⚠️ **注意**: `docker stats` 显示的 171.7 MiB 仅为 RSS (实际驻留的匿名页+文件映射页)，**不包含 Page Cache 和 Slab**。cgroup memory.current 显示真实内存占用为 **5.66 GB**，差异达 **5.49 GB**。

### 2.4 容器内 /proc/meminfo

| 指标 | 值 |
|------|-----|
| MemTotal | 15,986,876 kB (~15.25 GB) |
| MemFree | 9,187,696 kB (~8.76 GB) |
| MemAvailable | 15,070,208 kB (~14.37 GB) |
| Cached | 5,910,268 kB (~5.63 GB) |
| Buffers | 11,676 kB |
| SwapTotal | 4,194,304 kB (~4 GB) |
| SwapFree | 3,987,072 kB (~3.80 GB) |

---

## 3. cgroup OOM 事件历史

### 3.1 memory.events (cgroup 级)

```
low     : 0
high    : 0
max     : 0
oom     : 0
oom_kill: 0
oom_group_kill: 0
```

**cgroup 级 OOM 事件：全部为 0，容器从未触发过 cgroup OOM。**

### 3.2 宿主机 OOM 事件 (dmesg)

内核日志中发现 **2 次宿主机级 OOM 事件**，均与 `fault_reclaim_s` 进程相关：

```
[26548.860641] fault_reclaim_s invoked oom-killer:
    gfp_mask=0x140cca(GFP_HIGHUSER_MOVABLE|__GFP_COMP), order=0

[26548.864769] Out of memory: Killed process 20893 (fault_reclaim_s)
    total-vm:    6,556,265,176 kB  (~6.25 TB virtual)
    anon-rss:    8,798,976 kB      (~8.39 GB resident)
    file-rss:    384 kB
    pgtables:    6,427,712 kB      (~6.13 GB 页表开销!)
    oom_score_adj: 0

---

[26855.291583] fault_reclaim_s invoked oom-killer:
    gfp_mask=0x140dca(GFP_HIGHUSER_MOVABLE|__GFP_COMP|__GFP_ZERO), order=0

[26855.292605] Out of memory: Killed process 21383 (fault_reclaim_s)
    total-vm:    6,538,320,600 kB  (~6.24 TB virtual)
    anon-rss:    8,799,872 kB      (~8.39 GB resident)
    pgtables:    6,410,112 kB      (~6.11 GB 页表开销!)
```

> 🔴 **严重发现**: `fault_reclaim_s` 进程两次触发宿主机 OOM。其虚拟地址空间达 **~6.25 TB**，匿名内存占用 **~8.4 GB**，页表开销高达 **~6.1 GB**。两次 OOM 间隔约 306 秒（5 分钟），暗示该进程可能反复重启并再次触发 OOM。

---

## 4. 内存压力与回收指标

### 4.1 memory.pressure

```
some avg10=0.00 avg60=0.00 avg300=0.00 total=0
full avg10=0.00 avg60=0.00 avg300=0.00 total=0
```

**当前无内存压力。**

### 4.2 页面回收指标

| 指标 | 值 | 含义 |
|------|-----|------|
| pgscan | 0 | 无页面扫描发生 |
| pgsteal | 0 | 无页面回收发生 |
| pgscan_kswapd | 0 | kswapd 未触发 |
| pgscan_direct | 0 | 直接回收未触发 |
| pgmajfault | 50 | 少量主缺页 |
| pgfault | 81,865 | 正常次缺页 |

> ℹ️ Page Cache 虽然占用很高 (~5.5 GB)，但目前无需回收，因为宿主机仍有充足可用内存 (~8.76 GB free, ~14.37 GB available)。

---

## 5. Swap 使用情况

### 5.1 cgroup swap 统计

| 指标 | 值 |
|------|-----|
| memory.swap.max | `max` (无限制) |
| memory.swap.current | 0 B |
| swapcached | 0 |

### 5.2 容器内 swap 统计

| 指标 | 值 |
|------|-----|
| SwapTotal | 4,194,304 kB (~4 GB) |
| SwapFree | 3,987,072 kB (~3.80 GB) |
| SwapCached | 12,468 kB |

**容器当前无 swap 使用，swap 可用空间充裕。**

---

## 6. NUMA 分布

所有内存分配在 NUMA Node 0 上（WSL2 单 NUMA 节点环境）。

---

## 7. 综合风险评估

### 7.1 风险矩阵

| 风险维度 | 评分 | 说明 |
|----------|------|------|
| **内存限制缺失** | 🔴 高 | 容器无任何 cgroup 内存限制，可耗尽宿主机全部内存 |
| **Page Cache 占比** | 🟡 中 | 97.3% 为 Page Cache，属高水位但可回收 |
| **宿主机 OOM 历史** | 🔴 高 | `fault_reclaim_s` 已两次被宿主机 OOM killer 杀死 |
| **当前 OOM 紧迫度** | 🟢 低 | 无 cgroup OOM 事件，mem.pressure=0，宿主机有充足可用内存 |
| **Swap 风险** | 🟢 低 | 无 swap 使用 |
| **Slab 风险** | 🟢 低 | slab=188 MB，可回收 slab=188 MB，占比和绝对值正常 |
| **页表开销风险** | 🟡 中 | 当前容器页表 ~72 KB 正常，但 `fault_reclaim_s` 的 6.1 GB 页表异常 |

### 7.2 综合风险等级: 🟡 P2 (中等风险)

### 7.3 详细分析

1. **直接风险**: 容器未设置 cgroup memory 限制，无任何内存隔离保护。如果容器内进程（如 `fault_reclaim_s`）突发大内存分配，将直接耗尽宿主机/WSL2 VM 内存，触发 oom-killer。

2. **Page Cache 风险**: 当前 5.5 GB Page Cache 全部为 inactive_file，处于可回收状态。在宿主机内存充足的情况下不构成直接威胁。但如果其他内存压力上升，Page Cache 会自动回收。**当前无需干预**。

3. **fault_reclaim_s OOM 风险**: 该进程 2 次触发宿主机 OOM 的核心原因:
   - 虚拟地址空间巨大 (~6.25 TB)，可能使用了大量 mmap 映射
   - 匿名内存 ~8.4 GB 
   - 页表开销 ~6.1 GB 异常高（正常为 RSS 的 ~0.1%）
   - 两次 OOM 间隔 ~5 分钟，会被自动重新拉起并再次 OOM

4. **docker stats 误导性**: `docker stats` 显示 MEM USAGE=171.7 MiB，但实际 cgroup 占用 ~5.66 GB，差值主要来自被 docker stats 排除的 page cache 和 slab。监控时需注意此差异。

---

## 8. 建议措施

| 优先级 | 措施 | 说明 |
|--------|------|------|
| **P0** | 为容器设置 cgroup 内存限制 | `docker update --memory=<limit> pcr-pc`，建议根据业务需求设置合理值 |
| **P0** | 排查 `fault_reclaim_s` 进程异常 | 分析为何虚拟内存达 6.25 TB，页表开销 6.1 GB，存在严重内存映射异常 |
| **P1** | 设置 OOM Kill 策略 | 考虑 `--oom-kill-disable=false`（默认）确保容器 OOM 时被终止而非挂死 |
| **P2** | 监控 Page Cache 趋势 | 若 Page Cache 持续增长至逼近 MemTotal，需关注 memory reclaim 延迟 |
| **P2** | 考虑设置 Memory Reservation | 使用 `--memory-reservation` 设置软限制，在宿主机内存紧张时触发回收 |
| **P3** | 升级监控方案 | 使用 cgroup memory.current 替代 docker stats 获取真实内存占用 |

---

## 9. 原始数据附录

### 9.1 采集命令记录

```bash
# cgroup 信息
docker exec pcr-pc cat /sys/fs/cgroup/memory.max
docker exec pcr-pc cat /sys/fs/cgroup/memory.current
docker exec pcr-pc cat /sys/fs/cgroup/memory.stat
docker exec pcr-pc cat /sys/fs/cgroup/memory.events
docker exec pcr-pc cat /sys/fs/cgroup/memory.pressure
docker exec pcr-pc cat /sys/fs/cgroup/memory.swap.max
docker exec pcr-pc cat /sys/fs/cgroup/memory.swap.current
docker exec pcr-pc cat /sys/fs/cgroup/memory.numa_stat
docker exec pcr-pc cat /sys/fs/cgroup/cgroup.controllers
docker exec pcr-pc cat /proc/meminfo

# Docker 配置
docker stats pcr-pc --no-stream
docker inspect pcr-pc --format='{{json .HostConfig.Memory}}'
docker inspect pcr-pc --format='{{json .HostConfig.MemorySwap}}'

# 内核日志
docker exec pcr-pc sh -c "dmesg --level=err,warn 2>/dev/null | grep -i 'oom\|memory'"
```

### 9.2 宿主环境信息

- **平台**: WSL2 (Windows Subsystem for Linux 2)
- **内核**: 6.6.87.2-microsoft-standard-WSL2
- **CPU 架构**: x86_64
- **NUMA 节点**: 1 (Node 0)
- **容器可见总内存**: 15.25 GB (WSL2 VM 分配)

---

*报告由 witty-diagnosis-agent 自动生成 | 诊断任务: T3 | 时间戳: 2026-05-25 23:37:14 UTC*
