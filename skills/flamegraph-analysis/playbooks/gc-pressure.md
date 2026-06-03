# GC Pressure - GC 压力分析剧本

## 触发条件

用户问题包含以下关键词：
- "GC"、"垃圾回收"
- "内存抖动"
- "暂停时间长"
- "stop the world"
- "内存分配"

## 分析流程

### Step 1: 数据准备

1. 确认输入为 On-CPU 采样或 alloc 采样
2. 转换为折叠栈格式

### Step 2: GC 模式检测

```bash
python scripts/analyzers/pattern_match.py --input folded.folded --json
```

重点匹配：
- `gc_` / `GC`
- `G1Collect` / `G1GC`
- `MarkSweep` / `CollectGarbage`
- `gcBgMarkWorker`
- `mallocgc` / `newinstance`

### Step 3: 分配热点分析

从折叠栈中筛选包含 GC/分配相关帧的栈，识别：
- 分配内存最多的函数
- 触发 GC 最频繁的路径
- 对象生命周期问题

### Step 4: GC 暂停影响评估

```bash
python scripts/analyzers/stats.py --input folded.folded --json
```

根据栈深度分布评估 GC 暂停对延迟的影响

## 输出结构

```
## GC 压力分析

### GC 相关占比
- GC 总占比: XX%
- 分配相关占比: XX%

### GC 热点函数
| 函数 | 触发次数 | 分配对象数 |
|------|----------|------------|
| allocate_large | 1234 | 567MB |
| processRequest | 890 | 234MB |

### GC 调用栈
[触发 GC 的代码路径]

### 内存分配模式
[按调用栈聚合的内存分配]
```

## GC 类型识别

| GC 类型 | 特征帧 | 优化建议 |
|---------|--------|----------|
| G1GC | `G1Collect`, `G1Evacuate` | 增大堆，减少对象分配 |
| CMS/ParNew | `CMS`, `ParNew` | 对象分代优化 |
| Go GC | `runtime.gcBgMarkWorker` | 减少小对象分配 |
| V8 GC | `CollectGarbage` | 避免频繁创建对象 |

## 优化建议

1. **减少对象分配**：
   - 对象池复用
   - 避免在循环中创建对象
   - 使用基本类型替代包装类型

2. **优化对象生命周期**：
   - 尽量在栈上分配
   - 及时释放引用

3. **调整 GC 参数**：
   - 增大堆大小
   - 调整 GC 阈值
   - 选择合适的 GC 算法

4. **使用增量 GC**：
   - Epsilon GC（低延迟场景）
   - ZGC / Shenandoah（低暂停场景）
