# Scheduler Latency - Off-CPU 调度延迟分析剧本

## 触发条件

用户问题包含以下关键词：
- "响应慢"、"延迟高"、"P99 高"
- "sleep 等待"、"主动 sleep"
- "定时任务"、"poll"、"轮询"
- "线程 join"、"等子进程"
- "调度延迟"、"调度不及时"

## 场景说明

本剧本聚焦 Off-CPU 数据中**计时器与线程管理**类等待，区别于 I/O 等待和锁竞争。

典型症状：
- 业务代码里调用 `Thread.sleep` / `nanosleep` / `usleep` / `time.Sleep`
- 主动 `pthread_join` / `Thread.join` 等其他线程结束
- `wait4` / `waitpid` 等子进程退出
- 业务吞吐远低于理论值，但 CPU/IO 不高

## 分析流程

### Step 1: 准备 Off-CPU 采样

使用 `perf record -e sched:sched_stat_sleep -g` 或 `offcputime-bpfcc` 收集。

### Step 2: Off-CPU 分类

```bash
python scripts/analyzers/offcpu_classifier.py --input folded.folded --json
```

按 `references/offcpu-patterns.md` 第 4、7 类归类：
- 计时器与延迟
- 进程/线程管理

### Step 3: 模式检测

```bash
python scripts/analyzers/pattern_match.py --input folded.folded --json
```

重点匹配：

| 类别 | 特征函数/符号 | 权重 |
|------|-------------|------|
| 高精度定时器 | `hrtimer_nanosleep`, `hrtimer_run_queues`, `do_nanosleep` | 0.9 |
| 低精度定时器 | `schedule_timeout`, `schedule_hrtimeout_range` | 0.8 |
| 通用 sleep | `msleep`, `ssleep`, `sys_nanosleep` | 0.7 |
| usleep | `do_usleep_range`, `usleep_range` | 0.6 |
| 线程 join | `pthread_join`, `Thread.join`, `Join` | 0.9 |
| 等子进程 | `wait4`, `waitid`, `do_wait`, `waitpid` | 0.9 |
| Go sleep | `runtime.gopark`, `time.Sleep`, `runtime.sigpark` | 0.8 |
| Java park | `LockSupport.parkNanos`, `LockSupport.parkUntil` | 0.8 |
| 协程让出 | `runtime.Gosched`, `sched_yield` | 0.7 |

### Step 4: 调度延迟量化

火焰图宽度 ≈ 等待时间。结合样本总数与墙钟时间估算：

```
等待总时长 ≈ sum(所有睡眠样本) / 总样本数 × 采样窗口时长
单次等待时长 ≈ 等待总时长 / 调用次数
```

## 输出结构

```
## 调度延迟分析

### 等待类型分布
- 主动 sleep: XX%
- 线程 join: XX%
- 子进程等待: XX%
- 调度器 idle: XX%
- 合计: XX%

### 主动 sleep 热点
| 业务方法 | sleep 调用 | 累计等待 | 平均等待 | 占比 |
|---------|-----------|---------|---------|------|
| polling.loop | nanosleep(10ms) | 5.2s | 10ms | 35% |
| retry.backoff | Thread.sleep(100ms) | 3.1s | 100ms | 20% |

### 线程 join 热点
| 业务方法 | join 目标 | 累计等待 | 占比 |
|---------|----------|---------|------|
| batchProcessor | worker-1, worker-2 | 4.5s | 25% |

### 子进程等待
[wait4 / waitpid 路径]

### 调度 idle
[schedule;pick_next_task 的占比]
```

## 阈值标准

| 指标 | 阈值 | 严重度 |
|------|------|--------|
| sleep 类等待总占比 | > 10% | 中（业务主动让出） |
| sleep 类等待总占比 | > 30% | 高（轮询严重） |
| 调度 idle 占比 | > 20% | 高（系统负载不足） |
| 单次 sleep 平均时长 | > 100ms | 中（业务节奏过慢） |
| 线程 join 占比 | > 10% | 中（可能串行处理） |
| 调度延迟 P99 | > 10ms | 中（容器/cgroup 限制） |
| 调度延迟 P99 | > 100ms | 高（严重调度问题） |

## 典型场景

### 场景 1: 忙等轮询

**症状**：
- 火焰图 `nanosleep(1ms)` / `usleep(1000)` 反复出现
- 调用次数高，但每次 sleep 很短

**根因**：
业务用 sleep 模拟事件等待，没用 epoll / channel / 信号量。

**修复**：
- 改用事件驱动（epoll / io_uring / Go channel / Java NIO Selector）
- 用 `ConditionVariable` / `Semaphore` 替换 sleep
- 退避策略：用指数退避 + 抖动

### 场景 2: 退避过激

**症状**：
- 火焰图 `Thread.sleep(1000)` / `time.Sleep(time.Second)` 占比高
- 重试逻辑每次失败后 sleep 较长时间

**修复**：
- 退避时间合理化
- 限制最大退避时间（如 30s）
- 加抖动（jitter），避免雪崩
- 评估是否可改用异步通知

### 场景 3: 线程 join 串行化

**症状**：
- 火焰图 `pthread_join` / `Thread.join` 占比 > 10%
- 一组 worker 都 join 到同一根栈

**根因**：
- 业务主线程等所有子任务结束
- 任务可并行但被串行等待

**修复**：
- 改用 `CountDownLatch` / `CompletableFuture` / `Future.get(timeout)`
- Go 用 `errgroup` / `sync.WaitGroup`
- 评估是否真的需要等所有结果

### 场景 4: 子进程启动慢

**症状**：
- 火焰图 `wait4` / `waitpid` 占比 > 5%
- 主进程 fork 大量短命子进程

**根因**：
- 频繁 exec 外部命令
- fork 成本高（COW 写时复制 + 子进程启动开销）

**修复**：
- 用线程替代子进程（如果业务允许）
- 改用 RPC / 进程池
- 预 fork 池（prefork 模式）

### 场景 5: 容器 cgroup 限制

**症状**：
- 火焰图 `schedule` 占比不高，但 P99 调度延迟大
- 单核被 throttle（`cpu.cfs_throttled_us` 高）

**修复**：
- 调大 CPU quota
- 业务削峰（限流 + 队列）
- 拆分到多个容器

## 关键识别表

| 等待类型 | 根帧 | 业务场景 | 优化方向 |
|---------|------|---------|---------|
| 业务 sleep | `nanosleep`, `Thread.sleep` | 重试退避、轮询 | 改事件驱动 |
| 调度 idle | `schedule;pick_next_task` | 系统空闲 | 不算问题 |
| 线程 join | `pthread_join` | 主等子任务 | 改 Future / WaitGroup |
| 子进程 wait | `wait4`, `waitpid` | 外部命令 | 改 RPC / 线程 |
| Goroutine 调度 | `runtime.gopark` | Go 业务 | 检查 channel/锁设计 |
| 协程 yield | `runtime.Gosched` | Go 主动让出 | 合理即可 |
| Java park | `LockSupport.parkNanos` | Java 锁/条件 | 检查锁使用 |
| epoll | `epoll_wait` | 事件循环 | 见 [io-wait.md](io-wait.md) |

## 与其他剧本的协同

| 关联剧本 | 协同方式 |
|---------|---------|
| [io-wait.md](io-wait.md) | `epoll_wait` 等待事件 |
| [lock-contention.md](lock-contention.md) | `pthread_cond_wait` 走超时机制 |
| [why-context-switch.md](why-context-switch.md) | 频繁 sleep 也推高切换 |
| [joint-on-off-cpu.md](joint-on-off-cpu.md) | 调度延迟需 On/Off 联合看 |

## 优化建议

### 1. 用事件驱动替代 sleep 轮询

- **C/C++**：epoll / io_uring
- **Java**：NIO Selector / `CompletableFuture`
- **Go**：channel / `select` / context
- **Python**：`asyncio` / `aiohttp`

### 2. 合理退避

- 指数退避 + 抖动：`min(cap, base * 2^attempt) + random(0, jitter)`
- 最大退避不超过业务 SLA
- 失败 N 次后熔断（不再重试）

### 3. 异步化串行 join

- 用 Future 收集结果，主线程只 wait 一次
- Go 用 errgroup 控制并发数
- 评估是否真的需要"全成功才返回"

### 4. 减少子进程

- 内部命令改用库调用（如 `curl` → `requests`）
- 进程池复用
- 评估 fork 频率

### 5. 容器调优

- 调大 CPU quota（与 limit 对齐）
- 关闭 cgroup CPU 抢占（`cpu.cfs_quota_us` = 100000 × cores）
- 评估是否需要绑核

## 配套工具命令

```bash
# Off-CPU 采样
perf record -e sched:sched_stat_sleep -ag -p <pid> sleep 30
perf script > offcpu.perf

# 调度延迟
perf stat -e 'sched:sched_stat_sleep,sched:sched_switch' -p <pid> sleep 10

# cgroup throttling
cat /sys/fs/cgroup/cpu/system.slice/*.service/cpu.stat
# 关注 nr_throttled / throttled_time

# 进程级上下文切换
cat /proc/$PID/status | grep ctxt

# 调度器延迟（cfs）
perf bench sched pipe
```

## 常见误判

- **"sleep 多" 一定是问题吗**：业务合理节流是必要的，关键是看占比和必要性
- **"调度延迟高" 一定是系统问题**：可能是业务主动让出，需看栈上调用方
- **"子进程慢" 一定是子进程问题**：可能是 fork 本身慢，需分层排查
- **"协程让出多" 一定是问题**：Go 调度器本就频繁让出，正常
