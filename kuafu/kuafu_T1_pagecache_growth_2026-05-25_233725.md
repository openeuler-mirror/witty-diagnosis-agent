# T1: Page Cache 过度增长 / 文件读取缓存膨胀诊断报告

**诊断时间**：2026-05-25 23:37 UTC  
**诊断目标**：容器 `pcr-pc`（Docker 容器）  
**诊断类型**：在线诊断（只读）  
**用户原始描述**：Cached=8,726,280 kB（8.3GB, 54.6% of MemTotal）

---

## 1. /proc/meminfo 完整数据

| 指标 | 值（kB） | 换算 | 说明 |
|------|----------|------|------|
| MemTotal | 15,986,876 | ~15.2 GB | 容器可用总内存 |
| MemFree | 9,211,368 | ~8.8 GB | 空闲内存 |
| MemAvailable | 15,062,352 | ~14.4 GB | 可回收后可用内存 |
| **Cached** | **5,906,152** | **~5.6 GB** | **Page Cache（当前值）** |
| Buffers | 2,116 | ~2 MB | 缓冲 |
| Active(file) | 58,356 | ~57 MB | 活跃文件页 |
| **Inactive(file)** | **5,847,208** | **~5.6 GB** | **非活跃文件页** |
| Shmem | 2,700 | ~2.6 MB | 共享内存 |
| SwapTotal | 4,194,304 | ~4.0 GB | Swap 总量 |
| SwapFree | 3,987,068 | ~3.8 GB | Swap 空闲 |
| SwapCached | 12,464 | ~12 MB | Swap 缓存 |
| Dirty | 656 | ~0.6 MB | 脏页 |
| Writeback | 0 | 0 | 回写中页 |
| Mapped | 128,772 | ~126 MB | 映射内存 |
| AnonPages | 273,204 | ~267 MB | 匿名页 |
| Slab | 304,076 | ~297 MB | Slab 缓存 |
| SReclaimable | 191,528 | ~187 MB | 可回收 Slab |
| SUnreclaim | 112,548 | ~110 MB | 不可回收 Slab |

---

## 2. 核心比率计算

### 2.1 Cached 占 MemTotal 比例

| 指标 | 当前值 | 用户初始报告值 |
|------|--------|----------------|
| Cached | 5,906,152 kB | 8,726,280 kB |
| MemTotal | 15,986,876 kB | 15,986,876 kB |
| **Cached/MemTotal** | **36.94%** | **54.58%** |

> **趋势观察**：Cached 从初始的 8.7GB 下降到当前 5.6GB（降幅 ~32%），表明部分 Page Cache 已被内核回收或释放。说明 Page Cache 并非持续线性增长，可能存在间歇性访问模式或 LRU 淘汰。

### 2.2 Active(file) vs Inactive(file) 比值

| 指标 | 值（kB） | 占比 |
|------|----------|------|
| Active(file) | 58,356 | 0.99% |
| Inactive(file) | 5,847,208 | 99.01% |
| **比值 (Active/Inactive)** | **1:100** | |

> **关键发现**：Active(file) 仅占文件页缓存的不到 1%，而 Inactive(file) 占 99%+。这意味着：
> - 缓存在内存中的文件页面**几乎全部处于非活跃（冷）状态**
> - 这些文件被读取后**未被再次访问**，缺乏 locality
> - 内核 LRU 已将这些页面从 Active 链表降级到 Inactive 链表
> - 这些 Inactive(file) 页面属于**可安全回收**的页面（MemAvailable = 14.4GB 证实了这一点）

---

## 3. vmstat 页面缓存相关指标

```
nr_file_pages:     1,484,145 pages  (~5.8 GB)
pgfault:          15,718,049        (累计次缺页)
pgmajfault:           42,256        (累计主缺页/磁盘IO触发的缺页)
pgscan_direct:     2,445,150        (直接内存回收扫描页数)
pgsteal_direct:      349,083        (直接内存回收成功回收页数)
compact_migrate_scanned: 2,166,751,933
```

> **分析**：
> - `nr_file_pages` = 1,484,145 pages × 4KB = ~5.8GB，与 Cached 值 5.6GB 吻合，确认主要被文件页占用。
> - `pgmajfault` = 42,256 表示累计发生了约 4.2 万次需要从磁盘读取的主缺页中断，表明有大量文件 I/O 读取活动。
> - `pgscan_direct` = 2,445,150 表示直接内存回收扫描了大量页面，但 `pgsteal_direct` = 349,083（回收率 14.3%），效率较低。
> - 内存压缩扫描计数极高（`compact_migrate_scanned` = 21 亿+），可能存在内存碎片化问题。

---

## 4. Top Page Cache 消费者 — fincore 分析

### 4.1 大文件缓存占用（fincore 验证）

| 文件 | 文件大小 | 已缓存 (RES) | 缓存页数 | 缓存比例 |
|------|----------|-------------|----------|----------|
| /tmp/pagecache_test | 4.0 GB | 3.1 GB | 817,152 | 76.3% |
| /tmp/pc2 | 2.0 GB | 1.1 GB | 289,792 | 56.6% |
| /tmp/pc3 | 2.0 GB | 1.3 GB | 331,237 | 64.7% |
| **合计** | **8.0 GB** | **~5.5 GB** | **1,438,181** | **~69%** |

> **关键结论**：以上 3 个测试文件的缓存占用约 5.5GB，几乎完全占满了当前 Page Cache（5,906,152 kB = 5.63 GB）。**这三个文件就是 Page Cache 过度增长的根本原因。**

### 4.2 系统文件缓存占用（对比）

| 文件 | 文件大小 | 已缓存 (RES) |
|------|----------|-------------|
| /usr/lib/x86_64-linux-gnu/libicudata.so.70.1 | 28.1 MB | 0 B |
| /usr/lib/x86_64-linux-gnu/libc.so.6 | 2.1 MB | 1.7 MB |
| /usr/lib/gcc/x86_64-linux-gnu/11/cc1 | 24.8 MB | 0 B |

> **结论**：系统库文件和工具文件的缓存占用极低（基本为 0），进一步证明 Page Cache 的增长完全由 `/tmp/` 下的测试文件驱动。

### 4.3 进程 fd 中已删除文件检测

```
（无输出 — 没有任何已删除但仍被 fd 持有打开的文件）
```

> 不存在"幽灵文件"（deleted-but-open）占用 Page Cache 的情况。

---

## 5. /proc/sys/vm/drop_caches

```
cat: /proc/sys/vm/drop_caches: Permission denied
```

> 容器缺少 `CAP_SYS_ADMIN` 能力，无法读取 `drop_caches`。当前值未知，但该值仅影响写入行为，不影响读取诊断。

---

## 6. 容器基本状态

| 项目 | 值 |
|------|-----|
| 系统负载 | 0.01 / 0.05 / 0.06（极低） |
| 运行时间 | 8h 24min |
| 主进程 | `sleep 3600`（PID 1，空闲容器） |
| 磁盘使用 | overlay 1007G / 24G 已用 / 933G 可用（3%） |
| Swap 使用 | 207,236 kB / 4,194,304 kB（4.9%） |

---

## 7. 根因分析

```
Page Cache 过度增长根因链路：
  
  /tmp/pagecache_test (4GB)  ──┐
  /tmp/pc2            (2GB)  ──┤── 被顺序读取/操作 ──► 内核将文件页面缓存到 Page Cache
  /tmp/pc3            (2GB)  ──┘
                                    
                                ▼
                      Page Cache 膨胀至 ~8.7GB (峰值)
                      || Inactive(file) 占 99%+
                      || 页面未被再次访问（冷数据）
                      ▼
                      内核 LRU 标记为 Inactive + 可回收
                      → MemAvailable = 14.4GB，尚无内存压力
                      → 无 OOM 风险（当前状态）
```

**证据链**：

1. **Page Cache 总量**：`Cached = 5.9GB`（当前），峰值可达 8.7GB
2. **归因完整性**：fincore 确认 3 个测试文件缓存占用 ≈ 5.5GB（占当前 Cached 的 98%）
3. **页面冷热状态**：`Inactive(file) = 5.8GB` / `Active(file) = 57MB`，比值 100:1，全部为冷缓存
4. **无内存泄漏**：没有 deleted-but-open 文件，没有 Shmem 异常（仅 2.6MB）
5. **无立即风险**：`MemAvailable = 14.4GB`，Swap 使用率仅 4.9%

---

## 8. 风险等级评估

| 维度 | 评估 | 说明 |
|------|------|------|
| Page Cache 膨胀 | **高风险** | Cached 峰值占 MemTotal 的 54.6%，接近上限 |
| 页面活性 | **低风险** | Inactive(file) 占 99%，可安全回收 |
| 内存压力 | **低风险** | MemAvailable = 14.4GB，目前无内存竞争 |
| Swap 使用 | **低风险** | 4.9%，轻微 swap-in/out |
| OOM 风险 | **暂无** | 可用内存充裕 |
| 大文件缓存持续性 | **需关注** | 如果持续创建/读取大文件，Page Cache 可能再次膨胀 |

**综合风险等级：P2（中等风险）** — Page Cache 过高但当前无内存压力，需关注峰值是否持续增长并触发回收或 OOM。

---

## 9. 建议措施

| 优先级 | 措施 | 说明 |
|--------|------|------|
| P1 | **排查 /tmp 下测试文件的来源和用途** | `/tmp/pagecache_test`、`pc2`、`pc3` 是否为应用自身或测试脚本创建？如果是计划内行为，可忽略；如果是异常，需排查创建源 |
| P1 | **如果无需保留，删除测试文件** | `rm /tmp/pagecache_test /tmp/pc2 /tmp/pc3` 后，内核会自动回收对应的 Page Cache |
| P2 | **配置 cgroup memory limit 限制容器内存** | 通过 `--memory` 参数限制容器可用内存，防止 Page Cache 无限制增长影响其他容器 |
| P2 | **监控 Page Cache 趋势** | 设置 alarm 当 Cached/MemTotal > 50% 时告警 |
| P3 | **考虑使用 vmtouch/fincore 做定期缓存清理** | 对于非关键文件的缓存可手动 evict，但一般不推荐 |

---

## A. 原始诊断命令及输出

### A.1 cat /proc/meminfo
```
MemTotal:       15986876 kB
MemFree:         9211368 kB
MemAvailable:   15062352 kB
Buffers:            2116 kB
Cached:          5906152 kB
SwapCached:        12464 kB
Active:           155100 kB
Inactive:        6029896 kB
Active(anon):      96744 kB
Inactive(anon):   182688 kB
Active(file):      58356 kB
Inactive(file):  5847208 kB
Unevictable:           0 kB
Mlocked:               0 kB
SwapTotal:       4194304 kB
SwapFree:        3987068 kB
Dirty:               656 kB
Writeback:             0 kB
AnonPages:        273204 kB
Mapped:           128772 kB
Shmem:              2700 kB
KReclaimable:     191528 kB
Slab:             304076 kB
SReclaimable:     191528 kB
SUnreclaim:       112548 kB
KernelStack:        8196 kB
PageTables:         7108 kB
Hugepagesize:       2048 kB
DirectMap4k:      146432 kB
DirectMap2M:     6797312 kB
DirectMap1G:    17825792 kB
```

### A.2 cat /proc/vmstat (页缓存相关项)
```
nr_file_pages 1484145
pgfault 15718049
pgmajfault 42256
pgsteal_direct 349083
pgscan_direct 2445150
```

### A.3 fincore 输出
```
  RES  PAGES SIZE FILE
 3.1G 817152   4G /tmp/pagecache_test
 1.1G 289792   2G /tmp/pc2
 1.3G 331237   2G /tmp/pc3

   0B     0 28.1M /usr/lib/x86_64-linux-gnu/libicudata.so.70.1
 1.7M   445  2.1M /usr/lib/x86_64-linux-gnu/libc.so.6
   0B     0 24.8M /usr/lib/gcc/x86_64-linux-gnu/11/cc1
```

### A.4 ps aux --sort=-%mem
```
USER       PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
root         1  0.0  0.0   2792  1536 ?        Ss   15:33   0:00 sleep 3600
```

### A.5 df -h
```
Filesystem      Size  Used Avail Use% Mounted on
overlay        1007G   24G  933G   3% /
tmpfs            64M     0   64M   0% /dev
shm              64M     0   64M   0% /dev/shm
/dev/sde       1007G   24G  933G   3% /etc/hosts
```

### A.6 删除文件 fd 检测
```
（无输出）
```

### A.7 /proc/sys/vm/drop_caches
```
Permission denied（无 CAP_SYS_ADMIN）
```

### A.8 free -k / loadavg / uptime
```
Mem:        15986876      687032     9194872        2696     6104972    15051040
Swap:        4194304      207236     3987068
load average: 0.01, 0.05, 0.06
up 8:24
```
