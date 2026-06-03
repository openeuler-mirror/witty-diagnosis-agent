# 🔴 故障诊断报告

> **报告编号**：RCA-20260602-002
> **故障级别**：P2 / Major
> **报告时间**：2026-06-02 18:58:41
> **当前状态**：🔴 处理中

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | POSIX 文件锁竞争导致子进程挂起（process-hang-branch-c） |
| 影响范围 | 容器 process-hang-branch-c 内子进程 PID 7（filelock_content）完全阻塞 |
| 故障时段 | 未知（报告时仍在持续中）～ 至今 |
| 根本原因 | PID 1 持有 /tmp/test_lockfile.lock 的 WRITE 锁未释放，PID 7 尝试获取 READ 锁时被阻塞，陷入 D 状态（fcntl_setlk） |
| 是否恢复 | ❌ 未恢复 |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|---------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | /proc/locks、lslocks、wchan 三重证据完全吻合，无矛盾 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                   事件                                                     性质         溯源路径
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────
T0 (未知)             PID 1 (filelock_content) 启动，打开 /tmp/test_lockfile.lock    🟢 进程启动   [branch_c_report.md:4]
  │                   并调用 fcntl(F_SETLK, F_WRLCK) 获取 WRITE 锁
  ▼
T1 (未知)             PID 7 (filelock_content) 被 fork/创建，试图打开                ⚠️ 隐患出现   [branch_c_report.md:4]
  │                   同一文件并调用 fcntl(F_SETLK, F_RDLCK) 获取 READ 锁
  ▼
T2 (未知)             由于 PID 1 仍持有 WRITE 锁（互斥），内核拒绝授予 READ 锁          🔴 阻塞发生   [/proc/locks:6]
  │                   PID 7 进入 D 状态（TASK_UNINTERRUPTIBLE）
  ▼
T3 (未知)             /tmp/test_lockfile.lock 被 unlink 删除，但文件 inode              ⚠️ 锁残留     [lslocks:11-12]
  │                   仍被 PID 1 持有（fd 未关闭），POSIX 锁随 inode 继续存在
  ▼
T4 (当前)             PID 7 持续阻塞在 fcntl_setlk，wchan 永不解锁                    🔴 故障持续   [branch_c_report.md:15]
```

### 故障因果链

```text
PID 1 调用 fcntl(F_SETLK, F_WRLCK) 获取 WRITE 锁（互斥）
    └─► PID 7 调用 fcntl(F_SETLK, F_RDLCK) 获取 READ 锁
            └─► POSIX WRITE 锁是独占锁，与 READ 锁互斥
                    └─► 内核将 PID 7 加入锁等待队列
                            └─► PID 7 进入 D 状态（TASK_UNINTERRUPTIBLE）
                                    └─► wchan = fcntl_setlk（内核级 fcntl 文件锁系统调用）
                                            └─► /tmp/test_lockfile.lock 被删除但锁未释放
                                                    └─► 🔴 PID 7 永久阻塞，进程挂起
```

---

## 三、排查过程

### 3.1 初始现象

- 容器 `process-hang-branch-c` 内子进程（PID 7）疑似挂起，无响应
- 进程无法正常退出或响应业务请求
- 父进程 PID 1 正常运行但子进程 stuck

### 3.2 假设驱动排查

#### 假设 A：进程崩溃/SIGSTOP 信号

> 🧪 假设：子进程因段错误崩溃或被 SIGSTOP 挂起

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 进程状态 | 查看 `/proc/7/status` 及 wchan | ❌ 非 Z 非 T 状态，wchan=fcntl_setlk 表明阻塞在锁系统调用 |

**❌ 排除**：非崩溃也非信号挂起，而是内核可中断睡眠 D 状态。

---

#### 假设 B：死锁（ABBA/循环等待）

> 🧪 假设：两个进程互相等待对方持有的锁形成死锁

| 检查项 | 操作 | 结论 |
|--------|------|------|
| /proc/locks 分析 | 查看所有锁记录 | ✅ 只有一把锁：PID 1 持 WRITE，PID 7 等 READ |
| 依赖方向 | PID 7 → PID 1（单向等待） | ❌ 非循环等待，PID 1 没有等 PID 7 |

**❌ 排除**：非 ABBA 死锁，是单向等待（单方向阻塞）。

---

#### 假设 C：POSIX 文件锁竞争（父进程持 WRITE 锁未释放） ✅ 确认根因

> 🧪 假设：PID 1 获取了 WRITE 锁后未及时释放，导致 PID 7 的 READ 锁请求永久阻塞

**证据链 — Step 1：/proc/locks 确认锁状态**

| 字段 | 值 | 含义 |
|------|-----|------|
| 锁描述符 | `23: POSIX ADVISORY WRITE 1 00:97:376596 0 EOF` | PID 1 持有 WRITE 锁，范围 0~EOF（整个文件） |
| 等待队列 | `23: -> POSIX ADVISORY READ 7 00:97:376596 0 EOF` | PID 7 等待 READ 锁，阻塞在锁描述符 23 |

**证据链 — Step 2：lslocks 双重确认**

| 进程 | PID | 锁类型 | 文件 | 状态 |
|------|-----|--------|------|------|
| filelock_content | 7 | POSIX READ | `/tmp/test_lockfile.lock (deleted)` | **BLOCKED** (带 *) |
| filelock_content | 1 | POSIX WRITE | `/tmp/test_lockfile.lock (deleted)` | 已持有 |

**证据链 — Step 3：wchan 确认阻塞点**

```
PID 7 wchan = fcntl_setlk
```

- `fcntl_setlk` 是 Linux 内核中处理 `fcntl(fd, F_SETLK/F_SETLKW, ...)` 系统调用的内核函数
- 当请求的锁无法立即获得时（已有冲突锁），进程会进入 D 状态等待

**✅ 结论：PID 1 持有 WRITE 锁（独占）后未释放，PID 7 请求 READ 锁时被永久阻塞在 `fcntl_setlk`。POSIX WRITE 锁与 READ 锁互斥。文件虽已删除，但由于 PID 1 仍持有文件描述符，锁仍有效。**

**⚠️ 附加发现**：锁文件 `/tmp/test_lockfile.lock (deleted)` 显示文件已被删除，说明有程序执行了 `unlink()` 操作。这可能是：
1. PID 1 自己在加锁后删除了文件（典型错误模式）
2. 外部进程执行了清理操作

无论哪种情况，锁依然有效（POSIX 锁绑定 inode 而非文件名），因此删除文件无法解除锁竞争。

---

### 3.3 排查结论

```text
容器 process-hang-branch-c 子进程挂起
├─► 进程崩溃/SIGSTOP     → ✅ 正常（wchan=fcntl_setlk 非 T/Z 状态），排除
├─► ABBA 死锁            → ✅ 无循环等待（单向阻塞），排除
└─► POSIX 文件锁竞争     → ❌ 确认根因
        ├─► /proc/locks  → PID 1 持 WRITE，PID 7 等 READ
        ├─► lslocks      → 同文件 (deleted)，PID 7 阻塞
        └─► wchan        → fcntl_setlk 确认阻塞内核函数
                └─► 🎯 根因确认：PID 1 持 WRITE 锁未释放 → PID 7 READ 锁永久阻塞
```

---

## 四、修复方案

### 4.1 应急处置

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 查看 PID 1 是否可被杀：`kill -9 1` 需在容器外执行（容器内 PID 1 有特殊语义） | 系统管理员 | 尽快 | 释放 WRITE 锁，PID 7 自动解除阻塞 |
| 2 | 若无法杀 PID 1，尝试通过 `gdb --batch -ex "call close(fd)" -p 1` 关闭 PID 1 中持有锁的文件描述符 | 系统管理员（需安装 gdb） | 尽快 | 关闭 fd 后锁自动释放，PID 7 获取 READ 锁继续运行 |
| 3 | 重启容器 `docker restart process-hang-branch-c` | 系统管理员 | 尽快 | 完全重置进程状态，锁竞争消失 |

**注意**：步骤 1 在容器内 `kill -9 1` 无效（PID 1 是 init 进程，被内核特殊保护）。需在宿主机上通过 `docker exec` 或 `nsenter` 方式操作。

### 4.2 永久修复计划

| 修复措施 | 负责人 | 完成时间 |
|---------|--------|---------|
| 审查 filelock_content 源码中锁获取/释放逻辑，确保 WRITE 锁在使用后及时调用 `F_UNLCK` 释放 | 开发团队 | 待定 |
| 增加锁超时机制：使用 `F_SETLK`（非阻塞）配合重试 + 超时退出，避免永久 D 状态 | 开发团队 | 待定 |
| 避免在锁持有期间 unlink 文件——删除文件不影响锁状态，造成"锁已释放"的误导 | 开发团队 | 待定 |
| 添加锁监控和健康检测：定期检查 /proc/locks 是否存在长时间等待的锁条目 | 运维团队 | 待定 |

### 4.3 相关代码修复建议

```c
// 典型修复示例：确保 WRITE 锁使用后释放
struct flock fl = {
    .l_type   = F_WRLCK,   // 或 F_UNLCK 用于解锁
    .l_whence = SEEK_SET,
    .l_start  = 0,
    .l_len    = 0,         // 0 = EOF
};

// 获取锁
fcntl(fd, F_SETLKW, &fl);

// ... 业务逻辑 ...

// 关键：完成后必须释放锁
fl.l_type = F_UNLCK;
fcntl(fd, F_SETLK, &fl);

// 安全释放 fd
close(fd);
```
