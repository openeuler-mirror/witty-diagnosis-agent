# Lock Contention - 锁竞争分析剧本

## 触发条件

用户问题包含以下关键词：
- "锁竞争"、"锁等待"
- "互斥"、"同步开销"
- "mutex"、"lock"
- "futex"、"pthread"
- "死锁"、"活锁"

## 分析流程

### Step 1: 数据准备

1. 确认输入为 Off-CPU 采样或混合采样
2. 转换为折叠栈格式

### Step 2: Off-CPU 分类

```bash
python scripts/analyzers/offcpu_classifier.py --input folded.folded --json
```

输出阻塞原因分类：
- 锁与同步等待
- 磁盘 I/O
- 网络 I/O
- 计时器
- GC 暂停
- 页面错误

### Step 3: 锁模式检测

```bash
python scripts/analyzers/pattern_match.py --input folded.folded --json
```

重点匹配：
- `pthread_mutex_lock` / `__pthread_mutex_lock`
- `futex_wait` / `__lll_lock_wait`
- `Monitor::wait` / `Object.wait`
- `sync.(*Mutex).Lock`

### Step 4: 锁热点栈分析

从折叠栈中筛选包含锁相关帧的栈，聚合出：
- 等待次数最多的锁
- 持有锁时调用的函数
- 锁竞争最严重的代码路径

## 输出结构

```
## 锁竞争分析

### 阻塞时间分布
- 锁等待占比: XX%
- 磁盘 I/O 占比: XX%
- 其他占比: XX%

### 锁竞争热点
| 锁类型 | 帧 | 等待次数 | 占比 |
|--------|-----|----------|------|
| pthread_mutex | func_a | 1234 | 45% |
| futex | func_b | 567 | 20% |

### 锁持有栈
[持有锁时的调用栈]

### 等待模式
[锁等待的调用栈]
```

## 锁类型识别

| 锁类型 | 特征帧 | 建议 |
|--------|--------|------|
| pthread_mutex | `pthread_mutex_lock` | 检查锁粒度 |
| futex | `futex_wait` | 减少上下文切换 |
| Java synchronized | `Monitor::wait` | 减少 synchronized 块 |
| Go mutex | `sync.(*Mutex).Lock` | 考虑 channel |
| RWLock | `pthread_rwlock` | 读多写少场景适用 |

## 优化建议

1. **减小锁粒度**：减少持锁时间
2. **读写分离**：读多写少用 RWLock
3. **无锁结构**：使用原子操作
4. **避免死锁**：统一锁顺序
5. **锁分解**：一个大锁拆为多个小锁
