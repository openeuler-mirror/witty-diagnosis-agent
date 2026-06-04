# Python 内存泄漏诊断方法论

## 0. 先证伪和定界

RSS 单次高水位不是泄漏证据。先确认本轮范围、PID/worker/cgroup/mapping 口径和增长形态。短窗口、缓存预热、allocator high-water、mmap/file/shmem、worker skew 或 scope mismatch 都可能解释现象。

低输入离线证据包不因缺少故障时间窗口中断；时间只作为报告上下文和残余缺口。历史 Witty 报告只能作背景，不能替代当前范围内结构化证据。

## 1. 区分 Python retained 与非 Python 增长

Python retained leak 至少需要 Python heap/tracked object 增长，以及 semantic 或 retention 证据。RSS/Private_Dirty 增长但 Python heap 解释比例低时，转 native、allocator、mmap/file/shmem 或 fragmentation 方向。

## 2. 建立两条证据线

- 分配线：`tracemalloc_probe.py` 或已有 profiler 输出，回答“在哪里分配”。
- 保留线：`object_growth.py`、`semantic_probe.py`、`retention_chain.py`、`reachability_probe.py`，回答“为什么还活着”。

根因通常在保留线，不在分配线。分配热点只能作为交叉验证证据。

## 3. 做证据对账

报告前运行或读取 `correlate_evidence.py`。用 `correlation.json` 统一判断 Python heap、native/allocator、mmap/file/shmem、transient peak、mixed growth 或 readonly insufficient。

## 4. 排除竞争假设

按 `evidence-analysis.md` 的竞争假设矩阵填写 G2。复杂场景必须说明主因、次要来源和干扰项；候选 coverage 低时不能写唯一根因。

## 5. 输出根因与置信度

按 `validation-gates.md` 的 G0-G5 输出 confirmed、strong、weak 或 direction-only。G3/G4 未通过时，不把复杂根因写成 confirmed。
