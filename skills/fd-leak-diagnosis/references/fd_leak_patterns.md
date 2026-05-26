# FD 泄漏模式目录

> 本文件配合 SKILL.md 第二节四层下钻模型和第三节分支决策使用。
> 每种模式给出：泄漏特征、典型场景、诊断命令、根因定位方法。

---

## 模式1：系统级 FD 耗尽

| 属性 | 描述 |
|------|------|
| **特征** | `file-nr` 已分配 ≈ `file-max`，`dmesg` 有 "VFS: file-max limit reached" |
| **典型场景** | 多个进程同时泄漏；或单个进程 FD 数极大导致系统资源耗尽 |
| **诊断命令** | `cat /proc/sys/fs/file-nr`，`dmesg \| grep "VFS: file-max"` |
| **根因定位** | 通过 FD 消费 Top 10 列表找出主要泄漏进程，再逐个深入 |
| **分支脚本** | `branch_A_system_fd.sh` |
| **立即缓解** | `sysctl -w fs.file-max=新值` 临时扩大上限；重启高 FD 进程 |

---

## 模式2：进程级 FD 泄漏

| 属性 | 描述 |
|------|------|
| **特征** | 进程 FD 数持续增长，逼近 ulimit 软限制；`watch` 显示斜率 > 0 |
| **典型场景** | 循环中每次打开文件/socket 但漏了 close；异常路径早返回未释放 |
| **诊断命令** | `ls /proc/PID/fd \| wc -l`，`cat /proc/PID/limits`，`lsof -p PID` |
| **根因定位** | strace 追踪 open/close 统计确认差异 |
| **分支脚本** | `branch_B_process_fd.sh` |
| **根本修复** | 在异常路径补上 close/fclose |

---

## 模式3：Socket CLOSE_WAIT 堆积

| 属性 | 描述 |
|------|------|
| **特征** | `ss` 显示大量 CLOSE_WAIT（>1000），`lsof -p PID` 确认 IPv4 socket 占多数 |
| **典型场景** | 服务端未正确关闭 socket（收到 FIN 后未 close）；连接池在关闭上级连接时漏了子 socket |
| **诊断命令** | `ss -tn state close-wait \| wc -l`，`ss -tnp \| grep PID \| grep CLOSE-WAIT` |
| **根因定位** | 检查连接池代码：关闭连接时是否递归关闭了所有子 socket |
| **分支脚本** | `branch_C_close_wait.sh` |
| **根本修复** | 确保每个 accept/socket pair 在连接关闭时都执行 close() |

---

## 模式4：epoll FD 泄漏

| 属性 | 描述 |
|------|------|
| **特征** | 进程中 eventpoll FD 数 > 2（正常服务通常 1-2 个 epoll FD）；`fdinfo` 中 tfd 条目数异常多 |
| **典型场景** | 每次新建连接时附加 epoll 实例但未释放旧的；epoll_create 调用次数 >> epoll_ctl(EPOLL_CTL_DEL) |
| **诊断命令** | `ls -la /proc/PID/fd \| grep eventpoll`，`cat /proc/PID/fdinfo/N` |
| **根因定位** | strace 统计 epoll_create1 vs close；检查 epoll 实例复用逻辑 |
| **分支脚本** | `branch_D_epoll.sh` |
| **根本修复** | 复用单一 epoll 实例而非每次新建；确保资源清理时调用 close(epoll_fd) |

---

## 模式5：inotify watch 泄漏

| 属性 | 描述 |
|------|------|
| **特征** | inotify watch 数接近 `max_user_watches` 限制；`ENOSPC` 错误（"No space left on device" 实为 watch 耗尽） |
| **典型场景** | 文件监控框架在目录创建/删除时新增 watch 但未移除旧的 |
| **诊断命令** | `cat /proc/sys/fs/inotify/max_user_watches`，`find /proc -name fdinfo -exec grep "watch:" {} + \| wc -l` |
| **根因定位** | lsof 确认 inotify FD 数；检查 inotify_rm_watch 调用是否覆盖所有路径 |
| **分支脚本** | `branch_E_inotify.sh` |
| **根本修复** | 确保每个 inotify_add_watch 有对应的 inotify_rm_watch |

---

## 模式6：strace 显示 open/close 不匹配

| 属性 | 描述 |
|------|------|
| **特征** | strace -c 统计显示 open/openat/creat 调用数 > close 调用数（差异 > 5%） |
| **典型场景** | 函数正常路径正确关闭，但所有错误/异常分支都漏了 close |
| **诊断命令** | `strace -p PID -e trace=open,openat,creat,socket,close -c`（10-30 秒采样） |
| **根因定位** | valgrind --track-fds=yes 精确定位泄漏代码行 |
| **分支脚本** | `branch_F_syscall.sh` |
| **根本修复** | 使用 RAII/gotofree 模式确保所有路径释放 |

---

## 模式7：已删除文件仍被进程持有

| 属性 | 描述 |
|------|------|
| **特征** | `lsof +L1` 输出 > 0 行；磁盘空间无法释放即使删除了大文件 |
| **典型场景** | logrotate 轮转日志后进程未 reopen；临时文件使用后漏了 close 就被 unlink |
| **诊断命令** | `lsof +L1`，`ls -la /proc/PID/fd \| grep "(deleted)"` |
| **根因定位** | 查看 lsof 输出确认文件路径和 PID |
| **分支脚本** | `branch_G_deleted_file.sh` |
| **根本修复** | 配置 logrotate copytruncate；或确保进程正确处理 SIGHUP |

---

## 模式8：pipe FD 泄漏

| 属性 | 描述 |
|------|------|
| **特征** | `lsof -p PID` 显示大量 pipe 类型 FD；进程间通信相关 |
| **典型场景** | 子进程创建管道后父进程未关闭读端；线程池 pipe 通信未正确清理；`popen()` 调用后未 `pclose()` |
| **诊断命令** | `lsof -p PID \| grep -c pipe`，`ls -la /proc/PID/fd \| grep pipe` |
| **根因定位** | 检查 pipe()/popen() 后是否在子进程和父进程都正确关闭不用的端 |
| **根本修复** | 确保 pipe 两端正确关闭，使用 `pclose()` 替代 `close()` 关闭 popen 返回的句柄 |

---

## 模式9：事件/信号量/匿名 inode FD 泄漏

| 属性 | 描述 |
|------|------|
| **特征** | `lsof -p PID` 显示大量 `eventfd`、`signalfd`、`timerfd` 等匿名 inode 类型 FD |
| **典型场景** | 每次创建定时器/信号处理器时新建 FD 但未释放旧的；事件循环框架在重建时未清理旧事件 FD |
| **诊断命令** | `lsof -p PID \| grep -E "eventfd\|signalfd\|timerfd" \| wc -l` |
| **根因定位** | 检查 eventfd()/signalfd()/timerfd_create() 是否在不再使用时被 close() |
| **根本修复** | 在事件循环重建/销毁时清理对应的事件 FD |

---

## 模式10：线程间/进程间共享 FD 泄漏

| 属性 | 描述 |
|------|------|
| **特征** | 主进程 FD 数正常，但子线程/子进程 FD 数异常；`ps -eLf` 显示线程数偏多时 FD 总量激增 |
| **典型场景** | 线程池中每个线程重复打开同一资源（数据库/文件/日志）；fork 后子进程未关闭继承的不必要 FD |
| **诊断命令** | `ls /proc/PID/task/*/fd` 按线程统计；`lsof -i -P \| grep PID` 确认共享连接数 |
| **根因定位** | 检查线程初始化代码是否每个线程都重复 open；检查 fork 后是否 set O_CLOEXEC / FD_CLOEXEC |
| **根本修复** | 共享资源在进程启动时一次性打开；fork 后立即 close 子进程不需要的 FD |

---

## 模式11：JVM/Go runtime FD 泄漏

| 属性 | 描述 |
|------|------|
| **特征** | Java/Golang 进程中 FD 数持续增长，但用户无法直接控制底层 close() |
| **典型场景** | Java NIO selector 未关闭；netty/vert.x 连接池泄漏；Go HTTP client 的 Transport 未关闭空闲连接 |
| **诊断命令** | `jstack PID`（Java），`pprof`（Go）配合 `lsof -p PID` |
| **根因定位** | Java：检查 Selector.close()、Channel.close() 调用；Go：检查 http.Transport 的 IdleConnTimeout 配置 |
| **根本修复** | Java: 使用 try-with-resources；Go: 设置合理的 Transport.MaxIdleConns |

---

## 模式12：数据库连接池泄漏

| 属性 | 描述 |
|------|------|
| **特征** | 进程 socket FD 数持续增长，连接池监控显示活跃连接数 > 池大小 |
| **典型场景** | 应用获取连接后未归还（漏了 close/return）；异常路径中连接未释放 |
| **诊断命令** | `ss -tnp \| grep <PID> \| wc -l`，数据库连接池 JMX/MBean 监控 |
| **根因定位** | 检查所有 try-with-resources / finally 块是否覆盖了所有 return 路径 |
| **根本修复** | 设置连接池泄露检测（如 HikariCP leakDetectionThreshold）+ 确保所有路径释放连接 |
