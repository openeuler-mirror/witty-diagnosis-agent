# 内核 FD 相关参数调优参考

> 配合 SKILL.md L1 系统层分析使用。

---

## 一、系统级参数

### /proc/sys/fs/file-max

| 属性 | 值 |
|------|------|
| **路径** | `/proc/sys/fs/file-max` |
| **含义** | 系统级别打开文件描述符最大数量 |
| **默认** | 81920（64位系统，基于内存自动计算） |
| **推荐** | 繁忙服务器建议 1000000+，公式：`256 * 物理内存(GB) * 2` |
| **查看** | `cat /proc/sys/fs/file-max` |
| **修改（临时）** | `echo 1000000 > /proc/sys/fs/file-max` |
| **修改（持久化）** | `/etc/sysctl.conf` 添加 `fs.file-max = 1000000`，执行 `sysctl -p` |
| **注意** | 增大 file-max 会消耗内核内存（每个 FD 约 1KB slab），不可无限增大 |

### /proc/sys/fs/file-nr

| 属性 | 值 |
|------|------|
| **路径** | `/proc/sys/fs/file-nr` |
| **含义** | 三列值：已分配FD / 空闲FD / 最大FD（同 file-max） |
| **解读** | 已分配接近最大时系统面临 FD 耗尽；空闲FD表示已分配但未使用的闲置FD |
| **告警阈值** | 已分配/最大 > 80% → 告警；已分配/最大 > 95% → 严重预警 |

### /proc/sys/fs/nr_open

| 属性 | 值 |
|------|------|
| **路径** | `/proc/sys/fs/nr_open` |
| **含义** | 单个进程能打开的最大 FD 数（进程级硬限制，ulimit 硬限制不能超过此值） |
| **默认** | 1048576 |
| **注意** | 修改此参数需谨慎，过高可能导致 kernel memory 耗尽 |

---

## 二、inotify 相关参数

| 参数 | 路径 | 默认值 | 含义 |
|------|------|--------|------|
| max_user_watches | `/proc/sys/fs/inotify/max_user_watches` | 8192 | 单个用户可创建的最大 watch 数 |
| max_user_instances | `/proc/sys/fs/inotify/max_user_instances` | 128 | 单个用户可创建的最大 inotify 实例数 |
| max_queued_events | `/proc/sys/fs/inotify/max_queued_events` | 16384 | 队列最大事件数（超出则丢弃 IN_Q_OVERFLOW） |

**调优建议**：

```bash
# 文件监控密集场景（如 IDE、文件同步）
sysctl -w fs.inotify.max_user_watches=524288
sysctl -w fs.inotify.max_user_instances=512
sysctl -w fs.inotify.max_queued_events=32768
```

**注意**：`ENOSPC` 错误（No space left on device）在实际中常由 inotify watch 耗尽导致，而非真正的磁盘空间不足。

---

## 三、ulimit 相关

### 配置文件

| 配置文件 | 作用域 | 优先级 |
|----------|--------|--------|
| `/etc/security/limits.conf` | PAM 用户登录会话 | 高 |
| `/etc/security/limits.d/*.conf` | 单独配置覆盖 | 最高 |
| `/etc/systemd/system.conf` | systemd 系统服务默认 | systemd 服务 |
| `/etc/systemd/user.conf` | systemd 用户服务默认 | systemd 用户 |
| `/etc/systemd/system/<service>.service.d/override.conf` | 单个 service 覆盖 | systemd 服务 |

### PAM 配置示例

```
# /etc/security/limits.conf
*    soft    nofile    65536
*    hard    nofile    1048576
```

### systemd 服务配置

```ini
# /etc/systemd/system/<service>.service.d/limit.conf
[Service]
LimitNOFILE=65536
```

### 进程当前限制

```bash
cat /proc/<PID>/limits | grep "Max open files"
```

### 应用内调整

```c
// C/C++
#include <sys/resource.h>
struct rlimit rl;
rl.rlim_cur = 65536;  // soft
rl.rlim_max = 1048576; // hard
setrlimit(RLIMIT_NOFILE, &rl);
```

```python
# Python
import resource
resource.setrlimit(resource.RLIMIT_NOFILE, (65536, 1048576))
```

---

## 四、epoll 相关限制

epoll 本身没有独立的内核参数限制，受以下因素制约：

| 资源 | 限制方式 | 备注 |
|------|---------|------|
| 单个 epoll 最大监控 FD | `max_user_watches` 的概念不适用于 epoll | epoll 受 `max_fds` 和内存约束 |
| epoll 实例数量 | 受进程 `RLIMIT_NOFILE` 限制 | 每个 epoll FD 消耗一个 FD slot |
| epoll_wait 返回 | `maxevents` 参数限制每次返回的事件数 | 由应用调用 epoll_wait 时传入 |

**性能相关**：epoll 在监控大量 FD 时对内核内存的消耗约为 `sizeof(struct epitem)` ≈ 184 字节（x86_64）。

---

## 五、Socket 相关限制

### net.ipv4.tcp_mem

```bash
# 查看 TCP 内存限制
sysctl net.ipv4.tcp_mem
# 输出格式：min pressure max（单位：内存页）
# net.ipv4.tcp_mem = 123456  164608  246912
```

### net.core.somaxconn

```bash
# socket 监听队列最大长度
sysctl net.core.somaxconn
# 默认 128，高并发服务建议 1024~4096
```

### net.ipv4.tcp_max_tw_buckets

```bash
# TIME_WAIT 最大数量
sysctl net.ipv4.tcp_max_tw_buckets
# 超过此值的 TIME_WAIT 会被快速回收
```

### CLOSE_WAIT 相关

CLOSE_WAIT 没有独立的内核参数限制。它是 TCP 状态机中的一种状态，由应用层未调用 close() 导致。解决方法：

1. 应用层代码修复：确保收到 FIN 后调用 close()
2. 设置 socket 超时：`SO_RCVTIMEO` 和 `SO_SNDTIMEO`
3. 使用 `TCP_USER_TIMEOUT` 选项

---

## 六、参数调整综合建议

| 场景 | file-max | ulimit nofile | inotify.max_user_watches |
|------|----------|---------------|--------------------------|
| 通用服务器 | 100000 | 65536 | 8192（默认） |
| Web 服务器（高并发） | 500000 | 100000 | 8192 |
| 数据库服务器 | 1000000 | 1048576 | 8192 |
| 文件服务器 | 500000 | 65536 | 524288 |
| 文件同步/监控应用 | 500000 | 65536 | 524288 |
| IDE 开发机 | 100000 | 10240 | 524288 |

**调整原则**：
- 先确认当前水位：`file-nr`、`ulimit -a`、`inotify watch 使用量`
- 适量增大，不可过度分配（每个 FD 约 1KB slab 内存）
- 修改实时生效前评估对其他进程的影响
- 持久化修改必须经过 review 和测试
