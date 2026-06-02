# 死锁与锁竞争分析模式速查

> 配合 SKILL.md 分支 A（futex 等待）和分支 B（ABBA 死锁）使用。
> 按故障类型索引，每种模式给出：OS 侧特征、内省侧特征、搜索策略。

---

## 一、futex 锁等待

### 模式1：普通 mutex 竞争（非死锁，高竞争）

**OS 侧特征：**
- `wchan=futex_wait_queue_me`
- `cat /proc/<pid>/sched` 中 `wait_sum` 持续增长
- 进程 State=S，非 D

**内省侧特征：**
```
Thread 1: __lll_lock_wait → __pthread_mutex_lock → worker_func()
Thread 2: __lll_lock_wait → __pthread_mutex_lock → worker_func()
...
```
大量线程在 `__lll_lock_wait`（或 `__pthread_mutex_lock`），但持有锁的线程在正常运行（非阻塞）。

**诊断判断：** 非死锁，是锁竞争过高导致性能问题，不是 hang。
**推荐动作：** 检查锁粒度是否过大，能否改用读写锁/RCU/无锁结构。

---

### 模式2：futex 锁等待 + 持有者"消失"

**OS 侧特征：**
- `wchan=futex_wait_queue_me`
- `State=D` 或 `State=S` 长时间不变

**内省侧特征：**
```gdb
Thread 1: __lll_lock_wait → try_lock → ...
Thread 2: futex(FUTEX_WAIT) → ...
# 持有锁的线程（__owner）在 gdb 中不存在或处于异常状态
```

**诊断判断：** 锁持有者异常退出（crash/ kill -9）且锁未正确清理（非 robust mutex）。
**推荐动作：** 检查 `pthread_mutexattr_setrobust()` 的使用；或升级到 robust mutex。

---

### 模式3：PI futex（优先级继承）竞争

**OS 侧特征：**
- `wchan=futex_wait_queue_me`
- 高优先级线程等待低优先级线程持有的锁

**内省侧特征：**
```gdb
Thread A (high prio): __lll_lock_wait → __pthread_mutex_lock
Thread B (low prio):  正在运行持有锁（但可能被中优先级线程抢占）
```

**诊断判断：** 优先级反转——中优先级线程抢占低优先级锁持有者，高优先级被饿死。
**推荐动作：** 使用 `PTHREAD_PRIO_INHERIT`（优先级继承协议）或 `PTHREAD_PRIO_PROTECT`。

---

## 二、ABBA 死锁

### 模式4：经典 ABBA 死锁

**OS 侧特征：**
- 多线程 wchan 都是 `futex_wait_queue_me`
- 各线程之间没有 IO 活动（所有线程都在等锁）

**内省侧特征——关键识别模式：**
```gdb
Thread A:
  #0 __lll_lock_wait ()
  #1 __pthread_mutex_lock (mutex=0x7f...L2_addr)   ← 等 L2
  #2 resource_B_acquire ()
  #3 process_request ()
  #4 main_loop ()
  #5 ...
  #N __pthread_mutex_lock (mutex=0x7f...L1_addr)   ← 但持有了 L1
  #N+1 resource_A_acquire ()
  #N+2 dispatch ()

Thread B:
  #0 __lll_lock_wait ()
  #1 __pthread_mutex_lock (mutex=0x7f...L1_addr)   ← 等 L1
  #2 resource_A_acquire ()
  #3 other_request_handler ()
  #4 main_loop ()
  #5 ...
  #N __pthread_mutex_lock (mutex=0x7f...L2_addr)   ← 但持有了 L2
  #N+1 resource_B_acquire ()
  #N+2 dispatch ()
```

**验证条件：** Thread A 持有 L1 等 L2，Thread B 持有 L2 等 L1 → ABBA 死锁确认。

**不需要 LOCKDEP 即可通过 gdb bt 定位！**

**源码搜索策略：**
1. 从各线程的调用栈中提取加锁顺序
2. 对照各函数的 lock ordering 文档（或隐含约定）
3. 找到加锁顺序与其他路径相反的路径——即引入死锁的代码
4. 解法：统一加锁顺序

---

### 模式5：单线程递归死锁（非递归 mutex）

**OS 侧特征：**
- 单线程（或只有 1 个活跃线程）
- `wchan=futex_wait_queue_me`

**内省侧特征：**
```gdb
Thread 1:
  #0 __lll_lock_wait ()
  #1 __pthread_mutex_lock (mutex=0x7f...L1_addr)
  #2 func_B ()             ← 获取同一把锁（递归调用）
  #3 func_A ()             ← 先加了锁 L1
  #4 main ()
```

**诊断判断：** 同一线程试图锁住已持有的非递归 mutex，导致自己等自己。
**推荐动作：** 检查加锁路径是否有反向嵌套；或改用 `PTHREAD_MUTEX_RECURSIVE`。

---

### 模式6：持锁调用回调/通知

**OS 侧特征：**
- wchan 通常在 `futex_wait_queue_me` 或 `write`/`read`
- 可能多个线程 wchan 不同但共同阻塞

**内省侧特征：**
```gdb
Thread A (生产者):
  #0  write (fd=p[1], ...)    ← pipe 写阻塞（缓冲区满）
  #1  notify_consumer ()
  #2  produce_with_lock ()     ← 持有锁 L1
  
Thread B (消费者):
  #0  __lll_lock_wait ()
  #1  __pthread_mutex_lock (mutex=L1_addr)  ← 等 L1
  #2  consume ()               ← 持有锁 L1 才能消费
  #3  consumer_thread ()
```

**诊断判断：** Thread A 持有 L1 → 通知 pipe → pipe 满写阻塞（等待消费者读）→ 消费者在等 L1 → 循环死锁。
**推荐动作：** 持锁期间不应做阻塞通知；或使用非阻塞 IO/超时机制。

---

## 三、文件锁竞争

### 模式7：POSIX 文件锁（fcntl/F_SETLKW）冲突

**OS 侧特征：**
- `/proc/locks` 显示目标进程的 fd 对应的文件上有锁等待
- `wchan` 可能是 `sys_fcntl` 或 `do_lock_file_wait`

**定位步骤：**

```bash
# Step 1: 检查目标进程的 fd
ls -la /proc/<pid>/fd/ | grep lock

# Step 2: 查找对应的 inode 在 /proc/locks 中的锁状态
cat /proc/locks | grep <inode_number>

# Step 3: 确认锁持有者是否存活
cat /proc/locks | grep <inode> | grep WRITE
# 返回: 1: POSIX ADVISORY WRITE <holder_pid> ... (持有者 PID)
```

**典型场景：** 共享文件互斥写入 → 进程 B 持有写锁 → 进程 A 等待文件锁 → 表现为 A 挂起。

**推荐动作：** 确认持有者是否异常退出；文件锁在进程异常退出时会自动释放（POSIX 语义）；如持有者正常存活但处理慢，需优化锁持有时间或改用数据库层锁。

### 模式8：flock 冲突

**特征：** 同 POSIX 文件锁，但 `/proc/locks` 中类型列显示 `FLOCK` 而非 `POSIX`。

**与 POSIX 文件锁的差异：**
- POSIX 锁与 {PID,inode} 关联；flock 与 {fd} 关联
- POSIX 锁在进程退出时释放；flock 在 fd 关闭时释放
- 两者**不兼容**——同一文件上可以同时存在 POSIX 锁和 flock 锁

---

## 四、锁泄漏

### 模式9：锁未释放（lock leak）

**OS 侧特征：**
- wchan 在 `futex_wait_queue_me`，等待的锁计数器异常高
- `pthread_mutex_t.__data.__owner` 指向的线程 ID 已不存在

**内省侧特征：**
```gdb
(gdb) print my_lock
$1 = {
  __data = {
    __lock = 2,          # 标记为已锁定且有竞争者
    __owner = 54321,     # 但这个线程可能已不存在
  }
}
```

**诊断判断：** 线程获取锁后崩溃或异常中止，未执行解锁，锁永远由已终止的线程持有。

**推荐动作：** 使用 `pthread_mutexattr_setrobust()`（robust mutex），线程意外退出时内核会自动释放锁并通知下一个获取者。

---

## 五、锁分析通用工具命令

```bash
# 查看进程所有线程的 wchan
for t in /proc/<pid>/task/*/; do
  echo "TID: $(basename $t) wchan: $(cat $t/wchan)"
done

# 查看全部 futex 等待者（需要内核 ftrace/debug 支持）
cat /sys/kernel/debug/tracing/trace | grep futex 2>/dev/null

# 查看 perf lock 信息
perf lock report 2>/dev/null

# 使用 strace 追踪锁系统调用（慎用，会显著降低性能）
strace -e futex -p <pid> -c -t 3

# lslocks 命令（util-linux 包，查看全系统文件锁）
lslocks -p <pid>
```
