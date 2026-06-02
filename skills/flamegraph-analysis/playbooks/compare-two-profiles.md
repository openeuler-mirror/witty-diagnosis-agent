# Compare Two Profiles - 差分分析剧本

## 触发条件

用户问题包含以下关键词：
- "对比"、"比较"
- "变慢"、"回归"
- "before"、"after"
- "这次"、"上次"
- "差异"、"不同"
- 提供两个采样文件

## 分析流程

### Step 1: 数据准备

1. 检测两份输入文件格式
2. 分别转换为折叠栈格式
3. 确保元数据一致（单位、采样频率等）

### Step 2: 差分分析

```bash
python scripts/analyzers/diff.py baseline.folded target.folded --json
```

输出：
- 新增栈（target 中有，baseline 中无）
- 消失栈（baseline 中有，target 中无）
- 显著变化的栈（占比变化 > 1%）

### Step 3: 各自热点分析

```bash
python scripts/analyzers/hotspot.py baseline.folded --top 10 --json
python scripts/analyzers/hotspot.py target.folded --top 10 --json
```

### Step 4: 变化归因

```bash
python scripts/analyzers/attribution.py baseline.folded --json
python scripts/analyzers/attribution.py target.folded --json
```

## 输出结构

```
## 差分概览
### 总体变化
- 基准样本数: XXX
- 目标样本数: XXX
- 变化: +XX% / -XX%

### 显著新增栈
[在目标中出现的新栈]

### 显著消失栈
[在目标中消失的栈]

### 显著变化
[占比变化 > 1% 的栈]
```

## 变化检测标准

| 变化类型 | 阈值 | 严重程度 |
|----------|------|----------|
| 新增热点 | 占比 > 5% | 高 |
| 消失热点 | 原占比 > 10% | 高 |
| 占比上升 | 变化 > 10% | 中 |
| 占比下降 | 变化 > 10% | 中 |

## 典型场景

### 场景 1: 版本发布后变慢

1. Baseline = 发布前 profile
2. Target = 发布后 profile
3. 重点关注新增热点和占比上升的栈

### 场景 2: 配置变更导致性能下降

1. Baseline = 变更前 profile
2. Target = 变更后 profile
3. 定位配置敏感的代码路径

### 场景 3: 流量变化导致性能差异

1. Baseline = 低峰期 profile
2. Target = 高峰期 profile
3. 识别可扩展性瓶颈

## 注意事项

1. 采样时长不同会导致样本数差异，应关注占比而非绝对值
2. 采样频率变化会影响比较结果
3. 冷启动和预热阶段的 profile 不适合直接对比
