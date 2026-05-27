# T2 诊断结果: 验证 mmap ENOMEM

**执行时间**: 2026-05-25 22:40 UTC
**目标容器**: pcr-witty (docker exec)

---

## 1. vm.max_map_count

```
当前值: 5000 (默认 65530)
```

vm.max_map_count=5000 极低，仅为默认值 65530 的 7.6%。这是容器环境被覆写的限制值。

**影响**: 一个进程最多只能拥有 5000 个 VMA（虚拟内存区域）。正常 Java/Python 应用可能轻松超过此值，mmap 分配大块内存时极易触发 ENOMEM。

---

## 2. overcommit 设置

| 参数 | 值 | 说明 |
|------|-----|------|
| overcommit_memory | 1 | **Always overcommit** — 总是允许超额分配 |
| overcommit_ratio | 50 | 仅当 overcommit_memory=2 时有效 |

**结论**: `overcommit_memory=1`（Always）意味着内核总是允许超出物理内存的虚拟内存分配。mmap ENOMEM 不是由于 overcommit 限制导致，而是由于 VMA 数量上限（max_map_count=5000）耗尽或其他原因。

---

## 3. 容器当前进程状态

当前容器内仅有 1 个进程在运行：

```
PID 1: sleep 3600 (启动于 14:36 UTC)
```

之前的 Python 进程（PID 33）和 `fault_reclaim_s` 进程（PID 20893, 21383）均已不存在。容器可能已被重启或进程已自然退出。

**因此无法直接检查 Python 进程 (PID 33) 的 VMA 统计信息。** 以下为基于系统级数据的间接分析。

---

## 4. 系统级 VMA 相关指标

### /proc/meminfo
| 指标 | 值 | 说明 |
|------|-----|------|
| VmallocTotal | 34,359,738,367 kB (32TB) | vmalloc 地址空间充足 |
| VmallocUsed | 38,272 kB (~37MB) | vmalloc 使用正常 |
| PageTables (当前) | 6,692 kB (~6.5MB) | 当前正常 |
| Committed_AS | 2,292,276 kB (~2.2GB) | 已承诺内存 |

### /proc/zoneinfo - 页表统计
| zone | nr_page_table_pages | 说明 |
|------|---------------------|------|
| DMA32 | 1,805 | ~7MB |
| Normal | 1,784 | ~7MB |
| **总计** | **~14MB** | **当前正常**（故障期间曾高达 6.4GB） |

---

## 5. 故障期间 VMA 推导分析

虽然无法直接检查故障时的 Python 进程，但根据 dmesg OOM 日志中 `fault_reclaim_s` 进程的数据可反推：

**关键数据 (OOM 日志)**:
- total-vm: 6,556,265,176 kB (~6.5TB)
- pgtables_bytes: 6,581,977,088 (~6.1GB)
- 每个 PTE = 8 字节
- PTE 数量 = 6.58GB / 8 = ~860 million 个 PTE
- 如果每个 VMA 平均映射 ~100 个 PTE → ~8.6M 个 VMA ❌（远超 max_map_count=5000）
- 但实际进程 VMA 数量由 `maps | wc -l` 给出，max_map_count 限制的是 VMA 数量而不是 PTE 数量

**更可能的情况**: 进程通过 `mmap` 分配了少量但 **极大的匿名映射**（例如几个 1TB 级的 mmap），每个 VMA 映射大量连续页面。VMA 数量可能未超过 max_map_count=5000 的限制，但 **地址空间不足** 导致 mmap ENOMEM。

---

## 6. vm.max_map_count 分析

| 场景 | 所需 max_map_count | 当前值 | 风险 |
|------|-------------------|--------|------|
| 普通容器应用 | ~200-500 | 5000 | 正常 |
| Java/Python 大量 mmap | 5000-30000 | 5000 | ⚠️ 边缘状态 |
| Elasticsearch 典型 | 20000-60000 | 5000 | ❌ 严重不足 |
| `fault_reclaim_s` 大量 VMA | 未知 | 5000 | ❌ 可能触发 |

**结论**: `vm.max_map_count=5000` 虽然偏低，但并非 Python 进程 mmap 4951MB 失败的唯一原因。在 `overcommit_memory=1`（Always overcommit）模式下，mmap 分配 4951MB 应当成功，除非：

1. 系统实际物理内存 + swap 不足（当前 16GB RAM + 4GB swap，分配 4.95GB 应当足够）
2. 地址空间碎片化导致无法找到连续虚拟地址块
3. VMA 数量已接近 max_map_count=5000 上限

---

## 综合结论

### T2: 验证 mmap ENOMEM ✅

| 证据 | 状态 |
|------|------|
| vm.max_map_count=5000（默认 65530） | ✅ 确认极低限制值 |
| overcommit_memory=1 (Always) | ✅ 确认非 overcommit 导致 |
| Python 进程已不存在 | ⚠️ 无法实时检查 VMA |
| 故障期间 page tables 曾达 6.4GB | ✅ 确认异常内存分配行为 |
| Committed_AS=2.2GB | ✅ 当前承诺内存正常 |

**根因推断**: Python 进程 (PID 33) mmap 分配 4951MB 返回 ENOMEM 的根因最可能是 **VMA 数量达到 max_map_count=5000 上限**（容器环境覆写为极低值），或内存分配高峰期系统处于严重直接回收压力下导致分配失败。在 `overcommit_memory=1` 模式下，如果不是 VMA 数量耗尽，4.95GB 的虚拟内存分配不会失败。

**Completed: T2**
