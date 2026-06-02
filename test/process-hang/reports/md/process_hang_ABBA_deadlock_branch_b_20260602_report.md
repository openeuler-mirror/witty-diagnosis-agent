# 🔴 故障诊断报告

> **报告编号**：RCA-20260602-BRANCHB-001
> **故障级别**：P1 / Critical
> **报告时间**：2026-06-02 00:00:00
> **当前状态**：🔴 处理中

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | process-hang-branch-b 容器 PID 1 进程因 ABBA 死锁导致进程挂起 |
| 影响范围 | process-hang-branch-b 容器，PID 1（abba_deadlock）进程；容器内所有业务逻辑因主进程挂起而完全不可用 |
| 故障时段 | 进程启动后（具体时间未知）～ 持续至今（未恢复） |
| 根本原因 | ABBA 经典死锁：`thread1()` 持有 `lock_a` 等待 `lock_b`，`thread2()` 持有 `lock_b` 等待 `lock_a`，形成循环等待，导致 3 个线程全部阻塞在 futex_wait_queue，进程永久挂起 |
| 是否恢复 | ❌ 未恢复 |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|--------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | GDB 直接确认 ABBA 死锁环路，所有线程均阻塞在 futex_wait_queue，证据链完整 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | 定位到慢查询，但流量突增原因待查 |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | 多个组件同时异常，无法判断触发顺序 |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | 服务偶发崩溃，日志无异常，无法复现 |

---

## 二、根因速览

> **线程间锁顺序不一致导致循环等待，所有线程永久阻塞。**

### 事故时间线 & 故障传导链路

```text
时间                    事件                                             性质          溯源路径
───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
进程启动时              abba_deadlock 进程启动，创建 3 个线程               🚀 进程启动   [/home/win11/.witty-diagnosis-agent/baize/tmp/branch_b_report.md]
  │
  ▼
进程启动后不久          thread1 (LWP 7) 获取 lock_a 成功                   🔒 锁获取     [源码: abba_deadlock.c:33]
  │                    ↳ 进入临界区执行操作，随后尝试获取 lock_b
  ▼
进程启动后不久          thread2 (LWP 8) 获取 lock_b 成功                   🔒 锁获取     [源码: abba_deadlock.c:48]
  │                    ↳ 进入临界区执行操作，随后尝试获取 lock_a
  ▼
死锁瞬间                thread1 持 lock_a 等 lock_b  ⬅➡  thread2 持 lock_b 等 lock_a  🔴 死锁爆发
  │                    ↳ 两个线程均无法继续执行，futex_wait 无限期阻塞
  ▼
死锁发生后              所有线程阻塞在 futex_wait_queue                       🟡 进程挂起   [OS 状态: wchan=futex_wait_queue]
  │                    ↳ Thread 1 (LWP 1) 因 Thread 2/3 阻塞无法 join 返回，也一起卡住
  ▼
当前                    PID 1 进程永久挂起，容器内无响应                     🔴 服务不可用  [GDB 分析确认]
```

### 故障因果链

```text
ABBA 死锁（代码逻辑缺陷）
    │
    ├─► thread1() 加锁顺序：先 lock_a → 再 lock_b
    │      └─► 获取 lock_a ✅ → 尝试 lock_b ❌（已被 thread2 持有）→ futex_wait 阻塞
    │
    ├─► thread2() 加锁顺序：先 lock_b → 再 lock_a
    │      └─► 获取 lock_b ✅ → 尝试 lock_a ❌（已被 thread1 持有）→ futex_wait 阻塞
    │
    └─► 循环等待成立
           └─► thread1(LWP 7) ↔ thread2(LWP 8) 相互等待
                  └─► Thread 1(LWP 1) 主线程等待子线程无法返回
                         └─► 🔴 PID 1 进程永久挂起 / 容器服务完全不可用
```

---

## 三、排查过程

> 排查逻辑：**观察到进程挂起 → 检查 OS 线程状态 → GDB 附加分析 → 确认 ABBA 死锁环路**

### 3.1 初始现象

- **容器**：`process-hang-branch-b`，PID 1 进程 `abba_deadlock` 无响应
- **OS 状态**：进程共 3 个线程，全部处于 `wchan=futex_wait_queue`，即所有线程均阻塞在 futex 等待队列上
- **用户侧表现**：容器内服务完全不可用，无法响应任何请求

---

### 3.2 假设驱动排查

#### 假设 A：单个线程卡在锁上（非死锁）

> 🧪 假设：仅一个线程因锁持有时间过长而阻塞，其余线程正常

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 所有线程状态 | 检查 `/proc/PID/task/*/wchan` | ❌ 三个线程全部为 `futex_wait_queue`，无正常运行的线程 |
| 锁持有者判断 | 仅根据单一线程栈无法判断是否死锁 | ❌ 所有线程均在等待，不符合「单线程阻塞」模式 |

**❌ 排除**：全部线程阻塞，非单线程卡锁问题。

---

#### 假设 B：ABBA 死锁 ✅ 确认根因

> 🧪 假设：存在锁顺序不一致导致的循环等待死锁

**Step 1 — 获取各线程调用栈（GDB）**

**Thread 3 (LWP 8 / thread2) — 等待 `lock_a`：**
```text
#0  futex_wait (futex_word=0x5a191a929060 <lock_a>)
#1  __lll_lock_wait ...
#2  lll_mutex_lock_optimized (mutex=0x5a191a929060 <lock_a>)
#3  __pthread_mutex_lock (mutex=0x5a191a929060 <lock_a>)
#4  thread2 (arg=0x0) at abba_deadlock.c:48
```

**Thread 2 (LWP 7 / thread1) — 等待 `lock_b`：**
```text
#0  futex_wait (futex_word=0x5a191a9290a0 <lock_b>)
#1  __lll_lock_wait ...
#2  lll_mutex_lock_optimized (mutex=0x5a191a9290a0 <lock_b>)
#3  __pthread_mutex_lock (mutex=0x5a191a9290a0 <lock_b>)
#4  thread1 (arg=0x0) at abba_deadlock.c:33
```

**Thread 1 (LWP 1 / main) — 主线程：**
```text
无活跃栈（等待子线程 join）
```

**Step 2 — 锁持有关系推导**

| 线程 | 已持有的锁 | 正在等待的锁 | 源码位置 |
|------|-----------|------------|---------|
| Thread 2 (LWP 7, thread1) | `lock_a`（0x5a191a929060） | `lock_b`（0x5a191a9290a0） | abba_deadlock.c:33 |
| Thread 3 (LWP 8, thread2) | `lock_b`（0x5a191a9290a0） | `lock_a`（0x5a191a929060） | abba_deadlock.c:48 |

**Step 3 — 死锁环确认**

```text
thread1() 持 lock_a → 等 lock_b
                            ⤵
thread2() 持 lock_b → 等 lock_a
                            ⤴
          ↻ 循环等待 → ABBA 死锁确认 ↻
```

**✅ 结论：代码中 `thread1()` 和 `thread2()` 的加锁顺序不一致（前者先 A 后 B，后者先 B 后 A），导致在并发执行时出现 ABBA 死锁。所有线程永久阻塞在 futex_wait_queue，进程挂起。**

---

### 3.3 排查结论

```text
进程挂起（PID 1, abba_deadlock）
│
├─► OS 线程状态检查        → ❌ 3 线程全部 wchan=futex_wait_queue，异常
│       └─► 初步判定为锁竞争问题 → 🔍 深入 GDB 分析
│
└─► GDB 线程栈分析        → ❌ 确认互等关系
        │
        ├─► thread1 (LWP 7): 持 lock_a 等 lock_b
        ├─► thread2 (LWP 8): 持 lock_b 等 lock_a
        │
        └─► 🎯 根因确认：ABBA 死锁 —— 加锁顺序不一致导致循环等待
```

---

## 四、修复方案

### 4.1 应急处置

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 强制终止 `abba_deadlock` 进程：`kill -9 1`（容器内）或重启容器 | 运维/系统 | 尽快执行 | 释放所有锁和资源，恢复容器可用性 |
| 2 | 容器重启后确认进程恢复正常启动 | 运维/系统 | 步骤 1 后 | 验证临时恢复 |

> ⚠️ 注意：应急处置只能临时恢复服务，若代码不修复，死锁会在相同条件下再次触发。

### 4.2 永久修复计划

| 修复措施 | 负责人 | 完成时间 |
|--------|--------|--------|
| **统一加锁顺序**：修改源码 `abba_deadlock.c`，确保 `thread1()` 和 `thread2()` 以相同顺序获取锁（例如统一为先 `lock_a` 后 `lock_b`） | 开发团队 | 待定 |
| **引入死锁检测机制**：在加锁路径中添加 `trylock` + 超时回退机制，避免长时间阻塞 | 开发团队 | 待定 |
| **代码审查规范**：在代码审查流程中增加锁顺序一致性检查项 | 开发团队 | 待定 |
| **压力测试**：修复后执行多线程并发压力测试，验证无死锁回归 | 测试团队 | 待定 |

### 4.3 修复示例代码

```c
// ❌ 错误写法（当前代码）—— 加锁顺序不一致
void *thread1(void *arg) {
    pthread_mutex_lock(&lock_a);  // 先 lock_a
    // ... 临界区操作 ...
    pthread_mutex_lock(&lock_b);  // 再 lock_b
    // ...
}

void *thread2(void *arg) {
    pthread_mutex_lock(&lock_b);  // 先 lock_b ← 顺序不一致！
    // ... 临界区操作 ...
    pthread_mutex_lock(&lock_a);  // 再 lock_a ← 与 thread1 相反
    // ...
}

// ✅ 正确写法 —— 统一加锁顺序
void *thread1(void *arg) {
    pthread_mutex_lock(&lock_a);
    pthread_mutex_lock(&lock_b);
    // ... 临界区操作 ...
    pthread_mutex_unlock(&lock_b);
    pthread_mutex_unlock(&lock_a);
}

void *thread2(void *arg) {
    pthread_mutex_lock(&lock_a);  // 统一：先 lock_a
    pthread_mutex_lock(&lock_b);  // 统一：再 lock_b
    // ... 临界区操作 ...
    pthread_mutex_unlock(&lock_b);
    pthread_mutex_unlock(&lock_a);
}
```

---

*报告生成于 2026-06-02 00:00:00 | 数据来源：上游诊断报告 /home/win11/.witty-diagnosis-agent/baize/tmp/branch_b_report.md*
