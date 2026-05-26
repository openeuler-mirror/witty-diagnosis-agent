# mmap/VMA 故障场景专项分析指南

## 概述

本指南提供了六种 mmap/VMA 故障场景的专项分析流程。在信息收集阶段确定故障场景后，应根据对应的场景执行专项分析。

---

## 1. vm.max_map_count 耗尽分析 (MMAP_MAPCOUNT_EXHAUST)

### 1.1 核心日志文件

- `/proc/<PID>/maps` - 进程当前 VMA 列表（行数 = VMA 数量）
- `/proc/sys/vm/max_map_count` - 系统 VMA 上限
- `/var/log/messages` / `dmesg` - 内核 mmap 失败记录
- `/proc/<PID>/smaps` - 每段 VMA 的详细内存占用

### 1.2 关键错误模式

| 错误来源 | 错误关键字 | 含义 |
| :--- | :--- | :--- |
| **应用日志** | `mmap failed: Cannot allocate memory` / `java.io.IOException: mmap of ... bytes failed` | 应用层 mmap 返回 ENOMEM |
| **内核日志** | `mmap: <process> maps too large` | 内核检测到进程 VMA 数量超限 |
| **ES 日志** | `max file descriptors [4096] ... likely too low` | ES 启动警告（与 mmap 关联） |
| **strace** | `mmap(NULL, ...) = -1 ENOMEM (Cannot allocate memory)` | 系统调用级别确认 |

### 1.3 分析命令

```bash
# 查看当前 max_map_count 配置
cat /proc/sys/vm/max_map_count

# 查看目标进程 VMA 数量
cat /proc/<PID>/maps | wc -l

# 统计各类映射数量
cat /proc/<PID>/maps | awk '{print $5}' | sort | uniq -c | sort -rn

# 统计文件映射前 10 名
cat /proc/<PID>/maps | awk '{if ($NF != "") print $NF}' | sort | uniq -c | sort -rn | head -10

# 查看 VMA 类型分布
cat /proc/<PID>/maps | awk '{
    if ($7 ~ /^\[heap\]/) type="heap"
    else if ($7 ~ /^\[stack\]/) type="stack"
    else if ($7 ~ /^\[vdso\]\|^\[vsyscall\]\|^\[vvar\]/) type="vvar"
    else if ($7 ~ /^\[) type="anon"
    else if ($NF != "") type="file:"$NF
    else type="anon"
    print type
}' | sort | uniq -c | sort -rn

# 查看特定 fd 的 mmap（对 Java NIO 排错有用）
lsof -p <PID> | grep -i "mem\|mmap\|REG"
```

### 1.4 根因推理框架

- **泄漏路径**：`VMA 数量持续增长` -> `接近 max_map_count 上限` -> 可能存在 fd/mmap 泄漏（MappedByteBuffer 未关闭 / dlmopen 频繁加载库）
- **容量路径**：`VMA 数量较大但稳定` -> `达到业务正常水位` -> `max_map_count 默认值偏小` -> 需要增大系统限制
- **ES 专有路径**：`索引数量增长` -> `每个索引分片打开多个 mmap` -> `总 VMA 超出上限` -> 增大 max_map_count + 减少分片数

---

## 2. SIGBUS 文件截断分析 (MMAP_SIGBUS_TRUNCATE)

### 2.1 核心日志文件

- `core dump` - 进程崩溃快照（signal 7, SIGBUS）
- `/var/log/messages` - 内核 SIGBUS 记录
- 应用日志 - 崩溃前的操作记录

### 2.2 关键错误模式

| 错误来源 | 错误关键字 | 含义 |
| :--- | :--- | :--- |
| **core dump** | `signal 7` / `SIGBUS` | 进程被 SIGBUS 杀死 |
| **dmesg** | `bus error` / `segfault at ... ip ... sp ... error 6` | 内核总线错误（error code 6 = 写操作 + 用户态） |
| **应用日志** | `Bus error (core dumped)` | 进程 panic 日志 |
| **gdb 分析** | `Program received signal SIGBUS, Bus error` | 调试器确认 |

### 2.3 分析命令

```bash
# 查看崩溃时的 core dump 信息
coredumpctl info 2>/dev/null | head -20

# 分析 core dump（如文件存在）
gdb <binary> <core> -batch -ex "bt" -ex "info registers" -ex "quit"

# 在 gdb 中查看崩溃指令附近的映射
gdb <binary> <core> -batch -ex "info proc mappings" | grep -i "<crash_addr_range>"

# 检查文件状态
ls -la /path/to/suspected/file
stat /path/to/suspected/file

# 检查何时被截断（使用 inotifywait 需要提前部署，否则看审计日志）
auditctl -w /path/to/suspected/file -p wa -k file_truncate 2>/dev/null
ausearch -k file_truncate --start <start_time> --end <end_time>
```

### 2.4 根因推理框架

- **日志轮转路径**：`logrotate 配置` -> `copytruncate/create` 模式截断日志 -> `应用 mmap 了日志文件` -> `访问已截断区域触发 SIGBUS`
- **并发清理路径**：`进程 A mmap 文件 F` -> `进程 B truncate(F)` -> `进程 A 继续访问` -> SIGBUS
- **自截断路径**：`进程自身执行 ftruncate` -> `缩小文件到映射范围以下` -> `后续写入缩小部分` -> SIGBUS

---

## 3. mlock 超限分析 (MLOCK_LIMIT_EXCEEDED)

### 3.1 核心日志文件

- `/proc/<PID>/limits` - 进程资源限制
- `/proc/<PID>/status` - 当前锁定内存（VmLck）
- `/var/log/messages` / `dmesg` - mlock 失败记录
- 应用日志 - 启动时 mlock 失败信息

### 3.2 关键错误模式

| 错误来源 | 错误关键字 | 含义 |
| :--- | :--- | :--- |
| **应用日志** | `failed to lock memory` / `Cannot allocate memory` | mlock 返回 ENOMEM |
| **ES 日志** | `memory locking requested but [MEMLOCK] is too low` | ES bootstrap checks 失败 |
| **内核日志** | `mlock: <process> mlocked pages exceed limit` | 内核检测到 mlock 超限 |
| **strace** | `mlockall(MCL_CURRENT) = -1 ENOMEM` | 系统调用级别确认 |

### 3.3 分析命令

```bash
# 查看锁定限制
ulimit -l
ulimit -H -l

# 查看进程限制
cat /proc/<PID>/limits | grep "max locked memory"

# 查看已锁定内存
cat /proc/<PID>/status | grep VmLck

# 查看全局锁定内存
grep -E "Unevictable|Mlocked" /proc/meminfo

# 查看 systemd 服务限制（对于 systemd 管理的服务）
systemctl show <service> --property=LimitMEMLOCK

# 查看 session 级别的 memlock（pam_limits 生效情况）
cat /etc/security/limits.conf | grep -v "^#\|^$"
cat /etc/security/limits.d/*.conf | grep memlock
```

### 3.4 根因推理框架

- **默认不足路径**：`RLIMIT_MEMLOCK 默认 64KB` -> `应用需要锁定更多内存` -> `mlock 返回 ENOMEM`
- **服务配置路径**：`systemd service 未设置 LimitMEMLOCK` -> `继承默认限制` -> `mlock 失败`
- **容器路径**：`容器内 ulimit -l 继承宿主机限制` -> `容器资源隔离不足` -> `mlock 失败`
- **内存增长路径**：`启动时锁定成功` -> `运行中更多内存被锁定（MCL_FUTURE）` -> `超过限制`

---

## 4. 共享内存映射权限分析 (SHM_PERMISSION_DENIED)

### 4.1 核心日志文件

- `ipcs -m` 输出 - 共享内存段列表
- `/proc/sys/kernel/shm*` - 内核共享内存参数
- `/var/log/messages` - 共享内存相关错误
- 应用日志 - 共享内存创建/附加失败

### 4.2 关键错误模式

| 错误来源 | 错误关键字 | 含义 |
| :--- | :--- | :--- |
| **strace** | `shmget(...) = -1 EACCES` | 共享内存段已存在但权限不足 |
| **strace** | `shmat(...) = -1 EACCES` | 无法附加到共享内存段 |
| **容器日志** | `shmget failed: Permission denied` | 容器内共享内存创建失败 |
| **内核日志** | `shm: shmget with key ... denied` | 内核拒绝 shmget 请求 |

### 4.3 分析命令

```bash
# 查看共享内存限制
sysctl kernel.shmall
sysctl kernel.shmmax
sysctl kernel.shmmni

# 查看共享内存使用
ipcs -u

# 列出所有共享内存段
ipcs -m -a

# 查看特定共享内存段
ipcs -m -i <shmid>

# 查看进程的 IPC 能力
getpcaps <PID> 2>/dev/null || capsh --print 2>/dev/null

# 查看 SELinux 上下文
ls -Z /dev/shm/

# 查看容器 shm 大小
df -h /dev/shm
mount | grep shm
```

### 4.4 根因推理框架

- **权限路径**：`shmget IPC_CREAT|IPC_EXCL` -> `已存在` -> `EACCES` -> `检查 shm_perm.mode`
- **容器路径**：`容器 /dev/shm 太小` -> `shmget 超过限制` -> `ENOMEM/ENOSPC`
- **capability 路径**：`进程缺少 CAP_IPC_OWNER` -> `shmat 其他用户 shm 段` -> `EACCES`
- **cgroup 路径**：`cgroup memory.max 对 shmem 有限制` -> `共享内存超过 cgroup 限制` -> `OOM 或 ENOMEM`

---

## 5. 地址空间碎片化分析 (VMA_FRAGMENTATION)

### 5.1 核心日志文件

- `/proc/<PID>/maps` - 进程 VMA 布局
- `/proc/meminfo` - 系统内存信息
- `/proc/buddyinfo` - 物理页分配情况
- `/proc/pagetypeinfo` - 页面类型分布

### 5.2 关键错误模式

| 错误来源 | 错误关键字 | 含义 |
| :--- | :--- | :--- |
| **应用日志** | `mmap failed for huge page` | 大页映射失败 |
| **mmap 返回** | `mmap(... ENOMEM)` with large size | 大块连续映射失败 |
| **内核日志** | `page allocation failure: order:X` | 高阶页面分配失败 |

### 5.3 分析命令

```bash
# 分析 VMA 分布（寻找地址空间空洞）
python3 /dev/stdin << 'EOF'
import re
with open('/proc/<PID>/maps') as f:
    regions = []
    for line in f:
        m = re.match(r'([0-9a-f]+)-([0-9a-f]+)', line)
        if m:
            start, end = int(m.group(1), 16), int(m.group(2), 16)
            regions.append((start, end))
regions.sort()
gaps = []
for i in range(len(regions)-1):
    gap = regions[i+1][0] - regions[i][1]
    if gap > 0:
        gaps.append((gap, regions[i][1], regions[i+1][0]))
        print(f"  Gap: {gap/1024/1024:.1f}MB  [{hex(regions[i][1])} -> {hex(regions[i+1][0])}]")
EOF

# 查看物理内存碎片
cat /proc/buddyinfo

# 查看 hugepage 状态
grep -E "HugePages_Total|HugePages_Free|Hugepagesize" /proc/meminfo

# 查看 ASLR 设置
cat /proc/sys/kernel/randomize_va_space

# 查看 /proc/sys/vm/mmap_legacy 地址布局
cat /proc/sys/vm/legacy_va_layout 2>/dev/null || echo "N/A"
```

### 5.4 根因推理框架

- **dlopen 路径**：`频繁 dlopen/dlclose` -> `共享库映射碎片化` -> `地址空间空洞增多` -> `大块 mmap 失败`
- **mmap 泄漏路径**：`mmap 不 munmap` -> `VMA 持续增长` -> `地址空间被小映射占满` -> `大块分配无连续空间`
- **thread 栈路径**：`大量线程创建` -> `每个线程独占栈 VMA` -> `线程栈交错分布` -> `地址空间碎片化`
- **ASLR 路径**：`ASLR 完全随机化` -> `映射分布散乱` -> `高碎片化` -> `大块分配困难`

---

## 6. 通用 mmap 失败分析 (MMAP_GENERIC_FAILURE)

当无法归入以上 5 类场景时，按 errno 对应关系逐一排查：

| errno | 适用场景 | 排查命令 |
|-------|---------|---------|
| EACCES (13) | 权限不足 | `ls -l /path/to/file`；`ls -Z /path/to/file`（SELinux） |
| EAGAIN (11) | 文件被 seal | `grep -i memfd /proc/<PID>/fd/*` |
| EINVAL (22) | 参数错误 | 检查 length/offset/flags/fd 组合是否有效 |
| ENFILE (23) | 系统 fd 满 | `cat /proc/sys/fs/file-max`；`cat /proc/sys/fs/file-nr` |
| ENODEV (19) | 文件系统不支持 | `df -T /path`（检查 fs type）|
| EPERM (1) | seccomp/SELinux | `cat /proc/<PID>/status \| grep Seccomp` |
| EOVERFLOW (75) | 32位溢出 | `file` 确认二进制架构；`getconf LONG_BIT` |
