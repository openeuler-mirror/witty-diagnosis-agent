# 内存故障场景分类

内存诊断过程中，主要涉及以下七大核心硬件/系统级故障场景：

| 场景标签 | 中文描述 | 主要特征与案例 |
| :--- | :--- | :--- |
| `MEMORY_ECC_ERROR` | 内存 ECC 错误 | ① **Correctable Error (CE)** 分数超限/风暴；② **Uncorrectable Error (UCE)** 触发；③ **MCE (Machine Check Exception)** 上报；④ 华为 iBMC `Correctable error, logging limit reached` 告警 |
| `MEMORY_HARDWARE_FAILURE` | 内存硬件/单元故障 | ① **DIMM 插槽异常/在位丢失** (No DIMM detected)；② **SPD 读取失败** (SPD Read Error)；③ **Training 训练失败** (Memory Training Failed)；④ 浪潮 iBMC `Memory Device Fatal` |
| `MEMORY_CONFIG_ISSUE` | 内存配置与拓扑冲突 | ① **由于混插导致的频率降级** (Frequency Fallback)；② **非对称双通道/插槽拓扑错误** (Non-optimal Config)；③ BIOS 关闭了特定的性能增强特性 (Node Interleaving) |
| `MEMORY_CORRUPTION` | 硬件诱发的内存损坏 | ① **由于物理位反转导致的页表损坏** (Page Table Corruption/Bit-flip)；② 内核报告 **hwpoison**（静默物理坏道隔离）；③ 指向固定地址的频繁 Segfault 或 Illegal Pointer |
| `MEMORY_PERFORMANCE` | 内存带宽与访问性能 | ① **NUMA 节点间延迟过大** (Remote Node Access)；② **Swap 换入换出频繁** (Thrashing)；③ 大页 (Hugepages) 碎片化导致的分配缓慢；④ 华为 iBMC `Memory Bandwidth Usage High` |
| `MEMORY_OOM_KILLER` | 内存耗竭 (OOM) | ① 操作系统由于物理内存完全耗尽触发 **Out of memory** 指令；② **oom_reaper** 被激活；③ 驱动/内核模块申请分配连续物理页（Order > 0）失败 |
| `MEMORY_LEAK` | 系统/内核级资源泄漏 | ① **内核 Slab 缓存泄漏** (SUnreclaim 持续上涨)；② **kmemleak** 记录的驱动未释放块；③ 系统服务由于非正常句柄泄露导致的 RSS 内存缓慢爬升 |
