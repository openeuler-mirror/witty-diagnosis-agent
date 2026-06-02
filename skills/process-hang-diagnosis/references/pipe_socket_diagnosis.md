# 管道与 Socket 阻塞故障诊断

> 配合 SKILL.md 分支 D（管道/Socket 阻塞读写）使用。

---

## 一、管道（Pipe）阻塞

### 1.1 读端阻塞

**现象：** 进程 hang 在 `read(pipe_fd, ...)` 不返回。

**OS 侧特征：**
- `wchan=pipe_read`
- `cat /proc/<pid>/stack` 显示 `pipe_read` → `vfs_read` → `sys_read`
- `State=S`（读空管道默认睡眠，可中断）

**根本原因：** 写端没有写入数据就关闭了，或者写端写入速度低于读端读取速度且缓冲区为空。

**诊断步骤：**
```bash
# Step 1: 确认进程在那个 fd 上读
ls -la /proc/<pid>/fd/
# 输出: 3 -> pipe:[123456]

# Step 2: 找到 pipe 对端
find /proc/*/fd -lname "pipe:[123456]" 2>/dev/null
# 可以找到对端 PID

# Step 3: 检查对端状态
cat /proc/<対端PID>/status | grep -E "^State|^Name"
```

**典型场景：**
- 写端已崩溃/退出 → pipe 读端读空缓冲区后阻塞
- 写端 hang 住不写 → pipe 读端正常读空后等新数据
- 写端写入慢 → pipe 读端周期性被唤醒读少量数据

### 1.2 写端阻塞

**现象：** 进程 hang 在 `write(pipe_fd, ...)` 不返回。

**OS 侧特征：**
- `wchan=pipe_write`
- `State=S` 或 `State=D`（取决于写操作是否会触发 IO）
- 默认 pipe 缓冲区为 65536 字节（64KB，`/proc/sys/fs/pipe-max-size`）

**根本原因：** pipe 缓冲区满，读端没有读取。

**诊断步骤：**
```bash
# Step 1: 确认进程在那个 fd 上写
ls -la /proc/<pid>/fd/
# 输出: 4 -> pipe:[789012]

# Step 2: 找到读端 PID
find /proc/*/fd -lname "pipe:[789012]" 2>/dev/null

# Step 3: 检查读端状态
# 读端已退出 → pipe 满后继续写会收到 SIGPIPE（如果没有忽略/阻塞则会）
# 读端速度慢 → pipe 缓冲满导致写端阻塞
```

**`F_SETPIPE_SZ` 可调整 pipe 缓冲区大小：**
```c
fcntl(pipe_fd, F_SETPIPE_SZ, 1048576);  // 设为 1MB
```

---

## 二、Socket 阻塞

### 2.1 TCP Socket 读阻塞

**OS 侧特征：**
- `wchan=sock_rcvmsg` 或 `sock_recvmsg` 或 `tcp_recvmsg`
- `State=S`（可中断睡眠）
- `cat /proc/<pid>/syscall` 显示系统调用号 0（read）或 47（recvfrom）

**根本原因：** socket receive buffer 为空，对端没有发送数据。

**诊断步骤：**
```bash
# Step 1: 确认 socket 的 inode
ls -la /proc/<pid>/fd/
# 输出: 5 -> socket:[234567]

# Step 2: 查找 socket 状态
cat /proc/net/tcp | grep 234567
# 输出: sl local_address rem_address st tx_queue:rx_queue ...
# st = 0A 表示 TCP_ESTABLISHED
# rx_queue > 0 表示有可读数据但进程未读取

# Step 3: 检查对端连接状态
ss -t -p | grep <PID>
```

### 2.2 TCP Socket 写阻塞

**OS 侧特征：**
- `wchan=sock_sendmsg` 或 `tcp_sendmsg`
- `State=S`
- 可能同时伴有 `wchan=sk_stream_wait_memory`

**根本原因：** socket send buffer 满，对端读取速度太慢或窗口已关闭。
- 默认 send buffer 大小：`/proc/sys/net/ipv4/tcp_wmem`
- 对端窗口为 0（zero-window）时写会阻塞

**诊断步骤：**
```bash
# Step 1: 检查 tcp 连接状态
cat /proc/net/tcp | grep <inode>
# tx_queue:rx_queue — tx_queue 持续增大，rx_queue 不增长 → 对端不读

# Step 2: 确认 TCP 连接对端是否存活
ss -t -p | grep <local_port>

# Step 3: 确认 send buffer 是否满
cat /proc/net/sockstat | grep TCP
```

### 2.3 accept 阻塞

**现象：** 在 `accept()` 上阻塞，没有新连接到来。

**OS 侧特征：**
- `wchan=inet_csk_accept` 或 `sys_accept`
- 正常行为**不是故障**，除非应该接受连接但未收到
- `State=S`

**排查方向：** 检查对端是否能正常连接、`listen backlog` 是否满。

---

## 三、Unix Domain Socket 阻塞

### 3.1 Unix Socket 读阻塞

同 pipe 读阻塞——没有数据时阻塞在 `read()`。

### 3.2 Unix Socket 写阻塞

**差异点：** Unix socket 的 send buffer 是**共享内存**，缓冲区满时写阻塞。

**典型场景：** Unix DGRAM socket 缓冲区满。

**检查方法：**
```bash
ls -la /proc/<pid>/fd/ | grep socket
# 找到 socket:[inode]
find /proc/*/fd -lname "socket:[inode]" 2>/dev/null
# 确认对端进程是否存活
```

---

## 四、数据流分析卡点

### 4.1 管道缓冲区满 = 死锁的间接证据

当持有锁的线程向 pipe 写入但 pipe 满时：
```
Thread A(持锁L) → write(pipe) → pipe满 → 阻塞
Thread B(读pipe) → 需要lock L → 阻塞
→ 死锁（锁+缓冲区资源双重依赖）
```

**诊断方法：** 结合 `bt` 和 fd 分析，检查阻塞的读写操作是否在持锁帧的调用路径上。

### 4.2 对端消失检测

```bash
# 对 pipe
find /proc/*/fd -lname "pipe:[$INODE]" 2>/dev/null
# 若无输出 → 对端已退出

# 对 socket
fuser <socket_path> 2>/dev/null
# 若无输出 → 对端已退出

# 对 TCP
ss -t -p | grep <local_addr:port>
```

---

## 五、pipe/socket 阻塞快速检查命令

```bash
# 检查目标进程所有 fd 中有问题的
ls -la /proc/<pid>/fd/ 2>/dev/null | grep -E "pipe|socket"

# 对每个 pipe fd 找对端
for f in /proc/<pid>/fd/*; do
  link=$(readlink $f 2>/dev/null)
  if [[ $link == pipe:* ]]; then
    echo "FD $(basename $f): $link"
    echo "  对端:"
    find /proc/*/fd -lname "$link" 2>/dev/null | grep -v "/proc/$pid/"
  fi
done

# 确认进程是否在 pipe_read/pipe_write 状态
cat /proc/<pid>/wchan
# 若为 pipe_read/pipe_write → 管道阻塞

# 采集当前系统调用（Linux 5.x+）
cat /proc/<pid>/syscall
```
