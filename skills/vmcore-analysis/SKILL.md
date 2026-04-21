---
name: vmcore-analysis
description: 通过 crash 工具深度分析 Linux vmcore 文件，解决各类操作系统级疑难故障。核心能力包括：定位 Kernel Panic 和系统意外崩溃的根本原因；以及通过分析内存转储快照，诊断系统卡死、死锁、资源耗尽及性能异常等问题。提供从环境检查到根因报告生成的全流程指导。
---

# Analyze Vmcore Files (分析 Vmcore 文件)

本 Skill 旨在指导如何通过 `crash` 命令系统化地分析 `vmcore` 文件。

## Skill 文件夹目录说明

本 Skill 的目录结构：

```text
skills/vmcore-analysis/
├── SKILL.md                    # Skill 主文档（本文档）
├── references/
│   └── scene2-kernel-panic.md  # 场景 2 方法论细则（可选阅读）
├── scripts/                    # 辅助脚本
│   ├── check_environment.sh    # 环境检查脚本
│   ├── check_bitflip.sh        # Bit Flip 检查脚本
│   ├── scene_collect.sh        # 场景收集总入口（支持 --scene/--auto）
│   ├── scene1_bitflip.sh       # 场景1：比特翻转 / Bit Flip 专项收集
│   ├── scene2_kernel_panic.sh  # 场景2：内核崩溃信息收集
│   ├── scene3_oom.sh           # 场景3：OOM/内存信息收集
│   ├── scene4_deadlock.sh      # 场景4：死锁/挂死信息收集
│   ├── scene5_network.sh       # 场景5：网络故障信息收集
│   ├── scene6_filesystem.sh    # 场景6：文件系统故障信息收集
│   └── scene7_hardware.sh      # 场景7：硬件/驱动故障信息收集

```

**注意：** 这是 Skill 本身的目录结构，与故障目录（如 `pcie_panic/`）是分开的。`references/` 下为可选深读，不增加场景编号。

## 远程服务器故障目录结构

用户的故障目录结构：

```text
pcie_panic/     # 故障文件夹 
├── src/        # 可选，源码路径，如果存在则要针对问题进行源码分析 
├── crash       # crash命令 
├── vmlinux     # vmlinux命令  
└── vmcore      # vmcore文件
```

```bash
cd pcie_panic && ./crash ./vmlinux vmcore
```

## 环境检查与配置

**优先级规则：**
1. 用户已提供完整命令 → 直接执行，跳过环境检查
2. 用户仅提供路径参数 → 使用用户参数运行 `scripts/check_environment.sh`
3. 用户未提供信息 → 使用默认值
4. 检查脚本返回非0 → **立即停止**，反馈错误

```bash
# 基本用法
./scripts/check_environment.sh

# 指定路径
./scripts/check_environment.sh \
  --crash "/custom/path/to/crash" \
  --vmlinux "/custom/path/to/vmlinux" \
  --vmcore "/custom/path/to/vmcore"
 ```

## 分析工作流

### 第一步：基础信息收集（批量执行）

**⚠️ 重要：所有 crash 命令应在同一个会话中批量执行**

#### 使用 skill 文件夹中的脚本 `./scripts/scene_collect.sh` 批量收集


**执行命令**

```bash
# 自动识别场景（会先进行基础收集再判断）
./scripts/scene_collect.sh --auto \
  --crash /custom/path/to/crash \
  --vmlinux /custom/path/to/vmlinux \
  --vmcore /custom/path/to/vmcore
  
# 指定场景（1-7），示例：场景2 = 内核崩溃
./scripts/scene_collect.sh --scene 2 \
  --crash /custom/path/to/crash \
  --vmlinux /custom/path/to/vmlinux \
  --vmcore /custom/path/to/vmcore


```

**输出结果（与 `scene_collect.sh` 行为一致）**

| 模式 | 终端 | 磁盘日志（均在**运行命令时的当前工作目录**，一般为故障目录） |
|------|------|----------------------------------------------------------------|
| `--auto` | 打印 `[AUTO] 日志关键字分析结果`、命中行、`[AUTO] … 场景 N — …`，以及 **`scene_collect_autodetect_*.log` 保存路径**；**当前** `scene_collect.sh` 末尾**未** `exec` 专项脚本（该段为注释），需按识别出的 N **手动**执行下表对应脚本 | 生成 **`scene_collect_autodetect_YYYYMMDD_HHMMSS.log`**（单次 crash 会话中的 **`sys`/`log`/`bt`/`mod`**，**不含全量 `ps`** 以缩短大 vmcore 耗时；**场景 1** 对**整份**日志匹配 `Page Fault` / `Data Abort` / `unable to handle kernel paging request` 任一即最优先；**场景 7**（硬件）关键字仅在内核 `log` 段匹配） |
| `--scene N` | 校验 `N` 为 1–7；**当前**同样**不会**自动执行专项脚本（同上注释逻辑） | **不**生成 `scene_collect_autodetect_*.log` |

**说明（第一阶段）：** 以终端输出与（`--auto` 时）**`scene_collect_autodetect_*.log`** 为主。专项深挖请**手动**执行：`scene1_bitflip.sh`、`scene2_kernel_panic.sh`、`scene3_oom.sh`、`scene4_deadlock.sh`、`scene5_network.sh`、`scene6_filesystem.sh`、`scene7_hardware.sh`（与场景编号一一对应）。各脚本会按实现写出专项日志（文件名因场景而异），见下文各场景小节。

### 第二步：根据故障类型深入分析

**`scene_collect.sh --auto` 与场景 1：** 对 **`scene_collect_autodetect_*.log` 全文**（同一次 crash 批量输出中的 `sys` / `log` / `bt` / `mod`，**无全量 `ps`**）做关键字匹配，若命中以下**任一**，则自动识别时**最优先**选用 **场景 1**（优先级高于场景 7～2）：`Page Fault`、`Data Abort`、`unable to handle kernel paging request`。

#### 故障类型快速判断

| 故障类型 | 关键字特征 | 对应场景 |
|---------|-----------|---------|
| **比特翻转 / 页异常优先** | `Page Fault`、`Data Abort`、`unable to handle kernel paging request`（`--auto` 下由 `scene_collect.sh` 匹配整份 autodetect 日志）；结合非全 0 故障地址、寄存器数据异常 | 场景 1 |
| **内核崩溃** | `Kernel panic`、`Call Trace`、`RIP`、`oops` | 场景 2 |
| **内存问题** | `Out of memory`、`OOM`、`killed process`、`Memory cgroup out of memory` | 场景 3 |
| **系统挂死** | 无明显错误但系统无响应；或进程状态为 `D`、`UN` | 场景 4 |
| **网络故障** | 典型接口名（如 `eth0`、`ens33`、`enp0s1`、`bond0`）、`link down`、`tx timeout`、`NETDEV WATCHDOG` 等；**不用**裸词 `network` 或单段 `eth`/`ens`（易与其它串词误匹配） | 场景 5 |
| **文件系统** | `EXT4-fs error`、`XFS error`、`I/O error`、`remounting read-only` | 场景 6 |
| **硬件故障** | **事件型**日志：`Hardware Error`、`Machine Check`、`mce:`/`MCE:`、`PCIe`/`PCI`/`AER` 可纠正/不可纠正错误、`EDAC MC`、明确 **UE/CE memory** 或 **DRAM ECC error** 等；**不是** `mod` 里或**脚本全表 ps** 中出现的 `*_edac` 模块名或符号名（常态存在，不代表硬件报错） | 场景 7 |

**判断方法：** 优先以 **`--auto` 终端结论** + **`scene_collect_autodetect_*.log`**（若存在）为准。**`--auto` 下场景 1** 对整份 autodetect 输出匹配页异常类关键字；**场景 7** 仅在批量输出中的「内核 log」段做关键字匹配（避免 `mod` 等段落里的驱动符号误报）。若手动指定场景、结论与现象不符，或需复核时，在 **同一会话或后续专项日志里的 `log`/`bt`/`ps -G`（或交互全量 `ps`）** 中按上表检索核对（若已执行第二步专项脚本并生成落盘日志，亦可对照该文件）。

**根据判断结果，进入以下对应场景进行深入分析：**

#### 场景 1：比特翻转 / Bit Flip 排查

**【强制干预指令】**：根据 **`scene_collect_autodetect_*.log`（使用 `--auto` 且已生成该文件时）**，或 **同一 vmcore 分析中 `crash` 会话里的 `log` / `bt` / `bt -r` 等输出**（含交互式 `crash` 或批量输入），若出现 **非法内核虚拟地址访问**（如 `Page Fault`、`Data Abort`、`unable to handle kernel paging request`），且 **故障地址（FAR/CR2）不为显然的全 0**，**必须优先进行硬件单比特（SEU）相关排查**（`scene_collect.sh --auto` 命中上述关键字之一时会最优先识别为**本场景（场景 1）**）。

**进入条件与判定要点**

- 出现上述 **非法寻址类** 异常，且 **FAR/CR2 非全 0**。
- 能结合 **`dis -r`** 与内核结构，为某一对 **「预期值 ↔ 现场值」**（参与地址形成或控制流的数据字）建立 **一对一** 比较时，应 **优先** 用 `check_bitflip.sh` 做 **1-bit** 校验。
- **`check_bitflip.sh` 的两个参数** 必须是 **② 中根据 `dis -r` + `kmem`/`struct`/布局推出的「预期字」与「现场字」**（如基址、索引、字段、指针），**不要把 FAR/CR2 默认当作脚本的必有或唯一操作数**。
- **不要**仅凭「地址看起来很怪」或 **只对 FAR 本身做 XOR** 就下结论：FAR 多为 **最终故障线性地址（结果）**，被翻转的更常是 **基址/指针** 或 **索引/字段** 等 **参与运算的字**。

**原理与两类典型来源（只记一次）**

- **地址侧**：除 **基指针、栈指针、函数指针** 外，**per-CPU / this_cpu** 路径在 Linux 上极常见：经 **每 CPU 区域基址 + 偏移** 形成线性地址（x86 上常表现为 **段寄存器相对寻址，如 `%gs:`**；其它架构有等价机制）。此类异常多表现为 **线性地址高位/前缀或基址整字** 与预期不符，而 **立即数/偏移仍合理**。
- **数据侧**：**CPU 号、数组下标、PID、长度/边界、PTE** 等从内存读出的字段异常（基址看似正常）。
- 两类最终都可表现为 **非法访问 → 页异常**；分析上统一：**先用 `dis -r` 写清地址公式，再选定一对「预期 ↔ 实际」做校验**。

**操作流程（三步）**

**① 采集现场（批量优先）**  
整理：**FAR/CR2**、**崩溃 CPU**、**异常指令地址（PC/RIP 等）**、**`bt -r` 寄存器**、**`bt`/`ps -G` 的 task / 栈线索**（专项脚本默认为轻量 `ps -G`；全表 `ps` 极慢，按需交互补跑）。专项采集优先执行：

```bash
./scripts/scene1_bitflip.sh \
  --crash /custom/path/to/crash \
  --vmlinux /custom/path/to/vmlinux \
  --vmcore /custom/path/to/vmcore
# 需采集 per-CPU 对象布局（crash：kmem -o，输出可能很长）时追加：--deep 或 --kmem-o
```

脚本已批量包含 `sys`、`log`、`bt`、`bt -r` 及 **`bt -l`、`bt -f`、`ps -G`（轻量）、`mod`、`kmem -i`**，便于与后续场景衔接；**`--deep` / `--kmem-o`** 会在上述基础上追加 **`kmem -o`**（与下表「按需 `kmem -o`」一致）。**全量 `ps`** 在大 vmcore 上极慢，本 skill 专项脚本默认不跑；必要时在交互式 `crash` 中单独执行 `ps`。

**链式一致**：后续凡涉及 **per-CPU 区域**，须保证 **`sys`/PANIC 中的 task、当前分析任务、`bt` 所示崩溃 CPU、以及 `kmem -o` 中选取的 `CPU N`** 指向 **同一颗逻辑 CPU**（同一 PID/task 上下文），再与 **FAR/反汇编** 对照；避免串核导致「预期基址」张冠李戴。

**不完整 dump**：若 `sys` 等显示 **PARTIAL dump** 或信息明显不全，**per-CPU/模块/符号** 可能对不齐，结论宜 **保守**，并交叉 **log** 与其它场景。

**② 追公式并取预期**  
在 **`bt` 顶层异常帧** 取 **PC/RIP**，于同一会话执行 **`dis -r <该地址>`**，写出最终有效地址的常见形式（如 **基址+偏移**、**基址+(索引<<移位)**、**per-CPU 基址+偏移** 等），判断更可疑的是 **基址/指针** 还是 **索引/字段**。可选执行 **`dis -l <同一地址>`**，对齐源码/宏语义，便于推断「应有」行为（非必跑）。

**类型与命令**：对**疑似内核对象地址**，在 **`bt`/`dis`/源码** 等下**已有候选类型名**时，**先用 `struct <type> <addr>` 试解**，判断是否结构体对象；**合理则**配合 **`struct -o`、必要时 `sym`** 继续。**明显不是**结构体语义时（**RIP/指令**、纯数值、统计、per-CPU 比对字等）用 **`dis`/`kmem`/数值与 `check_bitflip.sh`**，勿硬套 `struct`。

再 **按需** 用下表辅助取「预期侧」参考（非穷举，以 `dis -r` 实际用到的操作数为准）：

| 倾向 | 高频对象 | 常用 crash 命令（按需） |
|------|----------|-------------------------|
| 指针/基址（含 per-CPU） | per-CPU 区域、task 指针、内核/vmalloc 指针、符号地址 | 执行 **`kmem -o`**，在输出中定位 **`CPU N` 行（N 须与 `bt` 中崩溃 CPU 一致）** 得到该 CPU **per-CPU 区域基址**，与 `dis` 推得的应有线性地址或相关基址对比；另可 **`struct task_struct <addr>`**、`sym <name>`、**System.map**（若需）。**勿**仅用 PANIC 行 FAR 与脚本做默认 XOR。 |
| 索引/字段 | CPU 号、下标、结构体成员、PTE | `struct <name> <addr>`、`struct <name> -o`、`vtop <vaddr>` |

**③ 校验与结论分流**  
对 **② 中已锁定的一对「预期字 ↔ 现场字」**（十进制或十六进制）执行（参数含义见 `./scripts/check_bitflip.sh --help`）；两参数须与 **`dis` + `kmem`/`struct`/布局** 的语义一致，**非**默认填入 FAR/CR2。

```bash
./scripts/check_bitflip.sh <预期值> <实际值>
```

示例：

```bash
./scripts/check_bitflip.sh 69 134217797
./scripts/check_bitflip.sh 0x45 0x08000045
# 完整 64 位内核指针（依赖本机 python3）：例如两枚 canonical 地址仅 1 bit 不同
# ./scripts/check_bitflip.sh 0xffff8fa6fe4d5c10 0xffff8f26fe4d5c10
```

- **脚本判定为 1-bit flip** → 以 **SEU / 硬件单比特** 作为本场景 **主要根因假设** 写报告；是否再结合 **场景 7**（MCE/EDAC 等）由现场日志与流程决定。
- **非 1-bit** → **不得**仅依赖本场景结案；按「故障类型快速判断」表转入 **场景 2～7** 等软件或其它根因分析。
- **注意**：多 bit、符号扩展、字宽选错（未按指令语义成对比较）均可能误判，比对时保持 **同一语义宽度**。

---

#### 场景 2：内核崩溃 / Kernel Panic

**【Agent 强制 — 不可跳过】**  
凡进入场景 2 且**即将撰写根因**，或 **`bt`/`log` 已出现** `release_task`、`__exit_signal`、`exit_notify`、`detach_pid`、`__change_pid`、`set_pid_unused`、`free_pid`、`task_pid_reserved` **任一**，**必须**使用 Read 工具加载 **`references/scene2-kernel-panic.md` 全文**（相对本 Skill 根目录）。**SKILL.md 本节摘要不能替代该文件。**

**执行脚本（场景2）：**

```bash
./scripts/scene2_kernel_panic.sh \
  --crash /custom/path/to/crash \
  --vmlinux /custom/path/to/vmlinux \
  --vmcore /custom/path/to/vmcore
```

**典型模式（可检索）**：**Identity（调用上下文 vs 操作对象）** —— 内核路径的形式参数常为「正在处理的 `task_struct *p`」，但实现仍读 **`current` / `current->group_leader`** 时，在 **exit / detach / `set_pid_unused`** 等栈上可能表现为 **BUG_ON / invalid opcode**；专项脚本已采集 **`bt -F`** 便于对照栈帧内对象类型。

**【易错】`bt` 顶栏 `TASK:` 是 current，不等于 `__exit_signal`/`release_task` 正在处理的 `p`；Identity 必须用 `bt -F`/`bt -f` 取该帧 `task_struct *` 与 `task` 输出做地址比较（细则 §1–§3）。**

**方法论（仅摘要，细则以 `references/scene2-kernel-panic.md` 为准）：**

- **证据链**：先 **`log` / `sys` 定性**，再 **`bt` / `bt -F` 定位栈与 RIP**，再对崩溃 RIP 做 **`dis -r` / `dis -l`** 弄清**指令在做什么**，最后按需 **`struct`、模块、多 CPU、`ps`**。退出链上 **Identity 以 [6/13] `bt -F` 帧内地址为准**，不可只复述顶栏 TASK。  
- **数据与寄存器**：任何「可疑数值」须先经 **`dis -r`** 对齐语义，再谈比对；勿默认 XOR。  
- **横切（条件启用）**：若栈处于 **进程/线程退出、detach、释放 task** 一类路径，用 **`task`** 与 **`bt -F`** 核对 **`current` 与 `__exit_signal`/`release_task` 帧内 `task_struct`（形参 `p`）是否同一地址**；若栈上还有 **PID 预留/detach** 相关符号（如 **`__change_pid`、`task_pid_reserved`、`set_pid_unused`**），须核对 **`CONFIG_PID_RESERVE` / `reserved_data` 路径是否在 `__change_pid` 内误用 `current`**（细则 **§5**）。**`px reserved_data` 为 NULL** 不能代替帧级 Identity，也**禁止**未完成 Identity + 预留路径论证时**单独**以「全局未初始化」结案。

**摘要：硬约束三条（全文见细则 §2）**  
1. 解释 **RIP** 前须 **`dis -r`/`dis -l`**；勿把 **RIP** 当 **`struct`**。  
2. 退出/detach/PID 栈须做 **Identity（§4）**：**`bt -F`/`bt -f` 在 `__exit_signal` 等帧的地址** vs **`task` 的 TASK**；**禁止**仅用顶栏 TASK 断言一致。  
3. 出现 **`set_pid_unused`/`task_pid_reserved`/`__change_pid`** 等时，结论须覆盖 **帧级 Identity + detach 主体 + 预留上下文**；**`px` NULL** 仅佐证 BUG 分支，**禁止**单独据此结案。

**摘要：触发器 → 论证（全文见细则 §3 表）**  
| 条件 | 须做 |  
|------|------|  
| `kernel BUG`/`invalid opcode` + 内核 RIP | `dis -r` RIP |  
| `release_task`/`__exit_signal`/`exit_notify` | §4 Identity：**帧内 `task_struct*` 地址 vs `task` TASK** |  
| 上 + `detach_pid`/`__change_pid`/`free_pid` | + detach 的 pid 属哪一 task |  
| 上 + `set_pid_unused`/`task_pid_reserved` | + `__change_pid` 是否误用 `current`/`group_leader` |  
| `set_pid_unused`/`reserved_data` BUG 或 **`px` NULL** | **先**帧级 Identity + 误入预留路径；**再**写初始化；**不得**仅 `px` 结案 |

#### 场景 3：内存泄漏 / OOM / 内存耗尽


**执行脚本（场景3）：**

```bash
./scripts/scene3_oom.sh \
  --crash /custom/path/to/crash \
  --vmlinux /custom/path/to/vmlinux \
  --vmcore /custom/path/to/vmcore
```

**分析方法论：**

1. **确认是否真实 OOM 触发** - 在 `log` 搜索 `Out of memory`、`oom_kill_process`、`Memory cgroup out of memory`。
2. **判断内存耗尽类型** - 用 `kmem -i` 看整体内存结构，再用 `kmem -s` 找异常 slab 大户。
3. **定位“谁在吃内存”** - 专项脚本输出为 **`ps -G` 管道排序的 Top 20**；需全表再交互 `ps`。**RSS/VSZ** 与 OOM 日志互证。**task/mm/cgroup**：有候选类型时**先用 `struct <type> <addr>` 试解**是否结构体对象；**勿**强行 `struct`。
4. **判断碎片化与分配失败模式** - 用 `kmem -z`、`kmem -f`、`kmem -p` 判断是总量不足还是高阶页分配失败。
5. **补充虚拟内存视角** - 用 `vm` 观察页回收、换页与系统压力，确认是否长期内存压力导致失稳。

#### 场景 4：系统挂死 / 死锁 / 无响应


**执行脚本（场景4）：**

```bash
./scripts/scene4_deadlock.sh \
  --crash /custom/path/to/crash \
  --vmlinux /custom/path/to/vmlinux \
  --vmcore /custom/path/to/vmcore
```

**分析方法论：**

1. **先判定挂死类型** - 在 `log` 搜索 `hung_task`、`soft lockup`、`RCU stall`、`blocked for more than`。
2. **定位阻塞对象** - 用 `ps -G` 或交互 **`ps`** 筛 `D/UN`，再用 `runq` 判断是否 CPU 级阻塞或全局拥塞（专项脚本默认 `ps -G` 以省时间）。
3. **构建等待链** - 用 `bt`、`bt -a`、`bt -f` 还原线程/CPU 间的等待关系，识别循环等待。**task/锁/waitqueue**：有候选类型时**先用 `struct <type> <addr>` 试解**是否结构体对象；纯寄存器/计数值勿硬套 `struct`。
4. **检查锁证据** - 用 `waitq`、`mutex -t`、`rwlock` 验证锁竞争类型（mutex/rwlock/等待队列）。
5. **区分锁死与资源枯竭** - 结合 `kmem -i` 与 `mod` 判断是否由内存/模块异常诱发“假死锁”。

#### 场景 5：网络不通 / 网络崩溃


**执行脚本（场景5）：**

```bash
./scripts/scene5_network.sh \
  --crash /custom/path/to/crash \
  --vmlinux /custom/path/to/vmlinux \
  --vmcore /custom/path/to/vmcore
```

**分析方法论：**

1. **先从日志定性故障** - 在 `log` 搜索 `link down`、`tx timeout`、`NETDEV WATCHDOG`、驱动报错关键字。
2. **检查设备与链路状态** - 用 `net` 与 `net -d` 看网卡状态、队列与设备细节。
3. **分析协议与连接层症状** - 用 `net -s`、`net -p`、`net -a` 判断是收发异常、协议异常还是路由/邻居异常。
4. **确认是否驱动级崩溃** - 用 `mod` + `bt`/`bt -l` 判断调用栈是否落在网卡驱动函数。**`net_device`/`sock`**：有候选类型时**先用 `struct <type> <addr>` 试解**是否结构体对象；统计/计数不必 `struct`。
5. **排查中断与系统资源影响** - 用 `irq`、`ps -G`（或交互 `ps`）、`kmem -i` 判断是否由中断异常或 skb 相关内存压力引发。

#### 场景 6：文件系统只读 / 挂载异常 / IO 卡顿


**执行脚本（场景6）：**

```bash
./scripts/scene6_filesystem.sh \
  --crash /custom/path/to/crash \
  --vmlinux /custom/path/to/vmlinux \
  --vmcore /custom/path/to/vmcore
```

**分析方法论：**

1. **先识别文件系统错误类型** - 在 `log` 搜索 `EXT4-fs error`、`XFS error`、`I/O error`、`remounting read-only`。
2. **确认影响范围与挂载状态** - 用 `mount` 看是否被重挂为 `ro`，判断受影响分区与文件系统类型。
3. **定位活跃访问与阻塞点** - 用 `files` 找高频访问对象，用 **`ps -G` / 交互 `ps`** 筛 `D` 态进程确认 IO 阻塞面。
4. **检查元数据与内核路径** - 用 `super` 看超级块状态，用 `bt`/`bt -l` 判断是否卡在 IO/日志提交路径。**superblock/inode/dentry**：有候选类型时**先用 `struct <type> <addr>` 试解**是否结构体对象；仅日志/错误码而无对象地址时勿硬套 `struct`。
5. **判断是否硬件链路问题外溢** - 结合 `irq`、`mod`、`runq` 判断是否需联动场景7继续排查存储控制器/驱动。

#### 场景 7：硬件故障 / 驱动崩溃


**执行脚本（场景7）：**

```bash
./scripts/scene7_hardware.sh \
  --crash /custom/path/to/crash \
  --vmlinux /custom/path/to/vmlinux \
  --vmcore /custom/path/to/vmcore
```

**分析方法论：**

1. **先确认硬件错误签名** - 在 `log` 搜索 **事件型** 记录：`MCE`/`mce:`、`Hardware Error`、`PCIe`/`PCI`/`AER` 报错、`EDAC MC` 或明确 **UE/CE memory** / **DRAM ECC error**；不要仅凭 `mod` 列表中的 `*_edac` 模块推断硬件故障。
2. **确认崩溃归属模块** - 用 `mod` 建立驱动版本清单，再用 `bt`/`bt -l`/`bt -f` 锁定是否在驱动栈崩溃。
3. **判断影响范围** - 用 `bt -a`、`runq`、`ps -G`（或交互 `ps`）判断是单驱动故障还是系统级连锁反应。
4. **核查中断与设备侧证据** - 用 `irq`、`net -d`、`mount` 判断网卡/存储控制器是否出现同步异常。
5. **识别潜在位翻转或内存损坏** - 用 `bt -r`、`kmem -i`、`kmem -p` 检查异常值与页错误，再用 `check_bitflip.sh` 验证。**PCI/设备**：有候选类型时**先用 `struct <type> <addr>` 试解**是否结构体对象；无可用地址时以 **log** 为主，勿强行 `struct`。



### 第三步：源码分析（可选，当源码文件存在）

**前提：** src 目录存在且版本匹配


#### 源码分析流程

**第一步：版本验证**

```bash
# vmcore 侧版本
crash> sys | grep RELEASE

# 源码侧版本
head -5 src/Makefile   # VERSION / PATCHLEVEL / SUBLEVEL
```

**第二步：源码追踪**

1. 指令语义维度 (Semantic) —— “CPU 在做什么？”
要求模型解析崩溃点的汇编指令。

输入： dis -l 的输出。
推演： 识别是内存读写故障（Data Access）、非法跳转（Function Call）还是逻辑自检（BUG/Assert）。
目标： 搞清楚事故发生的直接动作（如：试图往一个只读地址写数据）。

2. 上下文映射维度 (Context) —— “谁受害了？”
要求模型将内存偏移量与源码对象对齐。

输入： 寄存器值 + struct -o 偏移量信息。
推演： 将 +0x48 这种数字转换为具体的变量名（如 task->files）。
目标： 确定是哪个指针坏了，或者哪个结构体成员被污染了。

3. 因果路径维度 (Causality) —— “逻辑哪里崩了？”
要求模型结合 C 源码，复现导致上述“受害变量”进入“错误状态”的逻辑路径。

输入： 函数源码 + bt -f 参数。
推演： 扫描源码中的条件分支、循环或内联函数逻辑。
目标： 还原案发过程（如：由于竞争导致指针在判断后、使用前被置空）。


#### 故障链构建原则

源码分析的核心目标是**构建完整故障链**，每个节点必须同时有源码证据和 crash dump 证据：

示例：

```
[E-SRC] 源码证据：src/drivers/xxx.c:230 在高负载下进入 error 分支
    ↓
[E-DMP] crash 印证：log | grep "validation failed" 显示 3000 万次触发
    ↓
[E-SRC] 缺陷点：src/drivers/xxx.c:458 error_cleanup 缺少 kfree(buf)
    ↓
[E-DMP] crash 印证：kmem -s 显示 xyz_cache 占用 14.8GB，99% 未释放
```



**关键原则：**
- 每个源码结论必须有 crash 数据佐证
- 当 crash 数据与源码矛盾时，**以 crash 数据为准**
- 偏移量分析（`--offset`）可精确定位崩溃代码行
- 函数定位算法支持 GCC 属性（`static`、`__sched`、`notrace` 等）