# UDS / Pipe 内核参数调优参考

> 配合 SKILL.md L1 系统层分析使用。

---

## 一、Unix Domain Socket 参数

### net.core.somaxconn

| 属性 | 值 |
|------|------|
| **路径** | `/proc/sys/net/core/somaxconn` |
| **含义** | UDS listen socket 的最大 backlog 长度（UDS 的 Send-Q 上限） |
| **默认** | 4096（Linux 5.4+）；128（旧内核） |
| **推荐** | 高并发 UDS 服务建议 1024~4096 |
| **查看** | `sysctl net.core.somaxconn` |
| **修改（临时）** | `sysctl -w net.core.somaxconn=4096` |
| **修改（持久化）** | `/etc/sysctl.conf` 添加 `net.core.somaxconn = 4096`，执行 `sysctl -p` |

**注意**：UDS listen 的实际 backlog 上限 = `min(server.listen(backlog), somaxconn)`。即使代码中设 backlog=65535，实际上限也是 somaxconn。

### /proc/net/unix

| 属性 | 值 |
|------|------|
| **路径** | `/proc/net/unix` |
| **含义** | 内核中所有 UDS socket 的全局表 |
| **各列含义** | 见 `references/unix_socket_pipe_commands.md` 第一节 |
| **典型异常** | 同一 @address 出现多次（冲突）；无路径条目过多（socketpair 泄漏） |

---

## 二、管道参数

### /proc/sys/fs/pipe-max-size

| 属性 | 值 |
|------|------|
| **路径** | `/proc/sys/fs/pipe-max-size` |
| **含义** | 单个 pipe 的最大容量（bytes），通过 `fcntl(fd, F_SETPIPE_SZ, size)` 可设置到该上限 |
| **默认** | 1048576（1MB） |
| **推荐** | 管道密集型应用可增大到 2MB~4MB |
| **查看** | `cat /proc/sys/fs/pipe-max-size` |
| **修改（临时）** | `echo 2097152 > /proc/sys/fs/pipe-max-size` |
| **修改（持久化）** | `/etc/sysctl.conf` 添加 `fs.pipe-max-size = 2097152` |

### /proc/sys/fs/pipe-user-pages-soft

| 属性 | 值 |
|------|------|
| **路径** | `/proc/sys/fs/pipe-user-pages-soft` |
| **含义** | 非特权用户 pipe 占用的总内存页数的软限制 |
| **默认** | 0（无限制） |
| **注意** | 超过此限制后 pipe 容量会被限制在 1 个页面（通常 4096 bytes） |

### /proc/sys/fs/pipe-user-pages-hard

| 属性 | 值 |
|------|------|
| **路径** | `/proc/sys/fs/pipe-user-pages-hard` |
| **含义** | 非特权用户 pipe 占用的总内存页数的硬限制 |
| **默认** | 0（无限制） |
| **注意** | 硬限制被超过时 `fcntl(F_SETPIPE_SZ)` 会返回 `EPERM` |

### 管道各容量值表

| 容量配置 | 默认值 | 最大值（pipe-max-size） | 调整方式 |
|---------|--------|------------------------|---------|
| 默认 pipe 容量 | 65536（64KB） | 1048576（1MB） | `fcntl(fd, F_SETPIPE_SZ, size)` |
| 单页面最小 | 4096（4KB） | - | 系统自动限制 |
| 用户总 pages 限制 | 0（无限制） | - | `pipe-user-pages-soft/hard` |

---

## 三、Socket 凭证参数

### net.core.optmem_max

| 属性 | 值 |
|------|------|
| **路径** | `/proc/sys/net/core/optmem_max` |
| **含义** | 每个 socket 辅助数据（cmsg）缓冲区的最大大小（bytes） |
| **默认** | 20480（20KB） |
| **作用** | 限制 `SO_PASSCRED` / `SCM_RIGHTS` / `SCM_CREDENTIALS` 辅助数据的总大小 |
| **调整建议** | 凭证传递密集型场景建议 40960~81920 |

### net.core.rmem_default / rmem_max

| 参数 | 路径 | 默认值 | 含义 |
|------|------|--------|------|
| rmem_default | `/proc/sys/net/core/rmem_default` | 212992（~208KB） | UDS stream socket 默认接收缓冲区 |
| rmem_max | `/proc/sys/net/core/rmem_max` | 212992（~208KB） | UDS 接收缓冲区最大值（setsockopt SO_RCVBUF 的上限） |

### net.core.wmem_default / wmem_max

| 参数 | 路径 | 默认值 | 含义 |
|------|------|--------|------|
| wmem_default | `/proc/sys/net/core/wmem_default` | 212992（~208KB） | UDS stream socket 默认发送缓冲区 |
| wmem_max | `/proc/sys/net/core/wmem_max` | 212992（~208KB） | UDS 发送缓冲区最大值（setsockopt SO_SNDBUF 的上限） |

**注意**：对于 UDS dgram 模式，buffer 限制同样适用，但 dgram 模式下发送数据超过接收缓冲区会导致返回 `ENOBUFS` 或 `EAGAIN`。

---

## 四、Socket 文件系统参数

### UDS 文件权限位

UDS socket 文件的标准权限表示（`ls -la` 输出）：

| 权限位 | 含义 | 说明 |
|--------|------|------|
| `srwxrwxrwx` | 0777 | 所有用户可连接（最宽松） |
| `srwxr-xr-x` | 0755 | owner 完全控制，其他用户只读和执行（可 connect） |
| `srwx------` | 0700 | 仅 owner 可 connect |
| `s-------wx` | 0003 | 其他用户可写不可读（某些 IPC 场景） |
| `s---------` | 0000 | 无任何权限（所有用户无法 connect → 权限错误） |

**第一个字符** `s` 表示 socket 文件类型。

**Sticky bit**：在 socket 文件上设置 sticky bit (`chmod +t /path/to/socket.sock`) 无实际效果，UDS 不使用 sticky bit 语义。

### /proc/sys/fs/file-max

| 属性 | 值 |
|------|------|
| **路径** | `/proc/sys/fs/file-max` |
| **含义** | 系统级最大打开文件数（含 UDS socket、pipe 等所有 FD） |
| **关联** | UDS socket 和 pipe 都消耗 FD，当系统 FD 耗尽时也会导致 UDS/pipe 创建失败 |
| **推荐值** | 参见 `references/kernel_fd_params.md` |

---

## 五、ulimit 相关

### RLIMIT_NOFILE

| 属性 | 值 |
|------|------|
| **参数** | `RLIMIT_NOFILE` |
| **含义** | 进程可打开的最大文件数（含 socket / pipe / 普通文件） |
| **影响** | UDS socket、pipe FD 都计入此限制。超过限制时 socket()/pipe() 返回 `EMFILE` |
| **查看** | `cat /proc/<PID>/limits \| grep "Max open files"` |
| **推荐** | 高并发 UDS 服务建议 65536~1048576 |

### RLIMIT_SIGPENDING

| 属性 | 值 |
|------|------|
| **参数** | `RLIMIT_SIGPENDING` |
| **含义** | 进程可排队的信号最大数 |
| **影响** | SIGPIPE 信号排队也受此限制，但 SIGPIPE 如被忽略则不入队 |
| **查看** | `cat /proc/<PID>/limits \| grep "Max pending signals"` |

### RLIMIT_NPROC

| 属性 | 值 |
|------|------|
| **参数** | `RLIMIT_NPROC` |
| **含义** | 用户可创建的进程最大数 |
| **影响** | 管道多数用于父子进程通信，进程数限制间接限制 pipe 使用量 |

---

## 六、调优建议表

| 场景 | somaxconn | pipe-max-size | rmem_default | wmem_default | optmem_max | ulimit nofile |
|------|-----------|---------------|--------------|--------------|------------|---------------|
| 低并发 UDS 服务 | 128 | 1MB（默认） | 默认 | 默认 | 20KB（默认） | 65536 |
| 高并发 UDS 服务 | 4096 | 1MB | 512KB | 512KB | 40KB | 1048576 |
| UDS 凭证传递场景 | 128 | 1MB | 默认 | 默认 | 81920 | 65536 |
| 管道密集型应用 | 默认 | 2MB~4MB | 默认 | 默认 | 默认 | 65536 |
| socketpair 通信 | 默认 | 默认 | 默认 | 默认 | 默认 | 65536 |
| 混合 UDS + pipe | 4096 | 2MB | 512KB | 512KB | 40KB | 1048576 |

**调整原则**：
- `somaxconn`：不要超过实际预期并发数太多（浪费内核内存），但不要小于峰值并发
- `pipe-max-size`：增大 buffer 可以减少阻塞但增加内存开销，每个 pipe 多占 N KB
- `optmem_max`：凭证传递涉及辅助数据拷贝，设太小会导致 `SCM_RIGHTS` 发送失败
- 所有参数调整后建议使用 `stress` 或 `ab` 压测验证
- 持久化修改必须经过 review 和测试
- UDS 和 pipe 的创建也受 `file-max` 和 `RLIMIT_NOFILE` 双重限制
