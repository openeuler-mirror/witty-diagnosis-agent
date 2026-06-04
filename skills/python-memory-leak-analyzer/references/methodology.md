# Python 内存泄漏诊断方法论

## 阶段 0：证伪与定界

先判断是否真有持续增长。RSS 单次高水位不是泄漏证据，必须看时间序列、谷值是否抬升、增长是否与 workload 相关，以及是否进入 plateau。短窗口和缓存预热只能给 `inconclusive` 或 `plateau`，不能输出根因。

低输入离线证据包场景下，时间窗口是报告上下文字段，不是诊断入口的阻塞条件。若用户未提供故障时间，但范围目录已有 `discovery.json`、`metadata.json`、日志或结构化证据，先按现有证据完成定界和根因分析；报告中将时间窗口写为“未提供”或“按证据生成时间近似”，并列为残余缺口。只有在需要从海量系统日志中切片且没有可用证据包时，才把时间窗口作为必须追问项。

低输入场景必须保持当前范围隔离：一次诊断只使用用户本轮给出的目录、PID、服务名或 `discover_evidence.py` 在该范围内发现的证据。历史 Dayu/Baize 报告、上一次 stress 场景报告和归档目录里的旧 Markdown/HTML 不能作为本轮根因输入；它们最多作为归档或显式对照材料。若历史报告与当前范围的 `semantic.json`、`object_growth.json`、`retention.json`、`tracemalloc.json` 或 `monitor_rss_pid.json` 冲突，优先使用当前范围内结构化证据，并把历史报告视为无效输入。

## 阶段 1：区分 Python 堆与 native/allocator

Python 堆增长需要由 `object_growth.py` 或 `tracemalloc_probe.py` 支撑。若 RSS 增长明显，但 gc 跟踪对象和 tracemalloc diff 都解释不了主要增长，应转 native、C 扩展、mmap、allocator arena 或碎片化方向。

## 阶段 2：定位增长对象

按类型和容器规模找主候选。缓存型泄漏常表现为一个全局 dict/list 很大，而不是某个实例类型计数激增，所以必须同时看 `type_growth` 和 `big_containers_after`。

## 阶段 3：语义保留信号

在可复现 workload 中运行 `semantic_probe.py`，把模块全局容器、无界 cache、bound method registry、闭包 cell、generator/task frame、`gc.garbage` 等模式显式列出来。复杂场景先比较 `dominant_signals`，再进入保留链追踪；多源场景必须说明主因和次要干扰项，不能只选择最显眼的全局变量。

## 阶段 4：分配线与保留线交叉

tracemalloc 定位“在哪分配”，gc referrers 定位“为什么仍可达”。两条线互相校验。只看到分配热点不能说明根因，因为创建对象的代码可能是正常路径，真正缺陷在缓存、注册表、回调或生命周期管理。

## 阶段 5：验证门

结论前至少经过 G1 量化对账和 G2 竞争假设排除。G3 反事实验证只有在沙箱或批准后执行；生产环境可降级为静态可达性论证并降低置信度。

## 阶段 6：复测

修复后复跑相同 workload，期望 RSS 斜率下降、对象计数不再单调增长、tracemalloc diff 主要热点消失或进入稳定平台。
