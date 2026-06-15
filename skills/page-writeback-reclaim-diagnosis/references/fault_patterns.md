# 页缓存/回写/回收故障模式目录

## 故障模式分类

### 模式 A：脏页回写异常

| 子模式 | 触发条件 | 关键指标 | 典型值 |
|--------|---------|---------|-------|
| A1: dirty_ratio 被业务写满 | 写入速度 >> 回写速度 | Dirty > dirty_ratio × MemTotal | Dirty > 20%×total |
| A2: dirty_background_ratio 过小 | 频繁触发后台回写 | Dirty 在 bg_threshold 附近震荡 | CPU 大量 si/sy |
| A3: dirty_expire_centisecs 过短 | 脏页还没写满就被刷出 | 短寿页频繁回写 | IO 写放大 |
| A4: 回写线程卡住 | 回写路径 io_schedule 卡住 | nr_writeback 持续 > 0 无下降 | 同一值持续 30s+ |
| A5: dirty_ratelimit 过低 | 限流算法保守 | 回写带宽 << 设备吞吐 | 设备写 200MB/s 但限流到 20MB/s |

### 模式 B：kswapd / direct reclaim 高 CPU

| 子模式 | 触发条件 | 关键指标 | 典型值 |
|--------|---------|---------|-------|
| B1: kswapd CPU 100% | watermark low 持续 | kswapd CPU > 50% | 一个核被 kswapd 占满 |
| B2: direct reclaim 持续 | MemFree < watermark[min] | pgscan_direct > 0 持续 | 每次分配都触发回收 |
| B3: 回收效率低 | 大量不可回收页 | pgsteal/pgscan < 0.7 | 扫描 100 页只回收 50 页 |
| B4: 压缩/碎片回收 | 大 order 分配失败 | compact_stall >> compact_success | order > 3 分配失败 |
| B5: 多 kswapd 抢占 | cgroup 隔离 | 多个 kswapd N 争抢 | memcg 场景 |

### 模式 C：Page cache 反复回收抖动

| 子模式 | 触发条件 | 关键指标 | 典型值 |
|--------|---------|---------|-------|
| C1: 文件缓存不足 | 工作集大小 > 物理内存 | workingset_refault > 1000/s | refault 持续增长 |
| C2: inactive 列表过小 | 直接回收活跃文件页 | nr_inactive_file << nr_active_file | inactive 只占文件页 10% |
| C3: swappiness 过高 | 文件页比匿名页先被回收 | swap 活动高 + refault 高 | swappiness > 60 |
| C4: scan 不均衡 | LRU 不平衡 | pgrefill >> pgsteal | 大量 refill 但 steal 低 |

### 模式 D：慢设备拖垮回写（IO 背压）

| 子模式 | 触发条件 | 关键指标 | 典型值 |
|--------|---------|---------|-------|
| D1: 单设备脏页堆积 | 慢 HDD 回写跟不上 | BDI nr_dirty_this_bf >> bdi_dirty_limit | 某 BDI 占全局 dirty 90% |
| D2: wb_throttled 频繁 | BDI 限流 | wb_throttled 计数飙升 | 进程在 wb_throttled D 状态 |
| D3: 回写 IO 卡住 | 设备 IO 排队深 | nr_writeback_this_bf > 0 持续 | %util=100% + w_await>100ms |
| D4: BDI max_ratio 误配 | 人为限制回写带宽 | BDI dirty_ratelimit < 预期 | 设备能力 200MB/s 但限 10MB/s |

### 模式 E：min_free_kbytes 不足

| 子模式 | 触发条件 | 关键指标 | 典型值 |
|--------|---------|---------|-------|
| E1: 全局水位过低 | MemFree 徘徊在 min 附近 | Free < watermark[min] | 大内存 >64GB 仍需调整 |
| E2: 原子分配失败 | order > 0 分配时无空闲 | allocation failure order>0 | order 4 及以上失败 |
| E3: per-zone 稀缺 | 一个 zone 耗尽 | 某 zone free < min | Normal zone 水位低 |
| E4: watermark_boost 不足 | 无法快速提升水位 | watermark_boost_factor=0 | THP 分配频繁 |

### 模式 F：mmap writeback 停顿

| 子模式 | 触发条件 | 关键指标 | 典型值 |
|--------|---------|---------|-------|
| F1: msync 刷出卡顿 | msync 触发大量回写 | wchan msync | 应用感知 100ms+ 延迟 |
| F2: munmap 写回 | 卸载映射时刷脏页 | wchan munmap | mongo/rocksdb 场景 |
| F3: page_mkwrite 冲突 | 回写中再次写 | wchan page_mkwrite | 写时复制与回写碰撞 |
| F4: fput writeback | 关闭 fd 时回写 | wchan fput→writeback | 文件关闭负担 |

### 模式 G：vfs_cache_pressure 误配

| 子模式 | 触发条件 | 关键指标 | 典型值 |
|--------|---------|---------|-------|
| G1: slab 永不回收 | vfs_cache_pressure=0 | SReclaimable 只增不减 | 占用 50%+ MemTotal |
| G2: slab 回收过度 | vfs_cache_pressure > 1000 | SReclaimable < 1% MemTotal | CPU 用于频繁重建 dentry |
| G3: dentry 膨胀 | 大量文件操作 | dentry slab > 1GB | /proc/sys/fs/nr_dentry 高 |

## 故障关联映射

| 起始模式 | 触发关联模式 | 关联说明 |
|---------|------------|---------|
| A1: dirty_ratio 满 | → B2: direct reclaim | 回写慢 → 脏页占满 → 内存不足 → 直接回收 |
| A4: 回写线程卡住 | → D1: 单设备堆积 | 回写线程卡 → 脏页全堆积在某设备 |
| B2: direct reclaim | → C3: swappiness 高 | 回收匿名页 → 按 swappiness 换出文件页 |
| C1: 文件缓存不足 | → E1: 水位低 | 大量回收文件页 → free 页低 → 水位下降 |
| D1: 单设备堆积 | → A1: dirty_ratio 满 | 单设备慢 → 全局脏页超限 |
| G2: slab 回收过度 | → C1: 文件缓存不足 | dentry 回收 → 文件页也要回收 |
| F3: page_mkwrite 冲突 | → D1: 单设备 IO 背压 | mmap 冲突导致回写 IO 压力 |
