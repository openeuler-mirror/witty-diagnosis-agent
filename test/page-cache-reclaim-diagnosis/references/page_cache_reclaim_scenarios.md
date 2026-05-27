# 页缓存/内存回收故障场景分类

## 场景列表

| 场景标签 | 中文描述 | 主要特征与案例 |
|---------|---------|--------------|
| `KSWAPD_HIGH_CPU` | kswapd 高 CPU | ① kswapd0 进程 CPU 使用率 > 20%；② `/proc/vmstat` 中 pgscan_kswapd 持续增长；③ 内存压力大时启动频繁回收 |
| `DIRECT_RECLAIM_LATENCY` | direct reclaim 延迟抖动 | ① allocstall 计数非零；② 业务进程周期性延迟抖动；③ 伴随 pgscan_direct 增长 |
| `DIRTY_WRITEBACK_STORM` | 脏页回写风暴 | ① `/proc/meminfo` 中 Dirty 接近 dirty_ratio；② 磁盘写 IO 突发增高；③ 写入延迟抖动 |
| `PAGE_CACHE_OVERUSE` | page cache 过度占用 | ① Cached > 70% MemTotal；② MemAvailable 偏低但 MemFree 正常；③ 文件读操作频繁 |
| `DROP_CACHES_IO_STORM` | drop_caches 误用 | ① 执行 `echo 3 > /proc/sys/vm/drop_caches` 后；② pgmajfault 飙升；③ 磁盘 IO 暴增 |

## 场景关联性

| 关联模式 | 典型链路 |
|---------|---------|
| page cache 过度占用 → MemAvailable 低 → kswapd 高 CPU | 文件缓存占满内存 → watermark 降低 → kswapd 频繁回收 |
| dirty_ratio 过高 → 脏页积累 → balance_dirty_pages 阻塞写入进程 | 回写阈值过高 → 脏页积累到上限 → 写入进程被迫同步回写 |
| drop_caches → page cache 清零 → 后续文件读取 → I/O 风暴 | 清理热缓存 → 大量缺页 → 磁盘 I/O 激增 → 业务延迟 |
| 内存碎片 → high-order 分配失败 → direct reclaim + compaction | 碎片化严重 → 大页分配失败 → 触发回收和碎片整理 |
