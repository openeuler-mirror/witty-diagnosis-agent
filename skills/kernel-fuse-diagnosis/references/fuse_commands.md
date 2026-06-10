# FUSE 诊断命令速查

## 基础检测

| 命令 | 用途 | 示例 |
|------|------|------|
| `mount -t fuse` | 列出所有 FUSE 挂载点 | `mount -t fuse` |
| `grep fuse /proc/mounts` | 检查 /proc/mounts 中 FUSE 条目 | `grep fuse /proc/mounts` |
| `stat <mount_point>` | 检查挂载点状态 | `stat /mnt/fuse` |
| `ls -la <mount_point>` | 基本连通性测试 | `ls -la /mnt/fuse` |
| `ps aux \| grep -E "[f]use"` | 查找 FUSE daemon 进程 | `ps aux | grep "[f]use"` |

## FUSE 内核连接 (sysfs)

```bash
# 所有 FUSE 连接 ID
ls /sys/fs/fuse/connections/

# 连接详情
cat /sys/fs/fuse/connections/<ID>/waiting          # 等待请求数
cat /sys/fs/fuse/connections/<ID>/abort            # 是否已中止
cat /sys/fs/fuse/connections/<ID>/max_background   # 最大后台请求数
cat /sys/fs/fuse/connections/<ID>/congested_threshold_ms  # 拥塞阈值(ms)
cat /sys/fs/fuse/connections/<ID>/max_read         # 最大读取大小

# 遍历所有连接
for conn in /sys/fs/fuse/connections/*/; do
  echo "=== Connection $(basename $conn) ==="
  cat $conn/waiting
  cat $conn/max_background
  cat $conn/max_read
done
```

## FUSE 内核模块参数

```bash
# 查看 FUSE 模块信息
modinfo fuse

# 内核模块参数
cat /sys/module/fuse/parameters/max_read          # 全局最大读
cat /sys/module/fuse/parameters/max_write         # 全局最大写
cat /sys/module/fuse/parameters/use_writeback_cache  # writeback cache 开关

# 模块版本
cat /sys/module/fuse/version 2>/dev/null
cat /sys/module/fuse/srcversion 2>/dev/null
```

## 进程级诊断

```bash
# 进程 FD 列表确认 FUSE 相关
ls -la /proc/<daemon_pid>/fd/ | grep fuse

# 统计 FD 数
ls -1 /proc/<daemon_pid>/fd | wc -l

# 进程线程列表
ps -eLf | grep <daemon_name>

# 线程内核栈
for tid in $(ls /proc/<daemon_pid>/task/); do
  echo "TID:$tid"; cat /proc/$tid/stack 2>/dev/null
done

# 进程能力集
cat /proc/<daemon_pid>/status | grep Cap

# 进程 limits
cat /proc/<daemon_pid>/limits | grep "Max open files"
```

## strace 追踪

```bash
# 统计系统调用
strace -e trace=write,read,ioctl -p <daemon_pid> -c

# 多线程追踪
strace -f -e trace=write,read,ioctl -p <daemon_pid> -c

# FUSE 所有相关调用
strace -e trace=read,write,ioctl,open,openat,close -p <daemon_pid> -c

# 完整追踪到文件
strace -f -e trace=all -p <daemon_pid> -o /tmp/strace_fuse.log

# 客户端操作追踪
strace -e trace=all ls -la <mount_point> 2>&1
```

## lsof 诊断

```bash
# daemon 打开的文件
lsof -p <daemon_pid>

# 按类型统计
lsof -p <daemon_pid> | awk '{print $5}' | sort | uniq -c | sort -rn

# 统计 socket 数
lsof -p <daemon_pid> | grep -c "IPv4"

# 已删除但仍被持有的文件
lsof +L1
```

## 系统日志与 dmesg

```bash
# FUSE 相关内核消息
dmesg | grep -i fuse
dmesg | grep -iE "fuse|libfuse"

# 内核异常检查
dmesg | grep -iE "kernel panic|Oops|BUG|soft lockup"

# systemd 日志
journalctl -u <daemon_service> --since "10 min ago"

# 系统日志
grep -i fuse /var/log/messages 2>/dev/null | tail -20
grep -i fuse /var/log/syslog 2>/dev/null | tail -20
```

## GDB 诊断（daemon 死锁场景）

```bash
# 所有线程回溯
gdb -p <daemon_pid> -batch -ex "thread apply all bt"

# 特定线程回溯
gdb -p <daemon_pid> -batch -ex "thread 1" -ex "bt"

# 锁信息
gdb -p <daemon_pid> -batch -ex "info locks"

# 输出到文件
gdb -p <daemon_pid> -batch \
  -ex "thread apply all bt" \
  -ex "info threads" \
  -ex "quit" 2>&1 | tee /tmp/gdb_backtrace.txt
```

## 性能测试

```bash
# 顺序读测试
dd if=<mount_point>/test of=/dev/null bs=1M count=100

# 顺序写测试
dd if=/dev/zero of=<mount_point>/test bs=1M count=100

# 随机读写测试
fio --name=fuse-test --directory=<mount_point> \
    --rw=randrw --bs=4k --size=100M --numjobs=4

# I/O 延迟监控
iostat -x 1 <device>
```

## 权限与配置

```bash
# /dev/fuse 设备权限
ls -la /dev/fuse
getfacl /dev/fuse 2>/dev/null

# FUSE 全局配置
cat /etc/fuse.conf

# 用户组检查
grep fuse /etc/group
groups <daemon_user>

# 容器能力检查
capsh --print | grep -i fuse 2>/dev/null
```

## 调试与开发

```bash
# FUSE 文件系统调试挂载（libfuse 示例）
gdb --args <daemon_binary> -d -f <mount_point>

# 前台调试模式
<daemon_binary> -d -f <mount_point> -o allow_other

# libfuse 版本
pkg-config --modversion fuse 2>/dev/null
dpkg -l | grep libfuse 2>/dev/null
rpm -qa | grep fuse 2>/dev/null
```
