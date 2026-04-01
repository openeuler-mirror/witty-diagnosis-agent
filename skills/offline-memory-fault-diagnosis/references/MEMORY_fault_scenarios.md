# 内存故障场景分类

内存诊断过程中，主要涉及以下七大核心故障场景：

| 场景标签 | 中文描述 | 主要特征 |
| :--- | :--- | :--- |
| `MEMORY_ECC_ERROR` | 内存ECC错误 | 包含：① GPIO 中断上报 FATAL (BIOS 隔离) ② GPIO 中断上报 CE (CE 风暴) ③ 空闲页 UCE (hwpoison 隔离) ④ 使用页 UCE (SIGBUS 杀进程) |
| `MEMORY_OOM_KILLER` | 内存不足(OOM) | 系统日志出现 Out of memory、OOM killer 被调用、业务进程被强制中断 |
| `MEMORY_LEAK` | 内存泄漏 | 内存使用量随时间线性增长、Slab/Cache 异常增大且无法通过正常手段回收 |
| `MEMORY_CORRUPTION` | 内存损坏 | 内核报告 memory corruption、频繁 Segfault、Page Fault、数据校验失败 |
| `MEMORY_PERFORMANCE` | 内存性能问题 | Swap 换入换出频繁(thrashing)、NUMA 节点间访问延迟大、内存带宽受限 |
| `MEMORY_HARDWARE_FAILURE` | 内存硬件故障 | DIMM 在位丢失、SPD 读取错误、内存初始化失败、iBMC 报告内存条损坏 |
| `MEMORY_CONFIG_ISSUE` | 内存配置不当 | 内存频率降级、非对称双通道配置、NUMA 绑定策略异常 |
