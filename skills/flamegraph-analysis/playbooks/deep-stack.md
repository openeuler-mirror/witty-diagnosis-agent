# Deep Stack - 深栈/递归分析剧本

## 触发条件

用户问题包含以下关键词：
- "递归"
- "深栈"
- "死循环"
- "栈溢出"
- "stack overflow"
- "无限循环"

## 分析流程

### Step 1: 统计栈深度

```bash
python scripts/analyzers/stats.py --input folded.folded --json
```

关键指标：
- 最大栈深度 (max_depth)
- P99 栈深度
- 深度分布

### Step 2: 深栈热点识别

```bash
python scripts/analyzers/hotspot.py --input folded.folded --top 50 --json
```

识别深度最大的栈路径

### Step 3: 递归模式检测

在热点栈中识别：
- 相同的帧序列重复出现
- 深度超过阈值的栈（默认 > 30）

### Step 4: 递归函数定位

通过栈模式识别递归函数：
- 帧 A 调用帧 B 调用帧 A
- 相同帧序列在栈中重复

## 输出结构

```
## 深栈分析

### 栈深度统计
- 最大深度: XX
- P99 深度: XX
- 平均深度: XX

### 深栈列表
| 深度 | 栈路径 | 样本数 |
|------|--------|--------|
| 50 | main;process;recursive_func... | 123 |

### 递归检测
- 检测到递归函数: func_a, func_b
- 递归调用次数: 12345

### 潜在问题
[深度超过阈值或存在递归的栈]
```

## 深度阈值

| 阈值 | 含义 | 建议 |
|------|------|------|
| < 20 | 正常深度 | 无需关注 |
| 20-50 | 较深 | 检查是否有优化空间 |
| 50-100 | 很深 | 考虑迭代替代递归 |
| > 100 | 极深 | 很可能存在性能问题 |

## 递归类型识别

| 类型 | 特征 | 建议 |
|------|------|------|
| 直接递归 | A → A | 尾递归优化 |
| 间接递归 | A → B → A | 考虑迭代 |
| 互递归 | A ↔ B | 拆分为单向 |

## 优化建议

### 递归改迭代

```python
# 递归版本
def fib(n):
    if n <= 1:
        return n
    return fib(n-1) + fib(n-2)

# 迭代版本
def fib(n):
    a, b = 0, 1
    for _ in range(n):
        a, b = b, a + b
    return a
```

### 尾递归优化

编译器支持的尾递归可避免栈增长

### 栈深度限制

设置递归深度检查，避免栈溢出

```python
import sys
sys.setrecursionlimit(1000)
```

### 记忆化

对重复计算的递归使用记忆化：

```python
from functools import lru_cache

@lru_cache(maxsize=None)
def fib(n):
    if n <= 1:
        return n
    return fib(n-1) + fib(n-2)
```
