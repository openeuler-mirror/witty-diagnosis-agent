# UDS / Pipe 故障模式目录

> 本文件配合 SKILL.md 第二节三层下钻模型和第三节分支决策使用。
> 每种模式给出：泄漏特征、典型场景、诊断命令、根因定位方法。

---

## 模式 A：UDS Listen Backlog 满

| 属性 | 描述 |
|------|------|
| **特征** | client connect 返回 `ECONNREFUSED` 或 `EAGAIN`；`ss -xl` 显示 listen socket 的 Recv-Q 持续 > 0；Send-Q 值为 backlog 最大值 |
| **典型场景** | server backlog 参数设太小（如 backlog=1），client 并发 connect 超过 backlog 上限被拒绝；高并发突发请求时显现 |
| **诊断命令** | `ss -xl \| awk '$3 > 0 {print}'` 检查 Recv-Q 堆积；`strace -e trace=listen` 确认 backlog 参数；`cat /proc/sys/net/core/somaxconn` 查看系统上限 |
| **根因定位** | strace listen() 调用确认 backlog 设置值；对比 server 代码中 listen(fd, backlog) 参数；检查 `net.core.somaxconn` 系统限值；计算 min(backlog, somaxconn) 实际值 |
| **验证方法** | 修改 backlog 值后重启 server，用并发脚本模拟多 connect 测试 Recv-Q 不再堆积 |
| **分支脚本** | `branch_A_uds_backlog.sh` |
| **立即缓解** | `sysctl -w net.core.somaxconn=1024` 增大系统上限；重启 server 使用更大 backlog |
| **根本修复** | 修改 server 代码中 listen() 的 backlog 参数（推荐 128~1024）；对高并发场景使用 reactor 模式 + accept 循环 |

---

## 模式 B：Abstract Socket 冲突

| 属性 | 描述 |
|------|------|
| **特征** | bind() 返回 `EADDRINUSE`；`ss -xl \| grep @` 显示同一个 @address 有多个绑定记录；日志中出现 "Address already in use" |
| **典型场景** | 两个进程实例绑定到同一 abstract socket 地址（@xxx）；旧进程异常退出后新进程未清理 socket；进程热升级时新旧实例地址重叠 |
| **诊断命令** | `ss -xlp \| grep @abstract_name` 查看绑定者 PID 和进程名；`lsof -U \| grep ABSTRACT` 列出 abstract socket 持有者；结合 `ps -ef \| grep PID` 确认进程归属 |
| **根因定位** | 冲突的两个进程 PID 确认；检查进程启动参数/配置文件中 abstract socket 地址是否重复；检查 systemd unit 启动策略是否允许多实例 |
| **验证方法** | 停止冲突进程后单独启动测试；修改地址后确认 bind 成功 |
| **分支脚本** | `branch_B_abstract_conflict.sh` |
| **立即缓解** | 停止冲突进程之一；修改配置使各进程使用不同的 abstract 地址 |
| **根本修复** | 统一 service 地址管理机制，避免地址硬编码；使用 systemd socket activation 来自动管理；使用进程 PID 或实例 ID 生成唯一 abstract 地址后缀 |

---

## 模式 C：SO_PASSCRED / SCM_RIGHTS 凭证传递失败

| 属性 | 描述 |
|------|------|
| **特征** | recvmsg 收不到 `SCM_CREDENTIALS` 或 `SCM_RIGHTS` 辅助数据（cmsg）；`ss -xp` 不显示 credential 行；client 发送可信凭证后 server 无法读取 |
| **典型场景** | server 端 socket 未设置 `SO_PASSCRED` 选项，导致 recvmsg 返回 msg_control 为空；iptables/security 模块干扰辅助数据传递 |
| **诊断命令** | `ss -xp` 检查是否有 credential 信息；`strace -e trace=recvmsg -p PID \| grep -E "cmsg\|SCM\|credential"`；`cat /proc/sys/net/core/optmem_max` 检查辅助数据缓冲区上限 |
| **根因定位** | 检查 server 代码是否调用了 `setsockopt(sock, SOL_SOCKET, SO_PASSCRED, &one)`；检查 `net.core.optmem_max` 辅助数据缓冲区是否够用；验证 client 的 cmsg 构造是否正确 |
| **验证方法** | 添加 setsockopt 后重启，用 Python 测试脚本验证 recvmsg 能收到 cmsg |
| **分支脚本** | `branch_C_credential_fail.sh` |
| **立即缓解** | server 启动前设置 `export SO_PASSCRED=1`（如可行）；重启 server |
| **根本修复** | 在 server bind() 前添加 `setsockopt(sock, SOL_SOCKET, SO_PASSCRED, &one, sizeof(one))`；增大 optmem_max 到 81920 |

---

## 模式 D：Socket 文件权限拒绝

| 属性 | 描述 |
|------|------|
| **特征** | connect() 返回 `EACCES`（Permission denied）；`ls -la socket.sock` 显示权限位异常（如 000 或错误 owner/group） |
| **典型场景** | UDS socket 文件权限设为 000（无任何权限）；socket 文件所有者为 root 而 client 以普通用户运行；umask 过于严格（如 0077）导致 socket 对其他用户不可访问 |
| **诊断命令** | `ls -la /path/to/socket.sock` 查看权限；`stat /path/to/socket.sock` 查看所有者和组；`find / -type s -perm 000 2>/dev/null` 查找无效权限 socket；`getfacl /path/to/socket.sock` 查看 ACL |
| **根因定位** | 检查 umask 是否导致权限过严；检查 server 创建 socket 时是否设了错误 owner/group；验证 client 运行时用户；检查 socket 文件父目录是否可执行（目录权限影响 socket 访问） |
| **验证方法** | 以不同用户尝试 connect 确认错误复现；修改权限后验证 connect 成功 |
| **分支脚本** | `branch_D_socket_perm.sh` |
| **立即缓解** | `chmod 777 /path/to/socket.sock` 临时开放；或 `chown client_user /path/to/socket.sock` |
| **根本修复** | 在 server socket bind() 后添加 `chmod()` 设置正确权限；或调整 umask 为 0002/0022；使用 systemd socket unit 统一管理 |

---

## 模式 E：Pipe Buffer 满写阻塞

| 属性 | 描述 |
|------|------|
| **特征** | 进程处于 D 状态（不可中断睡眠）；`cat /proc/PID/wchan` 显示 `pipe_wait`；write() 调用被阻塞；系统 load 升高但 CPU 利用率正常 |
| **典型场景** | pipe buffer（默认 64KB）被写端填满，读端消费不足；生产者 > 消费者速率不匹配；批量数据处理管道中读端在处理大数据量时暂停 |
| **诊断命令** | `ps aux \| awk '\$8 ~ /D/ {print}'` 查找 D 状态进程；`cat /proc/PID/wchan` 确认 pipe_wait；`cat /proc/sys/fs/pipe-max-size` 查看系统 pipe 容量上限；`strace -e trace=write -p PID` 追踪卡住的 write |
| **根因定位** | 通过 strace 确认 write() 卡住的调用栈；查看 `/proc/PID/stack` 确认内核等待链；检查读写端速率不匹配原因：是读端太慢还是写端太快；确认 pipe 容量是否被调整过 |
| **验证方法** | 增大 pipe buffer 后观察 D 状态是否消失；或使用非阻塞 I/O（O_NONBLOCK）测试 write 返回 EAGAIN 是否符合预期 |
| **分支脚本** | `branch_E_pipe_block.sh` |
| **立即缓解** | `echo 1048576 > /proc/sys/fs/pipe-max-size` 临时扩大系统 pipe 上限；通过 `fcntl(fd, F_SETPIPE_SZ, 1048576)` 动态扩容；kill 阻塞进程恢复 |
| **根本修复** | 增大 pipe 缓冲区到合理值（fcntl(fd, F_SETPIPE_SZ, size)）；引入背压控制或调节生产/消费速率；考虑使用非阻塞 I/O + epoll 替代阻塞管道 |

---

## 模式 F：SIGPIPE 信号未处理进程退出

| 属性 | 描述 |
|------|------|
| **特征** | 进程意外退出无 core dump；`dmesg` 无异常日志；`/var/log/messages` 无 OOM/panic 记录；退出码通常为 141（128 + 13 SIGPIPE） |
| **典型场景** | 子进程写已关闭的 pipe 或 socket 时收到 SIGPIPE，由于没有注册 signal handler，进程被默认终止（SIG_DFL 行为）；管道读端在子进程写入前已退出 |
| **诊断命令** | `cat /proc/PID/status \| grep -E "SigIgn\|SigCgt"` 查看信号掩码（PID 为残留在 /proc 中的快照）；`strace -e trace=signal -p PID` 追踪信号发送；`echo \$?` 确认退出码（退出时核心转储检测） |
| **根因定位** | 检查代码中是否注册了 SIGPIPE handler；检查 pipe/socket 关闭时序：是否读端先关闭后写端还在写；检查多线程场景：写操作发生在错误的线程上下文中 |
| **验证方法** | 编写测试程序模拟关闭 pipe 后写入，观察是否产生 SIGPIPE；添加 signal handler 后确认进程不再退出 |
| **分支脚本** | `branch_F_sigpipe.sh` |
| **立即缓解** | 对目标进程执行前确认退出原因；使用 `trap '' SIGPIPE` 的包装脚本来启动进程 |
| **根本修复** | 添加 `signal(SIGPIPE, SIG_IGN)` 或 `sigaction(SIGPIPE, &sa, NULL)` 忽略 SIGPIPE；或在 write() 返回 EPIPE 时正确处理不退出；网络库中设置 `send()` 的 MSG_NOSIGNAL 标志位 |

---

## 模式 G：socketpair 泄漏

| 属性 | 描述 |
|------|------|
| **特征** | 匿名 UDS socket（无路径）FD 数持续增长；`lsof -p PID \| grep unix` 中 anon_unix 计数增加；`cat /proc/net/unix` 显示大量无路径条目；进程总 FD 数逼近 ulimit |
| **典型场景** | 线程池/进程间通信中使用 socketpair() 创建通信通道但未在适当时候 close() 两端；每次创建新 socketpair 而旧的未关闭；进程 fork 后父子进程未正确关闭不需要的一端 |
| **诊断命令** | `ls -la /proc/PID/fd/ \| grep socket \| wc -l` 监控增长；`lsof -p PID \| grep unix \| wc -l` 统计 UDS FD 数量；`strace -e trace=socketpair,close -p PID -c` 统计调用比；`watch -n 3 'ls -la /proc/PID/fd/ \| grep socket \| wc -l'` 趋势监控 |
| **根因定位** | strace 统计显示 socketpair() > (close() / 2)；检查 socketpair 创建和关闭的代码路径，确认两边是否都 close；检查进程退出时是否有未关闭的 socketpair FD（子进程的残留） |
| **验证方法** | 修复后 strace 统计确认 socketpair() = close() / 2；监控 FD 趋势确认不再增长 |
| **分支脚本** | `branch_G_socketpair_leak.sh` |
| **立即缓解** | 重启进程释放所有 FD；增大 `ulimit -n` 临时规避 |
| **根本修复** | 确保每个 socketpair() 的返回两个 FD 都在不再使用时被 close()；使用 RAII 或 defer 确保关闭；考虑使用 `SOCK_CLOEXEC` 标志防止 fork 后泄漏到子进程 |

---

## 补充模式 H：UDS 路径长度超限

| 属性 | 描述 |
|------|------|
| **特征** | bind() 返回 `EINVAL`；socket 路径长度 > 108 字节（`sun_path` 硬限制）；日志报 "invalid argument" |
| **典型场景** | 嵌套路径过深的 socket 文件位置（如 `/var/run/very/long/nested/path/service.sock`）；长 hostname + 长 service 路径组合超限；容器环境中 mount namespace 路径叠加 |
| **诊断命令** | `echo /path/to/socket.sock \| wc -c` 计算路径长度；`getconf PATH_MAX /` 查看系统路径限制；`man 7 unix` 确认 `sun_path` 大小 |
| **根因定位** | 路径长度 > 108 bytes 时考虑使用 abstract socket（@ 前缀）或缩短路径；检查应用配置中 socket 路径构造逻辑 |
| **根本修复** | 缩短路径长度 < 108 字节；或改用 abstract socket（路径不占用文件系统，也不受 108 字节限制） |
| **注意** | abstract socket 路径同样受 108 字节限制（含 @ 前缀），但通常更易控制长度 |

---

## 补充模式 I：UDS 缓冲区满导致背压

| 属性 | 描述 |
|------|------|
| **特征** | sendmsg() 在 UDS 上被阻塞；`ss -x` 显示 Send-Q 堆积（established socket 的 Send-Q > 0）；服务端消费慢于客户端生产 |
| **典型场景** | UDS stream socket 默认 send buffer（wmem_default ~208KB）满；消费者处理请求速度低于生产者发送速度；客户端多线程并发发送但服务端单线程处理 |
| **诊断命令** | `ss -xm` 查看 UDS 内存使用；`cat /proc/sys/net/core/wmem_default` 查看默认 send buffer；`strace -e trace=sendmsg -p PID` 追踪阻塞的写；`ss -x state established \| awk '$4 > 0 {print}'` 查看 Send-Q 堆积 |
| **根因定位** | 通过 strace 确认 sendmsg 阻塞；检查消费者处理速度瓶颈（CPU 绑定 / 锁竞争 / I/O 等待）；对比生产/消费速率 |
| **验证方法** | 增大 send buffer 或优化消费者后确认 Send-Q 不再堆积 |
| **立即缓解** | 增大 `sysctl -w net.core.wmem_default=524288` 临时缓解；或临时停止生产者 |
| **根本修复** | 增大 UDS send buffer（`setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &size)`）；或优化消费者处理速率；或引入流量控制机制（背压信号 / 令牌桶） |

---

## 补充模式 J：UDS Dgram 消息丢失

| 属性 | 描述 |
|------|------|
| **特征** | UDS dgram socket 发送消息无错误返回但接收端未收到；ss -x state established 显示连接正常；Send-Q 和 Recv-Q 均为 0；接收端 buffer 满时消息静默丢弃 |
| **典型场景** | UDS dgram 模式消息发送无确认机制，接收端 buffer 满时消息静默丢弃；发送端发送频率过高导致接收端来不及消费 |
| **诊断命令** | cat /proc/sys/net/core/rmem_default 查看接收缓冲区；ss -xm 查看 socket 内存使用；增大 rmem 后观察是否还有丢失 |
| **根因定位** | 确认 socket 类型为 dgram(SOCK_DGRAM)；检查接收端处理速率和缓冲区大小；检查 sendto 返回值和 errno 是否有 EAGAIN |
| **立即缓解** | 增大 rmem_default(sysctl -w net.core.rmem_default=262144)；临时降低发送速率 |
| **根本修复** | 改用 SOCK_SEQPACKET 保证消息有序完整投递；或在应用层添加确认/重传机制 |

---

## 补充模式 K：UDS Client 异常退出连接残留

| 属性 | 描述 |
|------|------|
| **特征** | UDS server 端出现大量半关闭连接或 CLOSE-WAIT；client 进程异常退出但未正确关闭 socket；server 端 FD 数持续增长 |
| **典型场景** | 客户端进程异常退出(crash/force kill)时未走正常关闭路径；client 只 close() 未 shutdown() 导致 server 端收不到 EOF |
| **诊断命令** | ss -x state close-wait 查看 UDS CLOSE-WAIT 连接数；ss -xp 查看进程的 UDS 连接状态 |
| **根因定位** | 检查 client 退出路径是否完整关闭了 UDS 连接；使用 atexit() 注册清理函数确保异常退出时 close() |
| **立即缓解** | 重启 server 清理残留在 server 端的无效连接；server 端设置 keepalive 超时 |
| **根本修复** | 在 client 的进程退出处理器(atexit/signal handler)中确保 close(fd) 被执行；server 端设置合理的 idle 超时机制清理僵尸连接；使用 shutdown()+close() 完整两阶段关闭 |
