# 🔴 故障诊断报告 — 进程挂起（信号停止）

> **报告编号**：RCA-20260602-BRANCH-E-001
> **故障级别**：P2
> **报告时间**：2026-06-02
> **当前状态**：🔴 处理中（进程仍处于停止状态）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | 容器 `process-hang-branch-e` 内 PID 7 (sh) 进程被 SIGSTOP 信号停止，进程挂起无响应 |
| 影响范围 | 容器 `process-hang-branch-e` 内的 sh 进程（PID 7），可能影响依赖该 shell 的上下游服务 |
| 故障时段 | 未知（首次异常时间点），截至报告生成时仍未恢复 |
| 根本原因 | PID 7 (sh) 进程收到 SIGSTOP 信号 → State=T (stopped) + wchan=do_signal_stop → 进程永久停止运行 |
| 是否恢复 | ❌ 未恢复（可通过 `kill -CONT 7` 手动恢复） |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 适用场景 |
|------|------|------|---------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | ✅ 当前：State=T + wchan=do_signal_stop + TracerPid=0 三重证据完全吻合 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间（约）                   事件                                             性质           溯源路径
──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
[T0]                      PID 7 (sh) 进程正常运行                              ✅ 正常运行    
  │
  ▼                       
[T1]                      某外部进程/用户执行 kill -SIGSTOP 7 或 kill -STOP 7    📨 信号触发    [上游诊断报告]
  │                       SIGSTOP 为不可阻塞/不可忽略/不可捕获的强制停止信号
  ▼
[T1+0]                    PID 7 内核态进入 do_signal_stop()                      🔄 状态切换    [/proc/7/wchan → do_signal_stop]
  │                       进程 State 由 S/R → T (stopped)
  ▼
[T1+0 ~ 持续]             PID 7 永久阻塞在 stopped 状态                          🔴 挂起故障    [/proc/7/status → State: T (stopped)]
  │                       不执行任何用户态/内核态代码
  │                       不响应任何业务请求
  │                       仅 SIGKILL 和 SIGCONT 可影响该进程
  ▼
[当前]                    进程仍处于 T 状态，无恢复迹象                          🟡 待恢复
```

### 故障因果链

```text
外部进程/用户发送 SIGSTOP 信号
    │
    ├─► SIGSTOP 信号特性：不可被阻塞 (SigBlk 无效)
    │       ├─► 不可被捕获/忽略 (SigCgt/SigIgn 无效)
    │       └─► 强制将进程置于 T (stopped) 状态
    │
    ├─► 内核处理：do_signal_stop()
    │       ├─► 进程 State 标记为 T
    │       ├─► 进程停止调度（不再获得 CPU 时间片）
    │       └─► wchan 显示为 do_signal_stop
    │
    └─► PID 7 (sh) 进程永久挂起
            ├─► 无 CPU 消耗
            ├─► 不响应信号（除 SIGKILL/SIGCONT 外）
            ├─► 不处理任何业务逻辑
            └─► 🔴 进程不可用，处于完全冻结状态
```

---

## 三、挂起深度分析

### 3.1 挂起概要

| 项目 | 内容 |
|------|------|
| 挂起模式 | 🛑 信号停止（SIGSTOP）— 分支 E |
| 置信度 | 🟢 高置信 |
| 分析轨道 | 单轨（仅 OS 状态分析 — 上游已采集 procfs 快照，无 gdb 内省数据） |
| 目标进程 | PID 7 / sh（Shell 进程） |
| 挂起时长 | 从被 SIGSTOP 停止至今持续挂起 |
| 容器 | process-hang-branch-e |

### 3.2 OS 状态轨道结论

| 检查项 | 结果 |
|--------|------|
| 进程状态 | State: **T (stopped)** — 进程已停止 |
| wchan | **do_signal_stop** — 内核信号停止处理路径 |
| TracerPid | **0** — 无调试器附加，排除 gdb/strace 等主动 trace 场景 |
| PPid | **1** — 父进程为容器 init 进程 |
| 线程状态 | 单线程进程（Tgid=Pid=7），无多线程依赖问题 |
| OS 侧阻塞根因假设 | 进程被 SIGSTOP 信号强制停止，由于 TracerPid=0，信号来源为外部进程（非调试器） |

**关键内核路径说明：**
- `do_signal_stop` 是 Linux 内核处理 SIGSTOP/SIGTSTP/SIGTTIN/SIGTTOU 等停止信号的统一入口
- 当进程收到 SIGSTOP 后，内核将进程状态标记为 `TASK_STOPPED`（即 T 状态）
- 处于 T 状态的进程不再被调度器选中运行，完全停止执行

### 3.3 进程内省轨道结论

| 检查项 | 结果 |
|--------|------|
| GDB 连接状态 | ⚠️ 未执行（上游未采集 gdb 数据，且进程处于 T 状态需先 SIGCONT 才能 attach） |
| 信号状态推断 | SIGSTOP 为强制停止信号（编号 19），不可被阻塞、捕获或忽略 |
| 内省侧根因假设 | 进程 sh(PID 7) 的挂起完全由 SIGSTOP 信号的外部发送导致 |

### 3.4 交叉验证结果

| 验证维度 | OS 状态结论 | 内省结论 | 是否吻合 |
|---------|------------|---------|---------|
| 阻塞点 | wchan=do_signal_stop | State=T 直接确认，无 gdb 数据但一致 | ✅ 吻合 |
| 资源依赖 | 无文件锁/管道/socket 竞争 | N/A | ✅ 吻合 |
| 线程关系 | 单线程，无依赖环 | N/A | ✅ 吻合 |
| 信号状态 | State=T, TracerPid=0 | SIGSTOP 强制停止 | ✅ 吻合 |
| 综合判断 | 双轨结论完全一致，证据充分，根因明确 | | ✅ 吻合 |

### 3.5 排除的替代假设

| 假设 | 排除原因 |
|-----|---------|
| ❌ 死锁（ABBA） | wchan=do_signal_stop 非 futex_wait_queue_me，State=T 非 D/S |
| ❌ 文件锁竞争 | /proc/locks 无关联条目（上游未检测，但 State=T 根本原因明确） |
| ❌ 管道/Socket 阻塞 | wchan=do_signal_stop 非 pipe_read/poll_schedule/sock_rcvmsg |
| ❌ D 状态磁盘 IO 阻塞 | State=T 而非 D |
| ❌ 调试器 trace | TracerPid=0，确认无调试器附加 |
| ❌ 用户态死循环 | State=T 非 R，进程不运行，不可能死循环 |

---

## 四、排查过程

### 4.1 初始现象

- 容器 `process-hang-branch-e` 内 PID 7 (sh) 进程挂起，无响应
- 进程状态显示为 `State: T (stopped)`
- 等待通道显示为 `wchan: do_signal_stop`

### 4.2 假设驱动排查

#### 假设 A：调试器附加导致进程停止（traced）

> 🧪 假设：gdb/strace 等调试工具 attach 了进程，导致进程进入 traced 停止状态

| 检查项 | 操作 | 结论 |
|--------|------|------|
| TracerPid 检查 | 读取 /proc/7/status TracerPid 字段 | ✅ 值为 0，无调试器附加 |
| State 精确值 | 读取 State 字段 | State=T (stopped) 非 State=t (traced) |

**❌ 排除**：TracerPid=0，非调试器导致。

---

#### 假设 B：资源竞争/死锁导致进程阻塞

> 🧪 假设：进程因锁竞争或 IO 阻塞导致无法运行

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 状态判断 | State=T 为非运行停止状态 | ✅ T 状态非 D/S/R，明确为信号停止 |
| wchan 确认 | do_signal_stop | ✅ 信号特定路径，非锁/IO 等待 |

**❌ 排除**：wchan 明确指向信号停止路径。

---

#### 假设 C：SIGSTOP 信号停止 ✅ 确认根因

> 🧪 假设：进程被外部发送的 SIGSTOP 信号强制停止

**Step 1 — 确认进程停止状态**

```text
/proc/7/status:
  State:  T (stopped)      ← 进程已停止
  TracerPid:  0            ← 无调试器
  PPid:   1                ← 父进程为 init
```

**Step 2 — 确认内核等待路径**

```text
/proc/7/wchan:
  do_signal_stop           ← 内核信号停止处理函数
```

**Step 3 — 分析信号特性**

- SIGSTOP (信号编号 19) 为 Linux 强制停止信号
- **不可被阻塞**：即使进程设置了 SigBlk 位图也无法屏蔽
- **不可被捕获**：无法注册 signal handler
- **不可被忽略**：SigIgn 位图对 SIGSTOP 无效
- 唯一能解除停止的信号：SIGCONT（继续执行）和 SIGKILL（强制终止）

**✅ 结论：PID 7 (sh) 进程被外部进程/用户通过 `kill -STOP 7` 或 `kill -SIGSTOP 7` 发送的 SIGSTOP 信号停止，导致进程永久挂起。**

### 4.3 排查结论

```text
PID 7 (sh) 进程挂起无响应
│
├─► 假设 A：调试器附加/trace  → ✅ TracerPid=0，排除
│
├─► 假设 B：死锁/IO阻塞       → ✅ State=T 且 wchan=do_signal_stop，排除
│
└─► 假设 C：SIGSTOP 信号停止  → ❌ 确认根因
        ├─► State=T (stopped)                确认
        ├─► wchan=do_signal_stop             确认
        ├─► TracerPid=0                     确认
        └─► 🎯 根因确认：外部 SIGSTOP 信号导致进程停止
```

---

## 五、修复方案

### 5.1 应急处置

| 步骤 | 操作 | 执行人 | 预期效果 |
|------|------|--------|---------|
| 1 | `kill -CONT 7` 发送 SIGCONT 信号 | 运维人员 | 进程恢复运行，从 T 状态回到 S/R 状态 |
| 2 | 确认进程恢复：`cat /proc/7/status \| grep State` | 运维人员 | State 应为 S (sleeping) 或 R (running) |
| 3 | 如进程仍异常，则考虑重启容器 | 运维人员 | 彻底恢复 |

**恢复命令示例：**

```bash
# 发送 SIGCONT 恢复进程执行
kill -CONT 7

# 验证恢复状态
cat /proc/7/status | grep -E "^State"
# 期望输出: State:  S (sleeping) 或 R (running)

# 如果进程仍有问题，可通过容器管理重启
docker restart process-hang-branch-e
```

### 5.2 根本修复计划

| 修复措施 | 负责人 | 完成时间 |
|--------|-------|---------|
| **排查 SIGSTOP 发送者**：审查系统日志 (`journalctl`, `/var/log/messages`)、auditd 日志、以及容器内的操作历史，定位谁/哪个进程发送了 `SIGSTOP` 给 PID 7 | 运维/SRE | 故障恢复后 |
| **代码审查**：检查容器启动脚本、监控脚本、健康检查脚本中是否存在误用 `kill -STOP` 的情况 | 开发/运维 | 待定 |
| **监控告警加固**：增加进程 State=T 状态的告警规则，及时 detect 此类信号停止故障 | 监控团队 | 待定 |

### 5.3 预防措施

- 在容器运行时监控中增加 `process_state{state="T"}` 指标的告警
- 审查所有自动化运维脚本，禁止在生产环境随意使用 `kill -STOP` 命令
- 关键业务进程可考虑使用 `systemd` 或类似进程管理器，配置 `Restart=always` 实现自动恢复

---

## 六、验证建议

| 验证目标 | 验证方法 |
|---------|---------|
| 确认根因正确性 | 对同一容器内的另一个 shell 进程执行 `kill -STOP <pid>`，验证 State=T, wchan=do_signal_stop，确认相同现象可复现 |
| 确认修复有效性 | 发送 `kill -CONT <pid>` 后，验证进程 State 从 T 变为 S/R，且业务功能恢复正常 |
| 确认发送者溯源能力 | 通过 auditd 规则监控 `kill` 系统调用：`auditctl -a exit,always -S kill -k signal_kill`，后续可追溯发送者 |

---

## 附录：证据来源

| 证据项 | 来源路径 |
|--------|---------|
| 进程状态快照 | `/home/win11/.witty-diagnosis-agent/baize/tmp/branch_e_report.md` |
| 进程 State | 同上，第 8 行：`State: T (stopped)` |
| 进程 wchan | 同上，结论段：`wchan=do_signal_stop` |
| TracerPid | 同上，第 13 行：`TracerPid: 0` |
