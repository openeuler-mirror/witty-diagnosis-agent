# 结构体分析参考手册

本文档详细介绍如何在 crash 中使用 `struct` 命令分析内核结构体。

## 分析任意内存地址的标准流程

当你获取一个内存地址时，**必须首先判断它是什么类型的数据**。

### 标准分析步骤

```bash
# 步骤 1：尝试将地址解析为符号（判断是否是函数指针）
crash> sym <address>

# 步骤 2：尝试解析为常见结构体类型
crash> struct task_struct <address>     # 进程/任务
crash> struct page <address>            # 内存页
crash> struct vm_area_struct <address> # 虚拟内存区域
crash> struct file <address>            # 文件结构
crash> struct sock <address>            # Socket 结构
crash> struct sk_buff <address>         # 网络包缓冲区

# 步骤 3：如果结构体解析失败，使用原始内存读取
crash> rd <address>                     # 读取原始内存
crash> rd -S <address>                  # 尝试解析为符号
```

## 常用结构体查询表

| 数据类型 | crash 命令 | 用途 |
|----------|-----------|------|
| 进程/任务 | `struct task_struct <addr>` | 查看进程状态、pid、comm、父子关系 |
| 内存页 | `struct page <addr>` | 页状态、引用计数、映射信息 |
| VMA | `struct vm_area_struct <addr>` | 虚拟内存区域、地址范围、权限 |
| 文件 | `struct file <addr>` | 文件句柄、inode、打开模式 |
| Socket | `struct sock <addr>` | 网络连接状态、协议信息 |
| 网络缓冲区 | `struct sk_buff <addr>` | 数据包内容、长度、协议头 |
| 等待队列 | `struct wait_queue <addr>` | 等待事件、进程列表 |
| 互斥锁 | `struct mutex <addr>` | 锁状态、持有者 |
| 自旋锁 | `struct spinlock <addr>` | 锁状态 |

## 实战示例：从地址到结构体

### 示例 1：分析 task_struct

```bash
# 场景：从回溯中获取了一个地址
crash> bt
#0  [<ffff920562309ec0>] xxx_function+0x45

# 分析步骤：
crash> sym ffff920562309ec0
# 输出：ffffffff8100a1c0 (T) __switch_to_asm+0x0

# 尝试解析为 task_struct
crash> struct task_struct ffff920562309ec0
# 输出完整的进程信息：
# struct task_struct {
#     state = 1,
#     comm = "nginx",
#     pid = 12345,
#     stack = 0xfffffb2e6608a4000,
#     ...
# }

# 只查看关键字段
crash> struct task_struct.comm,pid,state,parent ffff920562309ec0
```

### 示例 2：分析 sk_buff（网络包）

```bash
# 分析网络缓冲区
crash> struct sk_buff ffff888012345678
# 输出：
# struct sk_buff {
#     len = 1500,
#     data_len = 0,
#     mac_len = 14,
#     protocol = 0x0800 (IPv4),
#     pkt_type = PACKET_HOST,
#     ...
# }

# 查看数据包内容
crash> rd -s 0xffff888012345678+0x100 100  # 读取数据区域
```

### 示例 3：分析 page 结构

```bash
# 分析内存页
crash> struct page ffff888100000000
# 输出：
# struct page {
#     flags = 0x400000000000,
#     _refcount = 3,
#     mapping = 0xffff888012345678,
#     ...
# }

# 根据 flags 解码页状态
# 0x400000000000 = PG_active | PG_lru
```

## 常见技巧

### 只查看特定字段

```bash
# 查看 task_struct 的 comm 和 pid
crash> struct task_struct.comm,pid ffff888012345678

# 查看多个结构体的某个字段
crash> foreach task | grep comm
```

### 结构体数组

```bash
# 假设有一个 task_struct 数组，起始地址为 addr，间隔为 2048 字节
crash> struct task_struct ffff888012345000
crash> struct task_struct ffff888012345000+2048
crash> struct task_struct ffff888012345000+4096
```

### 配合 grep 过滤

```bash
# 过滤包含特定字符串的字段
crash> struct task_struct ffff888012345678 | grep comm
crash> struct task_struct ffff888012345678 | grep -E "pid|parent"
```

## 注意事项

1. **版本匹配**：确保 vmlinux 与 vmcore 版本匹配，否则 struct 输出可能不准确
2. **类型正确**：不确定时先用 `whatis` 或 `p` 查看类型信息
3. **地址对齐**：某些结构体需要地址对齐，不对齐时 crash 会报错
4. **大小限制**：超大结构体可能截断，使用字段过滤只显示需要的部分
