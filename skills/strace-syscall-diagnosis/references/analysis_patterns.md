# 常见 Syscall 故障模式速查

> 本文件配合 SKILL.md 第三节"内核语义分析"使用。
> 按故障类型索引，每种模式给出：现象特征、内核行为、根因定位策略。

---

## 一、Syscall 错误码模式

### 模式1：EACCES/EPERM 权限拒绝模式

**现象特征**：
- strace 中 open/access/connect 返回 -1 EACCES 或 -1 EPERM
- 目标文件/设备存在但操作失败
- 错误码集中在特定路径/资源上
- 应用日志可能有 "Permission denied"

**内核行为**：
- `sys_open()` → `do_filp_open()` → `path_openat()` → `may_open()` 返回 EACCES
- 或 LSIM（SELinux/AppArmor）拦截返回 EACCES

**根因定位策略**：
1. 检查目标文件/目录权限：`ls -la <path>`
2. 检查 SELinux：`getenforce` / `audit2why -a`
3. 检查 capabilities：`getcap <binary>`
4. 检查 `posix_acl`: `getfacl <path>`
5. 检查 mount 选项（noexec/nosuid/nodev）

### 模式2：ENOENT 文件不存在模式

**现象特征**：
- open/stat/execve 返回 -1 ENOENT
- 通常在启动阶段或访问特定文件时出现
- 可能持续重试但每次都 ENOENT

**根因定位策略**：
1. 确认路径完整性（路径中每级目录是否存在）
2. 检查符号链接：`readlink -f <path>`
3. 检查挂载点：`mount | grep <path_component>`
4. 检查 .so 依赖（execve ENOENT）：`ldd <binary>`
5. 检查容器镜像是否缺少文件

### 模式3：EAGAIN/EWOULDBLOCK 忙等模式

**现象特征**：
- read/write/connect/recv/send/accept 返回 -1 EAGAIN
- 高频率连续出现（每毫秒多次）
- CPU 使用率可能升高（忙等）

**内核行为**：
- 非阻塞 IO 模式下，资源暂不可用时直接返回 EAGAIN
- 正常模式：返回后应用应等待（poll/epoll/select），然后重试
- 异常模式：应用不等待直接忙等，CPU 空转

**根因定位策略**：
1. 检查两次 EAGAIN 之间是否有 poll/epoll_wait：`strace -e trace=read,poll,epoll -p <PID>`
2. 如果是 socket，检查对端是否处理及时
3. 如果是 pipe，检查读取端是否及时消费
4. 就绪事件通知策略（edge-triggered vs level-triggered）

**EAGAIN 严重度分级**：

| EAGAIN 模式 | 特征 | 建议 |
|-------------|------|------|
| 正常 | EAGAIN 后有 epoll_wait 等待 | 正常非阻塞操作，无需处理 |
| 忙等 | EAGAIN 后立即重试（无等待）| 需加 poll/epoll 或增加等待时间 |
| 高频忙等 | EAGAIN 每秒 > 1000 次 | 严重效率问题，需重构 |
| 伴随 ET | edge-triggered 漏事件 | 检查 ET 模式下数据是否读完 |

### 模式4：ENOMEM 内存不足模式

**现象特征**：
- mmap/brk/malloc 返回 -1 ENOMEM（或 NULL）
- 通常伴随性能下降
- 可能是持续性的或者是尖峰触发

**根因定位策略**：
1. 检查系统内存：`free -h` / `cat /proc/meminfo`
2. 检查 cgroup 限制：`cat /proc/<PID>/cgroup`
3. 检查 overcommit：`sysctl vm.overcommit_memory`
4. 检查进程 max_map_count：`sysctl vm.max_map_count`
5. 检查 ulimit -v：`ulimit -v`

---

## 二、慢 Syscall 定位

### 模式5：futex 高耗时

**现象特征**：
- strace 中 futex(FUTEX_WAIT) 耗时 > 100ms
- -c 汇总中 futex 占总时间的比例最高
- 进程可能看起来"卡住"

**内核行为**：
- futex(FUTEX_WAIT) 将线程放入等待队列
- 调度器切换出该线程
- 当 futex 所有者释放锁时，通过 FUTEX_WAKE 唤醒
- 耗时包括：锁持有时间 + 调度延迟 + 唤醒延迟

**根因定位策略**：
1. 检查锁持有者：`cat /proc/<PID>/stack`
2. 如果是 pthread mutex：检查哪个线程持锁
3. 使用 `perf record -e sched:sched_switch` 分析调度延迟
4. 区分：是锁竞争（多个线程抢锁）还是锁持有时间过长

**futex 耗时拆解**：

| 耗时范围 | 含义 | 常见原因 |
|---------|------|---------|
| < 10us | 快速锁，几乎无竞争 | 正常 |
| 10us-100us | 轻微竞争 | 正常 |
| 100us-1ms | 有竞争 | 检查锁粒度 |
| 1ms-10ms | 明显锁争用 | 需要优化锁策略 |
| > 10ms | 严重锁竞争或持有时间过长 | 需根本性重构 |

### 模式6：epoll_wait 异常

**现象特征**：
- epoll_wait 返回 0（超时）过于频繁
- 或 epoll_wait 耗时远大于预期
- 应用处理事件不及时

**内核行为**：
- `do_epoll_wait()` → `ep_poll()` 将当前线程放入等待队列
- 超时时间参数决定了最长阻塞时间
- 返回 0 表示超时时间内无事件到达

**根因定位策略**：
1. 检查 epoll_wait 超时参数设置（是否合理）
2. 检查 fd 是否在 edge-triggered 模式下漏读（导致 epoll 不再通知）
3. 检查注册的事件类型（EPOLLIN/EPOLLOUT 是否合理）
4. 使用 `/proc/<PID>/fdinfo/<epoll_fd>` 查看 epoll 内部状态

### 模式7：IO 操作（read/write）慢

**现象特征**：
- read/write 耗时 > 100ms（本地文件）或 > 1s（网络）
- bi/bo 高，iowait 高
- 进程可能进入 D 状态

**根因定位策略**：
1. 使用 `iostat -x 1` 检查存储设备状态
2. 使用 `iotop -oP` 定位 IO 密集进程
3. 检查文件系统类型和挂载参数（ext4/btrfs/nfs/cifs）
4. 检查是否 direct IO（跳过页缓存）
5. 检查网络文件系统延迟（如 NFS）

### 模式8：open 耗时长

**现象特征**：
- open 调用耗时 > 100ms
- 多发生在文件系统较慢或目录层级较深的场景

**根因定位策略**：
1. 检查目录层级深度（每级目录都需要权限检查）
2. 检查文件系统（网络文件系统延迟高）
3. 检查目录下有大量文件（线性扫描目录项）
4. 使用 `filefrag` 检查文件碎片情况

---

## 三、库函数级追踪（ltrace）

### 模式9：malloc 频繁重复

**现象特征**：
- ltrace 显示 malloc/free 频率极高（每秒数万次）
- CPU 用户态主要花在内存分配上
- 碎片化可能加剧

**根因定位策略**：
1. 检查是否在热路径中频繁分配临时对象
2. 使用内存池或对象复用
3. 使用 jemalloc/tcmalloc 替代 glibc malloc
4. 检查是否缺少适当的缓存

### 模式10：库函数调用路径异常

**现象特征**：
- ltrace 显示调用路径与预期不符
- 关键函数未调用或被跳过
- 条件分支走错

**根因定位策略**：
1. 检查库版本是否匹配（`ldd <binary>`）
2. 检查是否存在 LD_PRELOAD 拦截函数
3. 检查符号是否被正确解析（`nm -D <library>`）
4. 检查条件判断逻辑是否因数据错误走错分支

---

## 四、文件描述符泄漏

### 模式11：FD 持续增长不释放

**现象特征**：
- `/proc/<PID>/fd` 数量随时间持续增长
- 出现 "Too many open files" 错误（EMFILE）
- 进程性能逐步下降

**根因定位策略**：
1. 定时采样 fd 数量：`watch -n 2 'ls /proc/<PID>/fd | wc -l'`
2. 使用 strace 追踪 open/dup/epoll_create/socket 并配对 close
3. 检查所有 open/accept 路径是否都有对应的 close
4. 检查异常路径和错误处理分支是否遗漏 close

**泄漏模式识别**：

| 模式 | 特征 | 常见原因 |
|------|------|---------|
| 线性增长 | fd 数匀速增长 | 主循环中 open 未 close |
| 阶跃增长 | fd 数在某些操作后跳增 | 特定功能模块泄漏 |
| 周期性增长 | fd 数增长后部分回落 | 缓存或连接池未正确回收 |

---

## 五、综合模式

### 模式12：线程卡在 syscall

**现象特征**：
- 进程响应慢，但未被 kill
- ps 显示进程处于 S 或 D 状态
- /proc/PID/stack 显示卡在内核函数中

**根因定位策略**：
1. `cat /proc/<PID>/syscall` — 查看当前执行的 syscall
2. `cat /proc/<PID>/stack` — 查看内核调用栈
3. `cat /proc/<PID>/status` — 查看进程状态
4. 结合上述信息判断卡在哪个阶段

### 模式13：strace 本身性能开销

**现象特征**：
- strace 后进程明显变慢（10-100 倍）
- strace -c 显示 syscall 耗时异常

**原因**：
- strace 使用 ptrace，每个 syscall 触发两次上下文切换
- 高频率 syscall（如 getpid、clock_gettime）受影响最大
- 估计开销：10-100us/call

**缓解**：
- 使用 `perf trace` 替代 strace（开销更低）
- 使用 `-e trace=` 精确过滤，减少采集范围
- 采集时长不宜过长（30 秒内）
- 使用 `-c` 汇总模式而非完整日志

---

## 六、搜索通用工具命令

```bash
# 查看进程当前执行的 syscall
cat /proc/<PID>/syscall

# 查看进程内核调用栈（D 状态时必看）
cat /proc/<PID>/stack

# 查看进程 fd 列表
ls -la /proc/<PID>/fd

# 按 syscall 耗时排序汇总
strace -S time -c -p <PID>  # Ctrl+C 结束

# 只看失败的 syscall
strace -e status=failed -p <PID>

# 只看网络相关 syscall
strace -e trace=network -s 1024 -p <PID>

# 跟踪线程组
strace -f -o /tmp/trace.log -p <PID>

# 查看系统级 syscall 频率
perf stat -e 'syscalls:sys_enter_*' -a -- sleep 5

# 查看进程 fd 增长趋势
while sleep 2; do echo "$(date +%H:%M:%S) $(ls /proc/<PID>/fd 2>/dev/null | wc -l) fds"; done
```

---

## 七、文件描述符/资源泄漏

### 模式14：FD 线性泄漏

**现象特征**：
- `/proc/<PID>/fd` 数量随时间匀速增长
- 最终出现 EMFILE("Too many open files") 或 ENFILE
- 进程性能逐步下降直至不可用

**内核行为**：
- `sys_open()` → `get_unused_fd_flags()` 分配 fd
- `__close_fd()` 释放 fd
- 当 `current->files->next_fd >= rlimit(RLIMIT_NOFILE)` 时返回 EMFILE

**根因定位策略**：
1. 定时采样 fd 数量确认增长趋势
2. strace 追踪 open/accept/socket/epoll_create 与 close 配对情况
3. 检查错误处理路径是否遗漏 close
4. 检查连接池/线程池实现

### 模式15：mmap 映射泄漏

**现象特征**：
- `/proc/<PID>/maps` 区域数持续增长
- `cat /proc/vmstat` 的 `mmap_count` 增长
- 最终 mmap/malloc 返回 ENOMEM

**根因定位策略**：
1. strace 统计 mmap/munmap 配对: `strace -e trace=mmap,munmap -c -p <PID>`
2. 检查 mmap 的 MAP_ANONYMOUS 分配是否及时 munmap
3. 检查 `vm.max_map_count` 是否过小

---

## 八、网络 Syscall 异常

### 模式16：connect ECONNREFUSED

**现象特征**：
- connect 返回 -1 ECONNREFUSED
- 目标地址/端口无法连接
- 可能伴随重试

**根因定位策略**：
1. 确认目标监听: `ss -tlnp | grep <port>`
2. 确认网络命名空间: `nsenter -t <PID> -n ss -tlnp`
3. 防火墙拦截: `iptables -L -n` / `nft list ruleset`
4. 检查 hosts 解析: `getent hosts <hostname>`

### 模式17：connect ETIMEDOUT

**现象特征**：
- connect 耗时 > 内核设置的超时时间（默认 20s+）
- 返回 -1 ETIMEDOUT
- 通常伴随 TCP 重试

**根因定位策略**：
1. 网络连通性: `ping -c 3 <target>`
2. 路由跟踪: `traceroute -n <target>`
3. 防火墙丢弃 SYN: `tcpdump -i any host <target> and tcp[tcpflags] & tcp-syn != 0`
4. conntrack 表满: `sysctl net.netfilter.nf_conntrack_count`

### 模式18：ECONNRESET / EPIPE

**现象特征**：
- read/write 返回 -1 ECONNRESET 或 -1 EPIPE
- 连接在对端异常关闭后仍在读写

**根因定位策略**：
1. 对端进程状态: `ps aux | grep <peer_pid>`
2. 保活机制启用: `sysctl net.ipv4.tcp_keepalive_time`
3. read 返回 0 后继续 write → EPIPE
4. HTTP keep-alive 超时

### 模式19：EADDRINUSE

**现象特征**：
- bind 返回 -1 EADDRINUSE
- 端口被占用

**根因定位策略**：
1. 端口占用: `ss -tlnp | grep <port>`
2. TIME_WAIT 过多: `ss -tan state time-wait | wc -l`
3. 重用: `sysctl net.ipv4.tcp_tw_reuse=1`
4. SO_REUSEADDR: `strace -e trace=setsockopt -p <PID>`

---

## 九、信号/中断异常

### 模式20：EINTR 频繁

**现象特征**：
- strace 中大量 EINTR 出现
- syscall 被中断但未自动重试
- 通常涉及 read/write/connect/poll/epoll_wait/nanosleep

**内核行为**：
- 慢速 syscall 在等待期间收到信号
- 如果 sigaction 未设 SA_RESTART → 返回 EINTR
- 如果设了 SA_RESTART → 内核自动重发 syscall

**根因定位策略**：
1. 发送者识别: `strace -e trace=kill,tkill,tgkill -p <SENDER_PID>`
2. 检查 sigaction: `gdb -p <PID> -ex "p sigaction"` 或 `/proc/PID/status`
3. SA_RESTART 缺失: 在需要自动重启的信号上添加
4. 信号风暴: 确认发送频率是否正常

### 模式21：SIGPIPE 导致进程退出

**现象特征**：
- 进程无错误日志直接退出（退出码 141）
- 退出前 strace 有 EPIPE 错误
- 常见于管道/socket 编程

**根因定位策略**：
1. 确认 SIGPIPE 是否被忽略: `cat /proc/<PID>/status | grep SigIgn`
2. 如果忽略 → write 返回 EPIPE（可处理）
3. 如果不忽略 → 进程收到 SIGPIPE 信号默认终止
4. 修复: `signal(SIGPIPE, SIG_IGN)` + 处理 EPIPE

---

## 十、进程生命周期异常

### 模式22：fork 风暴

**现象特征**：
- fork/clone 调用次数极高（每秒数百次）
- PID 快速消耗
- CPU 系统态占比高

**根因定位策略**：
1. `strace -e trace=clone,fork -c -p <PID>` 统计频率
2. 检查是否为线程池实现不当（每次新建而非复用）
3. 检查是否有意外 fork（如 fork 炸弹）

### 模式23：execve 失败

**现象特征**：
- execve 返回 -1
- 新进程无法启动

**根因定位策略**：
1. ENOENT: `ldd <binary>` 检查动态库依赖
2. EACCES: `ls -la <binary>` 检查执行权限
3. ENOENT (解释器): `file <binary>` 检查 #! 路径
4. ETXTBUSY: 可执行文件正在被写入

### 模式24：僵尸进程累积

**现象特征**：
- 大量进程处于 Z 状态
- 父进程未回收子进程

**根因定位策略**：
1. `ps -eo pid,ppid,stat,comm | awk '$3~/^Z/'` 列出僵尸
2. 检查父进程状态是否卡住
3. 修复: `signal(SIGCHLD, SIG_IGN)` 或 wait 循环
4. 如果父进程已死 → 僵尸被 init 回收
