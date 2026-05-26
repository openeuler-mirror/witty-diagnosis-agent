# mmap/VMA 故障场景分类

mmap/VMA 故障诊断过程中，主要涉及以下六大核心故障场景：

| 场景标签 | 中文描述 | 主要特征与案例 |
| :--- | :--- | :--- |
| `MMAP_MAPCOUNT_EXHAUST` | vm.max_map_count 耗尽 | ① mmap 返回 ENOMEM；② `/proc/<PID>/maps` 行数 ≥ `vm.max_map_count`；③ Elasticsearch 在大量索引/分片场景下最常见；④ Java MappedByteBuffer 持续创建未释放 |
| `MMAP_SIGBUS_TRUNCATE` | 文件截断导致 SIGBUS | ① 进程收到 signal 7 (SIGBUS) core dump；② 对应文件已被截断至映射范围以下；③ 常见于日志轮转（logrotate）程序截断正在映射的文件、共享文件被并发 truncate |
| `MLOCK_LIMIT_EXCEEDED` | mlock 锁定内存超限 | ① mlock/mlockall 返回 ENOMEM；② `VmLck` = `ulimit -l`；③ 常见于 Elasticsearch bootstrap.memory_lock=true 且 MemLockLimit 不足；④ 实时应用（DPDK/声卡驱动）mlock 失败 |
| `SHM_PERMISSION_DENIED` | 共享内存映射权限拒绝 | ① shmget/shmat 返回 EACCES/EPERM；② `ipcs -m` 目标段权限不足；③ 跨用户/容器进程共享内存失败；④ 容器化场景下 shm_size 限制 |
| `VMA_FRAGMENTATION` | 进程地址空间碎片化 | ① 大块 mmap 返回 ENOMEM 但总地址空间充足；② 大量小 VMA 将地址空间分割为碎块；③ 常见于长时间运行的高并发服务、频繁 dlopen/dlclose 的应用 |
| `MMAP_GENERIC_FAILURE` | 通用 mmap 失败 | ① MAP_FAILED 返回但非 ENOMEM；② 包含 EACCES/EINVAL/ENFILE/ENODEV/EOVERFLOW/EPERM 等；③ 需要按 errno 分类排查 |

## 场景关联性

多个故障场景可能同时存在或具有因果关系：

| 关联模式 | 典型链路 |
|---------|---------|
| 碎片化 → map_count 耗尽 | 地址空间碎片化导致频繁创建 VMA → VMA 数量增长 → 触及 max_map_count |
| mlock → ES 启动失败 | ES 配置 memory_lock=true → mlockall 超限 → ES 启动失败告警 |
| shm → cgroup 限制 | 容器内共享内存超过 `/dev/shm` 大小 → shmget 返回 ENOMEM |
| SIGBUS → 日志轮转 | logrotate 截断日志文件 → 应用 mmap 了该文件 → 进程 SIGBUS 退出 |
