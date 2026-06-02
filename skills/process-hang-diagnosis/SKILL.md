---
name: process-hang-diagnosis
description: >
  用户态进程挂起/无响应（Hang）深度诊断技能（双轨：OS 状态 + 进程内省）。
  当用户提到进程挂起、进程夯死、无响应、hang、进程卡死、进程 D 状态、进程
  S 状态不运行、服务不可用、CPU 占用 0 但进程在、kill -9 杀不死、gdb 挂住、
  死锁、futex 等待、文件锁冲突、进程 stuck 等关键词时，必须使用本技能。
  覆盖场景：死锁检测（wchan + gdb bt）、futex 锁等待、文件锁竞争（/proc/locks）、
  管道/socket 阻塞读写、信号屏蔽导致无法终止、SIGSTOP 误发送、内核 D 状态
  (TASK_UNINTERRUPTIBLE) 阻塞、unix socket 缓冲区满等。
  支持进程级根因定位（有符号/源码时必须走双轨并行并交叉验证）。
---

# 进程挂起/无响应深度诊断（双轨：OS 状态 + 进程内省）

## 第一节：故障目录结构（脚本采集输出）

```text
hang_dir/                     # 故障工作目录
├── core/                     # 【可选】core dump 文件
├── gdb_output/               # gdb 现场采集输出（由分支脚本生成）
│   ├── gdb_bt_all.txt        # 全线程调用栈（branch_A）
│   ├── gdb_deadlock_bt.txt   # 死锁全线程栈（branch_B）
│   ├── gdb_bt_pipe_socket.txt # 管道/Socket 阻塞栈（branch_D）
│   ├── gdb_info_signals.txt  # 信号配置信息（branch_E）
│   └── gdb_sampling.txt      # 连续栈采样（branch_G）
├── proc/                     # 进程 procfs 快照
│   ├── status                # /proc/[pid]/status
│   ├── wchan                 # /proc/[pid]/wchan
│   ├── stack                 # /proc/[pid]/stack
│   ├── sched                 # /proc/[pid]/sched
│   ├── maps                  # /proc/[pid]/maps
│   ├── syscall               # /proc/[pid]/syscall
│   ├── fd_list               # /proc/[pid]/fd/ 目录列表
│   ├── io                    # /proc/[pid]/io
│   ├── limits                # /proc/[pid]/limits
│   └── signal_status.txt     # 信号位图（branch_E）
├── sys/                      # 系统级状态快照
│   ├── locks                 # /proc/locks
│   └── sysrq-trigger         # sysrq-w 输出（branch_F, 需root）
└── binary                    # 【可选】目标二进制文件
```

执行入口（无目录时自动采集）：

```bash
cd <工作目录>
# 使用技能自动采集并分析
```

---

## 第二节：分析策略（并行双轨，交叉验证）

**OS 状态分析和进程内省分析应同时进行，而非二选一。** 两条轨道相互独立推进，最终交叉比对以确认根因。

```
┌─────────────────────────────────────────────────────────────────┐
│                    并行双轨分析模型                                │
│                                                                 │
│  轨道一：OS 状态分析（系统侧）    轨道二：进程内省分析（进程侧）    │
│  ────────────────────────        ────────────────────────       │
│  从 procfs/sys 快照出发，        从 gdb/strace/lsof 出发，       │
│  逆向推断进程为何不运行          正向追踪进程卡在哪条路径上        │
│                                                                 │
│  回答：进程停在哪个内核状态？    回答：进程在用户态等什么资源？     │
│        wchan 什么？                   锁/IO/信号/管道？          │
│        blocking 在哪？               哪条代码路径？              │
│                                                                 │
│            ↓                                   ↓                │
│            └────────────── 交叉验证 ────────────┘                │
│                                                                 │
│  见：第三节（统一分析流程：分支决策→双轨并行→交叉验证→输出）       │
└─────────────────────────────────────────────────────────────────┘
```

**两条轨道的分工与互补**：

| | OS 状态轨道 | 进程内省轨道 |
|--|------------|-------------|
| **优势** | 进程的实时/快照内核状态；是否在 D 状态、等待什么事件；无需 gdb/符号 | 用户态精确等待点；锁持有关系、线程间依赖图；代码行级别的阻塞路径 |
| **局限** | 无法区分用户态具体等待链；wchan 只显示内核入口点（如 `futex_wait_queue_me`）| 需要进程可 ptrace（`gdb -p`）；高负载下 attach 可能阻塞；符号缺失时栈的精度下降 |
| **典型盲区** | 无法发现用户态应用层的 ABBA 死锁锁名；不知道进程在等哪个文件描述符的具体写入 | 无法知道进程为何被内核放在 D 状态不可中断 |

**何时两条轨道都必须做**：有目标进程且有符号/调试信息时，两条轨道**必须同时进行**，最终通过交叉验证收敛到高置信度结论。

**何时只能走 OS 轨道**：无权 ptrace、无调试符号、进程已终止只剩 procfs 快照时，仅走 OS 轨道分析，但应明确标注分析局限性。

---

## 第三节：统一分析流程（分支决策 → 双轨并行 → 交叉验证 → 输出）

本节将"执行总览 + OS 轨道 + 内省轨道 + 交叉验证"融合为一条可直接照做的统一流程。

> 执行约束：
> - `gdb -p <pid>` 必须在生产环境经用户确认后方可执行（attach 会暂停进程）；
> - `strace -p <pid>` 会降低进程性能，应限时采集（-t 3s）；
> - 所有 `cat /proc/<pid>/*` 操作为只读，可安全执行。

### Step 1：启动（基线信息收集 + 分支推荐）

运行基线脚本（或手动执行以下检查）：

```bash
bash scripts/01_baseline_info.sh <pid> [work_dir]
```

基线脚本自动采集以下四类信息（后续所有步骤围绕它们推进）：

**进程状态：**
```bash
cat /proc/<pid>/status          # State: R(unning)/S(sleeping)/D(disk sleep)/T(stopped)/t(traced)/Z(zombie)
cat /proc/<pid>/wchan           # 内核等待点（如 futex_wait_queue_me, do_signal_stop）
cat /proc/<pid>/stack           # 内核调用栈（内核 2.6.35+）
cat /proc/<pid>/sched           # 调度统计（se.statistics.wait_sum > 0 表示累计等待时间长）
cat /proc/<pid>/syscall         # 当前系统调用号和参数（内核 5.x+）
```

**线程组信息：**
```bash
ls /proc/<pid>/task/             # 列出所有线程 TID
for t in /proc/<pid>/task/*/; do
  echo "=== TID $(basename $t) ==="
  cat $t/status | grep -E "^State|^Name|^Pid"
  cat $t/wchan 2>/dev/null
done
```

**进程资源快照：**
```bash
ls -la /proc/<pid>/fd/           # 文件描述符列表，辨认管道/socket/文件锁
cat /proc/<pid>/io               # IO 统计（rchar/wchar 是否增长）
cat /proc/<pid>/limits           # 资源限制（如 RLIMIT_NOFILE）
```

**系统级竞争证据：**
```bash
cat /proc/locks                  # 所有文件锁（POSIX + FLOCK）
ps -eo pid,wchan,comm --sort=wchan  # 全系统 wchan 聚合，发现同类阻塞进程
```

记录输出中的**四类关键信息**（后续所有步骤围绕它们推进）：

- **进程状态**（`State`, `wchan`, `stack`——判断进程是 R/S/D/T 中的哪种 hang）
- **线程关系**（各线程 wchan 是否相同？是否形成等待环路？）
- **资源依赖**（fd 列表是否指向 pipe/socket/文件锁？对应 `/proc/locks` 或对端 fd）
- **异常值线索**（`wait_sum` 持续增长 / `syscall` 停在同一个系统调用 / fd 指向已关闭对端 / 信号屏蔽字含 `SIGKILL` 等关键词）

### Step 2：挂起类型定界（选择分支脚本一键跑）

按 Step 1 输出推荐，执行对应分支脚本：

```bash
bash scripts/branch_X_xxx.sh <pid> [work_dir]
```

说明：每个 `branch_*.sh` 已内置 OS 侧的 procfs/sys 命令序列（覆盖 O1–O4），并在检测到 `gdb` 可用时给出进程内省侧指引（覆盖 G0–G5）。

若 Step 1 输出推荐多个分支脚本，必须按输出顺序全部执行，不可只选其一。

```
挂起类型诊断树（基于 Step 1 关键字段）
  ├─ wchan="futex_wait_queue_me"                    → 分支A: futex 锁等待
  │     └─ 测：`gdb thread apply all bt` 确认锁持有者
  │
  ├─ wchan="do_futex" 或 futex 相关                  → 分支B: 死锁（ABBA/lock ordering）
  │     └─ 测：`gdb thread apply all bt full` 对比各线程锁顺序
  │
  ├─ /proc/locks 有与目标进程 fd 相关的锁条目          → 分支C: 文件锁竞争
  │     └─ 测：`lslocks` + `lsof -p <pid>` 确认持有者
  │
  ├─ fd 含 pipe/socket + wchan="pipe_read/poll_schedule"
  │  或 sock_rcvmsg/sock_sendmsg                       → 分支D: 管道/Socket 阻塞读写
  │     └─ 测：`fuser <pipe_inode>` + 对端 fd 检查
  │
  ├─ State="T" (stopped) 或 "t" (traced)             → 分支E: 信号停止/跟踪
  │     └─ 测：`cat /proc/<pid>/status | grep -i SigCgt`
  │         `gdb -p <pid> -batch -ex "info signals"`
  │
  ├─ State="D" (D 状态 uninterruptible sleep)          → 分支F: 内核 D 状态阻塞
  │     └─ 测：`cat /proc/<pid>/stack` 确认内核阻塞点
  │         `/proc/<pid>/wchan` 确认等待事件
  │
  ├─ State="S" 且 wchan 周期性变化 → 非 hang         → 非故障，提供性能分析建议
  │
  └─ 无明显 procfs 异常但进程不做功                     → 分支G: 用户态死循环/空转
       └─ 测：`gdb -p <pid> -batch -ex "bt"` 多次采样
           `perf top -p <pid> -s symbol` 确认热点
```

**分支脚本对应列表**（各脚本位于 `scripts/` 目录）：

| 分支 | 场景 | 脚本 |
|------|------|------|
| A | futex 锁等待 | `branch_A_futex_wait.sh` |
| B | 死锁（ABBA） | `branch_B_deadlock.sh` |
| C | 文件锁竞争 | `branch_C_filelock.sh` |
| D | 管道/Socket 阻塞 | `branch_D_pipe_socket.sh` |
| E | 信号停止/跟踪 | `branch_E_signal_stop.sh` |
| F | D 状态阻塞 | `branch_F_d_state.sh` |
| G | 用户态死循环 | `branch_G_user_loop.sh` |

---

### 第三步：OS 状态分析（回答"进程在系统侧处于什么状态？阻塞在哪个内核路径？"）

在分支脚本输出基础上，完成并固化四步证据链：

- **O1 进程状态快照**：确认 `State`（R/S/D/T/t）、`wchan`、`stack` 内核级等待路径
- **O2 线程组一致性检查**：所有线程是否在同一个阻塞点？还是形成等待图？
- **O3 系统级竞争证据**：`/proc/locks` 锁持有者是否存活？对端 fd 是否存在且可写？
- **O4 独立归因**：仅基于 OS 侧客观数据，给出"进程在系统侧被什么机制阻塞"

输出（供后续交叉验证使用）：

```
进程状态：State=<D/S/T>  wchan=<func_name>
内核阻塞路径：<stack 输出>
线程状态一致性：<所有线程同阻塞点 / 形成依赖环 / 线程已退出>
OS 侧阻塞根因假设：<一句话>
```

---

### 第四步：进程内省分析（有 gdb/ptrace 权限时必做；回答"进程在等什么资源？哪条代码路径？"）

#### G0：连接可行性检查（防止 attach 生产进程造成负面影响）

```bash
# 检查是否可 ptrace
kill -0 <pid> 2>/dev/null || { echo "PID不存在"; exit 1; }
cat /proc/sys/kernel/yama/ptrace_scope  # 0=任意, 1=同进程, 2=root-only, 3=no-attach
# 检查调试符号
gdb --batch -nx -ex "info sharedlibrary" -p <pid> 2>&1 | head -5
```

ptrace_scope > 0 时需 root 或 `sudo`。

#### G1：全线程调用栈采集（核心证据）

```bash
gdb --batch -nx -ex "thread apply all bt full" -p <pid> 2>&1
```

核心分析目标：
- 各线程在哪个函数停留（`pthread_cond_wait`, `__lll_lock_wait`, `read`, `write` 等）
- 是否有线程**同时持有锁**又**等待另一把锁**（ABBA 死锁关键信号）
- 是否有线程卡在 `accept` / `connect` / `recvfrom` / `sendto` 等网络调用

#### G2：锁关系推导（死锁分支强制）

```bash
gdb --batch -nx \
  -ex "thread apply all bt full" \
  -ex "info threads" \
  -p <pid>
```

对每一帧，标记：
```
Thread N: 持有锁 L1（pthread_mutex_t @0x7f...）→ 等待锁 L2（pthread_mutex_lock @0x7f...）
```
对齐标记：若 Thread A 持有 L1 在等 L2，Thread B 持有 L2 在等 L1 → ABBA 死锁确认。

#### G3：futex 深层验证（分支 A/B 强制）

```bash
# 查看 futex 等待者
gdb --batch -nx -ex "print (struct robust_list_head*) pthread_getattr_np(...)" -p <pid>
# 或更直接：
cat /proc/<pid>/maps | grep "\[stack"
# 用 crash/drgn 工具分析内核 futex 状态（需要内核符号）
```

#### G4：文件描述符状态验证（分支 C/D 强制）

```bash
# 查看每个 fd 详情
for fd in /proc/<pid>/fd/*; do
  link=$(readlink $fd)
  echo "$(basename $fd) -> $link"
  # 若为 pipe
  if [[ $link == pipe:* ]]; then
    # 从全系统范围找 pipe 对端
    find /proc/*/fd -lname "$link" 2>/dev/null | grep -v "/proc/$pid/"
  fi
done
```

#### G5：反向信号验证（分支 E 强制）

```bash
# 查看进程信号状态
cat /proc/<pid>/status | grep -E "^Sig(Q|Cgt|Blk|Ign)"
# SigCgt: caught 的信号集合
# SigBlk: blocked 的信号集合
# SigIgn: ignored 的信号集合

# 检查 STOP 信号：
# SIGSTOP 不可被阻塞/忽略，所以 `State=T` 意味着已收到 SIGSTOP
# 确认发送者：
#  - gdb 等调试器
#  - `kill -STOP <pid>`
#  - `kill -SIGSTOP <pid>`
```

#### G6：执行流采样验证（分支 G 强制——用户态死循环）

```bash
# 连续采样 bt 3-5 次，间隔 0.5s
for i in {1..5}; do
  echo "=== Sampling $i ==="
  gdb --batch -nx -ex "bt" -p <pid> 2>&1
  sleep 0.5
done

# 或使用 perf 定位热点
perf top -p <pid> -s symbol -d 1 -n 20 2>/dev/null
```

进程内省轨道输出格式：

```
GDB 连接状态：[成功 / 失败（原因）]
线程数量：<N>
线程概要：
  Thread 1: <func_name+offset> 等待类型：[锁/IO/信号]
  Thread 2: <func_name+offset> 等待类型：[锁/IO/信号]
  ...
锁关系图（如有死锁）：
  Thread A: 持有 L1→等待 L2
  Thread B: 持有 L2→等待 L1
  => ABBA 死锁确认
资源依赖链：
  [<pid>/Thread N] → [资源类型] → [持有者/状态]
内省侧根因假设：<一句话>
```

---

### 第五步：交叉验证（双轨汇合，冲突仲裁，置信度收敛）

对每条证据做对齐检查：

| 验证维度 | OS 状态结论 | 内省结论 | 是否吻合？ |
|---------|------------|---------|-----------|
| 阻塞点 | wchan=`<futex_wait_queue_me>` | gdb bt 在 `__pthread_cond_wait` | □ 吻合 □ 不符 |
| 阻塞资源 | `/proc/locks` 有等待条目 | `lsof` 确认 fd 指向锁文件 | □ 吻合 □ 不符 |
| 线程关系 | 所有线程 wchan 为 futex | gdb 显示多线程形成锁等待环 | □ 吻合 □ 不符 |
| 信号状态 | State=T, SigBlk 含关键信号 | gdb `info signals` 确认信号屏蔽 | □ 吻合 □ 不符 |
| 管道/Socket | fd 指向 pipe, wchan 为 pipe_read | 对端 fd 已关闭/缓冲区满 | □ 吻合 □ 不符 |

不一致时的仲裁原则：

```
wchan vs gdb bt 不一致：
  优先信任 wchan（内核事实），gdb bt 可能因 ptrace 中断点引入偏差
资源依赖不符：
  /proc/locks 与 lsof 不一致时，优先信任 /proc/locks（lsof 可能因权限受限）
状态冲突：
  State=S 但 wait_sum=0 => 进程未 hang，只是睡眠等待
  重新评估是否为"hang"还是"正常等待"
```

置信度收敛：

- **高**：两轨完全吻合 + 反事实验证通过（已有阻塞点和调用栈对应）
- **中**：两轨基本吻合，但有 1 个维度依赖推断；或仅完成 OS 轨道
- **低**：两轨存在矛盾且无法解释；或证据链缺失超过两环节
- **无法确定**：进程已恢复/终止，只留下 procfs 残存快照

常见误判陷阱（用于复核结论质量）：

- **gdb attach 改变了进程状态**：ptrace 会让进程暂停，导致 wchan 偏离实际阻塞点；应优先信任 attach 前的 procfs 快照
- **wchan 不唯一**：一个函数内有多个阻塞路径，wchan 只显示入口；需结合 stack 确认精确路径
- **/proc/*/stack 被截断**：内核默认 4K 栈输出，大深度调用栈可能不完整；用 `echo t > /proc/sysrq-trigger` 获完整 trace
- **假死真忙**：State=R 的进程不做功 = 用户态死循环，此时 gdb bt 连续采样即可确认
- **kill -9 杀不死**：通常为 D 状态或 zombie 状态——D 状态不可杀（等待 IO），zombie 需父进程 wait

---

### 第六步：最终输出（按第九节模板落盘）

将 Step 3/4/5 的输出填入第九节报告结构，并显式写清：结论、证据链、排除项、修复建议、验证建议。

---

## 第四节：轨道一 —— OS 状态分析（系统侧分析）

本节已合并进第三节的统一流程（Step 3）。

---

## 第五节：轨道二 —— 进程内省分析（进程侧分析）

本节已合并进第三节的统一流程（Step 4）。

---

## 第六节：交叉验证与结论收敛（双轨汇合）

本节已合并进第三节的统一流程（Step 5）。

---

## 第七节：挂起类型决策树（两条轨道共用）

本节内容已合并进第三节的统一流程（Step 2）。

---

## 第八节：注意事项与置信度评级

本节内容已合并进第三节的统一流程（Step 5）。

---

## 第九节：最终报告结构

```
## 挂起概要
  挂起模式：<futex 等待 / ABBA 死锁 / 文件锁竞争 / 管道阻塞 / Socket 阻塞 / 信号停止 / D 状态 / 用户态死循环>
  置信度：<高/中/低/无法确定>
  分析轨道：[双轨（OS + 内省）| 单轨（仅 OS）]
  目标进程：<PID> <进程名>
  挂起时长：<预估时间范围>

## OS 状态轨道结论
  进程状态：State=<D/S/T/R>  wchan=<func+offset>
  内核阻塞路径：<cat /proc/<pid>/stack 输出>
  线程组状态：<线程数 / 各线程 wchan / 状态一致性>
  OS 侧阻塞根因假设：<基于系统级状态>

## 进程内省轨道结论（有 ptrace 权限时填写）
  GDB 连接状态：<成功/失败>
  线程调用栈概览：
    Thread 1: <func> @<addr> — <等待类型>
    Thread 2: <func> @<addr> — <等待类型>
    ...
  锁/资源依赖图（如适用）：
    [Thread A] —持有→ [Lock L1] —等待→ [Lock L2] ←持有— [Thread B]
  内省侧根因假设：<基于 gdb 数据的推断>

## 交叉验证结果
  阻塞点吻合：  □ 是  □ 否（差异说明：<...>）
  资源依赖吻合：□ 是  □ 否（差异说明：<...>）
  线程关系吻合：□ 是  □ 否（差异说明：<...>）
  信号状态吻合：□ 是  □ 否（差异说明：<...>）
  综合判断：<两轨结论是否一致，若有矛盾如何解释>

## 完整因果链（双轨收敛后）
  [触发条件] → [资源竞争/锁顺序/信号] → [进程挂起状态]
  → [OS 级阻塞] ↔ [用户态等待路径] → [进程无响应]

## 排除的替代假设
  - <假设X>：排除原因 <...>
  - <假设Y>：排除原因 <...>

## 修复建议
  短期恢复：
    <具体恢复操作，如 kill -CONT / 重启 / 释放文件锁>
  根本修复：
    <代码级修改方案：锁顺序调整/超时机制/信号处理修正>
  预防措施：
    <监控指标 / 代码审查要点 / 测试覆盖>

## 验证建议
  <如何确认根因 + 如何验证修复有效（压测/模拟/同类场景验证）>
```

---

## 第十节：参考文件

- `references/procfs_cheatsheet.md`：进程 procfs 关键文件速查（status/wchan/stack/sched/syscall/fd 解读）
- `references/gdb_commands_for_hang.md`：gdb hang 诊断命令速查（thread apply all bt/信号检查/锁分析/采样）
- `references/lock_analysis_patterns.md`：死锁与锁竞争分析模式速查（futex/posix locks/file locks/ABBA）
- `references/pipe_socket_diagnosis.md`：管道与 socket 阻塞故障诊断方法
