# Off-CPU Leaf Frame Classification

Off-CPU 采样（如 `perf sched sleep`）的叶帧分类，用于识别线程阻塞原因。

## 阻塞原因分类

### 1. 锁与同步等待

| 类别 | 特征函数/符号 | 说明 |
|------|-------------|------|
| Futex 等待 | `futex_wait`, `futex_wait_setup`, `__lll_lock_wait` | 用户态 futex |
| Futex 唤醒 | `futex_wake`, `futex_requeue` | 等待被唤醒 |
| 互斥锁 | `pthread_mutex_lock`, `__pthread_mutex_lock`, `sync.(*Mutex).Lock` | Go style |
| 条件变量 | `pthread_cond_wait`, `pthread_cond_timedwait` | 条件同步 |
| 读写锁 | `pthread_rwlock_wrlock`, `pthread_rwlock_rdlock` | 读/写锁等待 |
| 自旋锁 | `pthread_spin_lock`, `__spin_lock` | CPU 忙等 |
| Java Monitor | `Monitor::wait`, `Object.wait`, `java.util.concurrent.LockSupport.park` | JVM 同步 |
| .NET 锁 | `Thread.Sleep`, `Monitor.Wait`, `lock()` | CLR 同步 |

### 2. 磁盘 I/O

| 类别 | 特征函数/符号 | 说明 |
|------|-------------|------|
| 调度等待 | `io_schedule`, `wait_on_page_bit`, `folio_wait_bit` | 等待磁盘 I/O |
| 块设备 | `blkdev_issue_flush`, `blk_mq_get_tag` | 块设备操作 |
| 文件系统 | `ext4_file_read`, `xfs_file_read`, `nfs_read` | 文件系统读 |
| 页缓存 | `filemap_fault`, `page_fault`, `__do_page_fault` | 页缓存未命中 |

### 3. 网络 I/O

| 类别 | 特征函数/符号 | 说明 |
|------|-------------|------|
| Socket 读 | `sk_wait_data`, `tcp_recvmsg`, `inet_recvmsg` | 等待网络数据 |
| Socket 写 | `tcp_sendmsg`, `inet_sendmsg`, `sock_sendmsg` | 等待发送缓冲区 |
| epoll | `epoll_wait`, `epoll_pwait`, `sys_epoll_wait` | 事件等待 |
| poll/select | `poll_schedule_timeout`, `do_select`, `sys_poll` | 传统 I/O 多路复用 |
| 网络连接 | `inet_csk_accept`, `tcp_v4_connect` | 连接建立等待 |

### 4. 计时器与延迟

| 类别 | 特征函数/符号 | 说明 |
|------|-------------|------|
| 高精度定时器 | `hrtimer_nanosleep`, `hrtimer_run_queues` | 高精度 sleep |
| 低精度定时器 | `schedule_timeout`, `schedule_hrtimeout_range` | 低精度延迟 |
| 通用 sleep | `do nanosleep`, `msleep`, `ssleep` | 各种 sleep |
| usleep | `do_usleep_range`, `idle_cpu` | 微秒级延迟 |

### 5. GC 协作暂停

| 类别 | 特征函数/符号 | 说明 |
|------|-------------|------|
| Safe Point | `SafepointSynchronize::begin`, `VMThread::execute` | JVM 安全点 |
| GC 线程 | `gcBgMarkWorker`, `GC_task_thread` | GC 工作线程阻塞 |
| GC 同步 | `GC_locker::lock`, `GCCause::string` | GC 相关暂停 |

### 6. 页面错误与换入

| 类别 | 特征函数/符号 | 说明 |
|------|-------------|------|
| 缺页异常 | `do_page_fault`, `handle_mm_fault` | 内存页未分配 |
| 交换等待 | `swapin`, `folio_swapin`, `do_swap_page` | 从 swap 换入 |
| 文件映射 | `filemap_fault`, `mmap_region` | 文件映射缺页 |

### 7. 进程/线程管理

| 类别 | 特征函数/符号 | 说明 |
|------|-------------|------|
| 进程调度 | `schedule`, `finish_task_switch`, `pick_next_task_fair` | 调度器主动切换 |
| 等待子进程 | `wait4`, `waitid`, `do_wait` | 等待子进程退出 |
| 线程 join | `pthread_join`, `Thread.join`, `sync.WaitGroup.Wait` | 线程 join |
| 信号处理 | `flush_signal`, `deliver_signal` | 信号传递 |

### 8. 内存分配

| 类别 | 特征函数/符号 | 说明 |
|------|-------------|------|
| 大页分配 | `hugetlbfs_fault`, `alloc_huge_page` | 大页内存分配 |
| OOM 等待 | `out_of_memory`, `pagefault_out_of_memory` | OOM 等待 |
| slab 分配 | `kmem_cache_alloc`, `____slab_alloc` | 内核对象分配 |

## 分类算法

```python
OFFCPU_PATTERNS = {
    "lock": {
        "futex_wait": 1.0,
        "futex_wait_setup": 0.9,
        "pthread_mutex_lock": 0.9,
        "__pthread_mutex_lock": 0.9,
        "sync.(*Mutex).Lock": 1.0,
        "Monitor::wait": 1.0,
        "Object.wait": 0.8,
        "pthread_cond_wait": 0.7,
        ...
    },
    "disk_io": {
        "io_schedule": 1.0,
        "wait_on_page_bit": 0.9,
        "blkdev_issue_flush": 0.8,
        ...
    },
    "network_io": {
        "sk_wait_data": 1.0,
        "tcp_recvmsg": 0.9,
        "epoll_wait": 0.8,
        ...
    },
    ...
}

def classify_offcpu_leaf(leaf_frame: str) -> tuple[str, float]:
    for category, patterns in OFFCPU_PATTERNS.items():
        for pattern, confidence in patterns.items():
            if pattern in leaf_frame:
                return category, confidence
    return "unknown", 0.0

def analyze_offcpu(folded_content: str) -> dict:
    results = defaultdict(lambda: {"count": 0, "samples": 0, "stacks": []})

    for line in folded_content.strip().split("\n"):
        if not line or line.startswith("#"):
            continue
        stack, count = parse_folded_line(line)
        leaf = stack.split(";")[-1] if stack else ""

        category, confidence = classify_offcpu_leaf(leaf)
        results[category]["count"] += 1
        results[category]["samples"] += int(count)
        results[category]["stacks"].append((stack, count))

    return dict(results)
```

## 联合分析输出格式

当同时分析 on-CPU 和 off-CPU 数据时，输出：

```json
{
  "on_cpu": {
    "total_samples": 100000,
    "categories": {"cpu_bound": 60000, "lock": 20000, "io": 15000, "gc": 5000}
  },
  "off_cpu": {
    "total_samples": 50000,
    "categories": {"lock": 20000, "disk_io": 15000, "network_io": 10000, "unknown": 5000}
  },
  "joint": [
    {
      "stack": "main;handle_request;process",
      "on_ms": 45000,
      "off_ms": 5000,
      "on_ratio": 0.9,
      "off_ratio": 0.1,
      "blocking_ratio": 0.1
    }
  ]
}
```

其中 `blocking_ratio = off / (on + off)`：
- 接近 1：纯阻塞型路径
- 接近 0：纯计算型路径
- 0.3-0.7：混合型，需要进一步分析
