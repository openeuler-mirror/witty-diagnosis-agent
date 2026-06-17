# 内核回收/回写关键参数速查

## 一、回写参数

### dirty_ratio
- **路径**: `/proc/sys/vm/dirty_ratio`
- **默认值**: 20
- **含义**: 脏页总量占 MemTotal 的百分比上限，达到后触发**同步回写**（所有写进程被节流）
- **过小**: 进程频繁被 throttle，写入延迟飙升
- **过大**: 脏页堆积多，故障恢复慢（重启需刷脏页）
- **修改**: `sysctl -w vm.dirty_ratio=10`
- **建议**: SSD 可设 5~10%，HDD 可保持 15~20%，大内存 >64GB 可考虑 5%

### dirty_background_ratio
- **路径**: `/proc/sys/vm/dirty_background_ratio`
- **默认值**: 10
- **含义**: 脏页达到此百分比后，内核启动后台 flusher 线程刷脏页（不阻塞进程）
- **过小**: flusher 频繁唤醒，增加 CPU 开销
- **过大**: 后台回写启动晚，脏页堆积接近 dirty_ratio 才刷
- **建议**: 通常设为 dirty_ratio 的一半

### dirty_bytes / dirty_background_bytes
- **路径**: `/proc/sys/vm/dirty_bytes`, `/proc/sys/vm/dirty_background_bytes`
- **默认值**: 0（使用 ratio 模式）
- **说明**: 与 `dirty_ratio`/`dirty_background_ratio` 互斥，设置 bytes 后 ratio 失效
- **适用**: 小内存系统或需要精确控制脏页总量的场景

### dirty_expire_centisecs
- **路径**: `/proc/sys/vm/dirty_expire_centisecs`
- **默认值**: 3000（30秒）
- **含义**: 脏页最长可驻留时间（百分之一秒），超时后 flusher 必须刷出
- **过小**: 脏页还没积累够就被刷出，写放大
- **过大**: 脏页长期留在内存中，故障时数据丢失风险大
- **建议**: 30 秒默认值适合大多数场景，需要更快数据落盘可调低至 500（5秒）

### dirty_writeback_centisecs
- **路径**: `/proc/sys/vm/dirty_writeback_centisecs`
- **默认值**: 500（5秒）
- **含义**: flusher 线程唤醒间隔
- **过小**: flusher 唤醒频繁，CPU 开销增加
- **过大**: 脏页响应延迟

### dirtytime_expire_seconds
- **路径**: `/proc/sys/vm/dirtytime_expire_seconds`
- **默认值**: 43200（12小时）
- **含义**: 仅在 `atime` 更新时脏的页的刷新超时

### block_dump
- **路径**: `/proc/sys/vm/block_dump`
- **默认值**: 0（关闭）
- **说明**: 设为 1 后，内核将每个脏 block 的写操作记录到日志，用于调试写放大

---

## 二、回收参数

### min_free_kbytes
- **路径**: `/proc/sys/vm/min_free_kbytes`
- **默认值**: 内核自动计算（约 MemTotal × 0.05%）
- **含义**: 内存保留的最低空闲量，低于此水位时只有内核可以分配（用户态分配被阻塞）
- **经典计算公式**: `sqrt(MemTotal_kB) × 4`
- **不足后果**: direct reclaim 激增、allocation failure、atomic 分配失败
- **建议**: 大内存机器（>64GB）可将默认值提高 2~4 倍
- **大内存参考**:
  | MemTotal | 默认 min_free_kbytes | 建议值 |
  |---------|--------------------|-------|
  | 8GB | ~37MB (~0.5%) | 64MB~128MB |
  | 64GB | ~150MB (~0.2%) | 256MB~512MB |
  | 256GB | ~300MB (~0.1%) | 1GB~2GB |
  | 1TB | ~600MB (~0.06%) | 4GB~8GB |

### watermark_scale_factor
- **路径**: `/proc/sys/vm/watermark_scale_factor`
- **默认值**: 10
- **含义**: min/low/high 水位间距。值越大，low 和 high 离 min 越远（提前唤醒 kswapd，回收更积极）
- **公式**: `low = min + (min / 100 × watermark_scale_factor)`
- **调大**: kswapd 更早唤醒，但也更早停止（减少直接回收概率）
- **调小**: 水位间距更窄，内存利用率更高，但直接回收概率增加

### watermark_boost_factor
- **路径**: `/proc/sys/vm/watermark_boost_factor`
- **默认值**: 15000
- **含义**: THP 等大块分配失败时，临时提升水位的倍数
- **说明**: 提升 = watermark[high] × watermark_boost_factor / 10000，然后衰减

### vfs_cache_pressure
- **路径**: `/proc/sys/vm/vfs_cache_pressure`
- **默认值**: 100
- **含义**: 控制 dentry/inode 等 slab 缓存的回收倾向。值越高，回收越积极
- **= 0**: 永不回收 slab（极度保守）
- **< 100**: slab 回收相对保守
- **= 100**: 默认平衡
- **> 100**: slab 回收偏激进
- **> 1000**: slab 回收极端激进（反复构造 dentry 反而浪费 CPU）
- **建议**: dentry 缓存膨胀时适度提高（150~200），内存充足时保持默认

### swappiness
- **路径**: `/proc/sys/vm/swappiness`
- **默认值**: 60
- **含义**: 控制回收时扫描匿名页（swap）vs 文件页的比例。值越高，越倾向回收匿名页
- **= 0**: 不考虑 swap（除非内存极度不足）
- **< 60**: 倾向回收文件页
- **= 60**: 默认平衡
- **> 60**: 倾向回收匿名页（使用 swap）
- **建议**: SSD 且有 swap 可设 10~30；无 swap 设 0~1；DB/redis 进程设 0~10

### zone_reclaim_mode
- **路径**: `/proc/sys/vm/zone_reclaim_mode`
- **默认值**: 0
- **含义**: 当本 node/zone 内存不足时的行为
- **= 0**: 可跨 node/zone 回收（NUMA 友好）
- **= 1**: 优先本 zone 回收，不跨 zone（减少远程内存访问）
- **= 2**: 可回写脏页到本地磁盘
- **= 4**: 可 swap 出本地页

### page-cluster
- **路径**: `/proc/sys/vm/page-cluster`
- **默认值**: 3（8 页）
- **含义**: swap 换入的预读页数（2^N 页）。设置太大 → swap 换入放大；太小 → swap 效率低

### extfrag_threshold
- **路径**: `/proc/sys/vm/extfrag_threshold`
- **默认值**: 500
- **说明**: 控制内核在什么碎片程度下试图做内存规整，值越小越容易触发规整

### drop_caches
- **路径**: `/proc/sys/vm/drop_caches`
- **= 1**: 释放 page cache（文件页）
- **= 2**: 释放 dentry/inode（slab 可回收部分）
- **= 3**: 释放 page cache + dentry/inode
- **⚠️ 风险**: 清除缓存后系统会经历一段"冷启动"期，IO 和 CPU 暂时升高

---

## 三、cgroup/memcg 参数

### memory.limit_in_bytes
- **路径**: `/sys/fs/cgroup/memory/<group>/memory.limit_in_bytes`
- **说明**: cgroup 内存上限，超限触发 OOM 或 reclaim

### memory.usage_in_bytes / memory.failcnt
- **路径同上**
- **说明**: 当前使用量 / 超限次数

### memory.stat
- **说明**: cgroup 内详细内存统计（类似 /proc/meminfo per-cgroup）

---

## 四、NUMA 特定参数

### /sys/devices/system/node/nodeN/vmstat
- per-node 的 vmstat 指标，用于 NUMA 场景定位

### numactl --hardware
- 查看内存分配策略和节点距离

---

## 五、调试与跟踪

### 快速开启 tracepoint

```bash
# vmscan 关键事件
trace-cmd record -e mm_vmscan_kswapd_wake \
                  -e mm_vmscan_direct_reclaim_start \
                  -e mm_vmscan_direct_reclaim_end \
                  -e mm_vmscan_lru_shrink_inactive \
                  sleep 10

# 回写关键事件
trace-cmd record -e writeback_start \
                  -e writeback_written \
                  -e writeback_wait \
                  -e writeback_single_inode_start \
                  -e writeback_single_inode \
                  -e balance_dirty_pages \
                  sleep 10

# THP 规整
trace-cmd record -e compaction_isolate_migratepages \
                  -e compaction_isolate_freepages \
                  -e mm_compaction_begin \
                  -e mm_compaction_end \
                  sleep 10
```

### perf 追踪 kswapd

```bash
# kswapd CPU 占用
perf top -p $(pgrep -x kswapd0)

# kswapd 火焰图（30s 采样）
perf record -g -p $(pgrep -x kswapd0) -- sleep 30
perf script | stackcollapse-perf.pl | flamegraph.pl > kswapd.svg
```

### BPF 工具（如 bcc 可用）

```bash
# 直接回收跟踪
/usr/share/bcc/tools/drsnoop

# 回写延迟跟踪
/usr/share/bcc/tools/writeback

# 内存分配延迟
/usr/share/bcc/tools/llcstat

# OOM 跟踪
/usr/share/bcc/tools/oomkill
```

---

## 六、快速诊断对照

| 症状 | 查看 | 参数调整方向 |
|------|------|------------|
| 写延迟突增 | Dirty, Writeback, balance_dirty_pages D 状态 | 检查脏页阈值 + BDI 限流 |
| kswapd 高 CPU | pgscan_kswapd, kswapd CPU% | 增大 min_free_kbytes 或 watermark_scale_factor |
| page cache 抖动 | workingset_refault 暴涨 | 增大 page-cluster 或降低 swappiness |
| 单盘拖慢全系统 | BDI nr_dirty_this_bf, wb_throttled | 更换设备或设 max_ratio |
| allocation failure | dmesg, min_free_kbytes | 增大 min_free_kbytes |
| msync 卡顿 | D 状态 wchan=msync | 调低 dirty_ratio / dirty_expire_centisecs |
| slab 缓存过高 | SReclaimable, vfs_cache_pressure | 调高 vfs_cache_pressure |
