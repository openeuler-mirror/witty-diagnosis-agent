# 常见 Syscall 错误码与内核源码路径参考

## 常见 errno 速查

### 应用级常见错误

| errno | 值 | 含义 | 常见场景 | 检查方向 |
|-------|-----|------|---------|---------|
| EACCES | 13 | 权限不足 | open/access 无读/写/执行权限 | 文件权限、SELinux、capabilities |
| EPERM | 1 | 操作不允许 | 需要 root/capability 但未具备 | capabilities(7)、权限模型 |
| ENOENT | 2 | 文件或目录不存在 | open/stat/exec 路径不存在 | 路径拼写、挂载点、符号链接 |
| EAGAIN | 11 | 资源暂时不可用（重试） | 非阻塞 read/write 无数据 | 重试间隔、是否忙等 |
| EWOULDBLOCK | 11 | 同 EAGAIN | 非阻塞 connect/accept 无连接 | 同 EAGAIN |
| ENOMEM | 12 | 内存不足 | malloc/mmap 分配失败 | cgroup 限制、overcommit、碎片 |
| EBADF | 9 | 错误的 fd | read/write 使用已关闭的 fd | fd 生命周期、多线程竞争 |
| EINTR | 4 | 系统调用被信号中断 | 慢速 syscall 收到信号 | 是否需 SA_RESTART |
| EINVAL | 22 | 无效参数 | mmap/mount/prctl 参数错误 | 参数范围、对齐要求 |
| EIO | 5 | I/O 错误 | 存储设备读写失败 | dmesg、硬件健康 |
| ENOSPC | 28 | 设备无空间 | write/mkdir 磁盘满 | df -h、inode 耗尽 |
| EEXIST | 17 | 文件已存在 | open(O_CREAT \| O_EXCL) | 文件是否预期存在 |
| ECONNREFUSED | 111 | 连接拒绝 | connect 目标端口未监听 | 服务状态、防火墙 |
| ETIMEDOUT | 110 | 连接超时 | connect/read 网络超时 | 网络延迟、防火墙丢包 |
| ECONNRESET | 104 | 连接被对端重置 | read/write 对端异常关闭 | 对端进程状态、保活机制 |
| EPIPE | 32 | 管道破裂 | write 到已关闭的管道/socket | 对端已关闭、SIGPIPE 处理 |

### 常见 syscall 错误模式

| 模式 | 涉及 syscall | 典型 errno | 根因排查方向 |
|------|-------------|-----------|------------|
| 文件不存在 | open/stat/access/execve | ENOENT | 路径检查、镜像/挂载完整性 |
| 权限拒绝 | open/access/mkdir/bind | EACCES/EPERM | 文件权限、SELinux、capability |
| 资源限流 | read/write/recv/send/accept | EAGAIN | 非阻塞模式、重试策略 |
| 内存不足 | mmap/brk/mmap/mprotect | ENOMEM | cgroup memory、overcommit、碎片 |
| 磁盘满 | write/rename/creat/mkdir | ENOSPC | df -i、磁盘配额 |
| 连接断开 | read/write/send/recv | ECONNRESET/EPIPE | 对端状态、网络稳定性 |
| 描述符无效 | read/write/close/fsync | EBADF | 多线程 fd 竞争、重复 close |

### 根据 errno 频率判断严重程度

| errno | 偶发（< 1%） | 频繁（1-10%） | 持续（> 10%） |
|-------|-------------|-------------|-------------|
| EAGAIN | 正常流量控制 | 可能存在忙等 | 🔴 严重忙等，需调整重试策略 |
| EACCES | 偶发权限错误 | 🟡 配置不匹配 | 🔴 功能严重受损 |
| ENOENT | 启动阶段正常 | 🟡 缺少依赖文件 | 🔴 安装/配置不完整 |
| ENOMEM | 内存压力尖峰 | 🟡 容量不足 | 🔴 严重泄漏或限制过小 |
| EBADF | 竞态偶发 | 🟡 编码问题 | 🔴 严重 fd 管理缺陷 |
| ECONNRESET | 网络偶发不稳 | 🟡 对端异常 | 🔴 大量连接中断 |

---

## 内核 Syscall 源码路径快查

### 文件系统 syscall

| syscall | 内核实现函数 | 源码路径 | 常见 errno |
|---------|------------|---------|-----------|
| open/openat | do_sys_open() | fs/open.c | EACCES, ENOENT, ENFILE, EMFILE |
| read | ksys_read() | fs/read_write.c | EBADF, EFAULT, EIO, EAGAIN |
| write | ksys_write() | fs/read_write.c | EBADF, EFAULT, EIO, ENOSPC |
| close | ksys_close() | fs/open.c | EBADF |
| stat/statx | vfs_statx() | fs/stat.c | EACCES, ENOENT |
| mmap | ksys_mmap_pgoff() | mm/mmap.c | ENOMEM, EACCES, EINVAL |
| munmap | ksys_munmap() | mm/mmap.c | EINVAL |
| readdir | iterate_dir() | fs/readdir.c | EBADF, ENOENT |

### 网络 syscall

| syscall | 内核实现函数 | 源码路径 | 常见 errno |
|---------|------------|---------|-----------|
| socket | __sys_socket() | net/socket.c | EACCES, EAFNOSUPPORT, EMFILE |
| bind | __sys_bind() | net/socket.c | EACCES, EADDRINUSE |
| listen | __sys_listen() | net/socket.c | EADDRINUSE, EOPNOTSUPP |
| accept/accept4 | __sys_accept4() | net/socket.c | EAGAIN, ECONNABORTED, EMFILE |
| connect | __sys_connect() | net/socket.c | ECONNREFUSED, ETIMEDOUT, EAGAIN |
| sendto/recvfrom | sock_sendmsg()/sock_recvmsg() | net/socket.c | EAGAIN, ECONNRESET, EPIPE |
| epoll_create | do_epoll_create() | fs/eventpoll.c | EMFILE, ENFILE |
| epoll_ctl | do_epoll_ctl() | fs/eventpoll.c | EEXIST, ENOENT, EINVAL |
| epoll_wait | do_epoll_wait() | fs/eventpoll.c | EBADF, EINTR |

### 进程/IPC syscall

| syscall | 内核实现函数 | 源码路径 | 常见 errno |
|---------|------------|---------|-----------|
| fork/clone | kernel_clone() | kernel/fork.c | ENOMEM, EAGAIN |
| execve | do_execveat_common() | fs/exec.c | EACCES, ENOENT, ENOMEM |
| wait4 | wait_consider_task() | kernel/exit.c | ECHILD, EINTR |
| futex | do_futex() | kernel/futex.c | EAGAIN, ETIMEDOUT, EINTR |
| nanosleep | hrtimer_nanosleep() | kernel/time/hrtimer.c | EINTR |
| mprotect | do_mprotect_pgoff() | mm/mprotect.c | ENOMEM, EACCES, EINVAL |

### 通用/其他 syscall

| syscall | 内核实现函数 | 源码路径 | 常见 errno |
|---------|------------|---------|-----------|
| ioctl | ksys_ioctl() | fs/ioctl.c | EBADF, EFAULT, ENOTTY |
| poll/ppoll | do_sys_poll() | fs/select.c | EINTR, ENOMEM |
| select | do_select() | fs/select.c | EINTR, ENOMEM |
| sendfile | do_sendfile() | fs/sendfile.c | EBADF, EINVAL, ENOMEM |
| splice | do_splice() | fs/splice.c | EBADF, EINVAL, ESPIPE |

---

## 关键内核参数与 syscall 行为

| 参数 | 影响范围 | 默认值 | 检查命令 |
|------|---------|--------|---------|
| fs.file-max | 系统级 fd 上限 | 动态（~内存/10） | `sysctl fs.file-max` |
| fs.nr_open | 进程级 fd 硬上限 | 1048576 | `sysctl fs.nr_open` |
| kernel.threads-max | 最大线程数 | 动态 | `sysctl kernel.threads-max` |
| kernel.pid_max | PID 上限 | 32768 | `sysctl kernel.pid_max` |
| net.core.somaxconn | listen  backlog | 4096 | `sysctl net.core.somaxconn` |
| vm.max_map_count | mmap 区域上限 | 65530 | `sysctl vm.max_map_count` |
| ulimit -n | 进程级 fd 软上限 | 1024 | `ulimit -n` |
| ulimit -u | 进程级线程上限 | 无限制 | `ulimit -u` |

---

## /proc/<PID>/syscall 字段解读

```
cat /proc/1234/syscall
```

输出格式：
```
0 0x7f1234567890 0x0 0x1 0x0 0x0 0x0
```

| 字段 | 含义 |
|------|------|
| 第 1 列 | syscall 编号（0=read, 1=write, ...）|
| 第 2-7 列 | syscall 参数（arg0-arg5）|
| 后续列 | 栈指针（sp）和指令指针（ip）|

> syscall 编号映射见 `/usr/include/asm/unistd_64.h` 或 `/usr/include/x86_64-linux-gnu/asm/unistd_64.h`

---

## 典型 D 状态与 syscall 关联

| /proc/PID/wchan | 相关 syscall | 典型原因 |
|----------------|-------------|---------|
| wait_on_page_bit | read/write | 磁盘 IO 慢，页缓存缺页 |
| inode_wait_for_writeback | write/fsync | 大量回写，IO 瓶颈 |
| mutex_lock | 取决于锁类型 | 锁竞争 |
| rwsem_down_write_failed | mmap/mprotect | 写者锁等待 |
| __blockdev_direct_IO | read/write(direct IO) | 直接 IO 同步等待 |
| do_epoll_wait | epoll_wait | epoll 等待事件（正常）|
| pipe_wait | read(s) | pipe 无数据（正常）|
| bt_sysfs_work | ioctl | 蓝牙/驱动阻塞 |

---

## strace 输出格式解读

### 标准行格式
```
<syscall>(<args>) = <return_value>   <error_info>   <elapsed_time>
```

示例：
```
open("/var/log/syslog", O_RDONLY) = 3   <0.000012>
read(3, "..."..., 1024) = 512            <0.000035>
open("/nonexist", O_RDONLY) = -1 ENOENT (No such file or directory) <0.000015>
futex(0x7f1234, FUTEX_WAIT, 2, NULL) = 0 <0.532107>
```

### 汇总格式（-c）
```
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
 50.23   23.456789      123456       190       100 futex
 30.12   14.123456       78901       179        20 read
 10.05    4.567890         123       456        15 write
```

### 关键字段

| 字段 | 含义 | 正常/异常判断 |
|------|------|-------------|
| = 3 | 返回值（正数通常表示 fd/成功）| fd 应连续增长；持续超 10万说明泄漏 |
| = -1 | 系统调用失败 | 结合 errno 判断严重性 |
| ENOENT | 错误码 | 见 errno 速查表 |
| <0.532107> | 耗时（秒）| futex > 500ms 通常正常；read > 1s 异常 |
| calls | 累计调用次数 | 与运行时间对比，异常偏高可能忙等 |
| errors | 错误次数 | 错误率 > 10% 一般需要关注 |
