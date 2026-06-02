# 🔴 故障诊断报告：futex 锁竞争导致进程挂起

> **报告编号**：RCA-20260602-001
> **故障级别**：P1 / Critical
> **报告时间**：2026-06-02 18:57:42
> **当前状态**：🔴 未恢复（进程完全挂起）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | futex_contentio 进程 8/9 线程阻塞于同一把 mutex，进程完全挂起 |
| 影响范围 | 容器 process-hang-branch-a 内 PID 1 (futex_contentio) 的全部业务线程（8 个工作线程均被阻塞） |
| 故障时段 | 未知（持续挂起中） |
| 根本原因 | Thread 6 (LWP 12) 持锁后调用 `usleep()` 不释放 `global_mutex`，其余 8 线程无限期等待该锁 |
| 是否恢复 | ❌ 未恢复 |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|--------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | SQL 无索引 → 复现后加索引立即恢复 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | 定位到慢查询，但流量突增原因待查 |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | 多个组件同时异常，无法判断触发顺序 |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | 服务偶发崩溃，日志无异常，无法复现 |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                              事件                                                         性质          溯源路径
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
[首次] (未知时间)                  Thread 6 (LWP 12) 调用 pthread_mutex_lock 获取 global_mutex     📈 锁获取     [futex_contention.c:33]
  │
  ▼
[关键错误]                         Thread 6 持锁后调用 usleep() 进入睡眠                            ⚠️ 隐患激活   [futex_contention.c:35]
  │                               ↳ wchan 从 futex_wait_queue → hrtimer_nanosleep
  │                               ↳ global_mutex 被锁住不释放（锁持有者在睡眠）
  ▼
[连锁反应]                         其余 8 个工作线程依次尝试 pthread_mutex_lock                      🟡 压力积累   [/proc/<pid>/task/*/wchan]
  │                               全部在 __lll_lock_wait → futex_wait 处阻塞
  │                               ↳ wchan = futex_wait_queue_me
  │                               ↳ 等待同一地址: 0x5c1fb9066060 <global_mutex>
  ▼
[故障爆发]                         8/9 线程均在 futex_wait_queue 阻塞，进程完全挂起                    🔴 故障爆发   [GDB thread apply all bt]
  │                               业务线程无法做任何有效工作
  │                               ↳ 监控可能告警（进程存活但无响应）
  ▼
[当前状态]                         🔴 持续挂起中，等待人工介入
```

### 故障因果链

```text
Thread 6 获取 global_mutex（pthread_mutex_lock @ futex_contention.c:33）
    └─► 持锁后调用 usleep(…)（futex_contention.c:35）← 程序错误
            └─► global_mutex 被锁定不释放，锁持有者进入睡眠状态
                    └─► 其余 8 个工作线程尝试 lock 同一 mutex
                            └─► 全部阻塞在 __lll_lock_wait → futex_wait_queue_me
                                    └─► 8/9 线程均卡在 futex_wait(wait_queue)
                                            └─► 🔴 进程完全挂起，无任何业务线程可运行
```

---

## 三、排查过程

> 排查逻辑：**OS 侧证据采集 → 进程内省 → 交叉验证 → 收敛根因**

### 3.1 初始现象

- **进程存活但无响应**：PID 1 (futex_contentio) 处于 Running/Sleeping 状态，但不做任何有效业务
- **线程级异常**：`/proc/<pid>/task/` 下 9 个线程中，8 个 wchan = `futex_wait_queue`，1 个 wchan = `hrtimer_nanosleep`
- **GDB 全线程回溯**：8 个线程停在 `__pthread_mutex_lock` → `__lll_lock_wait` → `futex_wait`，全部等待同一地址 `0x5c1fb9066060`（`global_mutex`）

---

### 3.2 假设驱动排查

#### 假设 A：死锁（ABBA）—— 排除

> 🧪 假设：多线程形成环形锁依赖，ABBA 死锁

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 锁获取顺序 | GDB 全线程 bt 检查各线程锁顺序 | 所有线程只等唯一的 `global_mutex` |
| 锁持有关系 | 检查是否有线程持有锁 A 等待锁 B | ❌ 只有一把锁，无环形依赖 |

**❌ 排除**：仅一把锁，不构成死锁必要条件（需要 ≥2 把锁且环形依赖）。

---

#### 假设 B：锁竞争 + 持锁线程异常 ✅ 确认根因

> 🧪 假设：锁持有者 Thread 6 在持锁后没有及时释放，导致其他线程饥饿

**Step 1 — OS 状态确认**

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 进程状态 | `cat /proc/<pid>/status` | State=S (sleeping) — 非 D 状态非 Zombie |
| 线程 wchan 聚合 | 遍历 `/proc/<pid>/task/*/wchan` | 8 线程 = `futex_wait_queue`，1 线程 = `hrtimer_nanosleep` |
| 等待锁地址统一性 | GDB bt 检查各线程 `futex_word` 参数 | 全部等同一地址 `0x5c1fb9066060 <global_mutex>` |

**Step 2 — 进程内省（GDB 全线程栈）**

```
Thread  6 (LWP 12) — 锁持有者:
  #0 __GI___clock_nanosleep
  #1 __GI___nanosleep
  #2 usleep
  #3 worker (futex_contention.c:35)    ← 持锁后调用 usleep！
  #4 start_thread
  #5 clone

Thread  5 (LWP 11) — 锁等待者:
  #0 futex_wait (futex_word=global_mutex)
  #1 __GI___lll_lock_wait
  #2 lll_mutex_lock_optimized
  #3 ___pthread_mutex_lock
  #4 worker (futex_contention.c:33)    ← 卡在 pthread_mutex_lock

Thread  7 (LWP 13) — 锁等待者: (同上)
Thread  8 (LWP 14) — 锁等待者: (同上)
Thread  9 (LWP 15) — 锁等待者: (同上)
...
```

**State** — 关键发现：
- **Thread 6** 在 `futex_contention.c:35` 持锁后调用 `usleep()`，这是根因代码行
- 其余所有 8 个线程都在 `futex_contention.c:33` 的 `pthread_mutex_lock` 处阻塞
- 锁等待地址 `0x5c1fb9066060` 在所有线程中完全一致（`global_mutex`）

**✅ 结论：Thread 6 (LWP 12) 在获取 `global_mutex` 后调用 `usleep()` 进入睡眠，未能及时释放锁，导致其他 8 个线程全部阻塞在 `futex_wait_queue_me`，进程完全挂起。**

---

### 3.3 排查结论

```text
进程挂起 (futex_contentio PID 1)
├─► 假设 A: ABBA 死锁
│       └─► 仅一把锁，不可能形成环形依赖 → ✅ 排除
│
└─► 假设 B: 锁竞争 + 持锁线程睡眠 ✅ 确认根因
        ├─► OS 轨道: 8/9 线程 wchan=futex_wait_queue
        │              1/9 线程 wchan=hrtimer_nanosleep
        ├─► 内省轨道: Thread 6 usleep() while holding lock
        │              其他 8 线程等同一 mutex
        └─► 交叉验证: OS + GDB 完全吻合
                └─► 🎯 根因确认: futex_contention.c:35 usleep() 持锁睡眠
```

---

## 四、修复方案

### 4.1 应急处置

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 重启容器/进程：`docker restart process-hang-branch-a` 或 `kill -9 1` | 系统/人工 | 立即 | 释放所有锁资源，进程重新初始化 |
| 2 | （备选）仅终止持锁线程：使用 GDB 强制 Thread 6 释放锁 | 人工专家 | 数分钟 | 其他线程可继续，但可能引入数据不一致风险 |

> ⚠️ `kill -9` 是最快恢复手段。生产环境中应先评估重启影响。

### 4.2 永久修复计划

| 修复措施 | 负责人 | 完成时间 |
|--------|------|--------|
| 代码修复：`futex_contention.c:35` 中 `usleep()` 应**放在临界区之外**，持锁期间禁止进入睡眠等待 | 开发团队 | 待定 |
| 代码审查：全面检查该进程所有 `pthread_mutex_lock` / `usleep` / `sleep` 调用模式，杜绝持锁睡眠 | 开发团队 | 待定 |
| 引入锁超时机制：使用 `pthread_mutex_timedlock` 替代 `pthread_mutex_lock`，避免无限期阻塞 | 开发团队 | 待定 |
| 增加监控：对进程级 wchan 分布进行监控，当大量线程集中在 `futex_wait_queue` 时提前告警 | 运维团队 | 待定 |

### 4.3 修复代码示例

```c
// ❌ 错误写法（当前代码）
void worker(void *arg) {
    pthread_mutex_lock(&global_mutex);    // futex_contention.c:33
    // ... 临界区操作 ...
    usleep(some_time);                     // futex_contention.c:35 ← 持锁睡眠！
    pthread_mutex_unlock(&global_mutex);
}

// ✅ 正确写法
void worker(void *arg) {
    // ... 非临界区前置操作 ...
    usleep(some_time);                     // 持锁前先睡眠
    pthread_mutex_lock(&global_mutex);
    // ... 临界区操作（快速完成）...
    pthread_mutex_unlock(&global_mutex);
}
```

---

## 五、验证建议

| 验证项 | 方法 | 预期结果 |
|--------|------|--------|
| 复现当前故障 | 运行未修复的二进制，观察 8 线程阻塞 | `wchan` 全部为 `futex_wait_queue` |
| 验证代码修复 | 运行修复后二进制，`usleep` 在临界区外 | 所有线程可正常轮流获取锁执行 |
| 模拟压力测试 | 9 线程并发压测持锁 -> 休眠 -> 释放循环 | 无线程阻塞超过预期时间 |
| 监控验证 | `ps -eo pid,wchan,comm` 检查 wchan 分布 | `futex_wait_queue` 无异常堆积 |

---

## 六、参考证据

| 证据项 | 来源 |
|--------|------|
| KuaFu 诊断报告 | `/home/win11/.witty-diagnosis-agent/baize/tmp/branch_a_report.md` |
| OS 线程 wchan 聚合 | 8/9 线程 wchan = `futex_wait_queue`, 1/9 = `hrtimer_nanosleep` |
| GDB 全线程回溯 | Thread 6 持锁后 `usleep`，其余全部等待同一 `global_mutex` |
| 锁地址 | `0x5c1fb9066060 <global_mutex>` — 所有等待线程目标一致 |
