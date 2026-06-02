# Joint On/Off-CPU Analysis - 联合分析剧本

## 触发条件

用户问题包含以下关键词：
- "为什么慢"
- "性能问题"
- "响应延迟"
- 提供 On-CPU 和 Off-CPU 两份采样

## 场景说明

- **On-CPU**：CPU 真正执行代码的时间
- **Off-CPU**：线程等待（I/O、锁、调度等）的时间

联合分析帮助理解：
- 纯计算瓶颈 vs 纯等待瓶颈
- 计算+等待的混合瓶颈

## 分析流程

### Step 1: 数据准备

1. 获取 On-CPU 采样 (如 `perf record`)
2. 获取 Off-CPU 采样 (如 `perf sched sleep`)
3. 转换为折叠栈格式

### Step 2: 各自独立分析

```bash
python scripts/analyzers/hotspot.py oncpu.folded --top 20 --json
python scripts/analyzers/hotspot.py offcpu.folded --top 20 --json

python scripts/analyzers/offcpu_classifier.py offcpu.folded --json
python scripts/analyzers/bottleneck_classifier.py oncpu.folded --off-cpu offcpu.folded --json
```

### Step 3: 瓶颈类型判定

根据 `bottleneck_classifier.py` 输出判定：
- `cpu_bound`：纯计算瓶颈
- `io_bound`：纯 I/O 瓶颈
- `lock_bound`：锁竞争瓶颈
- `gc_bound`：GC 压力瓶颈
- `mixed`：混合瓶颈

### Step 4: 联合热点分析

对于出现在两侧的栈路径，计算：
- `blocking_ratio = off / (on + off)`
- `blocking_ratio ≈ 1`：几乎全在等待
- `blocking_ratio ≈ 0`：几乎全在计算

## 输出结构

```
## On/Off-CPU 联合分析

### 瓶颈类型
**分类结果**: cpu_bound / io_bound / lock_bound / gc_bound / mixed

### On-CPU 分析
- 总样本: XXX
- CPU 热点: [Top 5 栈]

### Off-CPU 分析
- 总样本: XXX
- 阻塞原因分布:
  - 锁等待: XX%
  - I/O 等待: XX%
  - 其他: XX%

### 联合判定
| 栈路径 | On-CPU | Off-CPU | blocking_ratio |
|--------|--------|---------|----------------|
| main;process | 45000ms | 5000ms | 0.10 |

### 根因结论
[综合 On-CPU 和 Off-CPU 分析的结论]
```

## blocking_ratio 解释

| ratio | 含义 | 优化方向 |
|-------|------|----------|
| < 0.1 | 纯计算 | 优化算法，减少 CPU 密集操作 |
| 0.1-0.3 | 略偏计算 | 兼顾计算优化和等待减少 |
| 0.3-0.7 | 混合型 | 需要同时优化计算和等待 |
| 0.7-0.9 | 略偏等待 | 主要减少等待时间 |
| > 0.9 | 纯等待 | 定位阻塞原因，减少等待 |

## 典型场景

### 场景 1: CPU 计算瓶颈

- On-CPU: 高占比
- Off-CPU: 低占比
- `blocking_ratio < 0.1`
- 建议：优化算法，减少不必要计算

### 场景 2: I/O 等待瓶颈

- On-CPU: 低占比
- Off-CPU: 高占比（I/O 类）
- 建议：异步 I/O，增加并发

### 场景 3: 锁竞争瓶颈

- On-CPU: 正常
- Off-CPU: 高占比（锁类）
- 建议：减少锁粒度，优化锁策略

### 场景 4: 混合瓶颈

- On-CPU: 中等
- Off-CPU: 中等
- `blocking_ratio ≈ 0.5`
- 建议：系统性优化，计算和等待同时处理
