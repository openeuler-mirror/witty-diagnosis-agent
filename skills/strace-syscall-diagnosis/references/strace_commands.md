# strace/ltrace 命令速查手册

## strace 基础采集

| 命令 | 用途 | 示例 |
|------|------|------|
| `strace -p <PID>` | 跟踪运行中的进程 | `strace -p 1234` |
| `strace <command>` | 启动并跟踪新进程 | `strace ls -l` |
| `strace -f -p <PID>` | 跟踪进程及其子线程 | `strace -f -p 1234` |
| `strace -ff -p <PID>` | 每个线程单独输出到文件 | `strace -ff -p 1234 -o trace` |
| `strace -e trace=network -p <PID>` | 只跟踪网络相关 syscall | `strace -e trace=network -p 1234` |
| `strace -e trace=file -p <PID>` | 只跟踪文件相关 syscall | `strace -e trace=file -p 1234` |
| `strace -e trace=desc -p <PID>` | 只跟踪 fd 相关 syscall | `strace -e trace=desc -p 1234` |
| `strace -e trace=process -p <PID>` | 只跟踪进程管理 syscall | `strace -e trace=process -p 1234` |
| `strace -e trace=ipc -p <PID>` | 只跟踪 IPC syscall | `strace -e trace=ipc -p 1234` |
| `strace -T -p <PID>` | 显示每个 syscall 耗时（微秒） | `strace -T -p 1234` |
| `strace -r -p <PID>` | 显示相对时间戳 | `strace -r -p 1234` |
| `strace -tt -p <PID>` | 显示绝对时间戳（微秒级） | `strace -tt -p 1234` |

## strace 统计分析

| 命令 | 用途 | 示例 |
|------|------|------|
| `strace -c -p <PID>` | 按 syscall 汇总统计（次数/耗时/错误） | `strace -c -p 1234`（Ctrl+C 结束）|
| `strace -c <command>` | 命令执行完自动统计 | `strace -c ls -l` |
| `strace -S time -p <PID>` | 按时间降序排序 syscall（-c 模式下） | `strace -S time -c -p 1234` |
| `strace -S calls -p <PID>` | 按调用次数降序排序 | `strace -S calls -c -p 1234` |
| `strace -S name -p <PID>` | 按 syscall 名排序 | `strace -S name -c -p 1234` |
| `strace -w -p <PID>` | 累计耗时汇总（等价于 -c 的耗时版本） | `strace -w -c -p 1234` |

## strace 条件过滤（-e）

| 命令 | 用途 | 示例 |
|------|------|------|
| `strace -e trace=open,openat,read,write` | 只跟踪指定 syscall | `strace -e trace=open,read -p 1234` |
| `strace -e signal=` | 忽略信号 | `strace -e signal= -p 1234` |
| `strace -e read=<fd>` | 显示指定 fd 的 read 内容 | `strace -e read=3 -p 1234` |
| `strace -e write=<fd>` | 显示指定 fd 的 write 内容 | `strace -e write=3 -p 1234` |
| `strace -e status=success` | 只显示成功的 syscall | `strace -e status=success -p 1234` |
| `strace -e status=failed` | 只显示失败的 syscall | `strace -e status=failed -p 1234` |
| `strace -e fault=open:error=EACCES:when=1` | 注入 syscall 故障（测试用） | `strace -e fault=open:error=EACCES:when=1 command` |

## strace 输出控制

| 命令 | 用途 | 示例 |
|------|------|------|
| `strace -o /tmp/strace.log -p <PID>` | 输出到文件 | `strace -o /tmp/strace.log -p 1234` |
| `strace -s 1024 -p <PID>` | 显示字符串最大长度（默认 32） | `strace -s 1024 -p 1234` |
| `strace -v -p <PID>` | 显示完整参数（不缩写结构体） | `strace -v -p 1234` |
| `strace -x -p <PID>` | 以十六进制显示非 ASCII 字符串 | `strace -x -p 1234` |
| `strace -q -p <PID>` | 安静模式（不显示 attach/detach 信息） | `strace -q -p 1234` |
| `strace -n -p <PID>` | 显示 syscall 耗时列（适用于较新版本） | `strace -n -p 1234` |
| `strace -z -p <PID>` | 只显示有错误的 syscall | `strace -z -p 1234` |

## ltrace 库函数追踪

| 命令 | 用途 | 示例 |
|------|------|------|
| `ltrace -p <PID>` | 跟踪运行中进程的库函数调用 | `ltrace -p 1234` |
| `ltrace <command>` | 启动并跟踪新进程的库函数 | `ltrace ls -l` |
| `ltrace -e malloc+free -p <PID>` | 只跟踪内存分配/释放函数 | `ltrace -e malloc+free -p 1234` |
| `ltrace -e 'libc*' -p <PID>` | 跟踪 libc 所有函数 | `ltrace -e 'libc*' -p 1234` |
| `ltrace -S -p <PID>` | 同时跟踪库函数和 syscall | `ltrace -S -p 1234` |
| `ltrace -c -p <PID>` | 库函数调用汇总统计 | `ltrace -c -p 1234` |
| `ltrace -o /tmp/ltrace.log -p <PID>` | 输出到文件 | `ltrace -o /tmp/ltrace.log -p 1234` |
| `ltrace -T -p <PID>` | 显示每个库函数调用耗时 | `ltrace -T -p 1234` |
| `ltrace -r -p <PID>` | 显示相对时间戳 | `ltrace -r -p 1234` |
| `ltrace -n 2 -p <PID>` | 缩进显示调用层次（2 级缩进） | `ltrace -n 2 -p 1234` |

## 进程 /proc 状态查看

| 命令 | 用途 | 示例 |
|------|------|------|
| `cat /proc/<PID>/status` | 进程状态、内存、线程数 | `cat /proc/1234/status` |
| `cat /proc/<PID>/fd \| wc -l` | 文件描述符数量 | `ls /proc/1234/fd \| wc -l` |
| `ls -la /proc/<PID>/fd` | 列出所有 fd 指向 | `ls -la /proc/1234/fd` |
| `cat /proc/<PID>/stack` | 进程内核栈（D 状态时特别有用） | `cat /proc/1234/stack` |
| `cat /proc/<PID>/syscall` | 进程当前正在执行的 syscall | `cat /proc/1234/syscall` |
| `cat /proc/<PID>/wchan` | 进程在内核中等待的函数 | `cat /proc/1234/wchan` |
| `cat /proc/<PID>/maps` | 进程内存映射 | `cat /proc/1234/maps` |
| `cat /proc/<PID>/cgroup` | 进程 cgroup 信息 | `cat /proc/1234/cgroup` |

## perf 与 strace 交叉分析

| 命令 | 用途 | 示例 |
|------|------|------|
| `perf stat -e syscalls:sys_enter_* -a -- sleep 10` | 系统级 syscall 统计 | `perf stat -e 'syscalls:sys_enter_*' -a -- sleep 10` |
| `perf top -e syscalls:sys_enter_open` | 实时查看 open 系统调用 | `perf top -e syscalls:sys_enter_open` |
| `perf record -e syscalls:sys_enter_read -p <PID> -- sleep 10` | 记录指定进程的 read syscall | `perf record -e syscalls:sys_enter_read -p 1234 -- sleep 10` |
| `perf trace -p <PID>` | perf 内置的 strace 替代（更低开销） | `perf trace -p 1234` |

## 典型分析模式

### 快速查看进程当前在干嘛
```
cat /proc/<PID>/status | grep "State\|Sig"
cat /proc/<PID>/wchan
cat /proc/<PID>/stack
cat /proc/<PID>/syscall
```

### 检查文件描述符泄漏
```
# 每隔 2 秒查看 fd 数量变化
while true; do echo "$(date +%H:%M:%S) fd=$(ls /proc/<PID>/fd 2>/dev/null | wc -l)"; sleep 2; done

# 或一次性看所有 fd
ls -la /proc/<PID>/fd
```

### 找出最慢的 syscall
```
strace -T -c -p <PID>
# -T 显示耗时, -c 汇总统计, 找 avg time 最高的列
```

### 只看失败的 syscall
```
strace -e status=failed -p <PID>
```

### 追踪网络连接失败
```
strace -e trace=network -s 1024 -p <PID>
```

### 追踪文件操作失败（配合 errno）
```
strace -e trace=file -z -p <PID>
# -z 只显示错误
```

### 分析 EAGAIN 是否正常
```
strace -e trace=read,write,recv,send -e status=failed -p <PID>
# 观察 EAGAIN 出现的频率和间隔
# 正常非阻塞 IO 应有短暂间歇；忙等则说明需要调整
```

### ltrace 分析内存分配模式
```
ltrace -e malloc+realloc+calloc+free -T -p <PID> 2>&1 | head -100
```
