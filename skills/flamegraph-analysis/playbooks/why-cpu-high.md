# Why CPU High - 分析剧本

## 触发条件

用户问题包含以下关键词：
- "CPU 高"、"CPU 占用高"
- "CPU 使用率高"
- "CPU 热点"、"CPU 瓶颈"
- "哪些函数占 CPU"
- "top CPU"、"CPU top"

## 分析流程

### Step 1: 数据准备

1. 检测输入文件格式
2. 转换为折叠栈格式
3. 提取元数据

### Step 2: 热点分析

```bash
python scripts/analyzers/hotspot.py --input folded.folded --top 20 --json
```

输出：
- Top Down: 按根帧聚合的主要执行路径
- Bottom Up: 按叶帧聚合的真正 CPU 消费者

### Step 3: 模式检测

```bash
python scripts/analyzers/pattern_match.py --input folded.folded --json
```

重点检测：
- 锁与同步（可能导致 CPU 忙等）
- GC 压力（暂停导致响应延迟）
- I/O 操作（可能阻塞）

### Step 4: 归因分析

```bash
python scripts/analyzers/attribution.py --input folded.folded --json
```

判断：
- 用户代码 vs 库 vs 运行时 vs 内核

### Step 5: 统计摘要

```bash
python scripts/analyzers/stats.py --input folded.folded --json
```

关键指标：
- 栈深度分布
- 多样性熵（集中型 vs 分散型瓶颈）

## 输出结构

```
## 热点分析
### 主要热点栈
[Top 10 热点栈及占比]

### Leaf 函数分析
[真正消耗 CPU 的末端函数]

## 模式检测
### 锁同步
### GC 压力
### I/O 操作

## 根因结论
[按置信度排序的根因列表]
```

## 阈值标准

| 指标 | 阈值 | 说明 |
|------|------|------|
| 单帧占比 | > 30% | 可能存在优化点 |
| 累计占比 (top 3) | > 60% | 瓶颈集中 |
| 栈最大深度 | > 50 | 可能存在深递归 |
| 锁模式占比 | > 20% | 锁竞争可能严重 |

## 典型结论模式

1. **单点热点**：某函数占比 > 50%，直接定位
2. **集中热点**：Top 3 栈占比 > 70%，优化主要路径
3. **分散热点**：熵值高，需系统性优化
4. **锁竞争**：锁相关占比高，需减少锁粒度
5. **GC 压力**：GC 相关占比高，需优化内存分配
