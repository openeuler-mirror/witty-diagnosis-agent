# Page Fault / Swap - 换入与缺页分析剧本

## 触发条件

用户问题包含以下关键词：
- "swap 高"、"换入"
- "page fault"、"缺页异常"
- "minor fault"、"major fault"
- "内存不足"、"OOM"
- "thp"、"transparent hugepage"
- "mmap"、"munmap"
- "RSS 持续增长但 CPU 不高"

## 场景说明

页错误（Page Fault）是虚拟内存系统的正常组成部分，但异常高的页错误率意味着：
- **次要页错误（minor fault）**：匿名页或已缓存文件页的换入，开销较小但累积起来可观
- **主要页错误（major fault）**：需从磁盘读取的页，I/O 延迟高（10ms-100ms+）
- **swap 换入**：物理内存不足，被换出的页需读回，灾难级延迟

典型症状：
- `vmstat 1` 中 `si`/`so`（swap in/out）持续 > 0
- `ps` 中 `%si`（swap in CPU）占比 > 1%
- 应用启动后 P99 远高于稳态
- 火焰图 `do_page_fault` / `handle_mm_fault` / `filemap_fault` 出现明显宽度
- 与 [why-mem-high.md](why-mem-high.md) 联动

## 分析流程

### Step 1: 准备页错误事件

```bash
# 收集次要/主要页错误
perf record -e page-faults -g -p <pid> sleep 30
perf script > pf.perf

# 收集 swap 事件
perf record -e swap:swap_in -g -p <pid> sleep 30

# 系统级统计
perf stat -e 'page-faults,major-faults' -p <pid> sleep 10
```

### Step 2: 模式检测

```bash
python scripts/analyzers/pattern_match.py --input folded.folded --json
```

重点匹配（来自 `analysis-patterns.md` 第 8 类 + `offcpu-patterns.md` 第 6 类）：

| 类别 | 特征函数/符号 | 权重 |
|------|-------------|------|
| 缺页异常 | `do_page_fault`, `handle_mm_fault`, `__do_page_fault` | 0.7 |
| 交换等待 | `swapin`, `folio_swapin`, `do_swap_page`, `swap_readpage` | 1.0 |
| 文件映射 | `filemap_fault`, `mmap_region`, `vmf_insert_pfn` | 0.6 |
| 大页分配 | `hugetlbfs_fault`, `alloc_huge_page`, `khugepaged` | 0.7 |
| OOM 等待 | `out_of_memory`, `pagefault_out_of_memory`, `__oom_kill_process` | 1.0 |
| 内存映射 | `mmap`, `munmap`, `mremap`, `do_brk` | 0.5 |
| 堆扩展 | `sys_brk`, `do_brk_flags` | 0.5 |
| 缺页回收 | `shrink_inactive_list`, `page_referenced` | 0.6 |

### Step 3: 页错误热点分析

```bash
python scripts/analyzers/hotspot.py --input folded.folded --top 30 --json
```

按"叶帧是页错误处理函数"聚合：
- 在哪段代码触发
- 是文件映射还是匿名页
- 是否在循环中触发（典型：边读边解析大文件）

### Step 4: 内存压力评估

```bash
# 整体内存使用
free -h
cat /proc/meminfo | grep -E "(MemTotal|MemFree|MemAvailable|Buffers|Cached|SwapTotal|SwapFree|AnonPages|Mapped)"

# 进程 RSS / VSZ / 共享内存
ps -o pid,rss,vsz,shr,pmem,comm -p $PID

# 各进程 swap 使用
for pid in $(ls /proc | grep -E "^[0-9]+$"); do
  if [ -f /proc/$pid/smaps ]; then
    swap=$(grep -E "Swap:" /proc/$pid/smaps 2>/dev/null | awk '{sum+=$2} END {print sum}')
    [ "$swap" != "" ] && [ "$swap" != "0" ] && echo "$pid $swap $(cat /proc/$pid/comm)"
  fi
done | sort -k2 -n -r | head
```

## 输出结构

```
## 页错误/换入分析

### 内存压力概览
- 系统总内存: XX GB
- 已用: XX GB (XX%)
- 可用: XX GB
- Swap 使用: XX GB / XX GB
- 是否触发过 OOM: 是/否

### 页错误统计
- 次要页错误: XXX K/s
- 主要页错误: XXX /s（需关注）
- Swap 换入: XXX KB/s
- 触发 page_fault 的 CPU 占比: XX%

### 页错误热点
| 业务方法 | 触发类型 | 累计次数 | 占比 |
|---------|---------|---------|------|
| indexService.load | mmap + filemap_fault | 120k | 45% |
| decoder.parse | anonymous page | 80k | 30% |
| cacheLoader | swap in | 5k | 5% |

### 热点栈
```
mmap → do_page_fault → filemap_fault → iomap_readpage
  └─ IndexLoader.openFile
     └─ IndexService.load
```
```

## 阈值标准

| 指标 | 阈值 | 严重度 |
|------|------|--------|
| 次要页错误率 | > 10K/s | 中（系统级正常） |
| 次要页错误率 | > 100K/s | 高（短命对象多） |
| 主要页错误率 | > 10/s | 高（频繁磁盘读） |
| 主要页错误率 | > 100/s | 严重（页缓存未命中） |
| Swap 换入 | > 0 | 高（物理内存不足） |
| Swap 换入持续 | > 1MB/s | 严重（已 swap 颠簸） |
| page_fault 帧占比 | > 2% | 中（内核开销） |
| 内存使用率 | > 90% | 警告（接近 OOM） |
| 内存使用率 | > 95% | 高（频繁回收） |

## 典型场景

### 场景 1: 大文件 mmap 读取

**症状**：
- 火焰图 `mmap` / `filemap_fault` / `iomap_readpage` 占 CPU
- 业务用 mmap 读取大文件（如 ES 索引、RocksDB SST）

**根因**：
- mmap 触发按需调页（demand paging）
- 随机访问导致大量 page fault
- 比 `read()` 系统调用预读效率低

**修复**：
- 顺序访问：增大 `readahead`（`posix_fadvise` / `madvise(MADV_SEQUENTIAL)`）
- 预读：`readahead` 系统调用
- 评估是否真的需要 mmap（顺序读时 `read()` + 用户态缓存可能更快）

### 场景 2: 短命对象导致 minor fault 风暴

**症状**：
- 次要页错误 > 100K/s
- 火焰图 `do_anonymous_page` / `__handle_mm_fault` 占比 > 2%
- 与 [why-mem-high.md](why-mem-high.md) 联动

**根因**：
- 大量 new/malloc 触发新页分配
- 每个页 4KB，碎片化严重

**修复**：
- 对象池复用
- 减少分配速率
- 调大 THP（Transparent Huge Page）：减少页表项
  ```bash
  echo always > /sys/kernel/mm/transparent_hugepage/enabled
  ```

### 场景 3: 物理内存不足导致 swap

**症状**：
- `free` 中 `available` < 总内存 10%
- `si`/`so` 持续 > 0
- 火焰图 `swap_readpage` / `do_swap_page` 出现
- 应用 P99 突刺明显

**根因**：
- 进程 RSS 超过物理内存
- 内核将冷数据换出到 swap
- 访问时再换入

**修复**：
- **立刻**：降低进程内存占用（缓存清理、连接数减少）
- **短期**：扩容内存 / 拆分到多机
- **中期**：优化分配（[why-mem-high.md](why-mem-high.md)）
- **配置**：调整 `vm.swappiness`（容器场景 0-10，物理机场景 10-60）
- **检查**：是否设置了 `vm.overcommit_memory=0`（拒绝超额分配）

### 场景 4: 大页相关

**症状**：
- 火焰图 `hugetlbfs_fault` / `alloc_huge_page` / `khugepaged` 出现
- 业务显式使用大页（如 Java `-XX:+UseLargePages`、数据库）

**优化**：
- 预分配大页：`sysctl vm.nr_hugepages`
- 透明大页 THP：评估 `madvise` vs `always`
- 监控 `/proc/meminfo | grep Huge`

### 场景 5: 冷启动 / 预热不足

**症状**：
- 应用刚启动时 P99 极高
- 几分钟后趋于平稳
- 火焰图 `do_page_fault` 在启动期明显

**根因**：
- 文件页未加载到页缓存
- 类未 JIT 编译
- 缓存未预热

**修复**：
- 预热：启动后用部分流量触发
- 预加载：用 `cachestat` / `vmtouch` 提前热页
- 启用 AOT 编译（GraalVM Native Image）

## 关键识别表

| 触发点 | 帧 | 含义 | 优化方向 |
|--------|-----|------|---------|
| 匿名页 | `do_anonymous_page` | 堆/stack 新页 | 减少分配 |
| 文件页（缓存命中）| `filemap_fault` → page cached | 页缓存命中 | 正常 |
| 文件页（需读盘）| `filemap_fault` → `readpage` | 页缓存未命中 | 增大缓存 / 预热 |
| 写时复制 | `do_wp_page`, `COW` | fork 后 | 评估是否真需 fork |
| 换入 | `do_swap_page`, `swap_readpage` | 物理内存不足 | 扩容 / 减内存 |
| 大页分配 | `hugetlb_fault`, `alloc_hugepage` | 大页按需分配 | 预分配大页 |
| 收缩 | `shrink_inactive_list` | 内存压力 | 减内存占用 |

## 与其他剧本的协同

| 关联剧本 | 协同方式 |
|---------|---------|
| [why-mem-high.md](why-mem-high.md) | 分配速率高 → 触发 minor fault |
| [gc-pressure.md](gc-pressure.md) | Java 堆大 → 可能触发 OS 换出 |
| [io-wait.md](io-wait.md) | major fault = 磁盘 I/O |
| [why-cpu-high.md](why-cpu-high.md) | `do_page_fault` 本身消耗 CPU |

## 优化建议

### 1. 减少分配

见 [why-mem-high.md](why-mem-high.md) 全部建议。

### 2. 启用大页

```bash
# 系统级 THP
echo always > /sys/kernel/mm/transparent_hugepage/enabled

# 显式大页
sysctl -w vm.nr_hugepages=1024
# Java
-XX:+UseLargePages -XX:LargePageSizeInBytes=2m
```

### 3. 优化 mmap

```c
// 顺序访问
madvise(addr, length, MADV_SEQUENTIAL);
// 随机访问
madvise(addr, length, MADV_RANDOM);
// 不再使用
madvise(addr, length, MADV_DONTNEED);

// 异步预读
readahead(fd, offset, count);
```

### 4. 内存调优

```bash
# 减少 swap 倾向（容器推荐 0）
sysctl -w vm.swappiness=10

# 脏页比例（影响写回节奏）
sysctl -w vm.dirty_ratio=10
sysctl -w vm.dirty_background_ratio=5

# vfs cache 压力
sysctl -w vm.vfs_cache_pressure=50
```

### 5. 预热

- 启动后访问热点数据
- 用 `vmtouch` 强制预读：
  ```bash
  vmtouch -t /data/index.dat  # 临时热页
  vmtouch -l /data/index.dat  # 锁定不被换出
  ```

### 6. 监控

- `/proc/vmstat` 中 `pgfault` / `pgmajfault`
- `/proc/$PID/smaps` 看每个 VMA 的页数
- `perf stat -e page-faults,major-faults`

## 配套工具命令

```bash
# 整体内存
free -h
vmstat 1 5

# 进程内存细节
cat /proc/$PID/status
cat /proc/$PID/smaps | grep -E "(Size|Rss|Shared|Private|Swap):" | head -40

# 页错误
perf stat -e page-faults,major-faults -p $PID sleep 10

# swap 监控
cat /proc/$PID/smaps_rollup
# 找 VMA 中 Swap: > 0 的段

# 缺页采样
perf record -e page-faults -g -p $PID sleep 30
perf script > pf.perf
# 转 folded
python scripts/adapters/perf_to_folded.py pf.perf -o pf.folded

# vmtouch
vmtouch -v /path/to/file  # 看缓存情况
vmtouch -t /path/to/file  # 临时热页
```

## 常见误判

- **"swap 有数据" 不一定在用**：可能历史遗留，重启后清空
- **"page fault 高" 不全是问题**：次要页错误是正常的（程序启动、栈扩展）
- **"启用 THP" 一定好**：对某些数据库（Redis、ClickHouse）反而有害，会造成 latency spike
- **"扩容内存就解决"**：可能掩盖泄漏问题，需先看 [why-mem-high.md](why-mem-high.md) 是否有泄漏
