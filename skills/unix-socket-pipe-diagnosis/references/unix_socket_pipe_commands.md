# UDS / Pipe 诊断命令速查手册

> 配合 SKILL.md 第三节统一分析流程使用。

## 一、UDS 全局诊断

### ss -x（UDS socket 统计）

| 命令 | 说明 |
|------|------|
| `ss -x` | 列出所有 UDS socket |
| `ss -xl` | 只显示 UDS listen socket |
| `ss -xp` | 显示 UDS 进程凭证信息（PID、FD） |
| `ss -xa` | 所有 UDS socket（含已关闭的） |
| `ss -x state all` | 所有状态的 UDS socket |
| `ss -x state listening` | 只显示监听状态 |
| `ss -x state established` | 只显示已建立连接 |
| `ss -x src @abstract_name` | 按 abstract 地址筛选 |

**输出示例**：

```
Netid  State      Recv-Q Send-Q  Local Address:Port   Peer Address:Port   Process
u_str  LISTEN     0      128     /var/run/app.sock    * 0                  users:(("app",pid=1234,fd=3))
u_str  ESTAB      0      0       /var/run/app.sock    12345                users:(("client",pid=5678,fd=7))
```

**关键字段解读**：
- `Recv-Q`：listen socket 的已接收但尚未被 accept 的连接数（backlog 积压指标）
- `Send-Q`：对于 listen socket，表示 backlog 最大值
- `State`：LISTEN / ESTAB / CLOSE-WAIT / TIME-WAIT 等

### cat /proc/net/unix

```bash
cat /proc/net/unix
```

**输出示例**：

```
Num       RefCount Protocol Flags    Type St Inode Path
ffff...: 00000002 00000000 00010000 0001 01 123456 /var/run/app.sock
ffff...: 00000003 00000000 00000000 0001 01 123457 @abstract_sock
ffff...: 00000002 00000000 00010000 0002 01 123458
```

**字段说明**：

| 字段 | 含义 |
|------|------|
| Num | 内核 socket 地址 |
| RefCount | 引用计数 |
| Protocol | 协议（UDS 为 0） |
| Flags | `00010000` = listen socket |
| Type | 1=stream（SOCK_STREAM），2=dgram（SOCK_DGRAM），5=seqpacket（SOCK_SEQPACKET） |
| St | 状态（01=established，02=listen，03=close） |
| Inode | socket inode 号 |
| Path | UDS 路径（带 @ 前缀表示 abstract socket，空表示未命名匿名 socket） |

### lsof -U

```bash
# 列出所有 UDS FD
lsof -U

# 按进程过滤
lsof -U -p <PID>

# 按进程名过滤
lsof -U -c <process_name>

# 统计 UDS FD 数量
lsof -U | wc -l
```

---

## 二、进程级 UDS 诊断

### /proc/<PID>/fd

```bash
# 列出进程所有 FD，过滤出 UDS socket 和 pipe
ls -la /proc/<PID>/fd/ | grep -E "socket|pipe"

# 统计 socket FD 数量
ls -la /proc/<PID>/fd/ | grep "socket" | wc -l

# 统计 pipe FD 数量
ls -la /proc/<PID>/fd/ | grep "pipe" | wc -l
```

**输出示例**：

```
lrwx------ 1 root root 64 Apr 8 10:00 3 -> socket:[123456]
lrwx------ 1 root root 64 Apr 8 10:00 4 -> socket:[123457]
lrwx------ 1 root root 64 Apr 8 10:00 5 -> pipe:[234567]
lrwx------ 1 root root 64 Apr 8 10:00 6 -> pipe:[234568]
```

### lsof -p <PID>

```bash
# 过滤 UDS 类型
lsof -p <PID> | grep unix

# 过滤 pipe 类型
lsof -p <PID> | grep pipe

# 按类型统计 UDS/pipe 分布
lsof -p <PID> | awk '{print $5}' | sort | uniq -c | sort -rn
```

---

## 三、UDS 连接状态诊断

### 按状态过滤

```bash
# 所有状态的 UDS socket
ss -x state all

# 只显示 listen 状态
ss -x state listening

# 只显示 established 状态（活跃连接）
ss -x state established

# 只显示 closed 状态
ss -x state closed

# 只显示 close-wait 状态
ss -x state close-wait
```

### 计数组合

```bash
# 统计 listen socket 总数
ss -Hxl | wc -l

# 统计 established 连接数
ss -Hx state established | wc -l

# 统计指定进程的 UDS 连接
ss -xp | grep "pid=<PID>" | wc -l
```

### UDS 连接详情查看

```bash
# 展开显示详细信息
ss -xlp

# 显示 UDS socket 内存使用
ss -xlm

# 显示 UDS socket 计时器状态
ss -xlo
```

---

## 四、Abstract Socket 诊断

### 识别 abstract socket

```bash
# 查看所有 abstract socket（地址以 @ 开头）
ss -xl | grep @

# 用 lsof 查看 abstract socket
lsof -U | grep ABSTRACT

# 从 /proc/net/unix 中过滤
cat /proc/net/unix | grep @
```

### Abstract socket 冲突检测

```bash
# 检查同一个 @address 是否有多个 listen socket
ss -xl | grep "@myservice" | wc -l

# 检查某 abstract socket 的使用者进程
ss -xlp | grep "@abstract_name"
```

### Abstract socket 调试

```bash
# 绑定 abstract socket 需要进程权限
# 108 bytes 路径限制同样适用于 abstract socket

# 查看 abstract socket 绑定的进程详情
ss -xlp | grep @ | awk '{print $NF}'
```

---

## 五、Socket 文件权限诊断

### 查看 socket 文件属性

```bash
# 查看 socket 文件权限和所有者
ls -la /path/to/socket.sock

# 使用 stat 查看完整元数据
stat /path/to/socket.sock

# 查看 ACL 权限
getfacl /path/to/socket.sock
```

**输出示例**：

```
srwxr-xr-x 1 root root 0 Apr  8 10:00 /var/run/app.sock
```

`srwxr-xr-x`：第一个字符 `s` 表示 socket 文件，后 9 位为标准权限位。

### 搜索 socket 文件

```bash
# 全系统查找 socket 文件
find / -type s 2>/dev/null

# 指定目录下查找 socket 文件
find /var/run -type s -ls

# 按权限查找
find / -type s -perm 000 2>/dev/null
```

### 权限问题诊断

```bash
# 检查用户能否连接
sudo -u <username> test -w /path/to/socket.sock && echo "writable" || echo "not writable"

# 检查连接时的实际权限需求：
# connect 需要 socket 文件可写权限
# listen 需要父目录可写 + socket 文件创建权限

# strace 连接时的权限错误
strace -e trace=connect -p <PID>
```

---

## 六、管道诊断

### 管道参数查询

```bash
# 系统 pipe 最大值
cat /proc/sys/fs/pipe-max-size

# pipe 用户页面限制
cat /proc/sys/fs/pipe-user-pages-soft
cat /proc/sys/fs/pipe-user-pages-hard

# 查看 pipe 容量（bytes）
# 通过 fcntl F_GETPIPE_SZ 查询
```

### 进程管道状态

```bash
# 查找 D 状态进程
ps aux | awk '$8 ~ /D/ {print $2, $11, $8}'

# 查看 D 状态进程的内核等待原因
cat /proc/<PID>/wchan

# 查看 D 状态进程的内核栈
cat /proc/<PID>/stack
```

**wchan 输出解读**：
- `pipe_wait`：进程在 pipe 读写操作上阻塞（管道缓冲区满/空）
- `sock_alloc_send_pskb`：socket 发送缓冲区满
- `__lock_sock`：socket 锁竞争

### 进程 pipe FD 诊断

```bash
# 列出进程的 pipe FD
ls -la /proc/<PID>/fd/ | grep pipe

# 通过 lsof 看 pipe 详情
lsof -p <PID> | grep pipe

# 查看 pipe 大小（通过 fdinfo）
cat /proc/<PID>/fdinfo/<pipe_fd_num>
```

**fdinfo 输出示例**：

```
pos:    0
flags:  02004000
mnt_id: 21
```

注意：pipe fdinfo 不直接显示缓冲区大小，需通过 fcntl 查询。

### 管道容量查询（fcntl）

```c
// C 代码查询 pipe 大小
#include <unistd.h>
#include <fcntl.h>
long size = fcntl(fd, F_GETPIPE_SZ);
```

```bash
# 通过 gdb 附加进程查看 pipe 大小（开发环境）
gdb -p <PID> -batch -ex "call (long)fcntl(<fd_num>, 1032)"

# Python 方式
python3 -c "
import fcntl, os
fd = os.open('/proc/<PID>/fd/<pipe_num>', os.O_RDONLY)
print(fcntl.fcntl(fd, 1032))
"
```

---

## 七、SIGPIPE 信号诊断

### 信号处理状态

```bash
# 查看进程信号处理配置
cat /proc/<PID>/status | grep -E "SigIgn|SigCgt"

# SigIgn 是位掩码（已忽略的信号），SigCgt 是位掩码（已捕获的信号）
# SIGPIPE = signal 13
# 第 13 位为 1 表示已忽略/已捕获

# 将位掩码转为二进制查看
echo "obase=2; ibase=16; $(cat /proc/<PID>/status | grep SigIgn | awk '{print $2}')" | bc

# 更简便的查看方式
python3 -c "
with open('/proc/<PID>/status') as f:
    for line in f:
        if 'SigIgn' in line or 'SigCgt' in line:
            val = int(line.split()[1], 16)
            sigpipe_ignored = bool(val & (1 << 13)) if 'Ign' in line else None
            sigpipe_caught = bool(val & (1 << 13)) if 'Cgt' in line else None
            print(f'{line.split()[0]}: 0x{line.split()[1]:>16s}')
            if 'Ign' in line:
                print(f'  SIGPIPE (13) ignored: {sigpipe_ignored}')
            if 'Cgt' in line:
                print(f'  SIGPIPE (13) caught: {sigpipe_caught}')
"
```

### strace 追踪信号

```bash
# 追踪进程的信号处理
strace -e trace=signal -p <PID>

# 记录 SIGPIPE 被发送
strace -e trace=kill,tkill,tgkill -p <PID>

# 追踪接收到 SIGPIPE 时的行为
strace -e trace=signal -p <PID> 2>&1 | grep -E "SIGPIPE|signal 13"
```

### SIGPIPE 发送端定位

```bash
# 查看谁在发送 SIGPIPE
# 通过 auditd 监控（需 root）
auditctl -a exit,always -S kill -F pid=<PID>

# 查看系统日志中的信号相关信息
dmesg | grep -i signal

# 使用 perf 追踪 signal 传递
perf record -e signal:signal_generate -p <PID>
```

---

## 八、strace 追踪

### UDS 系统调用追踪

```bash
# 追踪 UDS 相关系统调用
strace -e trace=bind,listen,accept,connect,sendmsg,recvmsg -p <PID>

# 统计 UDS 调用次数
strace -e trace=bind,listen,accept,connect -p <PID> -c

# 追踪 socket 创建（含 socketpair）
strace -e trace=socket,socketpair -p <PID>

# 新建进程追踪 UDS
strace -e trace=bind,listen,accept,connect,sendmsg,recvmsg /path/to/program
```

### Pipe 系统调用追踪

```bash
# 追踪 pipe 相关调用
strace -e trace=pipe,pipe2,write,read -p <PID>

# 统计 pipe 调用
strace -e trace=pipe,pipe2,write,read -p <PID> -c

# 追踪新建进程的 pipe 操作
strace -e trace=pipe,pipe2,write,read /path/to/program
```

### socketpair 追踪

```bash
# 追踪 socketpair 和 close
strace -e trace=socketpair,close -p <PID>

# 统计 socketpair vs close 比例
strace -e trace=socketpair,close -p <PID> -c
```

**输出解读**：

```
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
 40.00    0.001000       10.00       100         0 socketpair
 60.00    0.001500        0.01      1000         0 close
------ ----------- ----------- --------- --------- ----------------
100.00    0.002500                 1100         0 total
```

解读：socketpair(100) ≠ close(1000)/2 -> 100 次 socketpair 应产生 200 个 FD，close 只被调了 1000 次？需进一步验证是否每个 FD 都被关闭。若 socketpair 调用后每个产生 2 FD，100 次产生 200 FD，close 1000 次看似够但需要确认关闭的是否对应 socketpair FD。

---

## 九、凭证传递诊断

### SO_PASSCRED 设置检查

```bash
# 查看 UDS 连接凭证信息
ss -xp

# 检查是否需要 SO_PASSCRED（server 端）
# 如果已设 SO_PASSCRED 则 ss -xp 会显示凭据信息
# 如果未设置，recvmsg 收不到辅助数据
```

**ss -xp 输出示例**（已设置 SO_PASSCRED）：

```
u_str  LISTEN     0      128    @abstract_sock  * 0
  users:(("server",pid=1234,fd=3))
  credential: pid=1234,uid=0,gid=0
u_str  ESTAB      0      0      @abstract_sock  @client_sock
  users:(("client",pid=5678,fd=7))
  credential: pid=5678,uid=1000,gid=1000
```

**ss -xp 输出示例**（未设置 SO_PASSCRED - 无凭证行）：

```
u_str  LISTEN     0      128    @abstract_sock  * 0
  users:(("server",pid=1234,fd=3))
u_str  ESTAB      0      0      @abstract_sock  @client_sock
  users:(("client",pid=5678,fd=7))
```

### 辅助数据（SCM_RIGHTS / SCM_CREDENTIALS）诊断

```bash
# 系统辅助数据缓冲区上限
cat /proc/sys/net/core/optmem_max

# 检查 recvmsg 是否能收到辅助数据
strace -e trace=recvmsg -p <PID> 2>&1 | grep -E "SCM_RIGHTS|SCM_CREDENTIALS|cmsg"

# 查看缓冲区设置
cat /proc/sys/net/core/rmem_default
cat /proc/sys/net/core/wmem_default
```

### 编程验证

```bash
# 使用 Python 快速测试 UDS 凭证传递
python3 -c "
import socket, struct
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_PASSCRED, 1)
print('SO_PASSCRED set successfully')
"
```

---

## 十、趋势监控

### UDS 趋势

```bash
# 监控 UDS listen socket 数量
watch -n 5 'echo "UDS listen sockets: $(ss -Hxl | wc -l)"'

# 监控 UDS Recv-Q 异常
watch -n 5 'ss -xl | awk "NR>1 && \$3 > 0 {print \$0}"'

# 监控 abstract socket 数量
watch -n 5 'echo "Abstract sockets: $(ss -xl | grep -c @)"'

# 监控 UDS 连接建立数
watch -n 5 'ss -x state established | wc -l'
```

### Pipe 趋势

```bash
# 监控 pipe FD 总数
watch -n 5 'echo "Pipe FDs: $(lsof -U 2>/dev/null | grep -c pipe || echo 0)"'

# 监控 D 状态进程
watch -n 5 'ps aux | awk "\$8 ~ /D/ {print \$2, \$11, \$8}"'
```

### socketpair 趋势

```bash
# 监控匿名 socket（含 socketpair）
watch -n 5 'ss -xa | grep -v "@\|/" | wc -l'

# 监控指定进程的 socketpair FD 增长
watch -n 5 'ls -la /proc/<PID>/fd/ | grep "socket" | wc -l'

# 采样并保存到文件
for i in $(seq 1 12); do
  echo "$(date +%H:%M:%S) UDS:$(ss -Hxl | wc -l) Pipe:$(lsof -U 2>/dev/null | grep -c pipe || echo 0)"
  sleep 5
done
```

**输出示例**：

```
10:00:00 UDS:15 Pipe:23
10:00:05 UDS:15 Pipe:25
10:00:10 UDS:16 Pipe:27
10:00:15 UDS:16 Pipe:29
```

→ Pipe FD 每 5 秒增长 2 → 管道泄漏。
