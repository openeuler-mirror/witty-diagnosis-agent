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
├── scripts/                    # 辅助脚本
│   ├── check_environment.sh    # 环境检查脚本
│   ├── check_bitflip.sh        # Bit Flip 检查脚本
│   ├── scene_collect.sh        # 场景收集总入口（支持 --scene/--auto）
│   ├── scene1_kernel_panic.sh  # 场景1：内核崩溃信息收集
│   ├── scene2_oom.sh           # 场景2：OOM/内存信息收集
│   ├── scene3_deadlock.sh      # 场景3：死锁/挂死信息收集
│   ├── scene4_network.sh       # 场景4：网络故障信息收集
│   ├── scene5_filesystem.sh    # 场景5：文件系统故障信息收集
│   └── scene6_hardware.sh      # 场景6：硬件/驱动故障信息收集

```

**注意：** 这是 Skill 本身的目录结构，与故障目录（如 `pcie_panic/`）是分开的。

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
  
# 指定场景（1-6）
./scripts/scene_collect.sh --scene 1 \
  --crash /custom/path/to/crash \
  --vmlinux /custom/path/to/vmlinux \
  --vmcore /custom/path/to/vmcore


```

**输出结果（与 `scene_collect.sh` 行为一致）**

| 模式 | 终端 | 磁盘日志（均在**运行命令时的当前工作目录**，一般为故障目录） |
|------|------|----------------------------------------------------------------|
| `--auto` | 打印 `[AUTO] 日志关键字分析结果`、命中行、`[AUTO] 自动识别结果: 场景 N — …`，再打印即将执行的场景脚本路径 | 先生成 **`scene_collect_autodetect_YYYYMMDD_HHMMSS.log`**（单次 crash 会话中的 `sys`/`log`/`bt`/`ps`/`mod`，供关键字匹配与人工复核；**场景 6 关键字仅在内核 `log` 段匹配**） |
| `--scene N` | 直接打印所选场景与 `sceneN_*.sh` 路径 | **不**生成 `scene_collect_autodetect_*.log`（未做自动探测） |

**说明（第一阶段）：** 以终端输出与（`--auto` 时）**`scene_collect_autodetect_*.log`** 为主；**不要求、默认也不依赖**各场景专项落盘日志。若在第二步**单独执行** `./scripts/sceneN_*.sh` 做深挖，再由该脚本按其实现写出专项日志（文件名因场景而异），见下文各场景小节。

### 第二步：根据故障类型深入分析


#### 🚨 硬件 Bit Flip 前置排查

**【强制干预指令】**：根据 **`scene_collect_autodetect_*.log`（使用 `--auto` 且已生成该文件时）**，或 **同一 vmcore 分析中 `crash` 会话里的 `log` / `bt` / `bt -r` 等输出**（含交互式 `crash` 或批量输入），如果发现由未知、越界内存地址引发的异常（如 `Page Fault`、`Data Abort`、`unable to handle kernel paging request`，且地址不为显然的全 0），**必须优先进行硬件 Bit Flip 检查！**

**何时需要检查 Bit Flip：**
根据上述材料中的输出，如果发现以下情况，**必须**进行 Bit Flip 检查：

**触发条件：**
- ✅ 出现 `Page Fault`、`Data Abort`、`unable to handle kernel paging request`
- ✅ 故障地址不是全 0（如 `0x00000000`）
- ✅ 地址看起来异常或越界（如 `0x08000045` 这种高位突然置位的情况）

**核心原理：Bit Flip 通常发生在数据本身，而不是计算的地址。需要检查寄存器值，而不是内存地址！**
**快速检查流程：**
1. **提取崩溃信息**：从 `sys` 和 `bt` 输出中提取故障地址 (FAR/CR2) 和寄存器值
2. **追踪数据来源**：使用 `dis -r` 反汇编，追踪寄存器值从哪里来（通常是从内存读取）
3. **推断预期值**：从代码逻辑推断数据应该是什么值
4. **运行验证脚本**：使用 `scripts/check_bitflip.sh` 验证是否为 1-bit flip

**⚠️ 重要区别：**
- **检查对象错误**：内存地址（如 `ffff543c2265aaf8`）→ 通常不是bit flip
- **检查对象正确**：数据值（如寄存器值 `0x8000045`）→ 这才是bit flip检查对象
- **关键洞察**：Bit Flip是**数据**损坏，检查寄存器中的**数据值**，而不是计算出的**内存地址**

**使用脚本：**

```bash
# 查看帮助
./scripts/check_bitflip.sh --help

# 检查 CPU ID 是否发生 bit flip（真实案例）
# 参数1: 预期值（从代码逻辑推断，如 CPU ID = 69）
# 参数2: 实际值（从 crash dump 获取，如 struct rq->cpu = 134217797）
./scripts/check_bitflip.sh 69 134217797

# 或使用十六进制
./scripts/check_bitflip.sh 0x45 0x08000045
```

**检查结果处理：**
- ✅ **确认是 Bit Flip** → 根因已定位，无需继续场景分析，直接生成报告
- ❌ **不是 Bit Flip** → 继续进行故障类型判断和场景分析

---

#### 故障类型快速判断

| 故障类型 | 关键字特征 | 对应场景 |
|---------|-----------|---------|
| **内核崩溃** | `Kernel panic`、`Call Trace`、`RIP`、`oops` | 场景 1 |
| **内存问题** | `Out of memory`、`OOM`、`killed process`、`Memory cgroup out of memory` | 场景 2 |
| **系统挂死** | 无明显错误但系统无响应；或进程状态为 `D`、`UN` | 场景 3 |
| **网络故障** | 典型接口名（如 `eth0`、`ens33`、`enp0s1`、`bond0`）、`link down`、`tx timeout`、`NETDEV WATCHDOG` 等；**不用**裸词 `network` 或单段 `eth`/`ens`（易与其它串词误匹配） | 场景 4 |
| **文件系统** | `EXT4-fs error`、`XFS error`、`I/O error`、`remounting read-only` | 场景 5 |
| **硬件故障** | **事件型**日志：`Hardware Error`、`Machine Check`、`mce:`/`MCE:`、`PCIe`/`PCI`/`AER` 可纠正/不可纠正错误、`EDAC MC`、明确 **UE/CE memory** 或 **DRAM ECC error** 等；**不是** `mod`/`ps` 里出现的 `*_edac` 模块名或符号名（常态存在，不代表硬件报错） | 场景 6 |

**判断方法：** 优先以 **`--auto` 终端结论** + **`scene_collect_autodetect_*.log`**（若存在）为准。**`--auto` 下场景 6 仅在批量输出中的「内核 log」段做关键字匹配**（避免 `mod` 等段落里的驱动符号误报）；若手动指定场景、结论与现象不符，或需复核时，在 **同一会话或后续 `crash` 收集到的 `log`/`bt`/`ps`** 中按上表检索核对（若已执行第二步专项脚本并生成落盘日志，亦可对照该文件）。

**场景关系说明：**
- 场景 1（内核崩溃）最常见，多数 panic 归入此类。
- 场景 6 常与场景 1 重叠（崩溃点在驱动/硬件路径时优先用场景 6 深挖）。
- 场景 2–5 多为子系统问题，可单独出现或叠加 panic。

**根据判断结果，进入以下对应场景进行深入分析：**

#### 场景 1：内核崩溃 / Kernel Panic


**执行脚本（场景1）：**

```bash
./scripts/scene1_kernel_panic.sh \
  --crash /custom/path/to/crash \
  --vmlinux /custom/path/to/vmlinux \
  --vmcore /custom/path/to/vmcore
```

**分析方法论：**

1. **先看 panic 主证据** - 在 `log` 中确认 `Kernel panic`/`oops`/`Call Trace` 及首次报错点。
2. **定位崩溃函数与代码行** - 用 `bt` 找崩溃链路，用 `bt -l` 对应源码行，用 `bt -f` 看完整参数帧。
3. **判断是否系统性问题** - 用 `bt -a` 看所有 CPU 是否卡在同一路径（排除单点异常）。
4. **确认触发模块与上下文** - 用 `mod` 确认模块归属，并结合 `irq`、`runq`、`ps` 判断是否由中断风暴或调度阻塞触发。
5. **检查硬件位翻转迹象** - 若 `bt -r` 出现寄存器高位异常突变（如 `0x08000045`），优先走 `check_bitflip.sh` 验证。

#### 场景 2：内存泄漏 / OOM / 内存耗尽


**执行脚本（场景2）：**

```bash
./scripts/scene2_oom.sh \
  --crash /custom/path/to/crash \
  --vmlinux /custom/path/to/vmlinux \
  --vmcore /custom/path/to/vmcore
```

**分析方法论：**

1. **确认是否真实 OOM 触发** - 在 `log` 搜索 `Out of memory`、`oom_kill_process`、`Memory cgroup out of memory`。
2. **判断内存耗尽类型** - 用 `kmem -i` 看整体内存结构，再用 `kmem -s` 找异常 slab 大户。
3. **定位“谁在吃内存”** - 用 `ps` 与 `ps -G` 锁定 RSS/VSZ Top 进程，和 OOM 日志中的被杀进程互证。
4. **判断碎片化与分配失败模式** - 用 `kmem -z`、`kmem -f`、`kmem -p` 判断是总量不足还是高阶页分配失败。
5. **补充虚拟内存视角** - 用 `vm` 观察页回收、换页与系统压力，确认是否长期内存压力导致失稳。

#### 场景 3：系统挂死 / 死锁 / 无响应


**执行脚本（场景3）：**

```bash
./scripts/scene3_deadlock.sh \
  --crash /custom/path/to/crash \
  --vmlinux /custom/path/to/vmlinux \
  --vmcore /custom/path/to/vmcore
```

**分析方法论：**

1. **先判定挂死类型** - 在 `log` 搜索 `hung_task`、`soft lockup`、`RCU stall`、`blocked for more than`。
2. **定位阻塞对象** - 用 `ps` 筛出 `D/UN` 进程，再用 `runq` 判断是否 CPU 级阻塞或全局拥塞。
3. **构建等待链** - 用 `bt`、`bt -a`、`bt -f` 还原线程/CPU 间的等待关系，识别循环等待。
4. **检查锁证据** - 用 `waitq`、`mutex -t`、`rwlock` 验证锁竞争类型（mutex/rwlock/等待队列）。
5. **区分锁死与资源枯竭** - 结合 `kmem -i` 与 `mod` 判断是否由内存/模块异常诱发“假死锁”。

#### 场景 4：网络不通 / 网络崩溃


**执行脚本（场景4）：**

```bash
./scripts/scene4_network.sh \
  --crash /custom/path/to/crash \
  --vmlinux /custom/path/to/vmlinux \
  --vmcore /custom/path/to/vmcore
```

**分析方法论：**

1. **先从日志定性故障** - 在 `log` 搜索 `link down`、`tx timeout`、`NETDEV WATCHDOG`、驱动报错关键字。
2. **检查设备与链路状态** - 用 `net` 与 `net -d` 看网卡状态、队列与设备细节。
3. **分析协议与连接层症状** - 用 `net -s`、`net -p`、`net -a` 判断是收发异常、协议异常还是路由/邻居异常。
4. **确认是否驱动级崩溃** - 用 `mod` + `bt`/`bt -l` 判断调用栈是否落在网卡驱动函数。
5. **排查中断与系统资源影响** - 用 `irq`、`ps`、`kmem -i` 判断是否由中断异常或 skb 相关内存压力引发。

#### 场景 5：文件系统只读 / 挂载异常 / IO 卡顿


**执行脚本（场景5）：**

```bash
./scripts/scene5_filesystem.sh \
  --crash /custom/path/to/crash \
  --vmlinux /custom/path/to/vmlinux \
  --vmcore /custom/path/to/vmcore
```

**分析方法论：**

1. **先识别文件系统错误类型** - 在 `log` 搜索 `EXT4-fs error`、`XFS error`、`I/O error`、`remounting read-only`。
2. **确认影响范围与挂载状态** - 用 `mount` 看是否被重挂为 `ro`，判断受影响分区与文件系统类型。
3. **定位活跃访问与阻塞点** - 用 `files` 找高频访问对象，用 `ps` 筛 `D` 态进程确认 IO 阻塞面。
4. **检查元数据与内核路径** - 用 `super` 看超级块状态，用 `bt`/`bt -l` 判断是否卡在 IO/日志提交路径。
5. **判断是否硬件链路问题外溢** - 结合 `irq`、`mod`、`runq` 判断是否需联动场景6继续排查存储控制器/驱动。

#### 场景 6：硬件故障 / 驱动崩溃


**执行脚本（场景6）：**

```bash
./scripts/scene6_hardware.sh \
  --crash /custom/path/to/crash \
  --vmlinux /custom/path/to/vmlinux \
  --vmcore /custom/path/to/vmcore
```

**分析方法论：**

1. **先确认硬件错误签名** - 在 `log` 搜索 **事件型** 记录：`MCE`/`mce:`、`Hardware Error`、`PCIe`/`PCI`/`AER` 报错、`EDAC MC` 或明确 **UE/CE memory** / **DRAM ECC error**；不要仅凭 `mod` 列表中的 `*_edac` 模块推断硬件故障。
2. **确认崩溃归属模块** - 用 `mod` 建立驱动版本清单，再用 `bt`/`bt -l`/`bt -f` 锁定是否在驱动栈崩溃。
3. **判断影响范围** - 用 `bt -a`、`runq`、`ps` 判断是单驱动故障还是系统级连锁反应。
4. **核查中断与设备侧证据** - 用 `irq`、`net -d`、`mount` 判断网卡/存储控制器是否出现同步异常。
5. **识别潜在位翻转或内存损坏** - 用 `bt -r`、`kmem -i`、`kmem -p` 检查异常值与页错误，再用 `check_bitflip.sh` 验证。



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