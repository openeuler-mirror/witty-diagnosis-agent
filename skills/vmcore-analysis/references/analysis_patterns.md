# 常见 Crash 分析模式 (Common Crash Analysis Patterns)

用于识别和诊断常见内核故障的特征模式。

## Panic 类型

### 空指针解引用 (NULL Pointer Dereference)

**特征签名 (Signature):**
```
BUG: unable to handle kernel NULL pointer dereference at 0000000000000000
IP: [<ffffffff81234567>] function_name+0x12/0x34
```

**回溯模式 (Backtrace pattern):**
- Crash 发生在尝试访问结构体成员的函数中
- 地址接近零 (0x0, 0x8, 0x10 等)

**调查方法 (Investigation):**
1. `bt` - 查看哪个指针为 NULL
2. `dis -l <function>` - 查看解引用位置
3. 检查代码路径中是否缺少 NULL 检查

**常见原因 (Common causes):**
- 未初始化的指针
- 释放结构体时的竞争条件 (Race condition)
- 未检查分配失败的情况

---

### 一般保护错误 (General Protection Fault)

**特征签名 (Signature):**
```
general protection fault: 0000 [#1] SMP
IP: [<ffffffff81abcdef>] function_name+0x45/0x67
```

**特征 (Characteristics):**
- 无效的内存访问 (坏指针，损坏的结构体)
- 通常显示非规范地址 (0x6b6b6b6b, 0x5a5a5a5a 模式)

**调查方法 (Investigation):**
1. 检查故障地址 - 常见模式：
   - `0x6b6b6b6b` - SLAB_POISON (释放后使用 use-after-free)
   - `0x5a5a5a5a` - kmalloc redzone (缓冲区溢出 buffer overflow)
2. `struct <type> <bad_address>` - 尝试解析结构体
3. 在回溯中查找最近的内存操作

---

### 栈溢出 (Stack Overflow)

**特征签名 (Signature):**
```
stack overflow detected
Double fault
```

**回溯模式 (Backtrace pattern):**
- 非常深的调用栈 (100+ 帧)
- 递归函数调用
- 巨大的局部变量

**调查方法 (Investigation):**
1. `bt` - 统计深度
2. 查找重复的函数名 (递归)
3. 检查无界循环

---

### 内存不足 (Out Of Memory - OOM)

**特征签名 (Signature):**
```
Out of memory: Kill process <pid> (<name>) score <X> or sacrifice child
Killed process <pid> (<name>) total-vm:<X>kB, anon-rss:<Y>kB, file-rss:<Z>kB
```

**日志模式 (Log patterns):**
- 多次 OOM killer 调用
- 内存分配失败
- 带有内存分数的进程列表

**调查方法 (Investigation):**
1. `kmem -i` - 检查内存分布
2. `ps` - 按内存使用量排序
3. `vm <pid>` - 检查最大的消费者
4. `kmem -s` - 检查 slab 泄漏

**常见原因 (Common causes):**
- 内存泄漏 (应用程序或内核)
- 系统对于负载来说配置过低
- 内存限制 (cgroup) 太低

---

### 死锁 (Deadlock)

**特征签名 (Signature):**
- 系统挂起 (System hang)
- 多个进程处于 D (UN) 状态
- Watchdog 超时

**日志模式 (Log patterns):**
```
INFO: task <name>:<pid> blocked for more than 120 seconds
```

**调查方法 (Investigation):**
1. `ps | grep UN` - 查找卡住的进程
2. `foreach bt` - 获取所有回溯
3. `bt -l <pid>` - 检查持有的锁
4. 查找循环等待 (Circular wait):
   - 进程 A 等待 B 持有的锁
   - 进程 B 等待 A 持有的锁

**模式识别 (Pattern recognition):**
```bash
# 查找 ABBA 死锁
foreach bt | grep -A10 "mutex_lock\|down\|spin_lock"
```

---

### 软锁定 (Soft Lockup)

**特征签名 (Signature):**
```
BUG: soft lockup - CPU#X stuck for Xs!
```

**特征 (Characteristics):**
- CPU 空转且不让出 (spinning without yielding)
- 中断被禁用太久
- 内核中的死循环

**调查方法 (Investigation):**
1. `bt -a` - 检查所有 CPU
2. `dis -l <function>` - 检查空转的函数
3. 查找：
   - 没有 break 的 while(1) 循环
   - 紧密的轮询循环 (Tight polling loops)
   - 无限期持有的锁

---

### 硬锁定 (Hard Lockup)

**特征签名 (Signature):**
```
NMI watchdog: BUG: hard lockup - CPU#X stuck for Xs!
```

**比软锁定更严重:**
- CPU 不响应中断
- 通常是硬件问题或严重的内核 Bug

---

## 内存损坏模式 (Memory Corruption Patterns)

### Slab 损坏 (Slab Corruption)

**特征签名 (Signature):**
```
slab error in <function>: cache `<cache_name>'
Freepointer corrupt
```

**调查方法 (Investigation):**
1. `kmem -s <cache_name>` - 检查 slab 缓存
2. 在回溯中查找 use-after-free
3. 检查缓冲区溢出

---

### 页表损坏 (Page Table Corruption)

**特征签名 (Signature):**
```
BUG: Bad page map
BUG: Bad page state
```

**表明 (Indicates):**
- 内核页表已损坏
- 可能是硬件内存错误

**调查方法 (Investigation):**
1. `kmem -p` - 检查页信息
2. 审查最近的内存操作
3. 考虑硬件诊断

---

## 驱动程序问题 (Driver Issues)

### 设备超时 (Device Timeout)

**特征签名 (Signature):**
```
<driver>: timeout waiting for <operation>
```

**常见于 (Common in):**
- 存储驱动 (SCSI, SATA, NVMe)
- 网络驱动

**调查方法 (Investigation):**
1. `dev` - 检查设备状态
2. `irq` - 验证中断传递
3. 在日志中查找硬件错误

---

### DMA 错误 (DMA Errors)

**特征签名 (Signature):**
```
DMA: Out of SW-IOMMU space
DMAR: DRHD: handling fault status
```

**调查方法 (Investigation):**
1. 检查硬件健康状况
2. 审查驱动程序初始化
3. 验证 IOMMU 配置

---

## 文件系统问题 (File System Issues)

### 检测到文件系统损坏 (Filesystem Corruption Detected)

**特征签名 (Signature):**
```
EXT4-fs error: <details>
XFS: Internal error <details>
```

**调查方法 (Investigation):**
1. `mount` - 检查文件系统状态
2. `files` - 查找有问题的文件操作
3. 审查最近的磁盘操作

---

### VFS 死锁 (VFS Deadlock)

**特征签名 (Signature):**
- 进程卡在 D 状态
- 回溯显示 VFS 函数

**常见模式 (Common patterns):**
```
do_sys_open
vfs_read
vfs_write
```

**调查方法 (Investigation):**
1. 检查文件系统挂载选项
2. 审查 NFS/网络文件系统问题
3. 查找锁顺序违规

---

## 网络问题 (Network Issues)

### RCU Stall

**特征签名 (Signature):**
```
INFO: rcu_sched self-detected stall on CPU
```

**特征 (Characteristics):**
- CPU 未完成 RCU 宽限期 (grace period)
- 通常与网络栈有关

**调查方法 (Investigation):**
1. `bt -a` - 检查 CPU 活动
2. 在回溯中查找网络驱动
3. 检查是否存在过多的数据包处理

---

### 网络栈溢出 (Network Stack Overflow)

**特征签名 (Signature):**
```
net_ratelimit: <X> callbacks suppressed
```

**表明 (Indicates):**
- 过度的网络活动
- 可能的攻击或错误配置

---

## 负载特定模式 (Workload-Specific Patterns)

### 数据库服务器崩溃 (Database Server Crashes)

**常见签名 (Common signatures):**
- 高内存压力 (OOM)
- 许多进程处于 D 状态 (IO 等待)
- 文件系统死锁

**调查重点 (Investigation focus):**
- `kmem -i` - 内存
- `files` - 打开的描述符
- `bt -a` - IO 操作

---

### Web 服务器崩溃 (Web Server Crashes)

**常见签名 (Common signatures):**
- Socket 耗尽
- 线程/进程限制达到上限
- 网络驱动问题

**调查重点 (Investigation focus):**
- `ps` - 进程计数
- 网络堆栈跟踪
- 内存分配失败

---

### 容器/虚拟化问题 (Container/Virtualization Issues)

**常见签名 (Common signatures):**
- Cgroup OOM
- 命名空间相关的 panics
- Virtio 驱动超时

**调查重点 (Investigation focus):**
- Cgroup 内存限制
- 虚拟设备状态
- 主机-客体交互

---

#### KVM/QEMU 虚拟化 Panic 分析 

当系统运行 KVM 虚拟机并发生 panic 时，崩溃可能发生在宿主机或虚拟机内部。分析方法同样适用于 ARM 架构的 KVM/ARM。

**特征签名：**
```
COMMAND: "CPU N/KVM"          # KVM vCPU 线程 (x86)
COMMAND: "CPU N/kvm"          # KVM vCPU 线程 (ARM)
COMMAND: "qemu-kvm"           # QEMU 进程
TASK: ffff...                 # 内核任务结构地址
```

**分析流程：**

1. **定位崩溃任务**
   ```
   crash> ps | grep -i kvm        # 查找 KVM 相关进程
   crash> ps | grep <PID>         # 按 PID 精确查找
   ```

2. **获取崩溃堆栈**
   ```
   crash> bt <task_addr>          # KVM 进程的 task 地址
   crash> bt -a                   # 查看所有 CPU 的状态
   ```

3. **反汇编分析（核心！）**
   ```
   crash> dis -r <RIP>             # 查看崩溃指令详情 (x86)
   crash> dis -l <RIP>             # 定位源码文件和行号
   
   # ARM 架构使用:
   crash> dis <address>           # 反汇编
   crash> dis -l <address>        # 带源码行号
   
   # 关键：理解崩溃指令在做什么操作
   # 常见模式 (x86):
   # - addl/mov 等指令操作 per-cpu 变量
   # - %gs/%fs 段寄存器访问 per-cpu 数据区
   # - vmcall/vmlaunch/vmexit 等虚拟机指令
   #
   # 常见模式 (ARM):
   # - ldr/str 指令访问内存
   # - bl/blr 调用函数
   # - eret 从异常返回
   ```

4. **Per-CPU 变量分析**
   ```
   crash> percpu                  # 列出所有 per-cpu 变量
   crash> sym <addr>              # 解析地址为符号
   
   # x86: %gs 段寄存器用于访问内核 per-cpu 数据区
   # ARM: 可能使用特定寄存器或内存映射
   ```

5. **架构特定的崩溃指令分析**

   | 架构 | 崩溃指令特征 | 关键分析点 |
   |------|-------------|-----------|
   | **x86** | RIP 指向内核代码 | 分析指令操作数，定位 per-cpu/内存访问 |
   | **ARM** | PC 指向内核代码 | 分析指令的 Load/Store 操作，理解异常类型 |
   | **通用** | 任何架构 | 找到指令对应的源码，理解预期行为 |

6. **常见根因类型**

   | 类型 | 特征 | 调查方法 |
   |------|------|---------|
   | **KVM 模块 Bug** | kvm 函数崩溃 | 分析 kvm 调用栈 |
   | **宿主机资源不足** | 内存/CPU 耗尽 | kmem -i, runq |
   | **嵌套虚拟化问题** | vmx/svm (x86) 或嵌套状态 (ARM) | 检查虚拟化状态 |
   | **虚拟机退出异常** | VMEXIT (x86) 或 HVC (ARM) 处理错误 | 分析退出的原因 |

**通用分析模板：**

```
步骤1: 崩溃指令分析
  crash> dis -r <RIP>             # x86: 查看指令详情
  crash> dis -l <RIP>             # 定位源码文件:行号
  
  追问: 这个指令在操作什么数据？
        - 内存地址？寄存器？per-cpu 变量？

步骤2: 源码逻辑理解
  查看源码，理解这个位置应该做什么操作
  
  追问: 这个操作的预期输入/输出是什么？

步骤3: 推导预期值
  crash> percpu                  # 列出 per-cpu 变量
  crash> sym <addr>              # 解析关键地址
  
  追问: 这个数据的正常值应该是什么？
        实际值是多少？
        差异在哪里？

步骤4: 根因定位
  - 竞态条件？ → 检查多核并发场景
  - 计算错误？ → 追踪数据来源
  - 内存损坏？ → 检查硬件/软件因素
```

**关键原则：**

- **不要依赖具体数值** - 关注指令模式和逻辑
- **跨架构思考** - x86 和 ARM 的指令不同，但分析思路相同
- **始终追问** - "正常值应该是什么？""为什么变成了异常值？"

---

## 快速模式匹配 (Quick Pattern Matching)

在日志输出上使用这些 grep 命令快速识别问题：

```bash
# Panic 指标
log | grep -i "panic\|oops\|bug:\|kernel bug"

# 内存问题
log | grep -i "out of memory\|oom\|allocation fail"

# 死锁指标
log | grep -i "blocked for\|hung task\|deadlock"

# 硬件错误
log | grep -i "hardware error\|mce\|machine check"

# 驱动问题
log | grep -i "timeout\|firmware\|driver.*fail"

# 文件系统问题
log | grep -i "ext4-fs\|xfs\|io error"
```

---

## 模式分析工作流 (Pattern Analysis Workflow)

对于任何 crash，遵循此模式识别工作流：

1. **分类 Panic 类型** (NULL deref, GPF, OOM 等)
2. **识别子系统** (MM, FS, NET, drivers)
3. **查找已知签名** (上面列出的模式)
4. **应用子系统特定的调查** (相关命令)
5. **检查硬件问题** (如果软件原因不明确)

## 常见的错误线索 (Common False Leads)

注意这些误导性的模式：

1. **Panic 处理程序中的 Panic:** 处理第一个 panic 时的二次崩溃
   - 在回溯中向前查找原始崩溃
   
2. **通用分配失败:** 可能是症状，而不是原因
   - 查找内存耗尽的地方
   
3. **超时消息:** 通常是其他地方死锁的后果
   - 查找是什么阻塞了操作

4. **Workqueue 卡住:** 通常在等待其他东西
   - 查找 workqueue 在等待什么