# io_uring 诊断命令参考

本文件记录常用诊断命令。所有命令默认用于信息采集；对在线进程执行 strace、perf、
ftrace 或 bpftrace 前，需要说明性能影响并取得确认。

## 基线信息

```bash
uname -a
cat /etc/os-release
ulimit -a
cat /proc/meminfo
cat /proc/sys/kernel/osrelease
```

## 进程状态

```bash
cat /proc/<pid>/status
cat /proc/<pid>/limits
cat /proc/<pid>/cgroup
ls -la /proc/<pid>/fd | head -100
ps -L -p <pid> -o pid,tid,psr,stat,pcpu,comm,wchan:32
```

## io_uring syscall 轨迹

```bash
strace -f -tt -T -e trace=io_uring_setup,io_uring_enter,io_uring_register -p <pid>
strace -f -e trace=%desc,%file,io_uring_setup,io_uring_enter,io_uring_register <command>
```

需要记录的字段：

- syscall 名称和 errno。
- setup entries 和 flags。
- register opcode。
- 调用耗时（`-T`）。
- 线程 ID 和时间戳。

## Worker 与 SQPOLL 线程

```bash
ps -eLf | grep -E 'iou-wrk|iou-sqp|io_uring|<process-name>'
ps -L -p <pid> -o pid,tid,stat,pcpu,pmem,comm,wchan:32
for t in /proc/<pid>/task/*; do
  echo "== $t =="; cat "$t/status" 2>/dev/null | grep -E 'Name|State|voluntary|nonvoluntary';
  cat "$t/wchan" 2>/dev/null;
done
```

有 root 权限时，可补充内核栈：

```bash
cat /proc/<pid>/task/<tid>/stack
```

## 日志

```bash
dmesg -T | grep -Ei 'io_uring|uring|iou-wrk|iou-sqp|direct I/O|O_DIRECT|EINVAL|ENOMEM|EAGAIN'
journalctl -k --since '2026-06-02 10:00:00' --until '2026-06-02 10:30:00' \
  | grep -Ei 'io_uring|uring|direct I/O|O_DIRECT|ENOMEM|EINVAL|EAGAIN'
```

## O_DIRECT 对齐

```bash
stat -fc 'fs_type=%T block_size=%s' <mount-point>
blockdev --getss /dev/<device>
blockdev --getpbsz /dev/<device>
findmnt -T <file>
```

需要向应用侧补充确认：

- buffer 地址。
- I/O 长度。
- 文件 offset。
- 文件打开 flags。
- 文件系统和后端块设备。

## 兼容性探测

```bash
grep -R "IORING_OP_" /usr/include/linux/io_uring.h 2>/dev/null | tail
grep -R "IORING_FEAT_" /usr/include/linux/io_uring.h 2>/dev/null
```

header 中存在符号不代表运行内核支持对应 feature。优先使用小型 runtime probe 或应用
strace 证据确认。
