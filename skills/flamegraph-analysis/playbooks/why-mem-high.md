# Why Memory High - 内存分配/泄漏分析剧本

## 触发条件

用户问题包含以下关键词：
- "内存高"、"内存占用高"、"RSS 高"
- "内存泄漏"、"memory leak"
- "OOM"、"OutOfMemoryError"
- "内存抖动"、"频繁 GC"
- "分配速率高"、"alloc profile"
- "eden space"、"young gen"

## 场景说明

内存问题在火焰图中有两种表现形式，需区分对待：
- **分配速率高（高 GC 压力）**：在 [gc-pressure.md](gc-pressure.md) 中已部分覆盖，本剧本从分配源头角度补充
- **驻留集高（疑似泄漏）**：同样函数持续在跑，但堆不断增长

本剧本侧重：
- 定位**分配热点**（哪段代码在疯狂 `malloc` / `new`）
- 识别**潜在泄漏**（即便 GC 也回收不掉的对象类型）
- 关联**页错误**（页错误/换入见 [page-fault-swap.md](page-fault-swap.md)）

## 分析流程

### Step 1: 确认采样类型

内存问题需要不同的事件类型：

| 数据源 | 事件 | 工具 |
|--------|------|------|
| alloc 采样 | `mem_alloc` / `heap` | async-profiler `-e alloc` / perf `kmem` |
| page fault | `page-faults` / `minor-faults` | perf `-e page-faults` |
| 高分配速率 | 周期采样（on-CPU 即可） | `perf record -F 999` |

如果只有 on-CPU 采样，可继续分析但置信度需标注为 Medium。

### Step 2: 分配模式检测

```bash
python scripts/analyzers/pattern_match.py --input folded.folded --json
```

重点匹配（来自 `analysis-patterns.md` 第 2、8 类）：

| 模式 | 特征函数/符号 | 权重 |
|------|-------------|------|
| C 堆分配 | `malloc`, `free`, `realloc`, `calloc`, `jemalloc_*` | 0.5 |
| C++ new | `operator new`, `operator new[]`, `operator delete` | 0.5 |
| Java 分配 | `AllocObject`, `AllocateInOldGen`, `eden_alloc`, `newinstance` | 0.6 |
| Go 分配 | `runtime.mallocgc`, `runtime.newobject`, `runtime.makeslice`, `runtime.makechan` | 0.7 |
| V8 分配 | `v8::internal::Heap::AllocateRaw`, `v8::internal::Factory::New` | 0.7 |
| 字节码生成 | `Blackbird`, `LambdaForm`, `BytecodeGenerator` | 0.6 |
| mmap 分配 | `mmap`, `mremap`, `munmap` | 0.5 |

### Step 3: 分配热点分析

```bash
python scripts/analyzers/hotspot.py --input folded.folded --top 30 --json
```

按"叶帧是分配函数的栈"聚合：

```
allocservice.processRequest      35%
├─ MyRequest.<init>              20%   ← 每次请求创建大对象
├─ new byte[8192]                12%   ← 缓冲区未复用
└─ ArrayList.add                  3%
```

### Step 4: 泄漏模式识别

针对**驻留集持续增长**场景，关注：

| 信号 | 检测方法 |
|------|---------|
| 同一类型对象数量随时间单调增长 | jcmd `GC.class_histogram` 对比两个时间点 |
| 大对象频繁进入老年代 | GC 日志中的 `promotion` 速率 |
| 引用链中存在"静态集合" | 在火焰图中搜 `HashMap.put` / `ArrayList.add` 的调用栈 |
| 监听器/回调未注销 | 在火焰图中搜 `addListener` / `register` 的调用栈 |

## 输出结构

```
## 内存分析

### 分配速率
- 总分配函数占比: XX%（含 malloc/new/runtime.mallocgc）
- 单位时间分配次数（估算）: XX K/s
- 分配热点函数 Top 5: [列表]

### 分配类型分布
| 类别 | 帧 | 占比 | 备注 |
|------|-----|------|------|
| 短命小对象 | new String | 40% | 高 GC 压力 |
| 中等对象 | DTO.<init> | 25% | 视生命周期 |
| 大对象 | byte[8192] | 15% | 警惕直接进老年代 |
| 长期存活 | 缓存 put | 5% | 疑似泄漏 |

### 潜在泄漏点
| 位置 | 帧 | 嫌疑等级 | 证据 |
|------|-----|----------|------|
| CacheManager | ConcurrentHashMap.put | 高 | 静态 Map 持续增长 |
| ListenerRegistry | addListener | 中 | 未见对称 remove |

### 建议
- 对象池复用: [热点函数列表]
- 改值类型: [装箱/拆箱热点]
- 警惕大对象: [分配大数组的路径]
```

## 阈值标准

| 指标 | 阈值 | 严重度 |
|------|------|--------|
| 分配函数（malloc/new/alloc）总占比 | > 10% | 高（GC 压力来源） |
| 分配函数总占比 | > 30% | 严重（业务线程大半在做分配） |
| 单类型对象实例数增长 | > 1%/分钟 | 警告（潜在泄漏） |
| eden 区填满速度 | < 5 秒/次 | 高（minor GC 频繁） |
| Full GC 频率 | < 60 秒/次 | 严重（老年代压力大） |

## 典型场景

### 场景 1: 短命对象风暴

**症状**：
- 火焰图底层 `runtime.mallocgc` / `newinstance` 占比 > 30%
- young GC 频繁（每秒数次）
- 但接口 P99 尚可

**根因**：
每次请求/循环都创建大量临时对象，主要来源是字符串拼接、JSON 解析、集合操作。

**修复**：
- 字符串拼接改用 `StringBuilder` / `string.Join`
- JSON 解析用流式 API（`Gson.stream` / Jackson `JsonParser`）
- 集合预分配容量（`new ArrayList<>(N)`）
- 引入对象池（特别是大对象）

### 场景 2: 大对象直接进老年代

**症状**：
- 火焰图有 `byte[]` / `large object` 分配热点
- GC 日志 `humongous allocation` 频繁
- Full GC 间隔短

**根因**：
单次分配大块内存（如读取大文件、加载大 JSON），超过 G1 region size 50%，直接进老年代。

**修复**：
- 拆分大对象读取（流式）
- 调大 `-XX:G1HeapRegionSize`（如 32M）
- 调整 `-XX:InitiatingHeapOccupancyPercent`

### 场景 3: 静态集合无界增长（典型泄漏）

**症状**：
- 火焰图中 `ConcurrentHashMap.put` / `HashMap.put` 在业务路径上反复出现
- 同一根帧下分配的总字节数随时间持续增长
- GC 后堆大小不下降

**根因**：
缓存、监听器注册表等静态 Map 缺少淘汰机制（或淘汰不充分），键只增不减。

**修复**：
- 引入 LRU + 最大容量限制
- 使用 `WeakHashMap` / `Caffeine` / `Guava Cache`
- 监听器场景加对称 `remove` 路径
- Go 场景警惕全局 `var cache = make(map[string]*Obj)`

### 场景 4: ThreadLocal 泄漏

**症状**：
- 火焰图中 `ThreadLocal.set` 频繁
- 线程池场景下，线程复用导致 ThreadLocal 累计

**修复**：
- 用 `try-finally` 显式 `remove`
- 改用 `ScopedValue`（Java 21+）或栈局部变量

### 场景 5: 闭包/回调持有大对象

**症状**：
- 火焰图底层是 lambda 创建，但栈上层仍存在大对象引用
- GC Roots 分析显示 lambda 持有意外引用

**修复**：
- 显式解引用
- 拆分 lambda，让大对象超出闭包捕获范围

## 与其他剧本的协同

| 关联剧本 | 协同方式 |
|---------|---------|
| [gc-pressure.md](gc-pressure.md) | 分配热点直接推高 GC，合并触发可定位"分配→GC"因果链 |
| [io-wait.md](io-wait.md) | 读大文件→大对象→大对象 GC，关联分析 |
| [page-fault-swap.md](page-fault-swap.md) | 内存不足时触发 swap，page fault 飙升 |

## 优化建议

### 1. 减少分配

- **对象池**：复用短生命周期对象（线程、连接、缓冲区、解析器）
- **基本类型替代包装类型**：`int` 替代 `Integer`
- **避免循环内分配**：把 `new` 提到循环外
- **字符串拼接**：`StringBuilder` / `+` 编译为 `invokedynamic`（JDK 9+）

### 2. 优化对象大小

- 扁平类（Java `record` / Go struct 顺序）
- 压缩指针：`-XX:+UseCompressedOops`
- 字段重排：把同类字段放一起提升压缩效率

### 3. 生命周期管理

- 用 `try-with-resources` 管理 `Closeable`
- 注册监听器对称解注册
- ThreadLocal 用完 `remove`
- 定时清理过期缓存

### 4. 选型与配置

- 选择合适 GC：低延迟选 ZGC/Shenandoah，吞吐选 G1/Parallel
- 调整堆大小：避免堆过大导致单次 GC 长
- 调 `-XX:MaxTenuringThreshold` 平衡晋升速率

### 5. 监控与告警

- RSS / heap usage 增长趋势
- GC 频率与暂停时间
- 各类对象实例数（`jcmd <pid> GC.class_histogram`）
- Native memory: `pmap` / jemalloc stats

## 配套工具命令

```bash
# Java 堆直方图
jcmd <pid> GC.class_histogram

# Native 内存跟踪
jcmd <pid> VM.native_memory summary

# Go 内存
go tool pprof -alloc_objects http://host/debug/pprof/heap

# 通用：分配追踪
perf mem record -t alloc -p <pid>
perf mem report

# async-profiler 分配采样
./asprof -e alloc -f alloc.html -d 30 <pid>
```

## 常见误判

- **"GC 频繁" 不等于"泄漏"**：分配速率本身就高，GC 是健康反应
- **"堆大" 不等于"泄漏"**：缓存预热是正常的大堆场景
- **"RSS 高" 不一定在堆**：可能是 native 内存、jemalloc arena、thread stack
- **泄漏不一定在火焰图上显现**：泄漏的是引用关系，需要 GC Roots 分析
