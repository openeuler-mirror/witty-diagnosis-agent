# 内存回收诊断命令速查

## 一、核心指标采集

### /proc/meminfo 关键字段

| 字段 | 含义 | 关注条件 |
|------|------|---------|
| MemTotal | 总物理内存 | — |
| MemFree | 空闲内存 | < 5% → 紧张 |
| MemAvailable | 可用内存（含 page cache 可回收部分） | < 10% → 紧张 |
| Buffers | 块设备缓冲 | — |
| Cached | Page cache | 剧烈波动 → thrash |
| SwapCached | Swap 中缓存的页 | — |
| Active | 活跃页 | — |
| Inactive | 非活跃页 | — |
| Active(anon) | 活跃匿名页 | — |
| Inactive(anon) | 非活跃匿名页 | — |
| Active(file) | 活跃文件页 | — |
| Inactive(file) | 非活跃文件页 | 不足 → refault |
| Dirty | 脏页量 | > dirty_ratio → 限流 |
| Writeback | 正在回写量 | 持续 > 0 → 回写卡住 |
| AnonPages | 匿名页总量 | — |
| Mapped | 文件映射页 | — |
| Shmem | 共享内存 | — |
| KReclaimable | 内核可回收 slab | — |
| Slab | Slab 总量 | — |
| SReclaimable | 可回收 slab | — |
| SUnreclaim | 不可回收 slab | — |
| KernelStack | 内核栈 | — |
| PageTables | 页表 | — |
| VmallocUsed | vmalloc 使用量 | — |
| NFS_Unstable | NFS 脏页 | — |
| WritebackTmp | FUSE 回写页 | — |

### /proc/vmstat 关键字段

| 字段 | 类型 | 含义 |
|------|------|------|
| pgfault | 累计 | 缺页中断总数（major+minor） |
| pgmajfault | 累计 | 主要缺页中断（需读盘） |
| pgfree | 累计 | 释放页数 |
| pgactivate | 累计 | 激活非活跃页 |
| pgdeactivate | 累计 | 去激活活跃页 |
| pgscan_kswapd | 累计 | kswapd 扫描的页数 |
| pgscan_direct | 累计 | direct reclaim 扫描的页数 |
| pgsteal_kswapd | 累计 | kswapd 回收的页数 |
| pgsteal_direct | 累计 | direct reclaim 回收的页数 |
| pgscan_direct_throttle | 累计 | 直接回收被限流的次数 |
| pgrefill | 累计 | 重填非活跃列表的页数 |
| pgoutrun | 累计 | kswapd 运行次数 |
| pgskip | 累计 | kswapd 跳过的 zone 次数 |
| allocstall_dma/dma32/normal/movable | 累计 | 各 zone 分配 stall 次数 |
| kswapd_inodesteal | 累计 | kswapd 偷取 inode 的页数 |
| nr_dirty | 瞬时 | 当前脏页数 |
| nr_writeback | 瞬时 | 当前回写页数 |
| nr_pageout | 瞬时？ | 换出（回写）页数 |
| nr_dirtied | 累计 | 脏页产生的总次数 |
| nr_written | 累计 | 回写完成的总次数 |
| workingset_refault | 累计 | 页面被回收后重新访问次数 |
| workingset_activate | 累计 | refault 后激活的页数 |
| workingset_restore | 累计 | refault 后恢复的非活跃页 |
| nr_inactive_anon | 瞬时 | 非活跃匿名页数 |
| nr_active_anon | 瞬时 | 活跃匿名页数 |
| nr_inactive_file | 瞬时 | 非活跃文件页数 |
| nr_active_file | 瞬时 | 活跃文件页数 |
| nr_zone_active_anon | 瞬时 | per-zone 活跃匿名页 |
| nr_zone_inactive_anon | 瞬时 | per-zone 非活跃匿名页 |
| nr_zone_active_file | 瞬时 | per-zone 活跃文件页 |
| nr_zone_inactive_file | 瞬时 | per-zone 非活跃文件页 |
| nr_mlock | 瞬时 | mlock 锁定的页数 |
| nr_page_table_pages | 瞬时 | 页表占用页数 |
| nr_kernel_stack | 瞬时 | 内核栈占用页数 |
| compact_migrate_scanned | 累计 | 内存整理扫描的迁移页 |
| compact_free_scanned | 累计 | 内存整理扫描的空闲页 |
| compact_stall | 累计 | 内存整理被触发的次数 |
| compact_fail | 累计 | 内存整理失败次数 |
| compact_success | 累计 | 内存整理成功次数 |
| pswpin | 累计 | 换入页数 |
| pswpout | 累计 | 换出页数 |

### BDI sysfs 结构

```
/sys/devices/virtual/bdi/<major>:<minor>/
├── dev_name          # 对应块设备名（如 sda）
├── stats/
│   ├── nr_dirty_this_bf        # 该 BDI 上的脏页数
│   ├── nr_writeback_this_bf    # 该 BDI 上的回写页数
│   ├── nr_dirty_threshold      # 该 BDI 的脏页阈值的副本
│   ├── bdi_dirty_limit         # 该 BDI 的脏页上限（全局按比例分配）
│   ├── wb_throttled            # 被限流的次数
│   ├── min_ratio               # 最小脏页比例
│   ├── max_ratio               # 最大脏页比例（默认 100%）
│   ├── dirty_ratelimit         # 当前脏页限速（bytes/s）
│   ├── avg_write_bandwidth     # 平均回写带宽
│   ├── avg_queue_size          # 平均回写队列深度
│   └── dirty_poll_interval     # 脏页轮询间隔
```

---

## 二、诊断步骤速查

### 步骤 1：快速定位问题域

```bash
# 1. 检查脏页是否堆积
grep -E "^(Dirty|Writeback)" /proc/meminfo

# 2. 检查回收是否活跃
awk '/pgscan|pgsteal|pgoutrun|allocstall/' /proc/vmstat

# 3. 检查 refault 抖动
awk '/workingset/' /proc/vmstat

# 4. 检查水位
grep -E "Node|zone|free |min |low |high " /proc/zoneinfo

# 5. 检查 D 状态进程（回写相关）
ps -eo pid,stat,wchan:32,comm | awk '$2 ~ /^D/'
```

### 步骤 2：增量采样（5~10s）

```bash
# 记录快照
awk '/pgscan|pgsteal|pgrefill|workingset|nr_dirty|nr_writeback|allocstall/' /proc/vmstat > /tmp/t1
sleep 10
awk '/pgscan|pgsteal|pgrefill|workingset|nr_dirty|nr_writeback|allocstall/' /proc/vmstat > /tmp/t2

# 对比
while read name val1; do
  val2=$(awk -v n="$name" '$1==n{print$2}' /tmp/t2)
  echo "$name Δ=$((val2-val1))"
done < /tmp/t1
```

### 步骤 3：BDI 逐设备排查

```bash
for bdi in /sys/devices/virtual/bdi/*/; do
  echo "--- $(cat ${bdi}dev_name) ---"
  cat ${bdi}stats/nr_dirty_this_bf ${bdi}stats/nr_writeback_this_bf \
      ${bdi}stats/bdi_dirty_limit ${bdi}stats/wb_throttled
done
```

### 步骤 4：kswapd CPU 分析

```bash
# kswapd CPU 占用
top -b -n1 -p $(pgrep -x kswapd0)

# kswapd 火焰图（需 perf）
perf record -g -p $(pgrep -x kswapd0) -- sleep 30
perf script | ./FlameGraph/stackcollapse-perf.pl | ./FlameGraph/flamegraph.pl > kswapd.svg
```

### 步骤 5：tracepoint 追踪

```bash
# vmscan 事件追踪
trace-cmd record -e mm_vmscan_kswapd_wake \
                  -e mm_vmscan_direct_reclaim_start \
                  -e mm_vmscan_direct_reclaim_end \
                  -e mm_vmscan_lru_shrink_inactive \
                  sleep 10

# 回写事件追踪
trace-cmd record -e writeback_start \
                  -e writeback_written \
                  -e writeback_wait \
                  -e balance_dirty_pages \
                  sleep 10
```

---

## 三、常见故障判断表

| 指标特征 | 含义 | 下一步 |
|---------|------|--------|
| `Dirty > dirty_ratio × MemTotal` | 全局限流触发 | 检查回写速度 + BDI |
| `workingset_refault` 增长 > 1000/s | Page cache 抖动 | 检查 inactive 大小 |
| `pgscan_direct` 持续 > 0 | 直接回收活跃 | 检查水位 + min_free_kbytes |
| `pgscan_direct_throttle` > 0 | 直接回收被限流 | 严重告警 |
| `pgscan_kswapd >> pgscan_direct` | kswapd 主导回收 | 检查 kswapd CPU |
| 某 BDI `nr_dirty_this_bf >> bdi_dirty_limit` | 单设备 IO 背压 | 检查该设备 IO 性能 |
| `allocstall_normal` 或 `allocstall_movabled` > 0 | 分配路径 stall | 检查水位 + 碎片 |
| `SReclaimable` > 50% MemTotal | slab 缓存膨胀 | 检查 vfs_cache_pressure |
| `pgsteal/pgscan < 0.7` | 回收效率低 | 检查不可回收页比例 |
| `nr_writeback` 持续 > 0 无下降 | 回写卡住 | 检查 BDI + 设备 IO |
