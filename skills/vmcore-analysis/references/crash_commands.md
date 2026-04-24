# crash 工具命令速查手册

## 基础命令

| 命令 | 用途 | 示例 |
|------|------|------|
| `sys` | 系统基础信息（内核版本/架构/panic时间） | `sys` |
| `log` | 内核环形缓冲日志（dmesg） | `log \| tail -100` |
| `bt` | 当前/指定进程调用栈 | `bt`, `bt <pid>`, `bt -a`（所有CPU） |
| `bt -f` | 带栈帧内容的调用栈 | `bt -f` |
| `bt -l` | 带源码行号的调用栈（需debuginfo） | `bt -l` |
| `bt -c N` | CPU N 的调用栈 | `bt -c 0` |
| `ps` | 进程列表 | `ps`, `ps \| grep " D "` |
| `mod` | 已加载模块列表 | `mod`, `mod -s` |
| `runq` | CPU 运行队列 | `runq` |

## 内存分析

| 命令 | 用途 | 示例 |
|------|------|------|
| `kmem -i` | 内存使用总览 | `kmem -i` |
| `kmem -s` | slab 缓存列表 | `kmem -s` |
| `kmem -S <name>` | 指定 slab 缓存详情 | `kmem -S kmalloc-64` |
| `kmem <addr>` | 查询地址的内存属性 | `kmem 0xffff888012345678` |
| `kmem -p <pfn>` | 按页帧号查询页信息 | `kmem -p 0x12345` |
| `rd <addr> <count>` | 读取内存内容（64bit单位） | `rd 0xffff888012345678 16` |
| `rd -32 <addr> <count>` | 读取内存（32bit单位） | `rd -32 <addr> 8` |
| `wr <addr> <val>` | 写内存（谨慎！） | 不建议使用 |

## 反汇编

| 命令 | 用途 | 示例 |
|------|------|------|
| `dis <addr>` | 反汇编指定地址 | `dis 0xffffffff810abc12` |
| `dis <func>` | 反汇编指定函数 | `dis schedule` |
| `dis -l <func>` | 带源码行号反汇编 | `dis -l __alloc_pages` |
| `dis -r <addr>` | 反汇编到指定地址 | `dis -r 0xffffffff810abc12` |

## 数据结构

| 命令 | 用途 | 示例 |
|------|------|------|
| `struct <type>` | 查看结构体定义 | `struct task_struct` |
| `struct <type> <addr>` | 按类型解析内存 | `struct task_struct 0xffff888...` |
| `p <var>` | 打印全局变量 | `p jiffies`, `p rcu_state` |
| `p <var.field>` | 打印结构体字段 | `p init_task.comm` |
| `whatis <sym>` | 查询符号类型信息 | `whatis schedule` |

## 进程与任务

| 命令 | 用途 | 示例 |
|------|------|------|
| `task <pid>` | 进程 task_struct 详情 | `task 1234` |
| `files <pid>` | 进程打开的文件 | `files 1234` |
| `vm <pid>` | 进程虚拟内存映射 | `vm 1234` |
| `sig <pid>` | 进程信号状态 | `sig 1234` |
| `foreach task bt` | 所有任务调用栈 | `foreach task bt` |

## 锁分析

| 命令 | 用途 | 示例 |
|------|------|------|
| `struct mutex <addr>` | mutex 锁状态（含 owner） | `struct mutex 0xffff...` |
| `struct spinlock <addr>` | spinlock 状态 | `struct spinlock 0xffff...` |
| `struct rw_semaphore <addr>` | 读写信号量状态 | `struct rw_semaphore 0xffff...` |

## 特殊分析命令

| 命令 | 用途 | 示例 |
|------|------|------|
| `inode <addr>` | inode 结构详情 | `inode 0xffff...` |
| `mount` | 已挂载文件系统 | `mount` |
| `net` | 网络设备信息 | `net` |
| `irq` | 中断信息 | `irq` |
| `swap` | 交换空间信息 | `swap` |
| `dev` | 设备信息 | `dev` |

## 地址与符号

| 命令 | 用途 | 示例 |
|------|------|------|
| `sym <addr>` | 地址转符号名 | `sym 0xffffffff810abc12` |
| `sym <name>` | 符号名转地址 | `sym schedule` |
| `sym -l` | 模块符号列表 | `sym -l` |

## 重要的内存 Poison 值

| 值 | 含义 |
|----|------|
| `0x6b6b6b6b6b6b6b6b` | SLAB_POISON: 已释放的 slab 对象 |
| `0x5a5a5a5a5a5a5a5a` | SLAB_POISON: 未初始化的 slab 对象 |
| `0xdeadbeef` | 通用 debug 标记 |
| `0xcccccccc` | 调试填充值 |
| `0x0` | NULL（未初始化指针） |

## 典型分析模式

### 快速确认崩溃类型
```
log | grep -E "BUG|Oops|panic|KASAN|MCE|lockup" | tail -20
bt
```

### 定位模块崩溃
```
mod                          # 列出模块和地址范围
sym <RIP_addr>               # 确认 RIP 属于哪个模块
dis <RIP_addr>               # 反汇编崩溃点
```

### 分析死锁
```
bt -a                        # 所有 CPU 调用栈
ps | grep " D "              # D 状态进程
foreach task bt              # 所有任务调用栈
struct mutex <lock_addr>     # 检查锁的 owner
```

### 分析内存破坏
```
kmem <suspicious_addr>       # 查内存状态
rd <addr> 32                 # 查内存内容
kmem -s | grep <cache_name>  # 查 slab 缓存状态
```
