---
name: kernel-fuse-diagnosis
description: >
  FUSE（用户态文件系统）内核端故障诊断技能。当用户提到 FUSE 文件系统 hang、
  所有操作返回 EIO、FUSE daemon 崩溃/重启、请求队列阻塞、D 状态进程堆积、
  /sys/fs/fuse/connections/ 异常、libfuse 兼容性、max_read/max_write 配置不当、
  writeback cache 一致性问题、多线程 FUSE daemon 死锁、容器中 /dev/fuse 权限问题、
  FUSE 性能退化等关键词时，必须使用本技能。
  覆盖场景：FUSE daemon 崩溃后 EIO、请求队列阻塞与 D 状态、max_read/max_write 配置不当、
  writeback cache 一致性问题、多线程 daemon 死锁、/dev/fuse 权限问题、内核 FUSE 模块 Bug、
  混合复杂 FUSE 故障。即使只收到"文件系统挂了"、"目录打不开"、"ls 卡死"但挂载点
  为 FUSE 类型时也应触发本技能。
  支持 FUSE 全链路诊断（sysfs 队列 → 内核参数 → daemon 进程 → 代码级根因）。
---

# FUSE 内核端故障诊断（三层下钻：系统层 → 类型层 → 代码根因层）

## 第一节：故障目录结构

```text
fuse_case/                  # 故障案例目录
├── scripts/                # 【内置】本技能的诊断脚本
│   ├── 01_baseline_info.sh
│   ├── branch_A_daemon_crash.sh
│   ├── branch_B_req_queue.sh
│   ├── branch_C_max_read_write.sh
│   ├── branch_D_writeback_cache.sh
│   ├── branch_E_mt_deadlock.sh
│   ├── branch_F_dev_fuse_perm.sh
│   ├── branch_G_kernel_bug.sh
│   └── branch_H_mixed.sh
├── logs/                   # 【可选】应用日志
│   ├── application.log
│   └── dmesg_output.txt
├── fuse_state/             # 【可选】故障时刻的 FUSE 状态快照
│   ├── connections.txt     # ls /sys/fs/fuse/connections/
│   ├── waiting.txt         # cat .../waiting
│   └── abort.txt           # cat .../abort
└── report/                 # 【输出】诊断报告目录
```

```bash
# 检查 FUSE 文件系统挂载状态基线
mount -t fuse
```

---

## 第二节：分析策略（三层下钻，逐层收敛）

FUSE 内核端故障诊断采用**三层下钻模型**，从最外层逐层深入，层间存在依赖关系：

```
┌─────────────────────────────────────────────────────────────────┐
│                   三层下钻分析模型                                 │
│                                                                 │
│   L1: 系统层         mount -t fuse /proc/mounts                 │
│       │               /sys/fs/fuse/connections/*                │
│       └─ 判断：FUSE 挂载点是否正常？连接是否存在？               │
│                                                                 │
│   L2: 类型层         strace -p <daemon_pid>                     │
│       │               cat /sys/fs/fuse/connections/*/waiting     │
│       └─ 判断：是 EIO？请求阻塞？性能退化？权限问题？            │
│                                                                 │
│   L3: 代码/内核层    FUSE daemon 源码分析                       │
│                      内核 FUSE 模块参数 (/sys/module/fuse/)     │
│                      /dev/fuse 设备状态                          │
│                      └─ 根因定位：daemon 崩溃 / 队列阻塞 / 配置  │
│                                                                 │
│   每层输出：证据 + 结论。L3 输出最终根因。                       │
└─────────────────────────────────────────────────────────────────┘
```

### 故障分类树

```
L1 ─ FUSE 挂载点与连接检查
│
├─ L2 ─ 挂载点正常？─────── 否 ──→ 非 FUSE 问题，转其他技能
│                         是
│                         ↓
├─ L2 ─ 操作返回 EIO？──── 是 ──→ Branch A (Daemon Crash)
│                         否
│                         ↓
├─ L2 ─ 进程 D 状态/Hang？ 是 ──→ Branch B (Req Queue) / Branch E (MT Deadlock)
│                         否
│                         ↓
├─ L2 ─ 性能退化？─────── 是 ──→ Branch C (Max Read/Write)
│                         否
│                         ↓
├─ L2 ─ 数据一致性异常？─ 是 ──→ Branch D (Writeback Cache)
│                         否
│                         ↓
├─ L2 ─ 权限问题？─────── 是 ──→ Branch F (dev/fuse Perm)
│                         否
│                         ↓
├─ L2 ─ 内核崩溃/Oops？── 是 ──→ Branch G (Kernel Bug)
│                         否
│                         ↓
└─ L2 ─ 混合/复杂现象？── 是 ──→ Branch H (Mixed)
```

---

## 第三节：诊断流程

### L1: 系统层 — 基线采集与挂载点检查

检查系统 FUSE 基础配置与挂载状态，判断是否为系统级配置问题。

```bash
# 1. 检查 FUSE 挂载点
mount -t fuse

# 2. 检查 /proc/mounts 中 FUSE 条目
grep fuse /proc/mounts

# 3. 检查 FUSE 内核连接状态
ls /sys/fs/fuse/connections/ 2>/dev/null

# 4. 检查 FUSE daemon 进程
ps aux | grep -E "[f]use|[F]ILESYSTEM_NAME"

# 5. 基本连通性测试
ls -la <FUSE_mount_point>
stat <FUSE_mount_point>/test_file 2>&1
```

**L1 结论判定**：

| 现象 | 可能原因 | 下一层 |
|------|---------|--------|
| 挂载点 ls 返回 EIO | FUSE daemon 崩溃 | Branch A |
| ls 卡死/D 状态 | 请求队列阻塞 | Branch B |
| 性能异常慢 | max_read/max_write 配置不当 | Branch C |
| 数据不一致 | writeback cache 问题 | Branch D |
| daemon 进程存在但无响应 | 多线程死锁 | Branch E |
| 权限 denied | /dev/fuse 权限 | Branch F |
| 内核 Panic/Oops | FUSE 内核模块 Bug | Branch G |
| 多种现象共存 | 混合故障 | Branch H |

### L2 → L3: 类型层与代码根因层

#### Branch A — FUSE Daemon 崩溃后 EIO

**触发条件**：L1 中访问 FUSE 挂载点返回 "Transport endpoint is not connected" 或 EIO。

```
L2 诊断：
├── 1. stat <mount_point>（确认 EIO 错误码）
├── 2. grep <mount_point> /proc/mounts（挂载条目是否仍存在）
├── 3. ls /sys/fs/fuse/connections/（连接是否已销毁）
├── 4. ps aux | grep <daemon_name>（daemon 进程是否存在）
├── 5. journalctl -u <daemon_service> --since "5 min ago"（daemon 退出日志）
├── 6. dmesg | grep -i fuse（内核 FUSE 消息）
├── 7. cat /sys/fs/fuse/connections/*/abort 2>/dev/null（abort 状态）
│
└── L3 根因判定：
    ├── daemon 进程不存在 + 连接已销毁 → daemon 崩溃/被 OOM Kill
    ├── daemon 进程不存在 + 连接残留 → daemon 退出但连接未清理
    ├── daemon 存在但连接状态异常 → daemon 内部状态机错误
    ├── dmesg 显示 "fuse: aborting connection" → 内核主动中止
    ├── OOM Killer 日志 → daemon 因内存超限被内核杀死
    └── 连接 abort 状态为 1 → 手动触发 abort 或 daemon 调用 abort
```

**典型输出**：
```
结论: FUSE daemon 进程不存在（已崩溃），
      /sys/fs/fuse/connections/ 目录为空（连接已销毁）。
      dmesg 无 FUSE 相关错误，但 journalctl 显示 daemon 因
      SIGSEGV (signal 11) 退出。
根因: FUSE daemon 程序存在内存访问越界 Bug，导致段错误崩溃。
```

#### Branch B — FUSE 请求队列阻塞

**触发条件**：LS 卡死、进程 D 状态（uninterruptible sleep）、`/sys/fs/fuse/connections/*/waiting` 持续增长。

```
L2 诊断：
├── 1. cat /sys/fs/fuse/connections/*/waiting（请求队列深度）
├── 2. cat /sys/fs/fuse/connections/*/max_background（最大后台请求数）
├── 3. ps aux | grep D | grep -v grep（D 状态进程列表）
├── 4. cat /proc/<D_pid>/stack（查看 D 状态内核栈）
├── 5. strace -e trace=write,read,ioctl -p <daemon_pid>（daemon 系统调用）
├── 6. cat /sys/fs/fuse/connections/*/congested_threshold_ms（拥塞阈值）
├── 7. dmesg | grep -i "fuse.*block"（阻塞告警）
│
└── L3 根因判定：
    ├── waiting 持续增长 + daemon 未处理请求 → daemon 侧线程阻塞
    ├── daemon 进程 strace 显示 read() 未被唤醒 → 内核/FUSE 调度问题
    ├── D 状态进程内核栈显示 fuse_request_send → 请求队列已满等待
    ├── max_background 设置过小 → 请求队列排队上限低导致积压
    ├── daemon write() 变慢或阻塞 → daemon 后端存储 I/O 瓶颈
    └── congested_threshold 触发 → FUSE 内核主动限流
```

**典型输出**：
```
结论: /sys/fs/fuse/connections/*/waiting 持续增长（当前值: 512），
      进程 D 状态栈显示 fuse_request_send。
      strace 显示 daemon read() 调用未被及时唤醒。
根因: FUSE daemon 工作线程池太小或线程卡在后端 I/O 上，
      无法及时消费内核下发的 FUSE 请求。
```

#### Branch C — max_read/max_write 配置不当

**触发条件**：FUSE 文件系统性能显著低于预期，小文件/大文件读写性能异常。

```
L2 诊断：
├── 1. cat /sys/fs/fuse/connections/*/max_read（当前 FUSE 最大读取大小）
├── 2. cat /sys/module/fuse/parameters/max_read（内核模块参数）
├── 3. mount | grep <fuse_type>（挂载参数 -o max_read=,max_write=）
├── 4. dd if=<mount_point>/test of=/dev/null bs=1M count=100（读性能测试）
├── 5. dd if=/dev/zero of=<mount_point>/test bs=1M count=100（写性能测试）
├── 6. iostat -x 1 <device>（底层 I/O 延迟）
├── 7. strace -e pread64,pwrite64 -p <daemon_pid>（系统调用大小对比）
│
└── L3 根因判定：
    ├── max_read=4096（4K）→ 每次读请求仅传输 4K，大文件读性能极差
    ├── max_write=4096（4K）→ 每次写请求仅传输 4K，写性能瓶颈
    ├── max_read 与底层存储块大小不匹配 → 产生大量小 I/O
    ├── 挂载时未指定 max_read= → 使用默认值（通常 1MB，但某些 FUSE 缩减）
    ├── daemon 未实现 readdir 缓存 → 目录遍历性能退化
    └── 内核 max_read 参数被 sysfs 限制 → 无法超过内核模块设置的上限
```

**典型输出**：
```
结论: max_read=4096（4K），远低于默认 1MB。
      dd 读测试仅 12 MB/s，远低于预期 200+ MB/s。
      strace 确认每次 pread64 仅传输 4096 字节。
根因: FUSE 挂载时未指定 max_read，daemon 初始化协商值为 4K
      （libfuse 旧版本默认），导致大文件顺序读性能退化。
```

#### Branch D — Writeback Cache 一致性问题

**触发条件**：FUSE 文件系统写入后读取数据不一致、写入顺序错误、重复内容。

```
L2 诊断：
├── 1. mount | grep <fuse_type> | grep -o "writeback_cache"（检查是否启用）
├── 2. cat /sys/module/fuse/parameters/use_writeback_cache（内核参数）
├── 3. echo "test" > <mount_point>/file && cat <mount_point>/file（一致性测试）
├── 4. strace -e write,pwrite64,fsync -p <daemon_pid>（跟踪写操作时序）
├── 5. dd if=/dev/urandom of=<mount_point>/test bs=4K count=100（并发写入）
├── 6. md5sum <mount_point>/test && sleep 1 && md5sum <mount_point>/test（变化检测）
├── 7. grep -i "fuse.*invalidate" /proc/<daemon_pid>/stack（缓存无效化状态）
│
└── L3 根因判定：
    ├── writeback_cache 启用但 daemon 未实现 ->release 回调 → 数据未刷入后端
    ├── 并发写入后的读取返回过期数据 → page cache 未正确无效化
    ├── daemon write() 返回成功但数据未持久化 → 缺少 fsync 语义
    ├── 内核 fuse_conn 中 writeback_cache=1 但后端不支持原子写
    ├── mmap 写入后数据丢失 → FUSE 不支持 shared mmap writeback cache
    └── multi-page writeback 顺序错误 → daemon 未按 LBA 顺序处理请求
```

**典型输出**：
```
结论: writeback_cache 启用后，写入 100 个 4K 块后的 md5sum
      在不同读取时间点返回不同值。
      daemon 未实现 ->write() 回调的完整 writeback 语义。
根因: FUSE daemon 启用 writeback_cache 模式但未正确处理
      内核的 writeback 请求，page cache 与后端存储数据不一致。
```

#### Branch E — 多线程 FUSE Daemon 死锁

**触发条件**：FUSE daemon 进程存在但操作挂起，挂载点操作无响应。

```
L2 诊断：
├── 1. ps -eLf | grep <daemon_name>（daemon 线程列表）
├── 2. cat /proc/<daemon_pid>/stack（主线程内核栈）
├── 3. for tid in $(ls /proc/<daemon_pid>/task/); do echo "TID:$tid"; cat /proc/$tid/stack 2>/dev/null; done
├── 4. strace -f -e trace=write,read,ioctl -p <daemon_pid>（多线程追踪）
├── 5. gdb -p <daemon_pid> -batch -ex "thread apply all bt"（全线程回溯）
├── 6. cat /sys/fs/fuse/connections/*/waiting（确认请求堆积）
├── 7. kill -USR1 <daemon_pid>（向 daemon 发送信号检查状态）
│
└── L3 根因判定：
    ├── 所有工作线程在 pthread_mutex_lock 等待 → 互斥锁死锁
    ├── 线程 A 持有锁 L1 等待锁 L2，线程 B 持有锁 L2 等待锁 L1 → 经典死锁
    ├── 工作线程在 write() 后端存储时阻塞 → I/O 死锁（等待自身填充）
    ├── 线程池所有线程都在 fuse_session_process 中 → 请求循环依赖
    ├── 主线程在 fuse_loop 中阻塞但工作线程已退出 → 线程管理 Bug
    └── daemon 中 fuse_reply_* 调用顺序错误 → 协议级死锁
```

**典型输出**：
```
结论: daemon 4 个工作线程全部在 pthread_mutex_lock 等待。
      gdb 显示 Thread 1 持有 lock A 等待 lock B，
      Thread 2 持有 lock B 等待 lock A——经典 ABBA 死锁。
根因: FUSE daemon 中锁获取顺序不一致，导致多线程死锁，
      文件系统操作完全挂起。
```

#### Branch F — /dev/fuse 设备权限问题

**触发条件**：容器或非 root 用户启动 FUSE daemon 时出现 Permission denied。

```
L2 诊断：
├── 1. ls -la /dev/fuse（设备节点权限）
├── 2. getfacl /dev/fuse（ACL 权限检查）
├── 3. cat /proc/<daemon_pid>/status | grep Cap（daemon 能力集）
├── 4. grep fuse /etc/group（fuse 用户组）
├── 5. groups <daemon_user>（用户所属组）
├── 6. cat /etc/fuse.conf（FUSE 全局配置）
├── 7. capsh --print | grep fuse（进程能力检查）
├── 8. container environment: cat /proc/1/cgroup（容器内 cgroup 检查）
│
└── L3 根因判定：
    ├── /dev/fuse 权限 0600 root:root → 非 root 用户无法访问
    ├── daemon 用户不在 fuse 组 → 缺少 /dev/fuse 访问权限
    ├── 容器内未挂载 /dev/fuse → 设备节点不存在
    ├── 容器缺少 CAP_SYS_ADMIN 或 CAP_MKNOD → 无法操作 FUSE 设备
    ├── user_allow_other 未在 /etc/fuse.conf 启用 → 无法使用 allow_other
    ├── AppArmor/SELinux 阻止 FUSE 操作 → 安全策略限制
    └── daemon 进程 capabilities 被移除 → container runtime 降权
```

**典型输出**：
```
结论: /dev/fuse 权限 0600 root:root，daemon 以非 root 用户
      运行且不在 fuse 用户组中。
      daemon 启动日志显示 "Permission denied" 打开 /dev/fuse。
根因: /dev/fuse 设备节点仅 root 可读写，FUSE daemon
      以普通用户运行且未加入 fuse 组，无法打开设备。
```

#### Branch G — FUSE 内核模块 Bug

**触发条件**：内核 Panic、Oops、soft lockup 与 FUSE 相关，或已知 FUSE 内核 Bug。

```
L2 诊断：
├── 1. dmesg | grep -iE "fuse|libfuse"（内核 FUSE 消息）
├── 2. dmesg | grep -iE "kernel panic|Oops|BUG|soft lockup"（内核异常）
├── 3. cat /sys/module/fuse/version（FUSE 模块版本）
├── 4. uname -r（内核版本）
├── 5. cat /proc/self/mounts | grep fuse（所有 FUSE 挂载）
├── 6. cat /sys/fs/fuse/connections/*/abort（abort 状态）
├── 7. test -f /var/crash/vmcore* 2>/dev/null && ls -lh /var/crash/（crash dump 检查）
├── 8. grep -i fuse /var/log/messages | tail -20（系统日志）
│
└── L3 根因判定：
    ├── 已知 FUSE 内核 Bug 列表匹配（CVE-xxxx-xxxx / 内核 commit）
    ├── 特定内核版本 + FUSE 版本组合已知不兼容
    ├── CR2 地址在 FUSE 模块区域内 → FUSE 内核模块导致 Panic
    ├── soft lockup 栈显示在 fuse_* 函数中 → FUSE 内核路径问题
    ├── 大规模并发操作触发的竞态条件 → 内核 FUSE 并发 Bug
    └── FUSE 模块参数不合理导致内核异常 → max_read 过小/过大
```

**典型输出**：
```
结论: dmesg 显示 "kernel BUG at fs/fuse/dev.c:1234"，
      内核版本 5.15.0-rc3 存在已知 FUSE 并发访问 Bug。
      CR2 地址 0xffff888123456789 在 fuse_dev_do_write 函数范围内。
根因: 内核 FUSE 模块在特定内核版本下存在并发竞态条件，
      多线程并发写操作触发内核 BUG。
```

#### Branch H — 混合/复杂 FUSE 故障

**触发条件**：多种现象共存，或以上分支无法覆盖的复杂 FUSE 问题。

```
L2 诊断：
├── 1. 执行所有以上分支的 L2 诊断（汇总所有证据）
├── 2. 交叉对比各分支症状（判定主次故障）
├── 3. 完整 strace -f -e trace=all -p <daemon_pid> -o /tmp/strace.log
├── 4. lsof -p <daemon_pid>（daemon 打开的文件/连接）
├── 5. tcpdump -i any host <backend_storage_ip>（后端存储网络抓包）
├── 6. strace -e trace=all ls -la <mount_point> 2>&1（客户端操作全追踪）
├── 7. 对比故障前后的 FUSE 配置快照（连接数、参数、daemon 版本）
│
└── L3 根因判定：
    ├── 按故障链优先级排序（先解决依赖的下层问题）
    ├── 多故障串联（daemon 崩溃 → 残留连接 → 新 daemon 无法挂载）
    ├── 配置错误叠加（max_read 过小 + 线程池太小 + writeback 未启用）
    ├── 环境变化触发（内核升级、cgroup 限制、SELinux 策略变更）
    └── 复杂的 libfuse API 使用错误（回调注册、会话管理、信号处理）
```

**典型输出**：
```
结论: 多种故障共存：daemon 线程池过小（4 线程）导致写性能差，
      同时 max_read=4K 进一步退化读性能，writeback cache 启用
      但 daemon 未正确处理 ->write 回调。
根因: 多重配置叠加导致 FUSE 极端性能退化，建议逐一修复：
      1. 增大线程池至 16+
      2. 设置 max_read=128K+
      3. 检查 writeback cache 回调实现
```

---

## 第四节：故障模式速查表

| 故障模式 | 核心命令 | 特征日志/现象 |
|---------|---------|-------------|
| Daemon 崩溃 EIO | `stat <mount_point>` | `Transport endpoint is not connected` |
| 请求队列阻塞 | `cat .../connections/*/waiting` | `waiting > 0` 且持续增长 |
| max_read/write 不当 | `cat .../connections/*/max_read` | `max_read=4096` 性能异常低 |
| writeback 不一致 | `mount \| grep writeback_cache` | 写入后读取数据不同 |
| 多线程死锁 | `cat /proc/<pid>/task/*/stack` | `pthread_mutex_lock` 全部阻塞 |
| /dev/fuse 权限 | `ls -la /dev/fuse` | `Permission denied` |
| 内核 Bug | `dmesg \| grep -i fuse` | `kernel BUG at fs/fuse/dev.c` |
| 混合故障 | 汇总所有诊断 | 多种现象并存 |

## 第五节：参考文档

- `references/fuse_commands.md` — FUSE 诊断命令速查
- `references/fuse_params.md` — 内核 FUSE 相关参数说明
- `references/fuse_patterns.md` — FUSE 故障模式与正则匹配
