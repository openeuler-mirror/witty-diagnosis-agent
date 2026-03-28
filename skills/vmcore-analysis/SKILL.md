---
name: vmcore-analysis
description: 通过 crash 工具深度分析 Linux vmcore 文件，解决各类操作系统级疑难故障。核心能力包括：定位 Kernel Panic 和系统意外崩溃的根本原因；以及通过分析内存转储快照，诊断系统卡死、死锁、资源耗尽及性能异常等问题。提供从环境检查到根因报告生成的全流程指导。
---

# Analyze Vmcore Files (分析 Vmcore 文件)

本 Skill 旨在指导如何通过 `crash` 命令系统化地分析 `vmcore` 文件。

## 标准目录结构与启动命令

用户提供的 vmcore 文件的具体路径，目录结构里面的内容是标准的，参考如下：

```text
pcie_panic/     # 故障文件夹 
├── src/        # 可选，源码路径，如果存在则要针对问题进行源码分析 
├── crash       # crash命令 
├── vmlinux     # vmlinux命令  
└── vmcore      # vmcore文件
```

**执行命令：**

```bash
cd pcie_panic && ./crash ./vmlinux vmcore
```

## 核心理念：区分分析场景

**这是分析的第一步，也是最关键的一步。**

`vmcore` 文件的产生来源决定了你的分析方向。在执行任何分析之前，必须首先确定当前的分析场景。

### 场景 A：系统故障触发 (System Fault Triggered)
- **定义**：系统因内核错误（如 NULL 指针引用、General Protection Fault、OOM）非预期地发生崩溃或重启。
- **目标**：找出导致系统崩溃的**根本原因 (Root Cause)**。
- **策略**：**从症状出发**，分析 Panic 堆栈，倒推代码逻辑漏洞。

### 场景 B：用户主动触发 (User Manually Triggered)
- **定义**：系统本身**没有**崩溃，但可能处于“亚健康”状态（如进程卡死、网络不通、性能抖动）。用户为了保留现场，主动通过 `sysrq-c`、`kdump` 或 NMI 强制触发了 crash。
- **关键特征**：Panic 原因通常是 `SysRq-c` 或人工信号。
- **目标**：**忽略** crash 本身的触发原因（因为是我们自己按的按钮）。**聚焦**于用户在输入中描述的**真正问题**。
- **策略**：将 `vmcore` 视为系统的**“全景快照”**，在其中寻找死锁、资源耗尽或逻辑停滞的证据。

### 场景识别方法

**判断依据：**
1. **用户描述**：用户是否提到“我手动触发了 panic”、“系统卡死了所以我抓了个包”？
2. **Panic 消息**：`sys` 命令显示的 panic 字符串。

**执行路径：**
- **如果是 场景 A** 👉 执行 [场景 A：标准 RCA 分析模式](#场景-a-标准-rca-分析模式)。
- **如果是 场景 B** 👉 执行 [场景 B：人为触发分析模式](#场景-b-人为触发分析模式)。

---

## 核心理念：根本原因 vs 症状 (仅适用于场景 A)

**永远不要止步于第一个答案。** 我们的目标是找到真正的**根本原因 (Root Cause)**，而不仅仅是直接原因或症状。

### 分析的 5 个层级

1. **症状 (Symptom)** - 哪里失效了？(例如："kernel panic")
2. **直接原因 (Proximate Cause)** - 是什么触发了它？(例如："空指针解引用")
3. **机制 (Mechanism)** - 它是如何发生的？(例如："访问了未初始化的指针")
4. **潜在原因 (Underlying Cause)** - 为什么这成为可能？(例如："错误处理路径中缺少初始化")
5. **根本原因 (Root Cause)** - 是什么系统性问题导致了这一切？(例如："不完善的错误处理设计模式")

**在得出结论之前，务必推进到第 4-5 层级。**

### 强制性自省问题

在确定你认为的根本原因后，**务必**问自己：

1. ❓ **这真的是根本原因，还是仅仅是一个诱因？**
2. ❓ **我能解释为什么存在这种条件吗？**
3. ❓ **修复这个问题能防止类似问题发生，还是只能解决这一个特例？**
4. ❓ **我有多少证据，又有多少是假设？**
5. ❓ **是否有我尚未检查的其他组件参与其中？**
6. ❓ **更有经验的内核工程师接下来会看什么？**

### 危险信号 (Red Flags) - 当你还没找到根本原因时

⚠️ 你的解释中包含 "莫名其妙" 或 "看起来像"
⚠️ 你无法解释事件的时间线或顺序
⚠️ 多个看似无关的问题指向同一个崩溃
⚠️ 修复方案只是一个变通办法 (workaround)，而不是解决实际问题
⚠️ 你没有用崩溃转储 (crash dump) 中的数据验证你的假设
⚠️ 只有假设发生了某些 "奇怪" 的事情，崩溃才解释得通

**如果出现任何危险信号，你必须继续深挖。**

## 环境检查与配置 (Pre-check & Configuration)

**在执行任何分析之前，必须严格执行以下检查步骤。**

推荐使用封装好的一键检查脚本 `scripts/check_environment.sh`。该脚本会自动验证命令、文件存在性以及版本兼容性。

**执行规则：**
1. **用户自定义执行优先**：如果用户已经明确提供了具体的 `crash` 执行命令（例如完整的命令行），**可以跳过**环境检测和配置步骤，直接按照用户提示的命令执行。
2. **用户参数优先**：如果用户仅提供了路径参数（如 `crash` 路径、`vmlinux` 路径或 `vmcore` 路径），则**必须**使用用户提供的值运行检查脚本。
3. **默认回退**：如果用户未指定任何信息，则使用脚本内置的默认值。
4. **强制阻断**：如果执行检查脚本且返回非 0 退出码，**必须立即停止**后续所有分析步骤，并将错误信息反馈给用户。

**使用方法：**

```bash
# 基本用法（使用默认路径）
./scripts/check_environment.sh

# 指定路径（优先使用用户提供的参数）
./scripts/check_environment.sh \
  --crash-cmd "/custom/path/to/crash" \
  --vmlinux "/custom/path/to/vmlinux" \
  --vmcore "/custom/path/to/vmcore"
```

**只有脚本显示 `✅ Environment check passed!`，才能进入 [分析工作流](#分析工作流)。**

## 分析工作流

### 第一阶段：初步评估与场景定性 (必须执行)

按顺序执行这些命令以建立基线信息，并确定分析路径：

```
crash> sys              # 系统信息：内核版本、panic 原因、运行时间
crash> log              # 内核日志 (关注最后 100 行)
crash> bt               # 崩溃任务的回溯 (Backtrace)
```

**关键分支决策：**

1.  **检查 `sys` 输出中的 Panic 消息**。
2.  **如果是 "SysRq"、"kdump" 或人为触发信号**：
    *   👉 **进入 [场景 B：人为触发分析模式](#场景-b-人为触发分析模式)**。
    *   **忽略** `bt` 中的 `sysrq` 调用栈，它只是触发机制。
    *   **聚焦** 于用户在输入中描述的**真正问题**（如 "Web服务器无响应"）。
3.  **如果是 "Oops"、"NULL pointer"、"General protection fault" 等**：
    *   👉 **继续执行 [场景 A：标准 RCA 分析模式](#场景-a-标准-rca-分析模式)**。

---

### 场景 A：标准 RCA 分析模式

**适用：** 系统非预期崩溃。目标是找到崩溃根因。

#### A-2. 第二阶段：上下文发现

基于初步评估，继续收集上下文：

```
crash> ps               # 所有进程 - 查找 UN (不可中断) 或 RU (运行中) 状态
crash> bt -a            # 所有 CPU 回溯 - 检查挂起的 CPU
crash> foreach bt       # 所有进程回溯 - 识别模式
```

**决策点：** 审查回溯以对问题进行分类：
- 内存相关 → 转至阶段 3A
- 锁/死锁 → 转至阶段 3B
- 中断/定时器 → 转至阶段 3C
- 文件系统/IO → 转至阶段 3D
- 驱动/硬件相关 → 转至阶段 3E
- 未知 → 执行所有阶段 3 的部分

### 场景 B：人为触发分析模式

**适用：** 用户主动触发 crash 以调试其他问题（如 Hung Task, Deadlock, Performance）。

**核心策略：** 忽略 Crash 本身，寻找用户描述的症状。

#### B-1. 问题映射与定点清除

根据用户描述的症状，直接跳转到相应的分析工具：

1.  **症状：进程卡死 / 不响应**
    *   **重点**：`D` (不可中断) 状态进程。
    *   **命令**：
        ```
        crash> ps | grep UN
        crash> foreach UN bt
        ```

2.  **症状：系统整体变慢 / CPU 飙高**
    *   **重点**：运行队列 (Runqueue) 和 当前运行的任务。
    *   **命令**：
        ```
        crash> runq
        crash> bt -a
        ```

3.  **症状：内存泄漏 / OOM**
    *   **重点**：内存统计与 Slab。
    *   **命令**：
        ```
        crash> kmem -i
        crash> kmem -s | sort -k 2 -n -r | head
        ```

4.  **症状：网络不通 / 丢包**
    *   **重点**：网络相关的数据结构 (socket, net_device)。
    *   **命令**：
        ```
        crash> net
        crash> mod | grep net
        ```

#### B-2. 验证假设

使用 **第四阶段：核心命令深度钻取** 中的工具 (`rd`, `struct`, `dis`) 来验证你在 B-1 中发现的可疑点，而不是验证 crash 的原因。

---

### 第三阶段 A：内存分析

```
crash> kmem -i              # 内存使用摘要
crash> kmem -s              # Slab 分配器状态 (寻找非零计数)
crash> vm                   # 虚拟内存信息
```

**⚠️ 重要：分析任意内存地址前，必须先判断数据类型**

当需要分析从 bt、struct 中获取的地址时，遵循以下流程：
1. 先用 `sym <address>` 尝试解析为符号
2. 再用 `struct <type> <address>` 尝试解析为结构体
3. 结构体解析失败时再用 `rd` 读取原始内存

**详细流程和常用结构体查询表请参阅：** `references/struct_analysis.md`

**寻找：** 内存耗尽、Slab 泄漏、OOM (内存溢出) 条件、Slab 数据损坏 (Corruption)

### 第三阶段 B：死锁分析最小必要步骤

```bash
# 1. 找UN状态进程
crash> ps | grep UN

# 2. 查看调用栈（看在等什么锁）
crash> bt <PID>

# 3. 查看锁的持有者
crash> struct mutex <锁地址>
# 看owner字段

# 4. 查看持有者的栈（看它在等什么）
crash> bt <持有者PID>

# 5. 重复3-4，直到形成环 → 确认死锁
```

**就这5步**，如果形成循环依赖就是死锁。

### 第三阶段 C：中断/定时器分析

```
crash> irq                  # 中断统计
crash> timer                # 定时器队列
crash> bt -a                # 验证所有 CPU 的卡死状态
crash> bt -f                # [进阶] 打印栈帧数据，查找中断上下文中的残留数据
```

**寻找：** 定时器风暴、中断洪水、挂起的 CPU 上下文

### 第三阶段 D：文件系统/IO 分析

```
crash> files                # 打开的文件描述符
crash> mount                # 挂载的文件系统
crash> dev                  # 设备信息
crash> task -R fs_struct    # [进阶] 检查任务的文件系统上下文
```

**寻找：** 陈旧的文件句柄、挂载问题、设备错误

### 第三阶段 E：驱动与硬件分析

```
crash> mod                  # 加载的内核模块 (检查 Tainted 标记)
crash> log | grep -iE "hardware|error|pci|mce|warn"  # 硬件与驱动日志
crash> dev                  # 设备中断与 I/O 统计
crash> sym <address>        # 确认崩溃地址属于哪个模块
```

**寻找：** 非树外驱动 (Out-of-tree modules)、Tainted 内核、MCE (Machine Check Exception)、PCIe 总线错误、特定的驱动函数调用。

### 第四阶段：核心命令深度钻取 (Core Commands Deep Dive)

运维专家推荐的三大核心命令：`bt` (定位路径), `rd` (验证数据), `task` (理解上下文)。

#### 1. bt (Backtrace) - 还原现场路径
不仅仅是看调用栈，更要挖掘栈帧中的线索。

```
crash> bt           # 基础回溯
crash> bt -l        # 显示源代码行号 (最常用，快速定位代码位置)
crash> bt -f        # 显示栈帧数据 (Stack Frame)
                    # 技巧：在栈帧中寻找函数参数和局部变量的十六进制值
crash> bt -t        # 显示栈顶的时间戳 (检查任务是否长期未调度)
```

#### 2. rd (Read Memory) - 验证数据实锤
当怀疑数据结构损坏或指针异常时，必须查看内存原始内容。

```
crash> rd <addr>            # 读取十六进制内容
crash> rd <addr> -e         # 自动转换端序 (Endians)
crash> rd -s <addr>         # 尝试作为字符串读取 (验证文件名、缓冲内容)
crash> rd -S <addr>         # 尝试解析地址为符号 (验证指针是否指向合法函数/变量)
                            # 技巧：如果你怀疑是 Use-after-free，看内存里是不是全是 6b6b6b6b (Poison)
```

**深度审查提醒：**
当发现异常值（如非法地址、巨大的索引、异常的指针）时，**必须追问**：
- 这个值是从哪里来的？（如：它是从某个结构体字段读取的）
- 它应该是什么值？（如：应该在合理范围内）
- 用 `runq`、`struct` 等命令交叉验证

**实战示例：**
```
追问来源 → 发现是某个结构体字段的值
   → 分析该字段的合法范围
   → 用 runq/struct 验证 → 定位根因
```

#### 3. dis (Disassembly) - 反汇编深度分析

**这是理解崩溃指令语义、推导预期值的关键命令。**

当你需要理解崩溃指令的具体行为时，必须使用反汇编分析。

```
crash> dis <addr>             # 反汇编函数
crash> dis -r <addr>          # 显示原始指令详情（含操作数）(x86)
crash> dis -l <addr>          # 定位到源码文件和行号
crash> dis -l <function>      # 反汇编函数并显示源码行号
```

**x86 和 ARM 架构差异：**

| 架构 | 反汇编命令 | 特点 |
|------|-----------|------|
| **x86** | `dis -r <RIP>` | 使用 RIP 寄存器，段寄存器 (%gs/%fs) 访问 per-cpu |
| **ARM** | `dis <PC>` | 使用 PC 寄存器，通过特定指令访问 per-cpu |

**核心组合：dis -r + dis -l**

这个组合能帮你：
1. 理解崩溃指令具体在做什么操作
2. 定位到源码，理解该操作的预期行为
3. 结合 rd/percpu 验证实际值与预期值的差异

**通用分析流程：**

```bash
# 步骤1：反汇编崩溃指令，查看操作详情
crash> dis -r <RIP>             # x86: 查看指令详情
# 或
crash> dis <PC>                 # ARM: 查看指令详情

# 步骤2：定位源码，理解指令含义
crash> dis -l <RIP/PC>         # 定位源码文件:行号

# 步骤3：验证预期值
crash> percpu                  # 分析 per-cpu 变量
crash> sym <addr>              # 解析关键地址
crash> rd <addr>               # 读取实际值进行对比
```

**常见指令模式识别与预期地址推导：**

| 模式 | x86 示例 | ARM 示例 | 预期地址推导方法 (Expected Address) |
|------|---------|---------|--------------------------------|
| per-cpu 访问 | `%gs:xxx`, `%fs:xxx` | 特定寄存器映射 | `p __per_cpu_offset[<CPU_ID>] + 偏移量` (或结合 `mach` 命令) |
| 寄存器基址偏移 | `0x10(%rbx)` | `ldr x0, [x1, #0x28]` | 从 `bt -f` 或 task 抓取基址寄存器当前值 + 偏移量 |
| 虚拟化指令 | `vmcall`, `vmlaunch` | `hvc #0` | 结合 VMCS/VCPU 结构体分析 VM Exit/HVC 原因 |

**核心哲学：预期与实际对照 (Expected vs Actual)**

无论是审查异常结构体还是非法地址，分析的根本逻辑在于：
1. `dis` (反汇编) 告诉你代码**想要**计算出什么地址或值（**Expected**）。
2. `CR2/FAR` 或 `rd/struct` 告诉你系统运行时到底拿到了什么（**Actual**）。
3. 两者对比，方见根因。

---

### 🚨 全局优先级卡点：内存故障的“比特翻转”前置排查
*(Mandatory Global Rule: Hardware Bit Flip First Priority)*

**【强制干预指令】**：在遇到任何由未知、越界内存地址引发的异常导致直接崩溃时（如 `Page Fault`、`Data Abort`、`unable to handle kernel paging request`，且地址不为显然的全0 `$0x0`），**严禁直接深入软件业务代码（如空指针、竞争条件）的逻辑排查！**

此时的**第一优先级动作（绝对优先）**：强制将排查方向转为**验证是否存在硬件比特翻转 (Hardware Bit Flip)**，排除物理硬件嫌疑后，才允许向软件缺陷溯源。

**强制执行标准工作流 (Mandatory Workflow)：**

1. **阶段性中止：立即提取地址**
   无论发生该崩溃的是 KVM、网络还是核心调度器，直接提取由于异常所访问到的**故障地址 (Actual, 如 CR2/FAR)** 以及**发生错误的指令指针 (RIP/PC)**。

2. **强制逆推预期值 (Calculate Expected Address)**
   依靠上表的“常见指令模式”公式，大模型**不允许跳过预期地址计算步骤**。必须依据反汇编（如 `%gs / rbx / x1` 等寄存器的上下文），计算出当前该条指令*原本逻辑上想要访问的真实正确地址*：即 **预期内存地址 (Expected)**。

3. **按位异或验证 (1-Bit XOR Default Diagnosis)**
   针对计算出的 **Expected** 与系统截获的 **Actual (CR2/FAR)** 实施十六进制二进制转化并验证。
   **默认认定规则**：硬件导致的物理比特翻转，**通常是一个独立字内部的 1 位比特翻转 (单一位翻转 / 1-bit flip)**。
   - 检查异或差值：在二进制比对下，二者是否**恰巧只有 1 个 bit 是不同的**（即差异值为 2 的整数次幂）。
   - 例如：`Expected`: `0xffff8f`**`a`**`612345678`  vs `Actual`: `0xffff8f`**`2`**`612345678`
     （差异仅在 `a (1010)` 变 `2 (0010)`，这正是一个精准的 1-bit `1 -> 0` 翻转！而诸如指针乱码等软件错误通常是散乱的多字节被污染。）

**强制阶段性结论界定**：
- 如果上述单比特验证命中：**停止一切软件调查！** 直接得出“**底层物理硬件故障（内存条缺陷或 CPU 高速缓存一致性硬件 Bug）**”的最终根因！并给出修复方案：“必须在线下隔离该物理宿主机，整体下线并进行 DIMM 内存条硬件更换”。
- 仅当二者差异极大且位翻转随机不符单比特翻转特征，或地址根本是尚未初始化的无效区段（Poison pattern）时，**才准许进入**死锁、Use-after-free 等针对该模块的软件常规排查流。

#### 4. task (Task Context) - 掌握任务全貌
崩溃只是表象，`task_struct` 包含进程的所有运行时状态。

```
crash> task                 # 显示当前崩溃任务的摘要
crash> task <pid>           # 查看特定 PID 的任务结构地址
crash> struct task_struct <addr>  # 展开整个任务结构体 (信息量巨大)
crash> struct task_struct.state,comm,parent <addr> # [推荐] 只看关键字段
                            # state: 进程状态 (运行、睡眠、僵死)
                            # comm: 命令名称
                            # parent: 父进程信息
```

一旦确定了问题区域，再结合 `dis -l <function>` 反汇编代码，完成从“数据”到“逻辑”的闭环。

使用 `scripts/analyze_struct.py` 进行自动化结构体分析。

### 第四阶段 B：源代码分析 (Source Code Analysis)

**适用场景：** 当用户提供了 `src` 目录（内核源码）时，必须结合源码进行深度分析。

**⚠️ 重要原则：**
- 源码分析是**证据验证**的重要手段，不是猜测的依据
- 每一个从源码得出的结论，都必须有 crash dump 中的数据作为佐证
- 当 crash 数据与源码矛盾时，**以 crash 数据为准**
- 场景条件不确认时，**不要乱给结论**，标注为"待验证假设"

#### 4B-1. 源码目录识别

标准目录结构如下：

```
故障文件夹/
├── src                              # 可选，内核源码目录
│   └── <kernel_version>/            # 内核版本目录 (如 linux-4.19.90-xxx)
│       ├── arch/                    # 架构相关代码 (x86, arm, aarch64 等)
│       ├── block/                    # 块设备驱动
│       ├── certs/                    # 证书签名相关
│       ├── crypto/                   # 加密子系统
│       ├── Documentation/            # 内核文档
│       ├── drivers/                  # 设备驱动程序
│       ├── firmware/                 # 固件 blob
│       ├── fs/                       # 文件系统
│       ├── include/                  # 头文件
│       ├── init/                     # 初始化代码
│       ├── ipc/                      # 进程间通信
│       ├── kernel/                   # 内核核心代码
│       ├── lib/                      # 通用库
│       ├── mm/                       # 内存管理
│       ├── net/                      # 网络协议栈
│       ├── samples/                  # 示例代码
│       ├── scripts/                  # 编译脚本
│       ├── security/                 # 安全模块
│       ├── sound/                    # 声音子系统
│       ├── tools/                    # 工具
│       ├── usr/                      # 用户空间初始化
│       ├── virt/                     # 虚拟化
│       ├── Makefile                  # 顶层 Makefile
│       └── Kconfig                   # 配置定义
├── crash                             # crash 命令
├── vmlinux                           # 内核镜像
└── vmcore                            # vmcore文件
```

#### 4B-2. 源码分析的核心价值

| 价值 | 说明 |
|------|------|
| **代码逻辑验证** | 验证 crash 数据中的调用路径是否符合源码逻辑 |
| **初始化路径追踪** | 追踪指针/变量的初始化路径，找出未初始化的根因 |
| **错误处理审计** | 检查错误路径是否正确释放资源 |
| **锁顺序验证** | 验证死锁场景中的锁获取顺序 |
| **版本匹配确认** | 确认 vmlinux 与源码版本一致 |

#### 4B-3. 源码分析工作流

**步骤 1：确认源码版本匹配**

```bash
# 从 vmcore 获取内核版本
crash> sys | grep -i "kernel"

# 从源码获取版本
head -20 src/Makefile | grep "VERSION"
cat src/include/generated/uapi/linux/version.h 2>/dev/null || \
grep -E "UTS_VERSION|linux_banner" src/version.h 2>/dev/null || \
grep -r "Linux version" src --include="*.c" | head -5
```

⚠️ **必须验证**：如果源码版本与 vmlinux 不匹配，源码分析的结论**无效**。

**步骤 2：定位崩溃函数源码**

```bash
# 从 bt 获取崩溃函数名
crash> bt | head -20
# #0  [<ffffffff81234567>] driver_function+0x23/0x100 at driver.c:456

# 在源码中定位
grep -rn "driver_function" src/
# src/drivers/net/ethernet/example/driver.c:123: static int driver_function(...)
```

**步骤 3：追踪变量初始化路径**

这是源码分析**最重要**的任务之一。当发现空指针解引用时：

```
分析模板：
1. 崩溃点：哪个指针为 NULL？
2. 该指针应该在哪里被初始化？
3. 追踪从创建到使用的完整路径
4. 在哪一步出现了问题？
```

**示例分析：**

```
崩溃点：driver.c:456, request->ptr 为 NULL

源码追踪：
1. request 在 driver.c:100 创建 (kzalloc)
2. driver_function 在 driver.c:200 调用 process_request
3. process_request 在 driver.c:300 分支：
   - 正常路径：ptr 被正确初始化 (line 350)
   - 错误路径：ptr 未初始化直接返回 (line 380)
4. 崩溃发生在 driver_function 调用时 (line 456)

结论：错误路径(line 380)缺少初始化，是根本原因
```

**步骤 4：验证错误处理路径**

```bash
# 查找函数的错误处理分支
grep -n "error\|fail\|NULL\|return.*-E" src/driver.c | head -30

# 使用 cflow 或其他工具追踪调用图
cflow -d 50 src/driver.c 2>/dev/null | head -50
```

**步骤 5：分析锁竞争场景**

```bash
# 查找所有锁操作
grep -rn "mutex_lock\|spin_lock\|rwlock" src/ | grep "function_name"

# 检查锁顺序
# 在源码中标记锁获取顺序，验证是否存在 ABBA 死锁
```

#### 4B-4. 源码分析的证据要求

**⚠️ 强制要求：源码结论必须有 crash 数据佐证**

| 源码结论 | 必须的 crash 证据 |
|----------|-------------------|
| "错误路径未初始化" | `struct` 显示该成员为 NULL/未定义值 |
| "锁顺序错误" | `bt -l` 显示两个进程持有相反的锁 |
| "资源泄漏" | `kmem -s` 显示对应 slab 增长 |
| "竞态条件" | `bt -a` 显示多 CPU 同时执行同一代码路径 |
| "函数调用顺序异常" | `bt` 显示的调用栈与源码逻辑矛盾 |

#### 4B-5. 源码分析检查清单

在完成源码分析后，必须验证：

□ 源码版本与 vmlinux 版本一致
□ 崩溃函数在源码中可定位
□ 源码逻辑与 crash bt 路径匹配
□ 每个源码结论都有 crash 数据佐证
□ 标注了所有"待验证"的假设
□ 当矛盾时，以 crash 数据为准

#### 4B-6. 常见源码分析模式

**模式 A：空指针解引用**

```
源码分析方法：
1. 定位崩溃函数
2. 追踪问题指针的来源
3. 找出所有可能设置该指针的位置
4. 确定哪个路径漏掉了初始化

示例命令：
grep -rn "ptr\s*=" src/ --include="*.c" | grep -v "ptr = ptr"
```

**模式 B：内存泄漏**

```
源码分析方法：
1. 从 kmem -s 定位泄漏的 cache 名称
2. 在源码中查找所有对该 cache 的 alloc/free 调用
3. 验证每个 alloc 都有对应的 free
4. 找出未配对的错误路径

示例命令：
grep -rn "kmem_cache_alloc\|kmalloc" src/driver.c
grep -rn "kmem_cache_free\|kfree" src/driver.c
```

**模式 C：死锁**

```
源码分析方法：
1. 从 bt 获取涉及的锁地址
2. 在源码中定位锁的定义位置
3. 分析涉及的函数调用路径
4. 验证锁获取顺序是否在所有路径中一致

示例命令：
grep -rn "DEFINE_MUTEX\|static.*mutex" src/
```

**模式 D：use-after-free**

```
源码分析方法：
1. 从 rd 读取问题地址，检查是否有 poison 值 (0x6b6b6b6b)
2. 在源码中查找该对象的 free 调用点
3. 追踪是否有代码路径在 free 后继续使用该指针

示例命令：
grep -rn "kfree\|kmem_cache_free" src/ | grep -B5 -A5 "object_name"
```

#### 4B-7. 当源码不存在时的处理

如果用户**未提供** src 目录：

1. 使用 `dis -l <function>` 进行反汇编分析
2. 使用 `crash> files` / `crash> mod` 获取更多上下文
3. 在结论中明确标注："由于缺少源码，无法进行代码逻辑验证"
4. 侧重于 crash 数据分析，给出基于 crash 证据的结论

---

### 第五阶段：根本原因分析与验证

**关键：不要跳过此阶段。这是区分症状与根本原因的关键。**

#### 步骤 5.0：证据链构建

**可信 RCA 的基础是一条完整的证据链。**

从崩溃点反向构建到根本原因的证据链：

```
证据链模板：

[观察到的现象] ← [直接证据]
    ↓
[直接原因] ← [技术证据]
    ↓
[技术机制] ← [代码/数据证据]
    ↓
[设计缺陷] ← [架构/流程证据]
    ↓
[根本原因] ← [系统性证据]
```

**示例 - 完整的证据链：**

```
[现象] 系统panic
├─ 证据: crash> sys 显示 "BUG: unable to handle kernel NULL pointer"
│
[直接原因] NULL指针解引用在do_work()
├─ 证据: crash> bt 显示
│   #0 panic
│   #1 oops_end
│   #2 no_context  
│   #3 __bad_area_nosemaphore
│   #4 do_work+0x23/0x45 ← 崩溃点
│   #5 process_request+0x67/0x89
│
[技术机制] struct request.ptr未初始化
├─ 证据: crash> struct request ffff880012345678
│   {
│     state = REQ_ERROR (0x2)
│     ptr = 0x0           ← NULL!
│     timestamp = 1234567890
│   }
├─ 证据: crash> dis -l do_work
│   120: mov 0x8(%rdi),%rax    ← 读取request.ptr
│   123: mov (%rax),%ebx       ← 解引用NULL，崩溃！
│
[设计缺陷] error_path缺少初始化
├─ 证据: crash> dis -l process_request  
│   456: test %eax,%eax
│   457: je error_path
│   ...
│   error_path:
│   460: mov $0x2,0x0(%rbx)    ← 设置state=REQ_ERROR
│   464: ret                   ← 直接返回，未初始化ptr!
│
[根本原因] 无错误处理规范，代码审查未覆盖
├─ 证据: git log process_request.c
│   commit abc123 - "Add error handling" (无code review记录)
├─ 证据: 项目无error path checklist
├─ 证据: 无静态分析工具检测未初始化成员
```

**每一个环节都必须有来自 crash dump 或代码的确凿证据。**

**可视化 - 带有证据的调用链：**

```
完整调用链可视化（从触发到崩溃）：

用户操作
    ↓
network_receive()           ← 网络包到达
    ↓ 
driver_interrupt()          ← 中断处理
    ↓
process_request()           ← 处理请求
    ├─ [正常路径]
    │   ↓
    │   allocate_buffer()   
    │   ↓
    │   ptr = buffer        ← ptr被正确初始化
    │   ↓
    │   do_work()           ← 安全执行
    │
    └─ [错误路径] ⚠️ BUG在这里
        ↓
        validation_failed   
        ↓
        state = REQ_ERROR   ← 只设置了状态
        ↓
        return              ← 未初始化ptr! ❌
        ↓
do_work()                   ← 仍被调用
    ↓
access ptr (NULL)           ← 崩溃！💥

证据支持：
✓ bt显示这个调用顺序
✓ struct显示state=ERROR但ptr=NULL
✓ dis显示error_path缺少初始化
✓ log显示validation error发生在崩溃前30ms
```

#### 步骤 5.1：构建时间线

重构导致崩溃的事件过程：

```
crash> log | grep -B50 "panic"             # Panic 之前的事件
crash> bt -t                                # 带时间戳的回溯
crash> ps -l                                # 任务当时在做什么
```

**需要回答的问题：**
- 系统崩溃时正在做什么？
- 最近有什么变更 (新负载、配置、代码)？
- 这是第一次发生还是反复发生？
- 哪些进程是活跃的？

#### 步骤 5.2：验证你的假设

**永远不要假设 —— 始终用数据验证。**

如果你认为是内存泄漏：
```
crash> kmem -s <suspected_cache>           # 验证增长
crash> kmem -s <cache> | grep "ALLOCATED"  # 检查分配计数
crash> foreach vm | grep -A5 <process>     # 验证进程内存
```

如果你认为是死锁：
```
crash> bt -l <pid1>                        # P1 持有什么锁？
crash> bt -l <pid2>                        # P2 持有什么锁？
# 验证：P1 持有 L1，想要 L2；P2 持有 L2，想要 L1
```

如果你认为是竞态条件：
```
crash> bt -a                               # 所有 CPU - 它们当时在做什么？
crash> struct <shared_data> <addr>         # 共享数据的状态
# 寻找：部分更新的状态、不一致的数据
```

#### 步骤 5.3：5 Whys 分析

应用 "5个为什么" 技术：

**示例：**
1. **为什么会崩溃？** → 函数 X 中空指针解引用
2. **为什么指针是空的？** → 结构体成员未初始化
3. **为什么没有初始化？** → 分配函数返回了 NULL
4. **为什么分配失败？** → 系统内存耗尽
5. **为什么系统内存耗尽？** → 驱动程序 Y 内存泄漏
   
   → **根本原因：驱动程序 Y 内存泄漏**

**轮到你了 —— 对你的崩溃应用 5 Whys：**
```
1. 为什么会崩溃？ → _________________
2. 为什么会发生这种情况？ → _________________
3. 为什么存在这种条件？ → _________________
4. 为什么被允许发生？ → _________________
5. 为什么设计中可能出现这种情况？ → _________________
```

#### 步骤 5.4：基于证据的验证

**检查清单 —— 你能用 crash dump 数据证明它吗？**

□ 我能展示导致崩溃的确切内存状态
□ 我能追踪导致此处的函数调用序列
□ 我能识别具体的数据结构损坏
□ 我能解释**为什么**系统处于这种状态
□ 我能指出造成该条件的代码路径
□ 我明白是什么阻碍了错误更早被捕获

**如果你勾选少于 4 项，你需要更多分析。**

#### 步骤 5.5：替代假设

**挑战自己：** 还有什么**其他原因**能解释这个崩溃？

列出至少 2 个替代解释：
1. 替代假设 #1: _________________
2. 替代假设 #2: _________________

然后用 crash dump 证据**反驳**每一个：
- 假设 #1 被反驳，因为：_________________
- 假设 #2 被反驳，因为：_________________

**只有那样**你才能对你的根本原因充满信心。

#### 步骤 5.6：影响分析

**理解范围：**

□ 这是一次性损坏还是系统性问题？
□ 这会影响其他配置类似的系统吗？
□ 是否有其他代码路径存在相同的漏洞？
□ 如果再次发生，爆炸半径 (影响范围) 有多大？

深度钻取问题示例：
```
crash> mod                                 # 这是一个内核模块吗？
crash> mod -s <module>                     # 检查模块版本
crash> grep <function> <source>            # 审查代码中类似的模式
```

#### 步骤 5.7：根本原因陈述 (Root Cause Statement)

一份专业的分析报告是运维工程师的核心产出。它不仅要告诉别人"坏在哪里"，更要展示"为什么坏"以及"凭什么这么说"。

**⚠️ 重要警告：根因笼统的常见原因**

如果你发现你的根因陈述属于以下情况，说明分析深度不足：

| ❌ 笼统的根因 | ✅ 具体的根因 |
|--------------|--------------|
| "内核 bug" | "xxx 驱动的 error_path 缺少 kfree" |
| "内存泄漏" | "xxx 函数的第 123 行在错误分支未释放 buffer" |
| "死锁" | "A 进程持有锁 X 等待锁 Y，B 进程持有锁 Y 等待锁 X，ABBA 死锁" |
| "空指针" | "struct xxx 的 member 字段在函数 yyy 的第 456 行未被初始化" |
| "代码问题" | "在 zzz.c 的 handle_request() 函数中，错误处理路径跨越第 100-120 行时遗漏了资源释放" |

**根本原因的具体性要求：**

```
✅ 必须包含：
   - 具体文件名 (如: driver.c, mm/slab.c)
   - 具体函数名 (如: xyz_driver_recv)
   - 具体问题类型 (如: 缺少初始化/资源泄漏/锁顺序错误)
   - 具体代码位置 (如: 第 123 行, error_cleanup 标签处)
   
✅ 如果有 src 源码：
   - 必须关联到具体源码文件和行号
   
✅ 必须有 crash 证据支撑：
   - 每个结论都要有对应的 crash 命令输出作为佐证
```

**专业 RCA 报告结构规范：**

建议采用以下结构生成最终报告，确保技术深度与可读性并存。

```text
# Linux Kernel Crash Root Cause Analysis Report
# Linux 内核崩溃根因分析报告

## 1. Executive Summary (故障摘要)
--------------------------------------------------------------------------------
| 故障现象 | [简短描述，如：系统在高负载下发生 Kernel Panic]                |
| 影响范围 | [受影响的机器数量、业务线]                                     |
| 根本原因 | [技术定性，如：网卡驱动在异常处理路径中存在内存泄漏]     |
| 修复建议 | [修复方案，如：补丁修复驱动 error_cleanup 函数]          |
--------------------------------------------------------------------------------

## 2. Technical Analysis (技术分析)

### 2.1 Failure Mechanism (故障机理)
[详细描述故障是如何一步步发生的，使用专业术语]
在网络高丢包率（>30%）场景下，`xyz_driver` 驱动在处理接收包时触发校验失败逻辑。在 `error_cleanup` 函数中，代码直接返回错误码，但**遗漏了释放**此前已分配的 `skb` 缓冲区。
随着时间推移（约48小时），泄漏对象堆积导致 slab 内存耗尽，最终触发 OOM Killer 误杀关键进程导致系统 Panic。

### 2.2 Sequence Diagram (时序图/流程图)
[使用图表清晰展示调用流与故障点]

正常流程:           异常流程 (故障复现):
network_irq         network_irq
    |                   |
    v                   v
alloc_skb()         alloc_skb() ----> [内存分配成功]
    |                   |
    v                   v
validate_pkt()      validate_pkt() -> [返回失败 -EINVAL]
    |                   |
    v                   v
process_pkt()       error_cleanup()
    |                   |
    v                   v
free_skb()          return -EINVAL -> [❌ 缺失 free_skb，内存泄漏!]

### 2.3 Evidence Chain (强证据链)
[核心证据展示，必须提供截图或命令输出片段，确保证据确凿]

* **E1: 内存耗尽事实**
  * 命令: `crash> kmem -i`
  * 证据: `Slab: 15.2GB (95%)`, `Free: 100MB`
  * 结论: 系统因 Slab 内存耗尽导致崩溃。

* **E2: 泄漏源定位**
  * 命令: `crash> kmem -s | sort -k6 -n -r | head -5`
  * 证据: `xyz_buffer_cache 100M 对象, 占用 14.8GB`
  * 结论: 内存泄漏源头为 `xyz_buffer_cache`。

* **E3: 泄漏代码定位**
  * 命令: `crash> foreach bt | grep -B5 "xyz_driver_receive"`
  * 证据: 所有泄漏对象分配来自 `xyz_driver_receive+0x45`
  * 结论: 泄漏发生在网络包接收处理函数。

* **E4: 源码验证（假设 src 存在）**
  * 命令: `grep -n "error_cleanup\|kmem_cache_free" src/drivers/net/xyz_driver.c`
  * 证据: 
    - 第 412 行: `buf = kmem_cache_alloc(xyz_buffer_cache, GFP_ATOMIC);`
    - 第 430 行: `if (validate_pkt(buf) != 0) goto error_cleanup;`
    - 第 458 行: `error_cleanup: return -EINVAL;` ← **缺失 kfree!**
  * 结论: `error_cleanup` 标签处直接返回，遗漏了第 412 行分配的 buffer 释放。

* **E5: 触发条件确认**
  * 命令: `crash> log | grep "validation failed" | wc -l`
  * 证据: 30,000,000 次验证失败
  * 结论: 高丢包率(>30%)导致错误路径频繁执行，48 小时内泄漏 14.8GB。

## 3. Root Cause (根本原因)
* **Direct Cause (直接原因)**: `drivers/net/ethernet/xyz/xyz_driver.c` 第 458 行的 `error_cleanup` 标签处，在处理 `validation failed` 分支时直接 `return -EINVAL`，遗漏了第 412 行 `kmem_cache_alloc()` 分配的 `xyz_buffer`，导致内存泄漏。
* **Root Cause (根本原因)**: `xyz_driver.c` 的 `xyz_driver_receive()` 函数在接收数据包的错误处理路径中，未遵循"谁分配谁释放"原则；项目代码规范中缺少"错误路径必须包含资源清理"的强制检查项。

## 4. Recommendations (改进建议)

| 类型 | 建议措施 | 预计完成时间 |
|------|----------|--------------|
| **短期** | 应用 Hotfix 补丁，在 `error_cleanup` 中添加 `kfree` | 立即 |
| **长期** | 在 CI 流程引入 `kmemleak` 扫描工具 | Q3 |
| **长期** | 增加驱动异常路径的代码走查 Checklist | Q3 |

```

**编写建议：**
1.  **图表胜千言**：对于复杂的锁竞争或调用关系，务必使用 ASCII 流程图。
2.  **证据说话**：不要说“我觉得是内存泄漏”，要说“`kmem -s` 显示该 slab 占用 90% 内存，且 `dis` 确认无释放逻辑”。
3.  **通俗易懂**：在摘要部分使用管理层能听懂的语言，在分析部分使用工程师通用的术语。

#### 步骤 5.8：最终验证问题

**在宣布找到根本原因之前，回答所有问题：**

✅ **你能向初级工程师解释清楚并让他完全理解吗？**
✅ **你的解释能涵盖 crash dump 中的所有观察结果吗？**
✅ **你是否确定了事情出错的第一个点？**
✅ **你的根本原因是否具体到足以指导修复？** （必须有具体文件名、函数名、行号）
✅ **提议的修复能否防止此类错误，而不仅仅是这个实例？**
✅ **你是否检查了代码库中其他地方是否存在此模式？**
✅ **你的根因陈述是否避免了笼统描述？** （不是"内核 bug"而是"xxx.c 第 N 行的问题"）

**如果有任何回答是 NO，你必须继续分析。**

## 快速分析模式

为了快速诊断，使用这些命令组合：

**模式 1：Panic 分析**
```
sys → log | tail -100 → bt → dis -l <crash_function>
```

**模式 2：OOM (内存溢出) 调查**
```
sys → kmem -i → ps (sort by memory) → kmem -s | grep -v " 0 "
```

**模式 3：死锁检测**
```
ps | grep " UN " → foreach bt | grep -A5 "UN" → bt -l
```

**模式 4：任务挂起 (Hung Task)**
```
ps → bt <pid> → bt -l → waitq
```

**模式 5：虚拟化/KVM Panic 分析（通用，兼容 x86/ARM）**
```
sys → log | tail -50 → bt → dis -r <RIP/PC> → dis -l <RIP/PC>
```

**虚拟化Panic关键分析点（通用）：**

1. **识别崩溃任务**：
   ```
   crash> ps | grep -i kvm     # 查找 KVM 相关进程 (x86/ARM)
   crash> bt <task_addr>        # 获取崩溃堆栈
   ```

2. **分析崩溃指令**（核心！）：
   ```
   crash> dis -r <RIP>         # x86: 查看崩溃指令详情
   crash> dis <PC>             # ARM: 查看崩溃指令详情
   crash> dis -l <RIP/PC>     # 定位源码
   ```

3. **常见虚拟化Panic类型**：
   - KVM 模块内部 panic → 分析 kvm 函数调用
   - 嵌套虚拟化问题 → 检查 vmx/svm (x86) 或嵌套状态 (ARM)
   - 宿主机资源问题 → 检查内存、CPU 负载

4. **Per-CPU 变量分析**：
   ```
   crash> percpu               # 列出 per-cpu 变量
   crash> sym <addr>          # 解析地址
   ```

## 辅助脚本

### scripts/evidence_chain.sh ⭐
**交互式证据链构建器** - 引导你从症状到根本原因构建完整、可验证的证据链。生成包含技术和通俗语言解释的综合报告。

**何时使用：** 在阶段 5 之前或期间，以确保每个主张都有确凿证据。

**输出：** 完整的证据链报告，包含可视化和通俗语言翻译。

### scripts/rca_wizard.sh ⭐
自动化 RCA 会话，包含结构化的 5 Whys、证据收集、验证清单。生成带时间戳的 RCA 报告。

### scripts/crash_wrapper.sh
使用配置好的路径进行自动化 crash 会话，将输出保存到带时间戳的日志中。

### scripts/quick_report.sh
一条命令生成初步评估报告 (sys, log, bt, ps, kmem -i)。

### scripts/analyze_struct.py
从 crash 输出中解析并美化打印内核数据结构。

## 详细参考资料

深入的命令文档和高级技术：

- `references/crash_commands.md` - 完整的 crash 命令参考
- `references/analysis_patterns.md` - 常见的故障模式和特征
- `references/troubleshooting.md` - 环境问题和符号解析
- `references/root_cause_analysis.md` - **关键：深度 RCA 方法论和案例研究**
- `references/source_code_structure.md` - 内核源码目录结构参考
- `references/struct_analysis.md` - 结构体分析指南

**何时阅读：**
- `crash_commands.md` - 当你需要特定 crash 命令的语法时
- `analysis_patterns.md` - 当识别故障特征 (NULL 解引用, OOM, 死锁) 时
- `troubleshooting.md` - 当 crash 工具本身出现问题时
- `root_cause_analysis.md` - **当从阶段 4 进入阶段 5 时务必阅读**
- `source_code_structure.md` - **当需要进行源码分析时**
- `struct_analysis.md` - **当需要分析内存地址对应的结构体时**

## 最佳实践

1. **始终从阶段 1 开始** - 基线信息指导后续分析
2. **永远不要跳过阶段 5** - 症状不是根本原因
3. **保存输出** - 重定向到文件以便稍后比较：`log > /tmp/kernlog.txt`
4. **应用 5 Whys** - 坚持问 "为什么" 直到找到系统性问题
5. **用证据验证** - 每个主张都必须有 crash dump 数据的支持
6. **考虑替代方案** - 生成并反驳替代假设
7. **质疑你的结论** - 使用阶段 5 中的反思问题
8. **上下文很重要** - 负载类型影响解释
9. **符号验证** - 不匹配的符号会产生垃圾输出
10. **渐进式聚焦** - 从宽泛开始，根据发现缩小范围
11. **源码佐证** - 当有 src 时，源码结论必须由 crash 数据佐证
12. **版本匹配** - 源码版本必须与 vmlinux 版本一致，否则结论无效

## 分析思维模式

**优秀的分析师认为：** "崩溃发生是因为 X"

**卓越的分析师认为：** "崩溃发生是因为 X，X 发生是因为 Y，Y 成为可能因为 Z，这反映了我们在错误处理设计模式上的系统性问题。"

**始终向深处挖掘，直到找到系统性问题。**