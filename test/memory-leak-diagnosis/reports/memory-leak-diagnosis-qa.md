# 内存泄漏检测与诊断 Skill — 特性问答

## 一、背景与价值

**Q: 为什么要构建 memory-leak-diagnosis 这个 Skill？**

A: 内存泄漏是生产环境中最常见且最难定位的系统性问题之一。用户态泄漏（RSS 增长、匿名页膨胀）和内核态泄漏（slab 增长、vmalloc 未释放）往往是导致 OOM、服务中断、容器被杀掉的根因。传统排查依赖运维人员手动执行 `top`、`pmap`、`slabtop`、`kmemleak` 等离散命令逐层分析，效率低且容易遗漏关联证据。

通过构建 witty-diagnosis-agent 的 memory-leak-diagnosis 诊断 Skill，可以实现：

- **自动化采集**：一键式获取系统内存、进程内存、slab、vmalloc、memcg 等 9 类关键指标
- **智能诊断**：基于假设驱动方法论，自动构建多假设树，区分用户态/内核态泄漏路径
- **趋势分析**：多时间点采样对比，识别增长趋势而非瞬态峰值
- **经验固化**：将内存泄漏排查的专家经验固化为可复用、可自动执行的诊断流程

## 二、需求说明

**Q: 这个 Skill 覆盖哪些故障场景？**

A: 覆盖 7 大核心分析场景：

| 分支 | 分析场景 | 假设数量 | 对应诊断脚本 |
|------|---------|---------|-------------|
| A | 用户态 RSS 持续增长 | 5 | `diagnose_rss_growth.sh` |
| B | 匿名页泄漏 | 5 | `diagnose_anon_page.sh` |
| C | Valgrind/ASan 堆泄漏 | 5 | `diagnose_heap_profiler.sh` |
| D | Slab 缓存泄漏 | 5 | `diagnose_slab_leak.sh` |
| E | vmalloc 泄漏 | 5 | `diagnose_vmalloc_leak.sh` |
| F | kmalloc 未释放 | 5 | `diagnose_kmalloc_leak.sh` |
| G | Memcg 泄漏 | 5 | `diagnose_memcg_leak.sh` |

## 三、注意事项

| 场景 | 处理方式 |
|------|---------|
| 进程已不存在 | 脚本检查 `/proc/[pid]` 是否存在，不存在则输出错误提示 |
| 缺少 root 权限 | kmemleak、部分 /proc 文件需要 root 权限，脚本有降级处理 |
| 采样间隔过短 | 默认间隔 5-10 秒，避免频繁读 /proc 造成性能影响 |
| 内存压力环境 | 诊断脚本本身内存开销极小，不会加剧内存压力 |
| 多时间点对比 | 所有趋势数据保存为 CSV，支持后续绘图分析 |
