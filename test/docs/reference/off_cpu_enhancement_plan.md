# Joint On/Off-CPU Analysis - 联合分析增强

## 新增文件

| 文件 | 用途 |
|------|------|
| `playbooks/joint-on-off-cpu.md` | 完整联合分析剧本（含详细步骤、数据对齐、交叉验证） |
| `scripts/analyzers/offcpu_classifier.py` | Off-CPU模式库增强（新增 5 种阻塞模式） |
| `scripts/analyzers/joint_analysis.py` | 联合分析工具（数据对齐、时间分解、交叉验证） |
| `scripts/analyzers/bottleneck_classifier.py` | 瓶颈分类器增强（根因链、优化建议） |
| `scripts/render/report_template.html` | 报告模板增强（墙钟时间分解章节） |

## 各子需求实现

### 2.6.1 联合分析剧本（完整步骤）

- 数据对齐验证（时间窗口、进程ID一致性）
- 时间构成分解（CPU时间 vs 等待时间）
- 交叉验证规则（on-cpu与off-cpu的互相验证）

### 2.6.2 Off-CPU模式库增强

新增 5 种阻塞模式：

| 模式 | 说明 |
|------|------|
| signal_wait | 信号等待（sigtimedwait、pause） |
| memory_wait | 内存等待（alloc_pages、kswapd） |
| net_io | 细分网络I/O（新增connect、tls、dns相关） |
| barrier | 屏障同步（pthread_barrier、cyclic_barrier） |
| rcu_wait | RCU等待（synchronize_rcu、call_rcu） |

### 2.6.3 瓶颈分类器增强

- 输出根因链：`[原始帧] → [模式分类] → [瓶颈类型] → [根因]`
- 输出优化建议：基于瓶颈类型给出具体建议

### 2.6.4 数据对齐验证

- 时间窗口一致性检查
- 进程ID匹配度检查
- 采样重叠度分析
- 输出一致性报告

### 2.6.5 报告模板增强

- 新增墙钟时间分解章节
- CPU占比 + 等待占比可视化
- 瓶颈类型分布图

### 2.6.6 联合分析可视化（P2）

- 时间线视图（CPU vs 等待时序）
- 堆叠柱状图（瓶颈分类分布）
