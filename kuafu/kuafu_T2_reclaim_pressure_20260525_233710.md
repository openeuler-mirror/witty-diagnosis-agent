# T2: 内存回收压力 / 内存抖动风险诊断报告

**诊断时间**: 2026-05-25 23:37 UTC  
**目标容器**: pcr-pc  
**诊断类型**: 在线只读探测  
**故障背景**: Page Cache 过高 (Cached=8,726,280 kB, 54.6% MemTotal)，需评估回收压力与抖动风险

---

## 1. 关键配置参数

| 参数 | 当前值 | 默认值 | 说明 |
|------|--------|--------|------|
| `vm.vfs_cache_pressure` | **100** | 100 | 默认值，VFS cache 回收压力未调优 |
| `vm.swappiness` | **60** | 60 | 默认值，倾向于回收匿名页 → Page Cache |
| `vm.min_free_kbytes` | **45,056 kB** | auto | ~0.28% MemTotal (15.99 GB)，偏低但非异常 |

**分析**: 三项核心调优参数均为默认值。在 Page Cache 占比 54.6% 的场景下，`swappiness=60` 意味着回收时 Page Cache 和匿名页的回收优先级相当，回收 Page Cache 在预期之内。

---

## 2. Slab（内核内存）分析

### 2.1 /proc/meminfo Slab 相关字段

| 字段 | 值 (kB) | 占比 |
|------|---------|------|
| MemTotal | 15,986,876 | 100% |
| Slab | 304,084 | **1.90%** |
| SReclaimable | 191,528 | 1.20% (63.0% of Slab) |
| SUnreclaim | 112,556 | 0.70% (37.0% of Slab) |
| KernelStack | 8,464 | 0.05% |
| PageTables | 7,956 | 0.05% |

**结论**: Slab 总量 304 MB，占物理内存仅 1.90%，**Slab 层面不存在过度开销**。可回收 slab (SReclaimable) 占比 63%，回收效率良好。

### 2.2 dentry/inode slab 用量 Top 10

```
dentry             34,146 obj × 192 B = ~6.4 MB  ( 813 slabs, active)
ext4_inode_cache    3,309 obj × 1168 B = ~3.7 MB ( 129 slabs, active)
shmem_inode_cache   3,167 obj × 784 B  = ~2.4 MB (  78 slabs, active)
sock_inode_cache    1,404 obj × 832 B  = ~1.1 MB (  36 slabs, active)
mqueue_inode_cache    510 obj × 960 B  = ~0.5 MB (  15 slabs, active)
fuse_inode            273 obj × 832 B  = ~0.2 MB (   7 slabs, active)
nfs_inode_cache         0 obj                      (   0 slabs, unused)
xfs_inode               0 obj                      (   0 slabs, unused)
ext2_inode_cache        0 obj                      (   0 slabs, unused)
udf_inode_cache         0 obj                      (   0 slabs, unused)
```

**结论**: dentry 缓存共 34,146 个对象约 6.4 MB，ext4_inode_cache 约 3.7 MB，均处于极低水平。**不存在 dentry/inode 膨胀问题**。

---

## 3. 内存回收扫描统计 (/proc/vmstat)

### 3.1 扫描统计

| 指标 | 值 | 说明 |
|------|-----|------|
| pgscan_kswapd | 7,891,748 | kswapd 后台回收扫描页数 |
| pgscan_direct | 2,445,150 | 直接回收扫描页数 |
| pgscan_khugepaged | 0 | 大页回收扫描 |
| **pgscan_total** | **10,336,898** | 历史总扫描 |
| pgscan_anon | 9,804,683 | 匿名页扫描 (94.8%) |
| pgscan_file | 532,215 | 文件页扫描 (5.2%) |

### 3.2 回收统计

| 指标 | 值 | 说明 |
|------|-----|------|
| pgsteal_kswapd | 2,007,684 | kswapd 后台回收页数 |
| pgsteal_direct | 349,083 | 直接回收页数 |
| pgsteal_khugepaged | 0 | |
| **pgsteal_total** | **2,356,767** | 历史总回收 |
| pgsteal_anon | 2,046,472 | 匿名页回收 (86.8%) |
| pgsteal_file | 310,295 | 文件页回收 (13.2%) |

### 3.3 回收效率分析

| 回收路径 | Scan | Steal | 效率 (Steal/Scan) | 评级 |
|----------|------|-------|-------------------|------|
| kswapd (后台) | 7,891,748 | 2,007,684 | **25.4%** | 中等 |
| direct (直接回收) | 2,445,150 | 349,083 | **14.3%** | 偏低 |
| anon (匿名页) | 9,804,683 | 2,046,472 | 20.9% | 中等 |
| file (文件页) | 532,215 | 310,295 | **58.3%** | 良好 |
| **全局** | **10,336,898** | **2,356,767** | **22.8%** | 中等 |

### 3.4 kswapd 水线触发统计

| 指标 | 值 | 风险 |
|------|-----|------|
| kswapd_high_wmark_hit_quickly | 22 | 极低 (历史累计) |
| kswapd_low_wmark_hit_quickly | 4 | 极低 |
| kswapd_inodesteal | 229 | 极低 |

**关键发现**:
1. **扫描以匿名页为主 (94.8%)**，文件页扫描仅 5.2%。这与 Cached 高达 8.7 GB 形成对比——说明当前内核**没有主动回收 Page Cache**，Page Cache 留存是合理的。
2. 直接回收 (direct reclaim) 占扫描总量 23.6%，效率仅 14.3%，**历史上存在一定直接回收压力**，但从 kswapd 水线触发次数来看，压力是历史累积，非持续活跃。
3. 文件页回收效率 58.3% **远优于**匿名页回收效率 20.9%，说明 Page Cache 回收是相对高效的。

---

## 4. PSI 内存压力指标

| 时间窗口 | some 压力 | full 压力 |
|----------|-----------|-----------|
| avg10 | **0.00** | **0.00** |
| avg60 | **0.00** | **0.00** |
| avg300 | **0.00** | **0.00** |

```
some avg10=0.00 avg60=0.00 avg300=0.00 total=3690070
full avg10=0.00 avg60=0.00 avg300=0.00 total=3656733
```

**结论**: 当前所有时间窗口内 PSI 均为 0.00，**当前无任何内存压力感知**。total 值 (some=3,690,070us, full=3,656,733us) 表示自容器启动以来累计阻塞时间，约 1 小时的总量（取决于运行时长），需结合 uptime 判断是否为近期累积。

---

## 5. Page Cache 辅助诊断

| 字段 | 值 (kB) | 说明 |
|------|---------|------|
| MemTotal | 15,986,876 | 物理内存总量 |
| MemAvailable | 15,058,384 | **94.2%** 可用 |
| Cached | 5,910,184 | 实际当前 Cached (非原始报告的 8.7GB) |
| Buffers | 11,660 | |
| Active(file) | 70,708 | 活跃文件页极小 |
| Inactive(file) | 5,848,776 | 非活跃文件页占 Cached 的 99% |
| Active(anon) | 96,772 | |
| Inactive(anon) | 179,800 | |
| Dirty | 656 | 脏页极少，IO 写入压力低 |
| Writeback | 0 | 无回写压力 |

**关键发现**:
1. **Cached 实际值 5,910 MB (37.0%)**，较原始报告的 8.7 GB 有下降，说明容器 Page Cache 存在波动。
2. **Inactive(file) 占 Cached 的 99%**，意味着几乎所有 Page Cache 都在非活跃链表上，**随时可回收**，不会产生显著回收延迟。
3. **MemAvailable = 14.4 GB / 94.2%**，系统内存充裕，无需紧急回收。
4. Dirty = 656 kB，Writeback = 0，IO 写入通道无积压。

---

## 6. 综合风险评估

| 风险项 | 评分 | 说明 |
|--------|------|------|
| 回收效率 | 🟢 低风险 | 文件页回收效率 58.3%，全局 22.8% |
| PSI 压力 | 🟢 低风险 | 所有窗口 avg10/60/300 = 0.00 |
| Slab 膨胀 | 🟢 低风险 | Slab/MemTotal = 1.90%，无膨胀 |
| dentry/inode 膨胀 | 🟢 低风险 | dentry 仅 6.4 MB |
| 直接回收历史 | 🟡 中低风险 | 历史 direct reclaim 累积但当前无活动 |
| Page Cache 可回收性 | 🟢 低风险 | 99% 在 Inactive(file)，回收代价低 |
| IO 抖动风险 | 🟢 低风险 | Dirty=656KB, Writeback=0, 无 IO 积压 |
| **综合风险** | **🟢 低** | **当前无内存回收压力，无抖动风险** |

---

## 7. 结论与建议

### 诊断结论
1. **当前无内存回收压力**: PSI 全窗口 0.00，kswapd 水线触发次数极低。
2. **Page Cache 可安全回收**: Inactive(file) 占比 99%，回收无需写回 (Dirty=656KB)。
3. **历史存在轻度直接回收**: pgscan_direct 占 23.6%，效率 14.3%，但为历史累积，不影响当前状态。
4. **Slab 健康**: Slab 仅占 1.90% MemTotal，dentry/inode 无膨胀。
5. **调优参数均为默认值**: swappiness=60, vfs_cache_pressure=100, min_free_kbytes=45056 kB。

### 建议
- **无需紧急调优**: 当前内存充裕 (MemAvailable=14.4GB)，Page Cache 99% 可回收。
- **可选优化**: 如果应用对 IO 延迟极其敏感，可适度降低 swappiness (如 `vm.swappiness=30`) 以减少未来可能的 Page Cache 回收触发。
- **持续监控**: 关注 Cached 波动趋势和 PSI full 压力的变化，建立基线后再决定是否调优。

---

**报告生成时间**: 2026-05-25 23:37:10 UTC  
**执行命令数**: 7 项诊断检查  
**诊断状态**: ✅ 全部通过
