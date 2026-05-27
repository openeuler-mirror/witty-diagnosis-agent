# T1 诊断结果: 验证 OOM (Out of Memory)

**执行时间**: 2026-05-25 22:40 UTC
**目标容器**: pcr-witty (docker exec)

---

## 1. /proc/vmstat - 内存回收计数器

| 计数器 | 值 | 说明 |
|--------|------|------|
| allocstall_normal | 2400 | 普通 zone 分配 stall 次数 — 严重 |
| allocstall_movable | 4666 | Movable zone 分配 stall 次数 — 非常严重 |
| allocstall_dma32 | 0 | 正常 |
| pgscan_kswapd | 7,891,748 | kswapd 扫描 7.9M 页 |
| pgscan_direct | 2,445,150 | 直接回收扫描 2.4M 页 — 直接回收频繁触发 |
| pgscan_anon | 9,804,683 | 匿名页扫描占绝大多数 |
| pgscan_file | 532,215 | 文件页扫描较少 |
| pgsteal_kswapd | 2,007,684 | kswapd 回收 2.0M 页 |
| pgsteal_direct | 349,083 | 直接回收 349K 页 |
| pgsteal_anon | 2,046,472 | 匿名页回收 2.0M |
| pgsteal_file | 310,295 | 文件页回收 310K |
| pgpgin | 4,949,409 | 换入约 19.8GB |
| pgpgout | 31,531,452 | 换出约 126GB — 大量换出 |
| kswapd_low_wmark_hit_quickly | 4 | kswapd 低水位快速命中 |
| kswapd_high_wmark_hit_quickly | 22 | kswapd 高水位快速命中 |
| pageoutrun | 29 | kswapd 实际扫描运行次数 |
| pgmajfault | 40,198 | 严重缺页中断数较高 |
| slabs_scanned | 364,705 | slab 扫描次数 |

**结论**: allocstall 合计 7,066 次，pgscan 总计 10.3M 页（约 40GB），表明系统承受了极端的直接内存回收压力。

---

## 2. /proc/meminfo - 当前内存状态

| 指标 | 值 (kB) | 说明 |
|------|---------|------|
| MemFree | 15,079,624 | 约 14.4GB 空闲 |
| MemAvailable | 15,145,692 | 约 14.4GB 可用 |
| Cached | 231,624 | 约 226MB page cache |
| Active(file) | 56,396 | 约 55MB 活跃文件页 |
| Inactive(file) | 178,940 | 约 175MB 非活跃文件页 |
| Dirty | 192 | 极少量脏页 |
| Writeback | 0 | 无回写 |
| Unevictable | 0 | 无不可回收页 |
| PageTables | 6,692 | 约 6.5MB 页表（当前正常） |
| Committed_AS | 2,292,276 | 约 2.2GB 已承诺内存 |
| VmallocTotal | 34,359,738,367 | 32TB vmalloc 空间 |
| VmallocUsed | 38,272 | 约 37MB vmalloc 已使用 |

**当前状态**: 空闲内存充足（~14.4GB），page cache 正常（~226MB），没有内存压力。**故障期间的内存压力已经消退**，当前容器处于低负载状态。

---

## 3. /proc/zoneinfo - Watermark 与 LRU 链表

### DMA32 zone (0~4GB)
- free: 996,637 pages (~3.8GB) >> high watermark (4,811)
- min: 2,815 | low: 3,813 | high: 4,811
- LRU: inactive_anon=432, active_anon=23, inactive_file=0, active_file=0
- **当前水位远高于 high watermark，无压力**

### Normal zone (4GB~16GB)
- free: 2,773,483 pages (~10.6GB) >> high watermark (14,438)
- min: 8,448 | low: 11,443 | high: 14,438
- LRU: inactive_anon=39,684, active_anon=25,646, inactive_file=44,754, active_file=14,330
- **当前水位远高于 high watermark，无压力**

**结论**: 故障高峰期已过，当前所有 zone 的空闲页远高于 high watermark，无内存回收压力。但在故障期间，kswapd 低水位被快速命中 4 次、高水位被快速命中 22 次，说明当时水位曾剧烈波动。

---

## 4. dmesg - OOM Killer 日志

### 第一次 OOM (14:34:44 UTC)
```
PID: 20893, Comm: fault_reclaim_s
total-vm: 6,556,265,176 kB (~6.5TB)
anon-rss: 8,798,976 kB (~8.4GB)
file-rss: 384 kB
pgtables: 6,427,712 kB (~6.1GB)
swapents: 1,001,504
```

### 第二次 OOM (14:39:51 UTC)
```
PID: 21383, Comm: fault_reclaim_s
total-vm: 6,538,320,600 kB (~6.5TB)
anon-rss: 8,799,872 kB (~8.4GB)
file-rss: 256 kB
pgtables: 6,410,112 kB (~6.1GB)
swapents: 992,576
```

**关键发现**:
- 两个进程的虚拟内存都是荒谬的 6.5TB（远超系统物理内存 16GB）
- page tables 占用约 6.1~6.4GB 物理内存 — **这是导致 OOM 的直接原因**
- 一个 page table entry 约 8 字节，6.4GB page tables 意味着约 860M 个 VMA 映射条目
- 容器 cgroup memory.max=max（无硬限制），OOM 为全局 OOM

---

## 5. cgroup v2 memory.stat - 容器级回收统计

| 计数器 | 值 (字节) | 说明 |
|--------|-----------|------|
| inactive_file | 8,351,744 | ~8MB 非活跃文件页 |
| active_file | 5,816,320 | ~5.5MB 活跃文件页 |
| pgscan (总计) | 4,844,353 | cgroup 级别扫描 4.8M 页 |
| pgscan_kswapd | 3,383,230 | kswapd 扫描 3.4M |
| pgscan_direct | 1,461,123 | 直接回收扫描 1.5M |
| pgsteal (总计) | 983,273 | 回收 983K 页 |
| pgsteal_kswapd | 846,985 | |
| pgsteal_direct | 136,288 | |
| workingset_refault_file | 444 | 文件页 refault |
| workingset_refault_anon | 154 | 匿名页 refault |

**结论**: cgroup 级别也记录了显著的直接回收活动（1.5M 页直接扫描），与系统级 vmstat 一致。

---

## 6. /proc/pressure/memory - 内存压力

```
some avg10=0.00 avg60=0.01 avg300=0.26 total=3,690,070
full avg10=0.00 avg60=0.01 avg300=0.25 total=3,656,733
```

- **some total**: 3,690,070 (some 压力累计)
- **full total**: 3,656,733 (full 压力累计)
- 当前瞬时压力极低（avg10=0.00），但累计总压力值较大，表明**故障期间曾经历长时间内存 stall**

---

## 综合结论

### T1: 验证 OOM (Out of Memory) ✅

| 证据 | 状态 |
|------|------|
| allocstall_normal=2400, allocstall_movable=4666 | ✅ 确认直接分配 stall |
| pgscan_direct=2,445,150, pgscan_kswapd=7,891,748 | ✅ 确认大量直接回收 + kswapd 回收 |
| pgsteal 仅 2.4M vs pgscan 10.3M（回收率 23%） | ✅ 确认回收效率低下 |
| dmesg 明确 2 次 OOM killer 触发 | ✅ 确认 OOM 事件 |
| page tables 占用 6.4GB 物理内存 | ✅ OOM 根因：异常 page tables 消耗 |
| 虚拟内存 6.5TB（远超物理内存） | ✅ 进程异常行为 |
| memory.max=max (无限制) | ✅ cgroup 未阻挡 |

**根因链路**: `fault_reclaim_s` 进程异常分配 6.5TB 虚拟地址空间 → page tables 膨胀至 6.4GB 物理内存 → 触发全局 direct reclaim + OOM killer → 进程被杀死

**Completed: T1**
