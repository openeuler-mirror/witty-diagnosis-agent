# FD 诊断命令速查手册

> 配合 SKILL.md 第三节统一分析流程使用。

## 一、系统级诊断

### /proc/sys/fs/file-nr

查询系统整体 FD 水位：

| 命令 | 说明 |
|------|------|
| `cat /proc/sys/fs/file-nr` | 三列值：已分配FD / 空闲FD / 最大FD（file-max） |
| `cat /proc/sys/fs/file-max` | 系统级 FD 上限 |

**解读**：若 `已分配 / 最大 > 80%` 应告警；若 `已分配 ≈ 最大`（差值 < 100）则系统 FD 即将耗尽。

### /proc/sys/fs/file-max

可通过以下方式调整：

```bash
# 临时调整
echo 1000000 > /proc/sys/fs/file-max

# 永久调整（/etc/sysctl.conf）
fs.file-max = 1000000
sysctl -p
```

计算公式：`file-max ≈ 256 * (物理内存 GB) * (1~2)`，以 64GB 内存为例约 16K~32K，繁忙服务器建议 100K+。

---

## 二、进程级诊断

### /proc/<PID>/fd

```bash
# 统计进程 FD 总数
ls -1 /proc/<PID>/fd | wc -l

# 查看 FD 具体指向
ls -la /proc/<PID>/fd/ | head -20
```

**输出示例**：

```
lr-x------ 1 root root 64 Apr 8 10:00 0 -> /dev/null
l-wx------ 1 root root 64 Apr 8 10:00 1 -> /var/log/app.log
lrwx------ 1 root root 64 Apr 8 10:00 3 -> socket:[123456]
lrwx------ 1 root root 64 Apr 8 10:00 4 -> anon_inode:[eventpoll]
lrwx------ 1 root root 64 Apr 8 10:00 5 -> anon_inode:[eventfd]
lrwx------ 1 root root 64 Apr 8 10:00 6 -> /proc/<PID>/fd (deleted)
```

### /proc/<PID>/limits

```bash
cat /proc/<PID>/limits | grep "Max open files"
```

输出：`Max open files    1024  4096  files`（软限制/硬限制）

### /proc/<PID>/cmdline

```bash
cat /proc/<PID>/cmdline | tr '\0' ' '
```

---

## 三、lsof 命令

### 基础用法

| 命令 | 说明 |
|------|------|
| `lsof` | 列出所有打开的文件 |
| `lsof -p <PID>` | 指定进程的 FD |
| `lsof -u <user>` | 指定用户的 FD |
| `lsof +L1` | 已删除但仍被持有的文件（link count = 0） |
| `lsof -i` | 网络 socket 连接 |
| `lsof -i :port` | 特定端口的连接 |
| `lsof /path/to/file` | 谁在打开某文件 |

### 输出字段

| 字段 | 含义 |
|------|------|
| FD | 文件描述符编号（cwd=当前目录，txt=程序代码，mem=内存映射） |
| TYPE | 文件类型（REG=普通文件，DIR=目录，IPv4=TCP socket，a_inode=匿名 inode） |
| NODE | inode 号 / 协议号 |
| NAME | 文件路径 / 连接信息 |

### 常用组合

```bash
# 按类型统计
lsof -p <PID> | awk '{print $5}' | sort | uniq -c | sort -rn

# 统计 TCP socket 数
lsof -p <PID> | grep -c "IPv4"

# 统计 eventpoll FD
lsof -p <PID> | grep -c "eventpoll"

# 统计 inotify FD
lsof -p <PID> | grep -c "inotify"

# 统计 pipe FD
lsof -p <PID> | grep -c "pipe"
```

---

## 四、ss 命令

### 连接状态诊断

| 命令 | 说明 |
|------|------|
| `ss -tn` | 所有 TCP 连接（数字端口） |
| `ss -tn state close-wait` | CLOSE_WAIT 状态连接 |
| `ss -tn state time-wait` | TIME_WAIT 状态连接 |
| `ss -tnp` | 带进程信息的 TCP 连接 |
| `ss -tnp \| grep <PID>` | 指定进程的 TCP 连接 |
| `ss -s` | socket 统计摘要 |
| `ss -lnt` | 监听中的端口 |

### 计数组合

```bash
# 统计 CLOSE_WAIT 总数
ss -Htn state close-wait | wc -l

# 统计指定进程的 CLOSE_WAIT
ss -tnp | grep "pid=<PID>" | grep CLOSE-WAIT | wc -l

# socket 类型分布
ss -s
```

---

## 五、strace 命令

### FD 相关系统调用追踪

| 命令 | 说明 |
|------|------|
| `strace -p <PID> -e trace=open,close -c` | 统计 open/close 调用次数（10-30秒采样） |
| `strace -p <PID> -e trace=open,openat,close -c` | 同上，含 openat |
| `strace -p <PID> -e trace=file -c` | 所有文件相关系统调用 |
| `strace -p <PID> -e trace=network -c` | 所有网络相关系统调用 |
| `strace -f -p <PID> -e trace=open -c` | 含子线程 |

### 输出解读

```
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
 50.00    0.001234        1.23      1000         0 openat
 50.00    0.001234        1.23       950         0 close
------ ----------- ----------- --------- --------- ----------------
100.00    0.002468                  1950         0 total
```

解读：openat(1000) >> close(950)，差 50 次 → 每次执行漏了 close。

---

## 六、inotify 诊断

```bash
# 查询 inotify 系统限制
cat /proc/sys/fs/inotify/max_user_watches
cat /proc/sys/fs/inotify/max_user_instances
cat /proc/sys/fs/inotify/max_queued_events

# 查询指定进程的 inotify watch 数
lsof -p <PID> 2>/dev/null | grep inotify | awk '{print $NF}' | grep -v '^$' | \
  while read wd; do cat /proc/<PID>/fdinfo/$(echo $wd | sed 's/[^0-9]//g') 2>/dev/null | \
  grep -c "watch:"; done

# 全系统 inotify watch 使用量
find /proc/[0-9]*/fdinfo -type f 2>/dev/null | xargs grep -h "watch:" 2>/dev/null | wc -l
```

---

## 七、epoll 诊断

```bash
# 查看进程 epoll FD
ls -la /proc/<PID>/fd | grep eventpoll

# epoll 监控的事件数（通过 fdinfo 查看）
cat /proc/<PID>/fdinfo/<epoll_fd_num>
```

**fdinfo 输出示例**：

```
pos:    0
flags:  02
mnt_id: 21
tfd:        7 events:       19 data: 1234  pos:0 ino:56789 sdev:8
tfd:        8 events:       19 data: 5678  pos:0 ino:12345 sdev:8
```

`tfd` 是被监控的 FD 编号，正常服务通常有固定数量的监控项，泄漏时 `tfd` 条目数会持续增长。

---

## 八、进程 FD 趋势监控

```bash
# 实时 FD 增长监控
watch -n 5 "ls -1 /proc/<PID>/fd | wc -l"

# 采样并保存
for i in $(seq 1 12); do
  echo "$(date +%H:%M:%S) $(ls -1 /proc/<PID>/fd 2>/dev/null | wc -l)"
  sleep 5
done
```

**输出示例**：

```
10:00:00 1245
10:00:05 1267
10:00:10 1289
10:00:15 1311
→ 每 5 秒增长 ~22，速率 ~264 FD/min → 明确泄漏
```

---

## 九、其它工具

| 工具 | 用途 | 常用参数 |
|------|------|---------|
| `valgrind --tool=--track-fds=yes` | 开发环境 FD 泄漏检测 | `--track-fds=yes` |
| `fuser -v <file_path>` | 谁在使用文件/目录 | |
| `ftpd` | 监控文件打开（需单独安装） | |
| `perf trace -e open,close -p <PID>` | 系统调用采样（性能优于 strace） | |
| `bpftrace -e 'kprobe:do_sys_open { @[comm] = count(); }'` | 全系统 open 调用分布 | |
