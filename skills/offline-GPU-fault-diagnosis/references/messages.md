# openEuler `/var/log/messages` 深度分析指南

---

## 一、日志文件概述

`/var/log/messages` 是 openEuler（及类 CentOS 系统）最核心的系统日志，由 `rsyslog` 或 `journald` 写入，记录除 auth/mail 之外几乎所有系统级事件。

### 日志格式结构

```
Mar 10 14:23:01 hostname kernel: [12345.678901] OOM killer invoked...
│─────────────│ │──────│ │──────│ │───────────────────────────────│
  时间戳              主机名   进程/组件        消息正文
```

---

## 二、错误类型全景图

### 🔴 1. 内核类错误（Kernel）

| 错误关键字 | 含义 | 严重级别 |
|---|---|---|
| `kernel: BUG:` | 内核代码逻辑错误 | 严重 |
| `kernel panic` | 内核崩溃，系统停止 | 致命 |
| `Oops` | 内核轻量级崩溃（可恢复）| 严重 |
| `NULL pointer dereference` | 空指针解引用 | 严重 |
| `general protection fault` | 非法内存访问 | 严重 |
| `Call Trace:` | 内核调用栈（与Oops/panic伴随）| 参考信息 |
| `RCU stall` | RCU 锁等待超时 | 严重 |
| `soft lockup` | CPU 被某任务独占超时 | 严重 |
| `hard lockup` | 硬件级别 CPU 挂死 | 严重 |
| `hung_task` | 进程 D 状态挂起超时 | 中高 |

---

### 🟠 2. 内存类错误（OOM / Memory）

| 关键字 | 含义 |
|---|---|
| `Out of memory` | OOM，系统内存耗尽 |
| `oom_kill_process` | OOM Killer 杀死进程 |
| `Killed process` | 被 OOM Killer 杀死 |
| `Memory pressure` | 内存压力告警 |
| `swap space low` | 交换空间不足 |
| `page allocation failure` | 内存页分配失败 |
| `SLUB: Unable to allocate` | slab 分配失败 |

---

### 🟡 3. 存储 / IO 类错误

| 关键字 | 含义 |
|---|---|
| `I/O error` | 块设备 IO 错误 |
| `EXT4-fs error` | EXT4 文件系统错误 |
| `XFS: ... error` | XFS 文件系统错误 |
| `SCSI error` / `sd X: [sdX]` | SCSI/磁盘错误 |
| `ata X: SATA link down` | SATA 链路断开 |
| `Buffer I/O error on device` | 设备缓冲 IO 错误 |
| `blk_update_request: I/O error` | 块层 IO 错误 |
| `end_request: I/O error` | 请求 IO 错误 |
| `RAID: ...failed` | RAID 盘失效 |

---

### 🟢 4. 网络类错误

| 关键字 | 含义 |
|---|---|
| `NETDEV WATCHDOG` | 网卡发送队列超时 |
| `eth0: link is not ready` | 网卡链路未就绪 |
| `neighbour table overflow` | ARP 表溢出 |
| `TCP: out of memory` | TCP 内存耗尽 |
| `martian source` | 路由异常（源地址欺骗）|
| `nf_conntrack: table full` | 连接跟踪表满 |
| `bond0: link down` | Bonding 链路故障 |

---

### 🔵 5. 服务 / 应用类错误

| 关键字 | 含义 |
|---|---|
| `segfault` | 应用段错误（用户态崩溃）|
| `systemd: Failed` | systemd 服务启动失败 |
| `core dumped` | 程序产生 core 文件 |
| `Cannot allocate memory` | 应用层内存不足 |
| `Too many open files` | 文件描述符耗尽 |
| `Connection refused` | 连接被拒 |

---

### ⚫ 6. 硬件类错误

| 关键字 | 含义 |
|---|---|
| `MCE: HARDWARE ERROR` | 机器检查异常（硬件故障）|
| `EDAC` | 内存 ECC 错误 |
| `PCIe Bus Error` | PCIe 总线错误 |
| `Hardware Error` | 通用硬件错误 |
| `NMI: ...Dazed and confused` | 不可屏蔽中断异常 |

---

## 三、分析工具链

### 基础命令

```bash
# 实时跟踪日志
tail -f /var/log/messages

# 查看最近 200 行
tail -200 /var/log/messages

# 按时间范围查询
sed -n '/Mar 10 10:00/,/Mar 10 11:00/p' /var/log/messages

# 统计各类错误出现次数
grep -iE "error|fail|warn|panic|oops" /var/log/messages | \
  awk '{print $5}' | sort | uniq -c | sort -rn | head -20
```

### 高级过滤命令

```bash
# 只看 error 及以上级别（journald 同步查询）
journalctl -p err --since "1 hour ago"

# 查看内核消息
journalctl -k --since today

# 查看某个服务的日志
journalctl -u nginx.service --since "2025-03-10"

# 过滤 OOM 事件
grep -E "Out of memory|oom_kill|Killed process" /var/log/messages

# 过滤 IO 错误
grep -iE "I/O error|blk_update_request|buffer.*error" /var/log/messages

# 过滤内核 panic / oops
grep -E "kernel panic|Oops|BUG:|Call Trace" /var/log/messages
```

---

## 四、标准分析流程（SOP）

```
┌─────────────────────────────────────────────────────────────┐
│                    STEP 1: 宏观扫描                          │
│  grep -ciE "error|fail|panic|oops" /var/log/messages        │
│  了解错误总量和时间分布                                       │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                    STEP 2: 时间线定位                         │
│  确定问题发生的时间窗口，缩小分析范围                          │
│  grep "Mar 10" /var/log/messages | grep -i error            │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                    STEP 3: 错误分类                           │
│  按 kernel/memory/io/network 分别统计，找最高频错误           │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                    STEP 4: 根因分析                           │
│  针对主要错误类型，深入关联上下文 (前后±50行)                  │
│  grep -A50 -B10 "keyword" /var/log/messages                 │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                    STEP 5: 交叉验证                           │
│  结合 dmesg / journalctl / 应用日志 多源印证                  │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                    STEP 6: 输出报告                           │
│  记录：发现时间 / 错误类型 / 根因 / 影响范围 / 处置建议        │
└─────────────────────────────────────────────────────────────┘
```

---

## 五、典型场景分析示例

### 场景 A：OOM 问题排查

```bash
# 1. 确认 OOM 发生
grep -n "Out of memory" /var/log/messages

# 输出示例：
# Mar 10 03:21:44 euler01 kernel: Out of memory: Kill process 12345 (java) 
#   score 982 or sacrifice child

# 2. 查看 OOM 前后完整上下文
grep -n "Out of memory" /var/log/messages | head -5
# 取行号，如 2341
sed -n '2300,2400p' /var/log/messages

# 3. 分析 OOM 时内存状态
grep -A30 "Out of memory" /var/log/messages | head -60
# 关注: free:XXXkB / active:XXkB / inactive:XXkB

# 4. 统计哪些进程反复被杀
grep "Killed process" /var/log/messages | \
  awk '{print $NF}' | sort | uniq -c | sort -rn

# 5. 查看 OOM score 分布（谁最危险）
grep "oom_score_adj" /var/log/messages | tail -20
```

---

### 场景 B：磁盘 IO 错误排查

```bash
# 1. 找出问题磁盘
grep -iE "I/O error|blk_update_request" /var/log/messages | \
  grep -oP "sd[a-z]+[0-9]?" | sort | uniq -c

# 2. 查看错误详情（包含 sector 信息）
grep "I/O error" /var/log/messages | tail -20
# 示例：
# Buffer I/O error on dev sdb1, logical block 1234567, async page read

# 3. 检查是否有文件系统报错
grep -E "EXT4-fs error|XFS.*error" /var/log/messages

# 4. 关联 SMART 信息（实时）
smartctl -a /dev/sdb
```

---

### 场景 C：内核 Oops / soft lockup

```bash
# 1. 提取完整 Oops 块
grep -n "Oops\|soft lockup\|BUG:" /var/log/messages

# 2. 获取 Call Trace（调用栈）
awk '/Oops/,/---\[ end trace\]---/' /var/log/messages | head -80

# 3. 分析挂死进程
grep "soft lockup.*CPU" /var/log/messages | \
  grep -oP "CPU#[0-9]+" | sort | uniq -c

# 4. 查看是否 watchdog 触发
grep "watchdog" /var/log/messages | tail -20
```

---

### 场景 D：服务启动失败

```bash
# 1. 找失败服务
grep -i "failed\|error" /var/log/messages | grep systemd

# 2. 结合 journalctl 获取详情
journalctl -u <service-name> --since "today" --no-pager

# 3. 查看 segfault（应用崩溃）
grep "segfault" /var/log/messages
# 示例：
# mysqld[1234]: segfault at 7f... ip 00007f... sp 00007f... error 4 in libc.so
```

---

## 六、快速诊断速查表

```bash
# ============================================================
# 一键健康检查脚本
# ============================================================

echo "=== 错误统计概览 ==="
grep -cE "error" /var/log/messages
grep -cE "warning" /var/log/messages
grep -cE "panic|Oops|BUG:" /var/log/messages

echo "=== OOM 事件 ==="
grep -c "Out of memory" /var/log/messages

echo "=== IO 错误 ==="
grep -c "I/O error" /var/log/messages

echo "=== 网络异常 ==="
grep -cE "NETDEV WATCHDOG|link down|table overflow" /var/log/messages

echo "=== 最近10条 error ==="
grep -i "error" /var/log/messages | tail -10

echo "=== 最近 kernel 警告 ==="
grep "kernel:" /var/log/messages | grep -iE "warn|error|fail" | tail -10
```

---

## 七、日志轮转与归档管理

```bash
# 查看轮转配置
cat /etc/logrotate.d/syslog

# 查看历史日志（已压缩）
ls /var/log/messages*
zcat /var/log/messages-20250301.gz | grep "error"

# 增加日志保留天数（修改 /etc/logrotate.d/syslog）
# rotate 30  ← 保留30个轮转文件

# 手动触发轮转
logrotate -f /etc/logrotate.conf
```

---

## 八、常见错误处置建议速查

| 错误类型 | 快速处置 |
|---|---|
| OOM | 检查内存占用 `free -h`，分析 `top`，考虑调整 OOM 策略或扩容 |
| IO Error | 执行 `smartctl -a /dev/sdX` 检查磁盘健康，必要时换盘 |
| soft lockup | 检查 CPU 是否过载 `vmstat 1 10`，排查高负载进程 |
| kernel panic | 分析 vmcore 文件，参考 crash 工具分析流程 |
| nf_conntrack full | `sysctl -w net.netfilter.nf_conntrack_max=131072` 临时调大 |
| EXT4-fs error | 重启进入单用户模式执行 `fsck /dev/sdXY` |
| segfault | 检查 core dump，用 `gdb` 分析；检查内存 `valgrind` |
| MCE Hardware Error | 立即检查硬件，内存/CPU 可能故障，联系硬件厂商 |

---

分析 `/var/log/messages` 的核心原则：**不要孤立地看单条错误，要看时间序列和上下文关联**。一个真实故障往往是多条错误的组合，找到最早出现的异常日志，往往就是根因所在。