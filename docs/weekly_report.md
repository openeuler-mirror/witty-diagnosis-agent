# 智能运维诊断系统开发周记

## 第一周：Trace 工具初步优化

**主要工作**：对 trace 工具进行初步分析与优化，定位性能瓶颈并提交代码到分支。

**功能细节**：
- 分析现有 trace 工具的执行流程，识别耗时的关键路径
- 对数据采集和处理环节进行针对性优化
- 提升 trace 工具的执行效率和资源利用率

**成果**：
- trace 工具性能取得一定提升
- 相关代码已提交到单独分支，方便后续合并与验证
- 确定了下一步需要增强故障时间评估能力

---

## 第二周：Trace 工具分层策略优化

**主要工作**：进一步优化 trace 工具，尝试解决分层策略的缺陷，提升可解释性。

**功能细节**：
- 分析现有分层策略的局限性（人工分层依赖性强）
- 优化分层算法的准确性和自动化程度
- 端到端跑通完整 trace 分析流程
- 去除冗余代码，精简工具链

**成果**：
- 分层策略优化方案已确定
- 端到端流程已跑通
- 代码已提交到分支
- 可解释性得到增强

---

## 第三周：Trace 工具泛化性提升

**主要工作**：优化 trace 工具的分层策略，使其不依赖人工分层，提升泛化能力。

**功能细节**：
- 实现自动化分层策略，减少人工干预
- 结合模型对工具的调用，分析工具的具体作用
- 阅读业界相关论文，关注 Agent + Trace 分析方向

**成果**：
- 分层策略实现自动化
- 泛化能力得到提升
- 完成相关论文调研

---

## 第四周：Trace 相关论文调研（一）

**主要工作**：开始系统性地调研业界 trace 分析相关论文。

**功能细节**：
- 搜索和筛选 trace 分析领域的重要论文
- 阅读核心论文，理解其方法和贡献
- 整理初步的论文列表

**成果**：
- 完成第一篇相关论文的深入调研
- 建立了论文列表框架
- 明确了后续调研方向

---

## 第五周：Trace 相关论文调研（二）

**主要工作**：继续调研多篇 trace 相关论文，梳理核心贡献。

**功能细节**：
- 扩展论文调研范围，覆盖更多研究方向
- 对比不同论文的技术路线和创新点
- 梳理每篇论文解决的核心问题

**成果**：
- 完成多篇论文的深入调研
- 梳理了各论文的核心贡献
- 建立了论文对比分析框架

---

## 第六周：Related Work 撰写

**主要工作**：形成相关工作的中文版本，为论文撰写做准备。

**功能细节**：
- 将论文调研结果整理为中文版 related work
- 补充英文版本的相关工作
- 完善论文的 Related Work 章节
- 进一步完善 Introduction 章节

**成果**：
- 完成中文版相关工作文档
- Related Work 章节框架已建立
- Introduction 章节得到完善

---

## 第七周：论文主线分析与批注

**主要工作**：Method 主线分析，完善论文整体结构和关联性。

**功能细节**：
- 分析 Method 主线逻辑
- 整合 Introduction / Related Work / Method 的整体关联
- 初步通读整篇论文，提供修改建议
- 检查 arXiv 论文的发表情况
- 在 PDF 上做批注并提供修改建议

**成果**：
- 论文整体结构得到梳理
- arXiv 发表情况已检查
- 批注版 PDF 已提供，部分修改已完成

---

## 第八周：故障注入工具调研

**主要工作**：完善选定故障注入工具的细节，尝试跑通工具，给出对比分析。

**功能细节**：
- 调研多个故障注入工具的实现原理
- 尝试跑通故障注入工具的基本流程
- 给出故障注入工具的细化对比分析
- 跑通 Witty 样例

**成果**：
- 完成多个故障注入工具的对比分析
- Witty 样例已跑通
- 确定了故障注入工具 + Witty 自动化流程的打通方案

---

## 第九周：故障注入 + Witty 自动化流程

**主要工作**：打通故障注入工具与 Witty 的自动化流程，合并为完整的诊断链路。

**功能细节**：
- 实现故障注入工具与 Witty 的自动对接
- 将故障注入与 Skill 合并为一个自动化流程
- 跑通 Witty + Skill 完整流程
- 提供 5 个场景的故障注入 + 诊断样例

**成果**：
- Witty + Skill 自动化流程已跑通
- 5 个场景的样例已提供
- 确定了 OpenCode 运行样例方案

---

## 第十周：OpenCode 集成

**主要工作**：完成在 OpenCode 中运行 Witty 进行故障注入与诊断分析的流程。

**功能细节**：
- 实现 OpenCode 环境中 Witty 的完整运行流程
- 完成故障注入 → Witty 诊断的端到端集成
- 梳理自动故障注入 Skill 的开发计划

**成果**：
- OpenCode 中 Witty 运行流程已完成
- 端到端故障注入与诊断流程已跑通
- 自动故障注入 Skill 待后续开发

---

## 第十一周：内存泄漏检测 Skill 开发

**主要工作**：完成用户态/内核态内存泄漏检测与诊断 Skill 的开发。

**功能细节**：
- 用户态：RSS 持续增长趋势分析、`/proc/[pid]/smaps` 匿名页增长、valgrind/AddressSanitizer 报告解析
- 内核态：slab 增长（slabinfo/slabtop 趋势）、vmalloc 泄漏、kmalloc 未释放追踪
- 包含 8 个诊断脚本和 10 个故障复现脚本
- 提供 Docker 测试环境

**成果**：
- 完成 `memory-leak-diagnosis` Skill 开发
- 8 个 RCA 报告已生成
- Docker 测试环境已搭建

---

## 第十二周：TLS/SSL 证书诊断 Skill 开发

**主要工作**：完成 TLS/SSL 证书与握手故障诊断 Skill 的开发。

**功能细节**：
- 证书过期/即将过期检测
- 证书链不完整检测
- CA 信任库缺失/过期检测
- TLS 版本/密码套件不兼容检测
- SNI 配置错误检测
- OCSP stapling 失败检测
- 客户端证书认证失败检测

**成果**：
- 完成 `tls-certificate-diagnosis` Skill 开发
- 覆盖 7 类 TLS/SSL 故障场景

---

## 第十三周：页缓存与内存回收诊断 Skill 开发

**主要工作**：完成页缓存与内存回收异常诊断 Skill 的开发。

**功能细节**：
- kswapd 高 CPU（频繁回收）检测
- direct reclaim 导致进程延迟抖动（allocstall 计数飙升）检测
- dirty page writeback 风暴（dirty_ratio/dirty_background_ratio 配置不当）检测
- page cache 过度占用导致可用内存假告警检测
- drop_caches 误用引发 I/O 风暴检测

**成果**：
- 完成 `page-cache-reclaim-diagnosis` Skill 开发
- 覆盖 5 类页缓存/内存回收故障场景

---

## 第十四周：内存映射诊断 Skill 开发

**主要工作**：完成内存映射与虚拟地址空间故障诊断 Skill 的开发。

**功能细节**：
- mmap 返回 ENOMEM（vm.max_map_count 耗尽）检测
- SIGBUS on truncated file（文件映射后被截断）检测
- mlock 超限（RLIMIT_MEMLOCK）检测
- 共享内存映射故障检测

**成果**：
- 完成 `mmap-vma-diagnosis` Skill 开发
- 覆盖 4 类内存映射故障场景

---

## 第十五周：Flamegraph 增强（上）

**主要工作**：完成 Flamegraph-Analysis Skill 的前半部分能力增强。

### SVG 导出增强 (2.1)

**功能细节**：
- HTML 模板新增 SVG 导出按钮和 `exportSvg()` 函数
- SVG 矢量图导出保留完整交互性（20 个 JS 函数：缩放、搜索、大小写切换）
- SVG 保留栈层次结构、颜色方案和 findings 标注
- PNG 导出功能保持不变
- 导出文件命名包含时间戳（`flamegraph_YYYYMMDD_HHmmss.svg`）

### SVG 反向解析增强 (2.2)

**功能细节**：
- 修复 `svg_to_folded.py` 的深度计算（Y 坐标聚类）、父节点匹配（重叠 ≥ 50%）、置信度算法
- 支持 3 种 SVG 格式（v1 inline events、v2 CSS classes、older flat rects）
- 批量验证：35/35 SVG 全解析（100%）
- 置信度分级准确率：100%（20/20 样本人工验证）
- 新增 5 个验证脚本（`validate_svg_pipeline.py`、`full_svg_v2.py` 等）

### 内存分析增强 (2.3)

**功能细节**：
- `analyze_heap_trend.py`：多时间点 RSS 采样，自动判定增长异常
- `diagnose_fragmentation.sh`：buddyinfo + Slab 利用率 + 碎片等级判定
- `diagnose_large_object.sh`：超过阈值（默认 1MB）的映射段扫描
- `diagnose_numa_affinity.sh`：5 项检查 + 优化建议
- `diagnose_false_sharing.sh`：perf c2c + cache miss 率 + 修复建议

**成果**：
- SVG 导出：按钮 + 交互 + 时间戳 ✅
- SVG 反向解析：35/35 (100%) ✅
- 内存分析：5 个诊断脚本 ✅
- Docker/WSL 测试通过 ✅
- 排查手册 `why-mem-high.md` ✅
- 文档：`svg_validation_guide.md`、`svg_reverse_parse_report.md`、`memory_analysis_report.md` ✅

---

## 第十六周：Flamegraph 增强（下）

**主要工作**：完成 Flamegraph-Analysis Skill 的后半部分能力增强。

### 并发/并行分析增强 (2.4)

**功能细节**：
- `diagnose_thread_pool.sh`：线程状态分布 + 上下文切换 + 运行队列
- `diagnose_work_stealing.sh`：各 CPU 利用率分布 + 不均衡系数
- `diagnose_task_queue.sh`：IO 吞吐 + 网络/磁盘队列
- `diagnose_parallelism.sh`：利用率 vs 核心数 + 运行队列
- `diagnose_cache_coherence.sh`：cache miss + LLC + snoop 分析

### 差分火焰图增强 (2.5)

**功能细节**：
- 模板 `flamegraph-diff-analysis.html` 提取 6 个 `{{VARIABLE}}` 占位符
- 新增差异分析总结段落（趋势 + 回退 + 改善 + 根因）
- `diff_report_generator.py`：对接 `diff.py` 分析引擎，自动生成 HTML 报告（55KB）

### Off-CPU 联合分析增强 (2.6)

**功能细节**：
- 补充完整剧本（200 行，6 步骤 + 6 场景）
- Off-CPU 模式库：新增 5 种（signal_wait、memory_wait、barrier、rcu_wait、net_io_detailed），总计 13 种
- `joint_analysis.py`：前缀匹配 + 数据对齐 + 时间分解 + 根因链
- 单元测试 `test_joint_analysis.py`：4 个测试全部 PASS

### 验证体系

**功能细节**：
- 6 层 SVG 验证：XML + 元素 + CSS + JS + 事件 + 反向解析
- 严格退出码：0=通过 / 1=失败
- CI 配置：`.github/workflows/validate.yml`
- 排查手册：`why-context-switch.md` + `joint-on-off-cpu.md`

**成果**：
- 并发分析：5 个诊断脚本 ✅
- 差分火焰图：模板变量 + 生成器 ✅
- Off-CPU 分析：13 种模式 + 单元测试 ✅
- 验证管道：6/6 全部通过 ✅
- Docker/WSL 测试通过 ✅
- 文档：`concurrency_docker_test_report.md`、`diff_optimization_guide.md`、`off_cpu_test_report.md`、`completion_report.md` ✅
