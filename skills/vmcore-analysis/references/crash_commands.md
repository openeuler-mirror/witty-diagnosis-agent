# Crash 命令参考手册

用于内核分析的 crash 工具命令完整参考。

## 核心分析命令

### sys
**用途:** 显示系统信息和 Panic 详情

**用法:** `sys`

**输出包含:**
- 内核版本和发布号
- 机器架构
- Panic 字符串（如果有）
- 系统正常运行时间 (Uptime)
- 崩溃时间
- CPU 数量

**何时使用:** 总是首先运行此命令以建立基准

---

### log
**用途:** 显示内核环形缓冲区 (dmesg 输出)

**用法:** 
- `log` - 完整日志
- `log | tail -100` - 最后 100 行（推荐）
- `log | grep ERROR` - 过滤错误信息

**查找内容:**
- Panic 消息
- Oops 报告
- 硬件错误
- 驱动程序故障
- 内存损坏警告

**何时使用:** 在 sys 之后首先运行的命令

---

### bt (backtrace)
**用途:** 显示当前/指定任务的调用栈

**用法:**
- `bt` - 当前任务的回溯
- `bt <pid>` - 特定进程的回溯
- `bt -a` - 所有 CPU 的回溯
- `bt -l` - 包含持有的锁
- `bt -t` - 包含时间戳
- `bt -f` - 完整的符号信息

**解读:**
- 栈顶显示崩溃发生的位置
- 向下追踪调用链
- 寻找已知的问题函数

**何时使用:** 理解崩溃上下文必不可少

---

### ps
**用途:** 显示进程状态

**用法:**
- `ps` - 所有进程
- `ps -l` - 包含锁信息
- `ps -u` - 用户/内核时间
- `ps -p` - 每 CPU 分解

**关键状态:**
- `RU` - 运行中 (Running)
- `IN` - 可中断睡眠 (Interruptible sleep)
- `UN` - 不可中断睡眠 (Uninterruptible sleep，通常是卡死)
- `ST` - 已停止 (Stopped)
- `ZO` - 僵尸进程 (Zombie)
- `DE` - 已死亡 (Dead)

**何时使用:** 查找卡死或有问题的进程

---

## 内存分析命令

### kmem
**用途:** 内核内存分析

**常见用法:**
- `kmem -i` - 内存使用摘要（从这里开始）
- `kmem -s` - Slab 分配器统计
- `kmem -s <cache>` - 特定缓存详情
- `kmem -p` - 内存页信息
- `kmem -v` - 虚拟内存上下文

**解读 kmem -i:**
- 总内存 vs 已用内存
- Slab 使用百分比
- 页缓存大小
- 崩溃时的空闲内存

**查找泄漏:**
```bash
kmem -s | grep -v "  0  "  # 非空缓存
kmem -s | sort -k6 -n -r   # 按总大小排序
```

**何时使用:** 任何与内存相关的问题

---

### vm
**用途:** 进程的虚拟内存信息

**用法:**
- `vm` - 当前任务的 VM 信息
- `vm <pid>` - 特定进程的 VM
- `vm -p` - 物理地址映射
- `vm -m` - 内存映射详情

**何时使用:** 进程内存问题，段错误 (segfaults)

---

### free
**用途:** 显示内存可用性

**用法:** `free`

**显示:** 系统视图中的总内存、已用内存、空闲内存

---

## 锁和等待分析

### waitq
**用途:** 显示等待队列信息

**用法:**
- `waitq <address>` - 特定等待队列
- 通常在看到任务处于 UN 状态后使用

**何时使用:** 死锁调查

---

## 中断和定时器命令

### irq
**用途:** 显示中断统计信息

**用法:** `irq`

**显示:**
- IRQ 编号
- 计数
- 处理函数
- 设备名称

**查找内容:** 指示中断风暴的异常高计数

---

### timer
**用途:** 显示内核定时器信息

**用法:** `timer`

**显示:** 活动定时器及其处理程序

**何时使用:** 定时器相关的挂起或看门狗触发

---

## 文件系统命令

### files
**用途:** 显示打开的文件描述符

**用法:**
- `files` - 当前任务的文件
- `files <pid>` - 特定进程的文件

**何时使用:** 文件描述符泄漏，文件系统问题

---

### mount
**用途:** 显示挂载的文件系统

**用法:** `mount`

**显示:** 挂载点，文件系统类型，设备

---

### dev
**用途:** 显示设备信息

**用法:** `dev`

---

## 结构体检查

### struct
**用途:** 显示内核结构体内容

**用法:**
- `struct <type> <address>`
- `struct task_struct <address>`
- `struct file <address>`

**技巧:**
- 从其他命令（ps, bt 等）获取地址
- 配合 | grep 过滤字段

**示例:**
```bash
struct task_struct ffff8800345fb040
struct file ffff88003456cd00
```

---

### union
**用途:** 显示联合体 (union) 内容

**用法:** 与 struct 相同，但用于联合体类型

---

## 反汇编命令

### dis
**用途:** 反汇编函数或地址

**用法:**
- `dis <function_name>` - 反汇编函数
- `dis -l <function_name>` - 包含源代码行
- `dis <address>` - 在地址处反汇编
- `dis -r <address>` - 反向反汇编

**何时使用:** 理解确切的崩溃点

**示例:**
```bash
dis -l panic
dis -l 0xffffffff81234567
```

---

## 内存读取命令

### rd (read)
**用途:** 读取内存内容

**用法:**
- `rd <address>` - 读取一个字
- `rd <address> <count>` - 读取多个
- `rd -8 <address>` - 读取 8 字节字
- `rd -4 <address>` - 读取 4 字节字

---

### px (print hex)
**用途:** 以十六进制格式打印内存

**用法:** `px <address> <count>`

**比 rd 更适合原始内存转储的格式化显示**

---

## 高级命令

### foreach
**用途:** 对每个元素执行命令

**用法:**
- `foreach bt` - 所有进程的回溯
- `foreach files` - 所有进程的文件
- `foreach vm` - 所有进程的 VM 信息

**强大之处:**
- 查找跨进程的模式
- 识别广泛存在的问题

**示例:**
```bash
foreach bt | grep -B2 "UN"  # 查找卡死的进程
```

---

### mod
**用途:** 内核模块信息

**用法:**
- `mod` - 列出所有模块
- `mod -S` - 重新加载模块的符号

**何时使用:** 模块相关的崩溃

---

### alias
**用途:** 创建命令快捷方式

**用法:**
- `alias <name> <command>`
- `alias ll log | tail -100`

**提示:** 为常用命令链创建别名

---

## 命令组合

### 快速 Panic 分析
```bash
sys
log | tail -100
bt
```

### 内存泄漏搜寻
```bash
kmem -i
kmem -s | grep -v "  0  " | sort -k6 -n -r | head -20
```

### 死锁调查
```bash
ps | grep UN
foreach bt | grep -A5 "UN"
bt -l <pid>
```

### 完整系统状态
```bash
sys
ps
bt -a
kmem -i
free
mount
```

## 技巧与窍门

1. **管道 (Piping):** 大多数命令支持管道传输到 grep, less, head, tail
   ```bash
   log | grep -i error
   ps | grep UN
   ```

2. **输出重定向:** 保存命令输出
   ```bash
   log > /tmp/kernlog.txt
   foreach bt > /tmp/all_backtraces.txt
   ```

3. **重复命令:** 使用 `!` 获取命令历史
   ```bash
   !sys    # 重复上一个 sys 命令
   !ps     # 重复上一个 ps 命令
   ```

4. **Tab 补全:** Crash 支持命令和符号的 Tab 补全

5. **帮助系统:**
   ```bash
   help <command>     # 特定命令的帮助
   help sys
   help bt
   ```

## 常见陷阱

1. **符号不匹配:** 如果输出看起来是乱码，检查 vmlinux 是否与 vmcore 匹配
2. **模块符号:** 如果需要，使用 `mod -S` 重新加载模块符号
3. **地址有效性:** 并非内存转储中的所有地址都是有效的 - crash 会发出警告
4. **输出缓冲区:** 非常大的输出可能会被截断 - 使用输出重定向