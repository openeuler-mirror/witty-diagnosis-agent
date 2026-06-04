# 内存泄漏故障场景分类

## 场景列表

| 场景标签 | 中文描述 | 主要特征与案例 |
|---------|---------|--------------|
| `RSS_GROWTH` | 用户态进程 RSS 持续增长 | ① `ps aux` 或 `top` 中进程 RSS 随时间递增不回落；② 进程重启后 RSS 从低值重新增长；③ 最终触发 OOM killer 或进程被系统杀掉 |
| `ANON_PAGE_LEAK` | 匿名页泄漏 | ① `/proc/[pid]/smaps` 中匿名页 (Anonymous) 持续增长；② `cat /proc/[pid]/status | grep VmRSS` 持续上升；③ pmap -x 显示 heap 段内存异常 |
| `HEAP_PROFILER` | Valgrind/ASan 报告堆泄漏 | ① valgrind memcheck 输出 `definitely lost` / `indirectly lost`；② AddressSanitizer 报告 `direct leak`；③ heap profile 显示持续分配未释放 |
| `SLAB_LEAK` | Slab 内存泄漏 | ① `slabtop` 显示特定 slab 缓存持续增长（如 `kmalloc-*`、`dentry`、`inode_cache`）；② `/proc/slabinfo` 中 active_objs > num_objs 且持续上升；③ `meminfo` 中 Slab 字段持续增加 |
| `VMALLOC_LEAK` | vmalloc 泄漏 | ① `/proc/vmallocinfo` 显示大量未释放的 vmalloc 区域；② `VmallocUsed` 在 `/proc/meminfo` 中持续增长；③ 模块加载/卸载后 vmalloc 区域未回收 |
| `KMALLOC_LEAK` | kmalloc 未释放 | ① `/proc/slabinfo` 中 `kmalloc-*` 缓存 active 对象持续增长；② `kmemleak` 报告 unreferenced objects；③ 特定内核模块反复分配小内存未释放 |
| `MEMCG_LEAK` | Memory cgroup 泄漏 | ① `memory.usage_in_bytes` 持续增长，但进程 RSS 未同步增长；② `memory.kmem.usage_in_bytes` 异常高；③ cgroup 内存回收后 usage 不回落 |

## 场景关联性

| 关联模式 | 典型链路 |
|---------|---------|
| RSS 增长 → 匿名页泄漏 | 进程 heap/anon 页增长必然导致 RSS 上升，先定位哪个区域在涨 |
| 用户态泄漏 → OOM killer | 用户态内存泄漏达到上限触发 OOM，需区分是进程限制还是系统级 OOM |
| Slab 泄漏 → 内核内存碎片 | slab 长时间泄漏会导致伙伴系统碎片化，影响大页分配 |
| vmalloc 泄漏 → 内核模块异常 | 频繁加载/卸载的内核模块若不释放 vmalloc 内存，最终分配失败 |
| Memcg 泄漏 → 容器 OOM | 容器内 slab 或匿名页泄漏导致 cgroup memory limit 命中 |
