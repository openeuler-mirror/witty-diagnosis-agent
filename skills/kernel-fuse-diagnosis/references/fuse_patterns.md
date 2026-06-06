# FUSE 故障模式与正则匹配

## 通用 FUSE 错误模式

| 模式 | 正则 | 对应故障 |
|------|------|---------|
| 连接已断开 | `Transport endpoint is not connected` | Daemon 崩溃/连接中止 |
| EIO 错误 | `Input/output error` | FUSE 操作失败 |
| 权限被拒 | `Permission denied` | /dev/fuse 权限 |
| 设备不存在 | `No such device` | /dev/fuse 缺失 |
| 资源暂时不可用 | `Resource temporarily unavailable` | 请求队列满 |
| 连接被拒绝 | `Connection refused` | FUSE socket 连接 |
| 操作不支持 | `Operation not supported` | FUSE 版本/功能不匹配 |
| 设备忙 | `Device or resource busy` | 挂载点被占用 |

## FUSE sysfs 异常模式

| 模式 | 正则 | 说明 |
|------|------|------|
| 连接不存在 | `ls: cannot access '/sys/fs/fuse/connections/*'` | 无活跃 FUSE 连接 |
| waiting 异常 | `/sys/fs/fuse/connections/\d+/waiting:\d+` | waiting 值持续 > 0 |
| waiting 持续增长 | `waiting:\d+` 序列递增 | 请求队列阻塞 |
| max_background 满 | `max_background:\d+` == waiting | 达到后台请求上限 |
| abort 已触发 | `abort:\d+` 返回 1 | 连接已中止 |
| 连接异常多 | `ls /sys/fs/fuse/connections/ \| wc -l` | 多个异常连接 |

## FUSE daemon 进程异常

| 模式 | 正则 | 说明 |
|------|------|------|
| 进程不存在 | `ps aux \| grep -E "[f]use"` 无输出 | Daemon 已崩溃/退出 |
| D 状态进程 | `^[^ ]+ D ` in ps output | 不可中断睡眠 |
| D 状态内核栈 | `fuse_request_send` in `/proc/PID/stack` | 等待 FUSE 完成 |
| 线程全部阻塞 | `pthread_mutex_lock` in all stack | 多线程死锁 |
| 线程数异常 | `NLWP` > 预期 | 线程管理问题 |
| OOM 记录 | `Out of memory:.*Killed process.*fuse` | OOM Killer |

## dmesg / 内核日志

```regex
# FUSE 连接中止
fuse.*aborting connection

# FUSE 请求超时
fuse.*timeout.*request

# FUSE 内核 BUG
kernel BUG at fs/fuse/dev.c:\d+

# FUSE Oops
Oops.*fuse_dev_do_write
Oops.*fuse_dev_do_read

# FUSE 软死锁
soft lockup.*fuse_

# FUSE 内存分配失败
fuse.*allocation failed

# FUSE 参数异常
fuse.*bad.*parameter

# 并发访问警告
fuse.*concurrent.*access

# FUSE 文件系统只读
fuse.*read.only
```

## 挂载/卸载异常模式

| 模式 | 正则 | 说明 |
|------|------|------|
| 挂载失败 | `fusermount: mount failed` | FUSE 挂载拒绝 |
| 已挂载 | `fuse.*is already mounted` | 挂载点冲突 |
| 设备不存在 | `fusermount: device not found` | /dev/fuse 缺失 |
| 权限拒绝 | `fusermount: permission denied` | 无权限挂载 |
| 用户不允许 | `fuse.*user_allow_other not set` | 配置缺失 |

## 性能退化模式

| 模式 | 正则 | 说明 |
|------|------|------|
| 小 max_read | `max_read:\d{1,4}$` (<= 65536) | max_read 配置过小 |
| 小 max_write | `max_write:\d{1,4}$` (<= 65536) | max_write 配置过小 |
| 高 I/O 等待 | `iowait:\s+\d+\.\d+` in top | FUSE I/O 瓶颈 |
| 请求堆积 | `waiting:\d{3,}` (>= 100) | 请求队列深度异常 |
| D 状态进程数 | `D` 状态进程 > CPU 线程数 | FUSE 后端阻塞 |

## 权限与安全模式

| 模式 | 正则 | 说明 |
|------|------|------|
| 设备权限 | `/dev/fuse.*(crw-rw-rw-|crw-rw----)` | 设备节点权限 |
| 用户组缺失 | `groups.*fuse` 未包含 | 用户不在 fuse 组 |
| SELinux 拒绝 | `SELinux.*fuse.*denied` | SELinux 策略阻止 |
| AppArmor 拒绝 | `apparmor.*fuse.*DENIED` | AppArmor 策略阻止 |
| 容器能力缺失 | `Cap.*=.*0000000000000000` | 容器缺少 capabilities |

## 已知 FUSE 内核 Bug 模式

### 内核版本特征匹配

| 版本范围 | 已知问题 | 匹配条件 |
|----------|---------|---------|
| 5.10 - 5.15 | 并发挂载竞争 | `uname -r` 匹配 `5.1[0-5]` |
| 4.18 - 5.0 | memory cgroup OOM | `uname -r` 匹配 `4.1[89]` 或 `4.[0-9]+` |
| 3.15 - 3.18 | 并发写死锁 | `uname -r` 匹配 `3.1[5-8]` |

### 内核栈回溯匹配

```regex
# FUSE 死锁模式
Call Trace.*
.*fuse_request_send.*
.*fuse_simple_request.*
.*fuse_write_begin.*
.*fuse_page_mkwrite.*

# FUSE 并发 BUG
Call Trace.*
.*fuse_dev_do_write.*
.*fuse_dev_do_read.*
.*spin_lock.*
```

## 日志时间线分析

FUSE 故障通常有明确的时间线：

```text
T0: [FUSE daemon 正常运行] → waiting=0
T1: [请求开始堆积] → waiting 开始增长
T2: [daemon 线程阻塞] → 所有线程在 FUSE 请求中等待
T3a: [daemon 崩溃] → 进程退出 → 连接中止 → EIO
T3b: [内核中止] → abort=1 → dmesg "aborting connection"
T4: [系统恢复/FD 清理] → 连接销毁
```

关键日志模式：

```regex
# 时间序列检测
T0->T1: 3分钟内 waiting 从 0 增长到 100+
T1->T2: waiting 增长同时 daemon 线程陷入 D 状态
T2->T3: daemon 退出或 OOM kill 日志
```

## 故障树匹配规则

```yaml
fuse_eio:
  match: "Transport endpoint is not connected|Input/output error"
  next: "branch_A_daemon_crash.sh"

fuse_hang:
  match: "waiting:\d{2,}"  # waiting >= 10
  next: "branch_B_req_queue.sh"

fuse_slow:
  match: "max_read:\d{1,4}"  # <= 65536
  next: "branch_C_max_read_write.sh"

fuse_inconsistent:
  match: "writeback_cache"
  next: "branch_D_writeback_cache.sh"

fuse_deadlock:
  match: "pthread_mutex_lock.*wait"
  next: "branch_E_mt_deadlock.sh"

fuse_perm:
  match: "Permission denied|/dev/fuse"
  next: "branch_F_dev_fuse_perm.sh"

fuse_kernel_bug:
  match: "kernel BUG at fs/fuse|Oops.*fuse"
  next: "branch_G_kernel_bug.sh"

fuse_mixed:
  match: ".*"  # 兜底
  next: "branch_H_mixed.sh"
```
