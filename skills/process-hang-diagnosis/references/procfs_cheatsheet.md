# 进程 procfs 关键文件速查（挂起诊断专用）

> 配合 SKILL.md "OS 状态轨道"使用。所有操作只读，对进程无影响。

---

## 一、核心状态文件

### 1. `/proc/[pid]/status` — 进程主状态

```bash
cat /proc/<pid>/status
```

| 字段 | 含义 | 挂起诊断价值 |
|------|------|-------------|
| `State` | 进程状态 | R=运行/S=睡眠/D=磁盘睡眠/T=停止/t=跟踪/Z=僵尸 |
| `SigBlk` | 被屏蔽信号位图 | 屏蔽了 SIGTERM/SIGINT 可能导致 kill 杀不死 |
| `SigCgt` | 已捕获信号位图 | 确认进程是否注册了信号处理函数 |
| `SigIgn` | 已忽略信号位图 | 确认是否忽略关键信号 |
| `ShdPnd` | 共享挂起信号 | 待发送的信号位图 |
| `vmRSS` | 物理内存占用 | 判断是否内存泄漏 |
| `Threads` | 线程数 | 确认是否为多线程进程 |

**State 的挂起含义：**

| State | 含义 | 典型原因 |
|-------|------|---------|
| R | 运行/可运行 | 正常/死循环/CPU 占用 100% |
| S | 可中断睡眠 | 正常等待 / 等待 event/IO 完成 |
| D | 不可中断睡眠 | 内核 IO 阻塞（磁盘/NFS/FUSE 等） |
| T | 停止 | 收到 SIGSTOP/SIGTSTP/SIGTTIN/SIGTTOU |
| t | 跟踪停止 | 被 ptrace（gdb/strace 等） |
| Z | 僵尸 | 已退出但父进程未 wait |

### 2. `/proc/[pid]/wchan` — 内核等待点（核心字段）

```bash
cat /proc/<pid>/wchan
```

**挂起场景 — wchan 典型值速查：**

| wchan | 含义 | 可能场景 |
|-------|------|---------|
| `futex_wait_queue_me` | futex 等待 | 锁竞争 / 死锁 |
| `do_futex` | futex 系统调用处理 | futex 操作（含 PI futex） |
| `__mutex_lock_slowpath` | 内核 mutex 等待 | 内核锁竞争 |
| `pipe_read` | pipe 读阻塞 | 读空管道 |
| `pipe_write` | pipe 写阻塞 | pipe 缓冲区满 |
| `sock_rcvmsg` / `sock_recvmsg` | socket 读 | socket 阻塞读 |
| `sock_sendmsg` | socket 写 | socket 阻塞写 |
| `inotify_read` | inotify 等待 | inotify 等待事件 |
| `do_signal_stop` | 信号停止 | 收到 SIGSTOP |
| `wait_woken` | 通用等待 | 多种睡眠场景 |
| `epoll_wait` | epoll 等待 | epoll 事件等待 |
| `poll_schedule_timeout` | poll 等待 | select/poll/epoll 超时等待 |
| `n_tty_read` | tty 读 | 终端输入等待 |
| `blkdev_direct_IO` | 块设备 IO | 磁盘直 IO |
| `__lock_page_killable` | 页缓存等待 | 内存页 IO |
| `rpc_wait_bit_killable` | NFS RPC 等待 | NFS 服务器无响应 |
| `wait_on_page_bit` | 页位图等待 | 文件系统缓存等待 |
| `__iowait` | IO 等待 | 通用 IO 阻塞 |
| `do_nanosleep` | 定时睡眠 | `sleep()` 调用中 |

### 3. `/proc/[pid]/stack` — 内核调用栈（Linux 2.6.35+）

```bash
cat /proc/<pid>/stack
```

**用途：** 当 wchan 不够精确时（如 `futex_wait_queue_me` 不区分 PI futex/PI futex/标准 futex），stack 显示完整内核路径。

**示例解读：**
```
[<ffffffff81234567>] futex_wait_queue_me+0x123/0x200
[<ffffffff81234890>] futex_wait+0xf0/0x250
[<ffffffff812350ab>] do_futex+0x11b/0x150
[<ffffffff8105ec1f>] SyS_futex+0xef/0x180
[<ffffffff8167f0c2>] entry_SYSCALL_64_after_hwframe+0x3d/0xa2
```
→ 进程在用户态调用 `futex(WAIT)` 后进入内核 futex 等待，表示在等待一个用户态锁。

### 4. `/proc/[pid]/sched` — 调度统计

```bash
cat /proc/<pid>/sched
```

**关键字段：**

| 字段 | 含义 |
|------|------|
| `se.statistics.wait_sum` | 累计等待时间（纳秒） |
| `se.statistics.nr_switches` | 上下文切换次数 |
| `se.statistics.nr_wakeups` | 被唤醒次数 |
| `se.statistics.nr_wakeups_affine` | 本地 CPU 唤醒 |
| `se.statistics.nr_wakeups_remote` | 跨 CPU 唤醒 |

**挂起诊断：** `wait_sum` 持续增长而 `nr_switches` 不变 → 进程在等待且未被调度。

### 5. `/proc/[pid]/syscall` — 当前系统调用（Linux 5.x+）

```bash
cat /proc/<pid>/syscall
```

**输出格式：** `0 futex 0x7f8c12345000 0x1d 0x0 0x0 0x7f8c12345000`
- 第1列：系统调用号（0=read, 1=write, 202=futex, ...）
- 第2列起：系统调用参数（arg0-arg5）

**挂起诊断：** 对处于 S/D 状态的进程，如果 syscall 连续多次采样不变，说明进程阻塞在该系统调用上。

**常用系统调用号：**
```
0   read
1   write
202 futex
35  nanosleep
23  select
7   poll
40  sendfile
```

---

## 二、文件描述符与资源依赖

### 6. `/proc/[pid]/fd/` — 文件描述符目录

```bash
ls -la /proc/<pid>/fd/
```

**输出示例：**
```
lrwx------ 0 -> /dev/null
lrwx------ 1 -> /dev/pts/0
lrwx------ 2 -> /dev/pts/0
lrwx------ 3 -> socket:[123456]
lrwx------ 4 -> pipe:[789012]
lrwx------ 5 -> /var/lock/myapp.lock
```

**fd 类型与阻塞关系：**

| fd 链接目标 | 可能阻塞的系统调用 |
|-------------|------------------|
| `pipe:[N]` | read/write/splice |
| `socket:[N]` | recv/send/accept/connect |
| `(deleted)` 文件 | 文件已被删除（可能引发 IO 异常） |
| 普通文件 | read/write 可能因 lock 阻塞 |
| `/dev/*` | 设备驱动 IO |

### 7. `/proc/[pid]/io` — IO 统计

```bash
cat /proc/<pid>/io
```

**关键字段：**
- `rchar` / `wchar`: 读/写字节数（所有系统调用累计）
- `read_bytes` / `write_bytes`: 实际物理 IO 字节数

**挂起诊断：** 全量挂起时 `rchar`/`wchar` 完全不增长；部分 IO 挂起时 `rchar` 增长慢于 `read_bytes`（页缓存命中 vs 磁盘读）。

---

## 三、信号相关

### 8. 信号位图解析

```bash
# 信号掩码（16进制位图，共 64bit）
SigBlk: 0000000000000200  # bit 9 = SIGKILL(不可屏蔽,显示为0)?
                          # 实际 SIGKILL(9)/SIGSTOP(19) 永远不在 Blk 中
SigCgt: 0000000000008000  # bit 15 = SIGTERM
SigIgn: 0000000000000001  # bit 1 = SIGHUP
```

**常用信号位图值速查：**
```
bit 1  (SIGHUP)     0x0000000000000001
bit 2  (SIGINT)     0x0000000000000002
bit 3  (SIGQUIT)    0x0000000000000004
bit 9  (SIGKILL)    不可屏蔽
bit 15 (SIGTERM)    0x0000000000004000  (1<<15)
bit 19 (SIGSTOP)    不可屏蔽
```

**SigBlk 包含 SIGTERM → 可能是 kill -15 杀不死的原因。**

---

## 四、系统级资源

### 9. `/proc/locks` — 全系统文件锁

```bash
cat /proc/locks
```

**输出格式：**
```
1: POSIX  ADVISORY  WRITE 12345 08:02:123456 0 EOF
2: FLOCK  ADVISORY  WRITE 12345 08:02:123456 0 EOF
```

| 列 | 含义 |
|----|------|
| `1:` | 锁 ID |
| `POSIX` / `FLOCK` | 锁类型（POSIX 锁 / flock 锁） |
| `ADVISORY` / `MANDATORY` | 建议锁 / 强制锁 |
| `READ` / `WRITE` | 读锁 / 写锁 |
| `12345` | 持有锁的进程 PID |
| `08:02:123456` | 设备号:inode |
| `0 EOF` | 锁范围（起始偏移 结束偏移） |

**挂起诊断：** 检查目标进程的 fd 对应的 inode 是否出现在 `/proc/locks` 中，以及锁的持有者是否存活运行。

### 10. sysrq-w / sysrq-t — 内核 trace 转储

```bash
# 需要 root
echo w > /proc/sysrq-trigger    # 输出所有 D 状态进程的 stack trace
echo t > /proc/sysrq-trigger    # 输出所有进程的 stack trace
```

输出在 `dmesg` 或 `/var/log/kern.log` 中。不受 `/proc/<pid>/stack` 截断限制，可获取完整内核栈。

---

## 五、状态变化监控

```bash
# 监控进程状态变化（采样间隔 1s）
while true; do
  date +%H:%M:%S
  cat /proc/<pid>/status | grep -E "^State|^Sig"
  cat /proc/<pid>/wchan
  echo "---"
  sleep 1
done
```

进程状态不随时间变化 = 已 hang 在该状态。
