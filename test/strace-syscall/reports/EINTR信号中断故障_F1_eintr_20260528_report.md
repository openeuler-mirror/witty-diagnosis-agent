# 🔴 故障诊断报告

> **报告编号**：RCA-20260528-BZ-001
> **故障级别**：P2
> **报告时间**：2026-05-28
> **当前状态**：🔴 处理中

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | 进程 `branch_f_signal` 因 SIGALRM 中断阻塞式 syscall 导致 EINTR 错误 |
| 影响范围 | 进程 `branch_f_signal` (PID 11354) 及其依赖的 I/O 和定时操作 | 
| 故障时段 | 进程启动后持续受影响（定时器每 100ms 触发一次 SIGALRM） |
| 根本原因 | SIGALRM 信号处理函数未设置 `SA_RESTART` 标志，导致 `read()`/`nanosleep()` 等慢速系统调用被信号中断后返回 -1 EINTR，内核不自动重试 |
| 是否恢复 | ❌ 未恢复（需代码修复） |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|---------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | 本文场景：SA_RESTART 缺失 → EINTR，且可稳定复现 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | - |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | - |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | - |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                          事件                                                 性质              溯源路径
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
进程启动时                     branch_f_signal --loop eintr 启动                        🟢 进程启动       [kuafu_F1_eintr.md:3]
  │                           PID: 11354
  ▼
进程初始化                     setitimer(ITIMER_REAL, 100ms) 设置间隔定时器               ⚠️ 信号源配置    [kuafu_F1_eintr.md:5]
  │                           每 100ms 发送 SIGALRM
  ▼
信号注册                       sigaction 注册 SIGALRM 处理函数                            ⚠️ 隐患引入      [kuafu_F1_eintr.md:5]
  │                           但未指定 SA_RESTART 标志
  ▼
第 1 个 100ms 周期             SIGALRM 信号到达                                           📈 定时触发
  │
  ▼
执行慢速 syscall 时中断        blocking read(空pipe) / nanosleep 被 SIGALRM 中断          🔴 故障触发      [kuafu_F1_eintr.md:6]
  │                           → 内核执行信号处理函数
  │                           → 返回后检查 SA_RESTART 标志 → 不存在
  │                           → 系统调用不自动重启
  ▼
syscall 返回 EINTR             read() / nanosleep() 返回 -1, errno = EINTR               🔴 故障爆发      [kuafu_F1_eintr.md:7]
  │                           应用层未正确处理 EINTR → 逻辑异常
  ▼
每 100ms 重复                  定时器持续触发，每次阻塞 syscall 均被中断                   🔴 持续影响
```

### 故障因果链

```text
setitimer(ITIMER_REAL, 100ms) 设置 100ms 间隔定时器
    └─► 每 100ms 向进程发送 SIGALRM 信号
            │
            ▼
sigaction 注册 SIGALRM 处理函数时未指定 SA_RESTART 标志
    └─► 当进程执行 blocking read(空pipe) 或 nanosleep 等慢速系统调用时
            │
            ▼
SIGALRM 到达 → 内核暂停系统调用 → 执行信号处理函数 → 返回用户态
    └─► 内核检查 SA_RESTART → 标志缺失
            │
            ▼
系统调用不自动重启 → 直接返回 -1，errno 置为 EINTR
    └─► 应用层若未对 EINTR 做重试/恢复处理
            │
            ▼
            └─► 🔴 业务逻辑异常 / I/O 操作失败 / 定时周期紊乱
```

---

## 三、排查过程

### 3.1 初始现象

- 进程 `branch_f_signal` (PID 11354) 在运行过程中出现 I/O 和定时器行为异常
- `blocking read(空 pipe)` 被信号中断，返回 -1 EINTR
- `nanosleep` 也被信号中断，返回 -1 EINTR
- 信号不自动重发，系统调用直接失败返回

### 3.2 假设驱动排查

#### 假设 A：信号处理器中存在 longjmp 或异常终止

> 🧪 假设：信号处理函数内部执行了 `longjmp` 或 `exit` 导致系统调用异常终止

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 信号处理行为 | 查看 sigaction 配置 | ✅ 未发现 longjmp，信号处理正常执行 |
| 进程是否终止 | 观察进程存活状态 | ✅ PID 11354 进程存活，未被杀死 |

**❌ 排除**：信号处理函数正常执行完毕返回，非 longjmp 场景。

---

#### 假设 B：SIGALRM 传递方式异常（如信号丢失或队列满）

> 🧪 假设：实时信号队列溢出或信号丢失导致状态不一致

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 信号类型 | SIGALRM 为标准信号（非实时信号） | ✅ 标准信号不会排队，但这里表现符合预期 |
| 信号行为 | 每隔 100ms 稳定收到 SIGALRM | ✅ 信号正常投递 |

**❌ 排除**：信号投递正常，每次定时器触发都能收到 SIGALRM。

---

#### 假设 C：`SA_RESTART` 缺失导致 EINTR ✅ 确认根因

> 🧪 假设：信号处理函数安装时未使用 `SA_RESTART` 标志，导致被中断的慢速系统调用不自动重启

**Step 1 — 确认信号处理参数**
```c
// 理论分析：sigaction 的 sa_flags 未包含 SA_RESTART
// sa_flags &= ~SA_RESTART → 系统调用被中断后不自动重启
```

**Step 2 — 确认 SIGALRM 发送频率**
- `setitimer(ITIMER_REAL, 100ms)` → 每 100ms 触发一次 SIGALRM
- 频率极高（10 次/秒），大幅增加 EINTR 出现概率

**Step 3 — 确认受影响系统调用类型**
| 系统调用 | 是否受影响 | 说明 |
|---------|-----------|------|
| `read(空 pipe)` | ✅ 是 | 阻塞等待数据时被 SIGALRM 中断 → EINTR |
| `nanosleep()` | ✅ 是 | 睡眠期间被 SIGALRM 中断 → EINTR |
| `write` | ❌ 通常不受影响 | write 到常规文件通常为快速操作 |
| `waitpid` | ✅ 是 | 阻塞等待子进程也可能被中断 |

**✅ 结论：根因明确**

```text
sigaction(SIGALRM, &act, NULL)  // act.sa_flags 中缺少 SA_RESTART
  + setitimer(ITIMER_REAL, 100ms)  // 每 100ms 发送 SIGALRM
  + 进程执行 blocking read / nanosleep 等慢速系统调用
  = 系统调用被 SIGALRM 中断 → 返回 -1 EINTR
```

---

### 3.3 排查结论

```text
进程 branch_f_signal EINTR 错误
├─► 假设 A：信号处理 longjmp    → ✅ 排除，信号处理正常返回
├─► 假设 B：信号投递异常        → ✅ 排除，信号稳定每 100ms 投递
└─► 假设 C：SA_RESTART 缺失     → ❌ 确认根因
        └─► setitimer(100ms) 持续触发 SIGALRM
                └─► sigaction 无 SA_RESTART 标志
                        └─► blocking read / nanosleep 被中断
                                └─► 🎯 根因确认：SA_RESTART 标志缺失
```

---

## 四、修复方案

### 4.1 应急处置

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 暂时停止该进程或修改定时器间隔（增大间隔或取消定时器） | 运维人员 | 立即 | 阻断 EINTR 频繁触发源 |

### 4.2 永久修复计划

#### 方案 A（推荐）：在信号处理中使用 `SA_RESTART` 标志

修改 sigaction 调用，在 `sa_flags` 中加入 `SA_RESTART`：

```c
struct sigaction act;
act.sa_handler = handler;          // 信号处理函数
sigemptyset(&act.sa_mask);
act.sa_flags = SA_RESTART;         // ← 关键修复：添加 SA_RESTART 标志

if (sigaction(SIGALRM, &act, NULL) == -1) {
    perror("sigaction");
    exit(1);
}
```

**效果**：内核在信号处理函数返回后自动重启被中断的慢速系统调用，应用层无需感知 `EINTR`。

#### 方案 B：应用层主动处理 `EINTR` 重试

如果因业务原因不能修改信号处理方式，则在所有可能被信号中断的系统调用处添加 EINTR 重试逻辑：

```c
// blocking read 重试模式
ssize_t safe_read(int fd, void *buf, size_t count) {
    ssize_t ret;
    do {
        ret = read(fd, buf, count);
    } while (ret == -1 && errno == EINTR);  // 被信号中断则重试
    return ret;
}

// nanosleep 重试模式（使用剩余时间）
int safe_nanosleep(const struct timespec *req) {
    struct timespec rem;
    int ret;
    do {
        ret = nanosleep(req, &rem);
        if (ret == -1 && errno == EINTR) {
            *req = rem;  // 用剩余时间继续睡眠
        }
    } while (ret == -1 && errno == EINTR);
    return ret;
}
```

**效果**：即使没有 `SA_RESTART`，应用层也能正确处理 EINTR，自动重试被中断的系统调用。

#### 方案 C：取消定时器或改用 `timer_create` + `SIGEV_THREAD`

如果定时信号并非业务核心需求，考虑移除定时器；若必须使用，可改用 `timer_create()` 配合 `SIGEV_THREAD` 在独立线程中处理信号：

```c
struct sigevent sev;
sev.sigev_notify = SIGEV_THREAD;   // 在新线程中处理，不中断主线程系统调用
sev.sigev_signo = SIGALRM;
sev.sigev_value.sival_ptr = &timer_id;
sev.sigev_notify_function = handler_thread;
timer_create(CLOCK_REALTIME, &sev, &timer_id);
```

### 修复措施汇总

| 修复措施 | 复杂度 | 侵入性 | 推荐指数 |
|---------|--------|--------|---------|
| A. 添加 SA_RESTART 标志 | 低（1行改动） | 低 | ⭐⭐⭐⭐⭐ |
| B. 应用层 EINTR 重试封装 | 中（需修改所有调用点） | 中 | ⭐⭐⭐⭐ |
| C. 改用 timer_create + SIGEV_THREAD | 高（重构定时逻辑） | 高 | ⭐⭐⭐ |

**建议优先采用方案 A**，改动最小，最符合 POSIX 信号处理最佳实践。

---

## 附录：技术背景

### EINTR 机制说明

- **EINTR** 是 POSIX 定义的一种错误码，表示系统调用在执行过程中被信号中断。
- 当进程配置了信号处理函数（通过 `sigaction`），且 `sa_flags` 中**不包含** `SA_RESTART` 时，慢速系统调用（如 `read`、`write`（管道/FIFO/设备）、`nanosleep`、`wait`、`accept` 等）被信号中断后，内核**不会自动重试**，而是返回 -1 并将 `errno` 设为 `EINTR`。
- 如果 `sa_flags` 中包含 `SA_RESTART`，则内核会在信号处理函数返回后**自动重启**被中断的系统调用，应用层无感知。
- Linux 中，`setitimer(ITIMER_REAL)` 会按照设定的间隔反复发送 `SIGALRM` 信号，频率越高，EINTR 出现的概率越大。
