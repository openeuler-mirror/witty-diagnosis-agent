# 内核 Swap 相关参数与 mm/ 子系统源码参考

## 内核可调参数（sysctl）

### vm.swappiness（核心参数）

| 参数 | 类型 | 默认值 | 范围 |
|------|------|--------|------|
| `vm.swappiness` | int | 60 | 0–200 |

**含义**：控制内核回收匿名页（swap out）相对文件页（page cache reclaim）的**倾向性**。

- **值越低**（倾向于 0）：尽量回收文件页缓存，少 swap out 匿名页
- **值越高**（倾向于 200）：更积极 swap out 匿名页，保留文件页缓存

**注意**：swappiness 是**倾向性权重**而非开关。即使 swappiness=0，在内存极端紧张（水位线以下）时内核仍然会进行匿名页回收。只有在 **CONFIG_MEMCG=y** 且 cgroup 内 `memory.swappiness=0` 时才能真正禁止 cgroup 内的 swap。

**内核源码路径**：
```c
/* mm/vmscan.c */
/* swappiness 在 shrink_lruvec() 中参与匿名页 vs 文件页扫描比例计算 */
struct scan_control {
    ...
    /* 扫描比例 = swappiness / (swappiness + 200) */
};
```

### vm.min_free_kbytes

| 参数 | 类型 | 默认值 | 范围 |
|------|------|--------|------|
| `vm.min_free_kbytes` | int | 动态计算（约 0.04% * 总内存） | 128–64M |

**含义**：保留最少空闲内存（KB），仅在紧急分配时可用。直接影响**水位线（watermark）**的 `min` 值。

- 影响 `watermark[min]` / `watermark[low]` / `watermark[high]` 三个水位线
- 值越大 → 水位线越高 → 更早触发放逐/reclaim → 更早 swap

**内核源码路径**：
```c
/* mm/page_alloc.c */
/* init_per_zone_wmark_min() 根据 min_free_kbytes 计算水位线 */
/* setup_per_zone_wmarks() 将 min_free_kbytes 分配到各 zone */
```

### vm.watermark_scale_factor

| 参数 | 类型 | 默认值 | 范围 |
|------|------|--------|------|
| `vm.watermark_scale_factor` | int | 10（万分之一） | 1–1000 |

**含义**：控制 `low` 和 `high` 水位线之间的距离（相对 `min` 的倍数）。

- `watermark[low] = watermark[min] + watermark_scale_factor * 0.0001 * available_memory`
- 因子越大 → `low` 和 `high` 越高 → 更早唤醒 kswapd → swap 更积极
- 大内存系统（数百 GB）默认值可能太小，导致 kswapd 唤醒不及时

### vm.vfs_cache_pressure

| 参数 | 类型 | 默认值 | 范围 |
|------|------|--------|------|
| `vm.vfs_cache_pressure` | int | 100 | 0–1000 |

**含义**：控制回收 dentry/inode 缓存的力度。

- 值 > 100：更激进回收 VFS 缓存
- 值 < 100：更倾向于保留 VFS 缓存（可能迫使内核更多 swap out）
- 值 = 0：内核几乎永不回收 VFS 缓存

### vm.overcommit_memory & vm.overcommit_ratio

| 参数 | 类型 | 默认值 | 范围 |
|------|------|--------|------|
| `vm.overcommit_memory` | int | 0 | 0–2 |
| `vm.overcommit_ratio` | int | 50 | 0–100 |

- **0（启发式）**：允许合理 overcommit，基于估算
- **1（总是）**：永远允许 overcommit → OOM 风险增大，swap 可能被快速填满
- **2（禁止 overcommit）**：限制提交地址空间 = swap + RAM * ratio / 100

### vm.dirty_ratio & vm.dirty_background_ratio

| 参数 | 类型 | 默认值 |
|------|------|--------|
| `vm.dirty_ratio` | int | 20（%可用内存）|
| `vm.dirty_background_ratio` | int | 10（%可用内存）|

**与 swap 的关系**：当 dirty_ratio 设置过高时，大量内存被脏页占用（不可回收），内核被迫 swap out 匿名页来释放内存。这是 **swappiness 配置正确但仍然大量 swap** 的常见原因。

### vm.zone_reclaim_mode

| 参数 | 类型 | 默认值 | 范围 |
|------|------|--------|------|
| `vm.zone_reclaim_mode` | int | 0 | 0–15（bitmap）|

**含义**：控制 NUMA 节点内存回收行为。

- 0：允许跨节点分配（默认）
- 1：优先从本节点回收
- 2：允许本节点 swap out
- 4：允许本节点脏页 writeback

**与 swap 的关系**：在 NUMA 系统中，zone_reclaim_mode=1 可能导致一个节点大量 swap 而其他节点空闲（需要检查 `numactl --hardware` 和 `/proc/zoneinfo`）。

---

## 内存管理关键数据结构（mm/ 源码分析用）

### struct zone（/proc/zoneinfo 的内核映射）

```c
/* include/linux/mmzone.h */
struct zone {
    unsigned long watermark[NR_WMARK];  // [WMARK_MIN, WMARK_LOW, WMARK_HIGH]
    long lowmem_reserve[MAX_NR_ZONES];  // 跨 zone 保留
    struct pglist_data *zone_pgdat;     // 所属 NUMA 节点
    struct per_cpu_pageset *pageset;    // 每 CPU 页缓存
    /* 空闲页统计 */
    struct free_area free_area[MAX_ORDER];
    /* 水位线使用的保护 */
    unsigned long zone_start_pfn;
    atomic_long_t managed_pages;
};
```

### struct scan_control（reclaim 控制参数）

```c
/* mm/vmscan.c */
struct scan_control {
    /* 扫描目标 */
    unsigned long nr_to_reclaim;     // 目标回收页数
    gfp_t gfp_mask;                  // 分配掩码
    /* 扫描范围 */
    int may_writepage;               // 是否允许页面写出
    int may_unmap;                   // 是否允许回收映射页
    int may_swap;                    // 是否允许 swap
    int proactive;                   // 是否为主动回收
    /* 追踪 */
    unsigned long nr_scanned;        // 已扫描页数
    unsigned long nr_reclaimed;      // 已回收页数
    /* 优先级控制 */
    unsigned int priority;           // 扫描优先级（0–12，0最高）
    /* 内存 cgroup */
    struct mem_cgroup *target_mem_cgroup;
};
```

### kswapd 唤醒机制

```c
/* mm/vmscan.c */
/* 核心唤醒路径：allocate_pages() → wake_all_kswapds() */
/* 检查逻辑：当前 zone 空闲页 < watermark[low] + 分配请求预留 */

/* kswapd 主循环 */
int kswapd(void *p) {
    while (true) {
        /* 检查所有 zone 是否需要 reclaim */
        for (每个 zone) {
            if (balanced(zone, ...)) continue;
            balance_pgdat(pgdat, order, classzone_idx);
        }
        /* 没有需要 reclaim 的 zone → 睡眠 */
        wait_event_freezable(...);
    }
}

/* balance_pgdat() 内部 */
static unsigned long balance_pgdat(pg_data_t *pgdat, ...) {
    do {
        /* 升高扫描优先级（每次循环扫描更多页） */
        sc.priority--;
        /* shrink_node() 收缩 LRU 链表 */
        shrink_node(pgdat, &sc);
    } while (仍然高于水位线 && priority > 0);
}
```

---

## /proc/vmstat 关键字段解读

| 字段 | 含义 | 正常范围 | 预警值 |
|------|------|---------|--------|
| `pgscan_kswapd` | kswapd 扫描页数 | 持续增长 | 单次唤醒扫描 > 10万页 |
| `pgscan_direct` | direct reclaim 扫描页数 | 接近 0 | > 0 说明内存压力大 |
| `pgsteal_kswapd` | kswapd 回收页数 | 接近 pgscan | 远小于 pgscan → 无效扫描 |
| `pgsteal_direct` | direct reclaim 回收页数 | 接近 0 | > 0 说明严重延迟 |
| `allocstall` | 分配 stall（进程等待内存）次数 | 接近 0 | 任何非零值都需关注 |
| `pgpgin` | 从磁盘/swap 读入页数 | 系统依赖 | 持续增长 |
| `pgpgout` | 写回磁盘/swap 页数 | 系统依赖 | 突发暴增 |
| `pswpin` | swap in 次数 | 低 | 持续 > 100/s |
| `pswpout` | swap out 次数 | 低 | 持续 > 100/s |
| `pgmajfault` | 主缺页（需磁盘 I/O） | 低 | 与 swap in 强相关 |
| `compact_stall` | 内存压缩 stall 次数 | 0 | > 0 说明碎片化 |
| `compact_fail` | 压缩失败次数 | 0 | 增长 → 碎片化严重 |
| `oom_kill` | OOM 击杀次数 | 0 | 任何 > 0 都需立即响应 |

---

## 内核水印水位线（Watermark）计算

```
watermark[min] = min_free_kbytes / num_zones
watermark[low] = watermark[min] + (watermark[min] / 4)
watermark[high] = watermark[min] + (watermark[min] / 2)

# 大致影响：
# min → low: 进入 kswapd reclaim 区域（内核逐步回收）
# low → high: kswapd 持续工作直到回到 high 以上
# < min: 只有 PF_MEMALLOC 可以分配，系统进入 direct reclaim
```

**实际查看**：
```bash
cat /proc/zoneinfo | grep -E "Node|zone|min|low|high|scanned|reclaim"
```

---

## NUMA 与 Swap 的关联

### 检查 NUMA 节点内存分布
```bash
numactl --hardware
numastat -p <PID>
cat /proc/zoneinfo | grep -A20 "Node 0, zone"
```

### NUMA swap 失衡的典型场景
- 进程绑定 CPU 在 Node 0，分配内存都在 Node 0
- Node 1 大量空闲但 Node 0 在 swap
- `numastat` 的 `allocation_miss` 持续增长

### 修复方向
- 使用 `numactl --membind` 或 `--interleave` 均衡内存分配
- 检查 `vm.zone_reclaim_mode` 配置
- 应用层使用 `libnuma` 进行亲和性设置

---

## 关键内核代码路径快查

| 功能 | 内核文件 | 关键函数 |
|------|---------|---------|
| kswapd 主循环 | mm/vmscan.c | `kswapd()` → `balance_pgdat()` → `shrink_node()` |
| LRU 扫描与回收 | mm/vmscan.c | `shrink_lruvec()` → `shrink_list()` → `shrink_active_list()` / `shrink_inactive_list()` |
| swap out 单页 | mm/vmscan.c | `try_to_unmap()` → `pageout()` → `swap_writepage()` |
| swap in 缺页 | mm/memory.c | `do_swap_page()`（缺页处理主函数） |
| swap 设备管理 | mm/swapfile.c | `get_swap_page()` / `swap_info_get()` / `swap_readpage()` |
| zswap 压缩写入 | mm/zswap.c | `zswap_frontswap_store()` → `zswap_pool_compress()` |
| zswap 读取解压 | mm/zswap.c | `zswap_frontswap_load()` → `zswap_pool_decompress()` |
| zram 驱动 | drivers/block/zram/zram_drv.c | `zram_write()` / `zram_read()` / `zram_bvec_write()` |
| OOM Killer 选择 | mm/oom_kill.c | `select_bad_process()` → `oom_badness()` → `__oom_kill_process()` |
| 水印检查 | mm/page_alloc.c | `zone_watermark_ok()` / `__zone_watermark_ok()` |
| direct reclaim | mm/page_alloc.c | `__alloc_pages_may_oom()` → `__perform_reclaim()` |
| LRU 链表管理 | mm/swap.c | `lru_add()` / `lru_deactivate()` / `deactivate_page()` |
| PSI 压力 | kernel/sched/psi.c | `psi_mem_stall()` / `psi_io_stall()` |
