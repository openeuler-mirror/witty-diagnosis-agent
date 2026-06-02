# Why Context Switch High - 上下文切换分析剧本

## 触发条件

用户问题包含以下关键词：
- "上下文切换高"、"切换频繁"
- "context switch"、"cs"
- "CPU 利用率高但跑不满"
- "sys% 高"、"系统调用占比高"
- "线程数过多"、"线程爆炸"
- "调度抖动"

## 场景说明

上下文切换（Context Switch）本身不消耗业务逻辑，但当其频率异常时，会带来两类问题：
- **直接开销**：`schedule` / `context_switch` / `switch_to` 等内核函数占 CPU
- **间接开销**：缓存（CPU cache / TLB）被冲刷，CPU 流水线被打断，导致"CPU 看着忙但活干得少"

典型症状：
- `vmstat 1` 中 `cs` 列 > 50,000/s
- `top` 中 `%sys` 占比 > 20%
- 火焰图中 `schedule`、`__schedule`、`context_switch` 出现明显宽度
- CPU 核数多但吞吐量增长缓慢（不可扩展）

## 分析流程

### Step 1: 数据准备

1. 优先使用包含 `sched` 事件的 perf 采样：`perf record -e sched:sched_switch -g`
2. 转换后调用 `scripts/analyzers/stats.py` 看 `schedule` / `__schedule` / `context_switch` / `switch_to` 等帧的总占比

### Step 2: 上下文切换帧检测

```bash
python scripts/analyzers/pattern_match.py --input folded.folded --json
```

重点匹配（来自 `analysis-patterns.md` 第 4 类）：

| 模式 | 特征函数/符号 | 权重 |
|------|-------------|------|
| 调度器 | `schedule`, `__schedule`, `scheduler`, `pick_next_task`, `pick_next_task_fair` | 0.6 |
| 上下文切换 | `context_switch`, `__context_switch`, `switch_to`, `finish_task_switch` | 0.5 |
| 进程创建 | `fork`, `clone`, `do_fork`, `runtime.newproc` | 0.4 |
| 线程创建 | `pthread_create`, `CreateThread`, `java.lang.Thread.start` | 0.4 |

### Step 3: 切换源头定位

```bash
python scripts/analyzers/hotspot.py --input folded.folded --top 30 --json
```

按"切换发生的栈"聚合，区分两类源头：
- **主动让出 CPU**：`nanosleep` / `usleep` / `pthread_cond_wait` / `select` 之后回到 `schedule`
- **被动抢占**：被更高优先级任务抢占，根栈是 `schedule` 而非业务

### Step 4: 多线程/进程统计

```bash
python scripts/analyzers/attribution.py --input folded.folded --json
```

观察：
- 同一根帧下子线程数量
- 是否存在线程数随时间线性增长（线程泄漏）

## 输出结构

```
## 上下文切换分析

### 切换相关占比
- schedule / __schedule: XX%
- context_switch / switch_to: XX%
- 合计: XX%（直接消耗）
- 间接影响: 缓存命中率下降 XX%

### 切换源头 Top 5
| 源头类型 | 帧 | 切换次数 | 占比 |
|----------|-----|----------|------|
| 主动 sleep | handle_request;usleep | 12345 | 35% |
| 锁竞争 | futex_wait | 8765 | 25% |
| 时间片耗尽 | schedule;pick_next_task | 5432 | 15% |
| 线程创建 | pthread_create | 2345 | 7% |
| 未知 | ... | 1234 | 4% |

### 线程/进程数
- 活跃线程数: XXX
- 是否存在线程泄漏: 是/否
- 线程创建热点: [Top 3 线程创建栈]

### 调度模式判定
- 主动让出 vs 被动抢占
- 短任务抢占长任务（反调度模式）
```

## 阈值标准

| 指标 | 阈值 | 严重度 |
|------|------|--------|
| `schedule` 直接占比 | > 5% | 高（系统已感知开销） |
| `schedule` 直接占比 | > 15% | 严重（CPU 在反复调度） |
| 每秒切换次数 | > 50,000 | 高（典型 web 服务线） |
| 每秒切换次数 | > 200,000 | 严重（线程池过载） |
| 线程数 | > CPU 核数 × 25 | 警告（调度开销上升拐点） |
| 线程数 | > CPU 核数 × 100 | 严重（大量无用切换） |

## 典型场景

### 场景 1: 线程池配置过大

**症状**：
- 线程数 = 1000+（远超 CPU 核数）
- `schedule` 占比 10%+
- 实际活跃线程 < 10%

**根因**：
线程池 `coreSize` 过大或 `maxSize` 不设上限。每个线程即便空闲也会被调度器检查，浪费时钟周期。

**修复**：
- CPU 密集任务：`poolSize = CPU 核数 + 1`
- I/O 密集任务：`poolSize = CPU 核数 × (1 + W/C)`，W=等待时间，C=计算时间
- 引入弹性线程池（`SynchronousQueue` + `maxPoolSize` 限制）

### 场景 2: 短生命周期线程频繁创建/销毁

**症状**：
- 火焰图中 `pthread_create` / `Go: newproc` 频繁出现
- 同一业务逻辑每次执行都创建新线程

**修复**：
- 使用线程池复用
- Go 场景考虑 goroutine 池（ants / tunny）
- Java 场景注意 `new Thread().start()` 的反模式

### 场景 3: 锁竞争导致被动切换

**症状**：
- 切换源头主要是 `futex_wait` 唤醒后的 `schedule`
- 火焰图同时存在 [lock-contention.md](lock-contention.md) 的特征

**修复**：
- 见 `playbooks/lock-contention.md`
- 减少临界区长度
- 改用无锁结构

### 场景 4: 自旋锁忙等

**症状**：
- 火焰图中 `__spin_lock` / `pthread_spin_lock` 占大量 CPU
- `schedule` 看似不高但 CPU 满载、吞吐低

**修复**：
- 自旋锁改用互斥锁（高竞争场景）
- 减少持锁时间

### 场景 5: 大量 sleep/yield

**症状**：
- 火焰图中 `nanosleep` / `usleep` / `runtime.Gosched` 密集
- 多出现于主动轮询（busy-poll）改 sleep 的过渡阶段

**修复**：
- 用事件驱动（epoll / io_uring / channel）替代 sleep 轮询

## 与其他剧本的协同

| 关联剧本 | 何时合并触发 |
|---------|-------------|
| [lock-contention.md](lock-contention.md) | 切换源头主要是 futex_wait |
| [joint-on-off-cpu.md](joint-on-off-cpu.md) | 需同时看 On/Off 才能区分忙等 vs 真等待 |
| [io-wait.md](io-wait.md) | 切换源头主要是 epoll_wait / select |

## 优化建议

### 1. 控制线程规模

- 线程数 = `min(业务并发需求, CPU 核数 × 合理倍数)`
- 避免线程数随请求量线性增长
- 使用协程（goroutine / virtual thread）替代 OS 线程

### 2. 减少主动让出

- 用事件驱动替代 sleep 轮询
- 合并小任务为批处理
- 避免不必要的 `Thread.yield`

### 3. 减少被动抢占

- 缩短持锁时间 → 减少 [锁竞争](lock-contention.md)
- 避免长循环不释放 CPU（可加 `runtime.Gosched()` 或时间片检查）

### 4. 绑核（CPU affinity）

- 高吞吐服务将工作线程绑核
- 避免多线程跨核迁移（缓存失效）
- 工具：`taskset` / `numactl` / Java `-XX:+UseContainerSupport` + `-XX:ActiveProcessorCount`

### 5. 调整调度策略

- 实时任务用 `SCHED_FIFO` / `SCHED_RR`
- 普通服务保持 `SCHED_OTHER`（CFS）
- 容器场景检查 cgroup CPU quota 是否过小（会导致频繁 throttling 切换）

## 配套工具命令

```bash
# 系统层切换次数
vmstat 1
# 或
cat /proc/stat | grep ctxt

# 进程级切换次数
cat /proc/$PID/status | grep voluntary_ctxt_switches
cat /proc/$PID/status | grep nonvoluntary_ctxt_switches

# perf 调度事件
perf record -e sched:sched_switch -g -p $PID sleep 30
perf script > cswitch.perf
```

## 常见误判

- **"%sys 高" 不一定是上下文切换**：也可能是 syscall（如 `read/write` 本身）或软中断
- **"线程多" 不一定有害**：I/O 密集型任务需要更多线程，关键看 CPU 利用率
- **"schedule 占比高" 也可能是合理让出**：协程调度器在用户态做 `schedule` 帧
