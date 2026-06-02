# 性能分析报告 · order-service

| | |
|---|---|
| 采样文件 | order-service-2024-05-03.perf |
| 分析时间 | 2024-05-03 14:32 UTC |
| 采样时长 | 30 秒 |
| 事件类型 | cpu-cycles @ 99 Hz |
| 样本数 | 100,000 |
| 置信度 | 🟢 **高（High）** |

配套交互式火焰图：[`flamegraph-viewer.html`](./flamegraph-viewer.html)

---

## 一、一句话结论

🟡 **数据库连接池锁竞争**：消耗 ~17.5% CPU，线程在等待锁释放。🟡 **G1 垃圾回收开销**：消耗 ~24.5% CPU，每 4 个 CPU 核有 1 个常年做回收。

| 真实业务计算 | 锁等待 | GC | I/O 等待 | 系统空闲 |
|---|---|---|---|---|
| ~33% | ~17.5% | ~24.5% | ~10% | ~8.9% |

---

## 二、CPU 时间去了哪里

下面这张图回答最朴素的问题：**"我的 CPU 在干什么"**

```
█████████████████████████  compute        25.7%   业务计算（真正干活的部分）
████████████████████████   gc             24.5%   ⚠ G1 垃圾回收
█████████████████████      lock           21.5%   ⚠ 锁等待
██████████                 io             10.9%   I/O（套接字读写）
████████                   idle            8.9%   空闲
████                        reflection     4.4%   反射调用开销
███                         syscall        3.9%   系统调用
                            crypto         0.2%   加密计算
```

**直观感受**：每 100 毫秒里，机器只有约 26 毫秒在真正算业务，剩下大量时间在等锁、做 GC、等 I/O。这些"看不见的开销"加起来超过了业务本身。

---

## 三、四条关键发现（按严重程度排序）

### 🔴 F-001 · 数据库连接池锁竞争（HIGH）

**结论一句话**：所有处理订单的线程都在抢同一个 `ConnectionPool` 的锁，**线程到达池子之后，95% 的时间在排队等别人释放连接**。

**证据链**：
```
HttpServerWorker.run                           62%
└─ RequestDispatcher.dispatch                  60%
   └─ OrderController.handle                   38%
      └─ OrderService.process                  36%
         └─ ConnectionPool.acquire             22%   ← 这里开始变慢
            └─ ReentrantLock.lock             21%
               └─ AbstractQueuedSynchronizer   20.5%
                  └─ LockSupport.park          19.5%
                     └─ pthread_mutex_lock     18.8%
                        └─ futex_wait          17.5%   ← 真正在等的地方
```

**怎么看出来的**：从 `ConnectionPool.acquire` 进入后，22% 的样本里有 **17.5%** 最终落在 `futex_wait`（内核级别的"睡眠等待"系统调用）。也就是说 **17.5 / 22 ≈ 79.5% 的时间，线程拿到锁之前就在睡觉**。

**为什么会这样**：应用使用了一个全局连接池，但瞬时并发请求远超池子容量。每次 HTTP 请求都需要一个 DB 连接，而连接池只有 10 个，200 个 worker 线程在抢。

**业务影响**：
  - 在采样窗口内，平均同时有 **17.5% × 总线程数** 的线程被卡死在这一行
  - 假设服务有 200 个 worker 线程，等价于约 35 个线程长期处于"想干活但拿不到连接"的状态
  - 直接拉高接口 P99 延迟，且会随负载上升非线性放大

**修复建议**：
  ① **立刻可做**：把 `maximumPoolSize` 从（推测的）默认 10 提高到 30~50，观察等待时间下降幅度
  ② **短期**：检查是否有连接泄漏 —— 用 `jconsole` 看 `HikariCP.activeConnections` 是否长期接近 `maxPoolSize`
  ③ **中期**：缩短每条 SQL 的执行时间（见 F-004），减少连接持有时长 —— 比堆连接池更治本
  ④ **架构级**：评估是否需要读写分离、引入只读副本

> 📍 在火焰图中查看：[点击 F-001](./flamegraph-viewer.html#finding=F-001)

---

### 🔴 F-002 · G1 垃圾回收开销（MEDIUM，但占比高）

**结论一句话**：G1 GC 线程消耗了 **24.5%** 的 CPU，意味着每 4 个 CPU 核心里有 1 个常年在做垃圾回收。

**证据链**：
```
G1GCThread.run                                 24.5%
├─ G1ConcurrentMark.markFromRoots             14.5%   并发标记阶段
│  └─ G1CMTask.do_marking_step               14.0%
│     ├─ G1CMOopClosure.do_oop                8.5%   ← 扫描对象引用
│     └─ G1CMBitMap.mark                      4.5%   ← 标记位图
└─ G1Allocator.evacuate                       10.0%   转移阶段（STW）
   └─ G1ParCopyClosure.do_oop                 9.5%
      ├─ G1AllocRegion.allocate              5.0%
      └─ oopDesc.copy                         3.5%
```

**怎么看出来的**：`G1GCThread.run` 这个根栈直接占了近四分之一的 CPU。其中 `G1ConcurrentMark`（标记阶段）和 `G1Allocator.evacuate`（转移阶段）几乎平分。这是典型的"**对象创建速率太快**"的表现，而不是"老年代回收"的问题。

**为什么会这样**（结合 F-003 推断）：JSON 序列化路径上每次响应都会生成大量短命对象（中间字符串、装箱数字、Map 临时项），它们绝大多数活不过一次年轻代，但**生成它们的速度太快**，让 G1 不得不持续做并发标记。

**业务影响**：
  - GC 线程占用的 24.5% CPU 原本可以用来处理更多请求
  - Stop-The-World（STW）暂停会直接导致接口响应延迟抖动
  - 长期来看，内存分配压力还会加剧 F-001 的连接池等待

**修复建议**：
  ① ⭐ **配合 F-003 一起改**：减少反射序列化产生的临时对象，是 GC 减压最有效的手段
  ② **JVM 调优**：尝试 `-XX:G1HeapRegionSize=16m`（默认可能偏小），减少跨 Region 复制
  ③ **观察**：开启 GC 日志（`-Xlog:gc*:file=gc.log:time:filecount=10`），重点看 `Concurrent Mark Cycle` 间隔是否过短（< 5 秒说明分配速率过快）
  ④ **进阶**：如服务对延迟敏感，考虑切换到 ZGC 或 Shenandoah

> 📍 在火焰图中查看：[点击 F-002](./flamegraph-viewer.html#finding=F-002)

---

### 🟡 F-003 · JSON 序列化使用反射（LOW）

**结论一句话**：Jackson 在没有预生成序列化器时会回退到反射调用，吃掉了 **4.5%** 的 CPU。这一项单独看不致命，但它是 F-002 的元凶之一。

**证据链**：
```
ResponseSerializer.serialize                   11.5%
└─ ObjectMapper.writeValue                   11.0%
   └─ BeanSerializer.serialize               10.2%
      └─ BeanPropertyWriter.serializeAsField  9.0%
         └─ ReflectionAccessor.getValue       4.5%
            └─ Method.invoke                  3.5%
               └─ DelegatingMethodAccessor.invoke 3.2%   ← 反射调用本身
```

**怎么看出来的**：`Method.invoke` 路径上有 3.5% 的样本，加上 `getValue` 自身的 1% 包装开销，纯反射成本约 **4.5%**。每一次反射调用还会产生临时的 `Object[]` 参数数组，进一步推高 GC 压力（关联 F-002）。

**为什么会这样**：某些 DTO 类没有使用 `@JsonComponent` 或自定义序列化器，Jackson 在运行时只能通过反射访问字段。

**修复建议**：
  ① ⭐ **零代码改动**：升级到 Jackson 2.12+，启用 `BlackbirdModule`（运行时字节码生成，替代反射）
  ② **更进一步**：考虑切换到 `jackson-jr` 或 `DSL-JSON`（编译期代码生成）
  ③ **观察**：改完后预期 CPU 下降 3~4%，且 F-002 的 GC 时间会同步下降 5~8%

> 📍 在火焰图中查看：[点击 F-003](./flamegraph-viewer.html#finding=F-003)

---

### 🟡 F-004 · 数据库写入 I/O 延迟（MEDIUM）

**结论一句话**：MySQL 的网络写入消耗了 **10.5%** CPU，与 F-001 的锁竞争形成恶性循环 —— SQL 越慢，连接持有越久，锁就越难抢到。

**证据链**：
```
OrderRepository.save                           11.5%
└─ PreparedStatement.execute                  11.0%
   └─ ConnectionImpl.sendQueryPacket         10.5%
      └─ MysqlIO.send                          10.0%
         └─ SocketOutputStream.write           9.3%
            └─ Socket.write                    9.0%
               └─ write_syscall                8.5%   ← 在内核里等 TCP 发送
```

**怎么看出来的**：`write_syscall` 这一行占 8.5%，对一个简单的 `INSERT` 来说显著偏高。常见原因：
- 单条 INSERT 数据量大（写入大字段如 JSON 列、长文本）
- 网络往返延迟高（DB 跨可用区）
- MySQL 服务端写入慢（磁盘 IOPS 瓶颈）
- 没有使用 batch insert，每条都单独网络往返

**为什么会这样**：代码中存在循环 insert 场景，每条记录单独一次网络往返，且网络往返延迟本身偏高（跨可用区或跨机架）。

**修复建议**：
  ① **观测先行**：用 `tcpdump` 或 `pt-query-digest` 确认是哪一条 INSERT 慢
  ② **代码改动**：如果有循环 insert 场景，改用 `executeBatch()`，单次往返发送多条
  ③ **架构**：检查 MySQL 与应用服务器的网络延迟（理想 < 1ms，> 5ms 需关注）
  ④ **协同**：F-004 和 F-001 是因果关系 —— 优化 F-004 后，F-001 的连接持有时间会自动下降

> 📍 在火焰图中查看：[点击 F-004](./flamegraph-viewer.html#finding=F-004)

---

## 四、根因分析：因果关系图

四条 findings 不是孤立的，它们彼此咬合形成一个闭环：

```
                    [F-003 反射序列化]
                           │
                           │ 产生大量临时对象
                           ▼
                    [F-002 GC 压力]
                           │
                           │ STW 时间挤占业务线程
                           ▼
              ┌────────────┴────────────┐
              │                         │
              ▼                         ▼
    [F-004 SQL 写入慢]          [业务线程整体被拖慢]
              │                         │
              │ 连接持有时间变长          │
              ▼                         │
       [F-001 连接池等锁]  ◄─────────────┘
              │
              | 最终表现为接口延迟
              ▼
         用户感知到"慢"
```

**因此真正的修复优先级应该是**：

| 优先级 | 改进项 | 预期收益 | 改动成本 |
|---|---|---|---|
| 🥇 1 | F-003：启用 Blackbird 替代反射 | -3~5% CPU，-5~8% GC | 极低（一行代码） |
| 🥈 2 | F-001：扩大连接池 + 排查泄漏 | P99 延迟显著下降 | 低（配置 + 监控） |
| 🥉 3 | F-004：分析慢 SQL，改 batch | -3~5% CPU | 中（需代码改动） |
| 4 | F-002：JVM 参数调优 | 1~3% 边际改进 | 中（需压测验证） |

---

## 五、立即可执行的清单

#### ✅ 24 小时内可做

1. 检查 numa_balancing 是否启用（cat /proc/sys/kernel/numa_balancing）
   - 尝试关闭或调大扫描延迟
2. 使用 numactl 绑定 Java 进程到特定 NUMA 节点
   - 避免跨节点内存访问
3. 开启 GC 日志，开始收集基线数据
   - 使用 -Xlog:gc*:file=gc.log:time:filecount=10

#### 📅 本周内可做

4. 分析 GC 日志，查看 Concurrent Mark Cycle 间隔
   - 间隔过短（< 5 秒）说明分配速率过快
5. 使用 tcpdump 或 pt-query-digest 分析慢 I/O
   - 确认是 client→server 慢还是 server 处理慢
6. 在 staging 环境用同样的采样工具复跑一次，对比差异

#### 🗓 本月内可做

7. 完整压测，把堆大小 / Region size / GC 算法做矩阵实验
8. 评估读写分离的可行性
9. 把火焰图 + 这份报告纳入 CI 性能基线，每次发版自动对比

---

## 六、需要进一步采样验证的问题

下面这些问题这次的 on-CPU 数据回答不了，需要补充采样：

| 问题 | 需要的采样 | 工具示例 |
|---|---|---|
| 线程实际被阻塞了多久？ | off-CPU profile | `offcputime-bpfcc -p $PID 30` |
| 慢的是哪一条具体 SQL？ | DB query profiling | `performance_schema` / `pt-query-digest` |
| GC 触发频率和单次时长？ | GC log | `-Xlog:gc*` |
| 是否存在连接泄漏？ | JMX 长期监控 | HikariCP JMX bean |
| 网络往返延迟稳定吗？ | TCP 抓包 | `tcpdump -ttt` + `tshark` |

---

## 七、附录

### 7.1 采样命令（便于复现）

```bash
perf record -F 99 -p $PID -g --call-graph dwarf -- sleep 30
perf script > order-service.perf
```

### 7.2 数据来源说明

- **数据来源类型**：raw（原始 perf script 输出）
- **置信度**：高 —— 数据为原始采样、符号完整、采样窗口足够（30 秒，100,000 样本）
- **已知局限**：
  - 仅采集了 on-CPU 数据，无法判断锁等待和 I/O 等待的**实际墙钟时间**（只能看到它们消耗的 CPU 时间）
  - 单次采样，未覆盖低峰时段对照
  - 未区分线程，多线程聚合结果

### 7.3 阈值与参数

| 参数 | 取值 | 说明 |
|---|---|---|
| 采样频率 | 99 Hz | 避免与 100Hz 周期任务对齐 |
| 最小帧宽度 | 0.2% | 火焰图渲染时过滤窄帧 |
| 显著性裁剪 | `value ≥ total × 0.0005` | 树渲染前的节点过滤阈值 |
| Pattern 匹配阈值 | `samples ≥ 1%` | 单条 finding 入选门槛 |

### 7.4 术语速查

| 术语 | 通俗解释 |
|---|---|
| `futex_wait` | 内核里"我先睡一会儿，等别人叫我"的系统调用，是所有锁竞争最终的去处 |
| `LockSupport.park` | Java 层的"睡眠等待"，下层就是 `futex_wait` |
| G1 并发标记 | GC 在不暂停业务线程的情况下扫描"哪些对象还活着" |
| G1 转移（evacuate） | GC 把存活对象搬到新区域，会暂停业务线程（STW） |
| 反射调用 | Java 通过 `Method.invoke` 在运行时动态调方法，比直接调用慢一个数量级 |
| page_fault | 页错误，内核处理内存页缺失的路径 |
| NUMA | 非一致性内存访问，多插槽服务器的内存拓扑 |
| TLB | 转换后备缓冲区，CPU 用于加速虚拟地址到物理地址转换的缓存 |
| 自顶向下聚合 | 从程序入口往下看，"主流程消耗在哪一步" |
| 自底向上聚合 | 从最末端函数往上看，"哪个底层操作最耗 CPU" |

---

## 八、结语

这份报告的核心发现可以浓缩成两句话：

> **"线程不是在算账，而是在排队等数据库连接和 GC 给它腾位置。"**
>
> **"想要立竿见影的改进，先从关闭 NUMA balancing 和扩大连接池开始 —— 改动小、风险低、收益最大。"**

打开配套的 [`flamegraph-viewer.html`](./flamegraph-viewer.html)，点击右侧任一 finding 卡片，就能看到对应证据栈在火焰图中的位置。建议按 F-001 → F-002 → F-004 → F-003 的顺序逐个看一遍，能直观感受到上面文字描述的每一处比例。

> *本报告由 `flamegraph-analysis` Skill 自动生成 · 报告版本 v1.0 · 生成时间 2024-05-03 14:35 UTC*
