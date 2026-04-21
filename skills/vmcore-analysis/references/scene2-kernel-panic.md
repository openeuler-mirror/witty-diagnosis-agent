# 场景 2：内核崩溃 / panic / oops — 方法论

> **【Agent 强制】** 满足**任一**条件即须用 **Read 工具读取本文件全文**（不得只读 SKILL.md 里的摘要）：① 准备写场景 2 根因/结论；② **`bt`/`log`** 已出现 `release_task`、`__exit_signal`、`set_pid_unused`、`__change_pid`、`task_pid_reserved`、`detach_pid` 等；③ 已打开 **`scene2_panic_*.log`** 或跑过 **`scene2_kernel_panic.sh`**。  
> **路径**（相对本 Skill 根目录）：`references/scene2-kernel-panic.md`

与 **SKILL.md** 场景 2 配套。采集以 **`scene2_kernel_panic.sh`** 为准。

**主文定位**：规定**证据顺序、硬约束与触发式检查**；具体 `struct` 字段、`rd`/`ps` 等由分析过程按需展开。**下文 §1 已含按需加深要点**。

**阅读时机**：已读过采集结果中的 **`log`、`bt`、`bt -F`**（专项 **[6/13]**），并准备对崩溃 **RIP** 做 **`dis`** 或撰写根因。若尚未读栈与日志，可只读上文【Agent 强制】与 §1；**一旦写根因或命中 PID/退出栈符号，须读全文**。

---

## 1. 通用主链（广度入口）

**建议顺序**：  
`log`（首次 `panic` / `oops` / `kernel BUG` / `invalid opcode` 等）→ `sys`（`PANIC:`、CPU、任务、**PARTIAL** 等）→ `bt` / `bt -l` / `bt -f` / **`bt -F`** → **`dis -r` / `dis -l`（内核态 RIP）** → 按需 **`mod`、`irq`、`runq`、`ps -G`（或交互 `ps`）、`bt -a`**。

**【易错 — `bt` 顶栏 ≠ Identity 已成立】**  
`crash` 打印在 **`bt` 最上方的** `PID: … TASK: …` 表示 **崩溃上下文下的 current**（或等价）。**`release_task` / `__exit_signal` 的形式参数 `p` 是正在回收的另一 `task_struct *`，二者地址可以不同。**  
**禁止**用「整段栈都在退出链、进程名看起来一样」或「主观上同一任务」**代替** §4：必须在 **`__exit_signal` / `release_task`** 等帧用 **`bt -F` / `bt -f`** 读出 **帧内标注的 `task_struct` 地址**，与 **`task` 命令给出的 TASK 地址**做**逐字比较**。

**与场景分流**：若以 **页故障**（如 `unable to handle kernel paging request` 等）为**主证据**，优先走 **SKILL 场景 1** 工作流；本文件以 **`log` + `bt` + `dis`** 为主的 **BUG_ON / trap / 非法指令** 类路径为默认。

**按需加深（仍属主文，与上链配合）**：  
- **退出 / detach 路径**：专项 **[6/13] `bt -F` 已采时，写 Identity **必须**引用其中 **`__exit_signal`/`release_task` 帧**的对象地址；缺则交互补 **`bt -F`/`bt -f`**，**不可**只复述顶栏 TASK。  
- **`sys` 标明 PARTIAL dump** 时，对 per-CPU、模块符号、全栈等结论宜**保守**，交叉 **`log`** 与其它场景。  
- **多 CPU**：**`bt -a`**；**PANIC CPU** 须与当前 **`bt` 帧 / task** 一致。  
- **模块**：**`mod`**；RIP 在模块内时 **`dis`** 配合 **`.ko`/调试符号**。  
- **调度/中断**：怀疑与崩溃 CPU、关中断、软中断风暴相关时加 **`runq`、`irq`**。  
- **对象**：**`bt`/`dis` 已有类型线索**时 **`struct <type> <addr>`** 试解；无类型勿强套 **`struct`**。  
- **寄存器**：**`bt -r`** 数值须先经 **`dis -r`** 再比对或接 **场景 1 / `check_bitflip`**（见 SKILL）。

---

## 2. 硬约束（模型须遵守）

1. **内核态 RIP**：解释寄存器、指针、**BUG 分支**前，须对 **RIP** 做 **`dis -r`**（必要时 **`dis -l`**）；勿将 **RIP** 当 **`struct`** 地址解析。  
2. **退出 / detach / PID 栈**：**`bt`** 中出现 **`release_task`、`exit_notify`、`__exit_signal`、`detach_pid`、`__change_pid`** 等时，**必须**做 **§4 Identity**（除非已明确证明与退出路径无关）。  
   **禁止**仅凭 **`bt` 顶栏 `TASK:`** 或「栈上都是退出符号」断言 **current 与正被 `__exit_signal`/`release_task` 处理的 `task_struct *` 一致**。**必须**在 **`__exit_signal`（及需要时的 `release_task`）帧**用 **`bt -F`/`bt -f`** 得到 **帧内 `task_struct` 地址**，与 **`task` 输出的 TASK 地址**做**相等或不等的明确结论**（可与 **RBP** 等寄存器互证，但**不得以寄存器替代帧内对象读出**）。  
3. **预留 / PID 符号**：**`bt`/RIP** 出现 **`set_pid_unused`、`task_pid_reserved`**（及 **`__change_pid`** 与 **`free_pid`** 同链）时，结论**须同时**覆盖 **§4 Identity（帧级地址比较）**、**detach 主体 task** 与 **预留路径上下文**；**禁止**在未完成前述论证前，**单独**以「全局未初始化」结案。  
   **`px reserved_data` / `px reserve_idr` 为 NULL**（或 **`dis`** 显示对 `reserved_data` 判空进入 BUG）只说明 **BUG 分支被命中**，**不能替代** §4，也**不能**在未完成帧级 Identity 时单独据此写「仅初始化问题」结案。  
4. **与自动化规则对齐**：**§2** 与 **§3** 的「条件 → 论证」应与 **`identity-constraints`** 等 Agent 规则同源，避免细则与代码侧触发不一致。

---

## 3. 触发器 → 必做论证

| 条件（来自 `log` / `bt`） | 必做论证 |
|---------------------------|----------|
| `kernel BUG` / `invalid opcode` 等 + 内核 **RIP** | **`dis -r` RIP**；对齐断言/控制流/访存 |
| **`release_task` / `__exit_signal` / `exit_notify`** | **§4 Identity**，且**须含**：**`bt -F`/`bt -f` 在 `__exit_signal`（及必要时 `release_task`）帧读出的 `task_struct *` 地址** vs **`task` 的 TASK 地址 |
| 上表 + **`detach_pid` / `__change_pid` / `free_pid`** | 上列 Identity + **当前 detach 的 pid 从属于哪一 `task_struct`** |
| 再叠加 **`set_pid_unused` / `task_pid_reserved`** | 上列 + **`__change_pid`（及同类）内预留逻辑是否错误依赖 `current` / `current->group_leader`**（**dis + 源码/vmlinux**） |
| **`set_pid_unused`** 等对 **`reserved_data` / `reserve_idr`**（名以 vmlinux 为准）的 **BUG_ON** / **`px` 为 NULL** | **先**完成上列 **Identity（帧级）** 与 **误入预留路径**；**再**写 `reserved_data`/初始化；**不得**仅用 **`px` NULL** 或「判空分支」单独结案 |

**表注**：若 **`bt -F` 显示两地址不等**，**禁止**在结论中写「无 Identity 问题」；应进入 **§5** 与 **`__change_pid`/`current` 混用** 论证。

---

## 4. Identity：调用上下文与操作对象

**问题类**：形式参数为 **`struct task_struct *p`**（或等价）的路径上，若实现仍按 **`current` / `current->group_leader`** 处理与 **`p`** 同一生命周期的事务，则在 **`exit_notify` 等按链表对多个 task 调用 `release_task`** 时，**`current` 与正被处理的 task 可能不一致** → UAF、错误 leader、**BUG_ON**。

**最小步骤**：  
专项采集已含 **`bt -F`** 时，**优先用帧内对象类型与地址**做 Identity，再决定是否补交互命令。  
**`task`**（或 PANIC）记录 **current** 的 **`task_struct` 地址** → **`bt -F` / `bt -f`** 查看 **`__exit_signal` 等帧**是否在处理**另一**地址 → 比较二者 → 不一致则 **current / 形参混用** 升为首要假设 → 可再按需 **`struct task_struct`**（如 `group_leader`、`thread_group`、`exit_state`、`signal->live`）、**`rd`** 加强论证。  
**反例（无效论证）**：「所有栈帧 / 顶栏 TASK 都是同一进程」却**未**给出 **`__exit_signal` 帧内 `task_struct` 地址**与 **顶栏 TASK** 的**逐地址比较**；或 **RBP** 已指向 **`ffff…c080`** 与 **顶栏 `ffff…` 另一地址** 仍声称 Identity 一致。

**收束**：「两地址是否同一对象」与 **`dis -r` 在 RIP 处语义**一致时，本段可结。

---

## 5. 预留 PID 与 `__change_pid`：上下文不变量

**适用范围**：启用 **`CONFIG_PID_RESERVE`**（或等价预留 PID）的**树/补丁**；符号名以 **vmlinux** 为准。本节描述**实现须满足的不变量**，不绑定单一业务或发行版叙事。

**调用关系（与栈对齐）**：  
`release_task(p)` → `__exit_signal(p)` → `detach_pid` / `__unhash_process` → **`__change_pid(task, …)`**  
此处 **`task`** 与上层 **`p` 一致**，**不得默认 `task == current`**。

**反模式（须 dis + 源码验证）**：在 **`free_pid(pid)` 之后**，若以 **`task_pid_reserved(current)`** 且 **`set_pid_unused(current->group_leader->pid, current->pid)`**（或等价）实现归还，则将 **「当前运行 task」** 与 **「本次 detach 的 `task`」** 错误耦合；当 **`release_task` 处理对象非 `current`** 时，可导致 **误入 `set_pid_unused`、预留全局状态与预期不符、断言失败**，表现为 **`kernel BUG at …`** 与 **`invalid opcode`** 等。

**实现/根因表述约束**：预留归还须以 **`__change_pid` 的 `task`（及 `group_leader`、线程组 PID 语义）** 为据；仅当可证明 **恒有 `current == task`** 时方可使用 **`current`**。常见修复方向：**`task_pid_reserved(task)`**，**`set_pid_unused` 参数与 `free_pid` 所关联的 task/leader 一致**（具体 API 以树为准）。

---

## 6. 缺陷类「最小特征向量」（检测用）

下列**同时或递进出现**时，应按 **§3 表** 满配论证（非个案描述，仅模式归纳）：

- **栈**：经 **`exit_notify` → `release_task` → `__exit_signal`**，并可出现 **`detach_pid` / `__change_pid` / `set_pid_unused`**。  
- **log**：**`kernel BUG at …`**，常继以 **`invalid opcode`**。  
- **关键论证**：**`task` 所示 current** 与 **`bt -F`/`bt -f` 中 `__exit_signal` 所处理 `task_struct`** **不一致**，且 **RIP/dis** 表明 **预留路径依赖 `current`/`group_leader`**。

---

## 7. 结论结构（短模板）

1. **`log` / `bt`**：异常类型、**RIP** 函数、关键帧。  
2. **Identity**：current 与帧内处理对象是否同一 **`task_struct`**。  
3. **若存在预留 PID 符号**：**`__change_pid`（及同类）** 是否 **以 `task` 为上下文**，是否 **误用 `current`**；与 **dis** 是否一致。  
4. **禁止**：在 (2)(3) 未澄清时，仅以「全局未初始化」结束。

**说明**：推理过程、补充命令与字段级解读写入分析正文；**结论须覆盖**上表要点。

---

**维护**：与本目录 **SKILL.md** 场景 2、`scripts/scene2_kernel_panic.sh` 同步；评审副本可置于仓库 **`test/scene2-kernel-panic.md`**。
