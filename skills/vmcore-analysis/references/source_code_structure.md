# Linux 内核源码目录结构参考

本文档描述 Linux 内核源码目录结构，帮助在进行 vmcore 分析时快速定位相关代码。

## 目录结构说明

```
故障文件夹/
└── src/                          # 内核源码目录
    └── <kernel_version>/         # 内核版本目录 (如 linux-4.19.90-xxx)
        └── [子目录和文件...]
```

## 顶层目录概览

```
<kernel_version>/
├── arch/              # 架构相关代码
├── block/             # 块设备驱动
├── certs/            # 证书签名相关
├── crypto/           # 加密子系统
├── Documentation/    # 内核文档
├── drivers/          # 设备驱动程序
├── firmware/         # 固件blob
├── fs/               # 文件系统
├── include/          # 头文件
├── init/             # 初始化代码
├── ipc/              # 进程间通信
├── kernel/           # 内核核心
├── lib/              # 通用库
├── mm/               # 内存管理
├── net/              # 网络协议栈
├── samples/          # 示例代码
├── scripts/          # 编译脚本
├── security/         # 安全模块
├── sound/            # 声音子系统
├── tools/            # 工具
├── usr/              # 用户空间初始化
└── virt/            # 虚拟化
```

## 核心目录详解

### arch/ - 架构相关代码

包含所有支持的 CPU 架构代码。

| 子目录 | 说明 |
|--------|------|
| `arch/x86/` | Intel x86/x86_64 架构 |
| `arch/arm/` | ARM 32位架构 |
| `arch/arm64/` | ARM 64位架构 (aarch64) |
| `arch/powerpc/` | PowerPC 架构 |
| `arch/s390/` | IBM s390 架构 |

**典型崩溃分析涉及：**
- `arch/x86/kernel/` - x86 核心内核代码
- `arch/x86/mm/` - x86 内存管理
- `arch/x86/entry/` - 系统调用入口

---

### drivers/ - 设备驱动程序

内核中最大的目录，包含所有设备驱动。

| 子目录 | 说明 |
|--------|------|
| `drivers/net/` | 网络设备驱动 |
| `drivers/block/` | 块设备驱动 |
| `drivers/char/` | 字符设备驱动 |
| `drivers/pci/` | PCI 总线驱动 |
| `drivers/scsi/` | SCSI 设备驱动 |
| `drivers/usb/` | USB 设备驱动 |
| `drivers/mmc/` | MMC/SD 卡驱动 |
| `drivers/gpu/` | GPU 驱动 |
| `drivers/infiniband/` | Infiniband 驱动 |
| `drivers/virt/` | 虚拟化驱动 (virtio, kvm) |

**常见崩溃分析涉及：**
- `drivers/net/ethernet/` - 网卡驱动
- `drivers/scsi/` - 存储驱动
- `drivers/virtio/` - 虚拟化驱动

---

### kernel/ - 内核核心

包含内核核心功能代码。

| 子目录/文件 | 说明 |
|-------------|------|
| `kernel/sched/` | 调度器 |
| `kernel/time/` | 时间管理 |
| `kernel/rcu/` | RCU 实现 |
| `kernel/locking/` | 锁实现 |
| `kernel/printk/` | 打印子系统 |
| `kernel/panic.c` | Panic 处理 |

---

### mm/ - 内存管理

内存管理子系统。

| 子目录/文件 | 说明 |
|-------------|------|
| `mm/page_alloc.c` | 页分配器 |
| `mm/slab.c` | Slab 分配器 |
| `mm/slub.c` | SLUB 分配器 |
| `mm/vmalloc.c` | 虚拟内存分配 |
| `mm/memory.c` | 内存管理核心 |
| `mm/oom_kill.c` | OOM Killer |
| `mm/page_table.c` | 页表管理 |

---

### net/ - 网络协议栈

完整的网络协议栈实现。

| 子目录 | 说明 |
|--------|------|
| `net/core/` | 网络核心功能 |
| `net/ipv4/` | IPv4 协议 |
| `net/ipv6/` | IPv6 协议 |
| `net/tcp/` | TCP 协议实现 |
| `net/udp/` | UDP 协议实现 |
| `net/sctp/` | SCTP 协议 |
| `net/netfilter/` | Netfilter 防火墙 |
| `net/wireless/` | 无线网络 |
| `net/bonding/` | 网卡绑定 |

---

### fs/ - 文件系统

所有文件系统实现。

| 子目录 | 说明 |
|--------|------|
| `fs/ext4/` | EXT4 文件系统 |
| `fs/xfs/` | XFS 文件系统 |
| `fs/btrfs/` | Btrfs 文件系统 |
| `fs/nfs/` | NFS 客户端/服务器 |
| `fs/cifs/` | CIFS/SMB |
| `fs/fuse/` | FUSE 用户态文件系统 |
| `fs/vfs/` | VFS 虚拟文件系统层 |

---

### include/ - 头文件

内核头文件。

| 子目录 | 说明 |
|--------|------|
| `include/linux/` | 通用 Linux 头文件 |
| `include/asm/` | 架构相关头文件 |
| `include/net/` | 网络相关头文件 |
| `include/uapi/` | 用户空间 API |

---

### block/ - 块设备层

块设备抽象层和调度器。

| 文件 | 说明 |
|------|------|
| `block/blk-core.c` | 块设备核心 |
| `block/blk-iopoll.c` | IO 轮询 |
| `block/cfq-iosched.c` | CFQ 调度器 |
| `block/deadline-iosched.c` | Deadline 调度器 |

---

### crypto/ - 加密子系统

加密算法实现。

| 子目录 | 说明 |
|--------|------|
| `crypto/api.c` | 加密 API |
| `crypto/algapi.c` | 算法 API |
| `crypto/aead.c` | AEAD 加密 |
| `crypto/crypto_user.c` | 用户空间接口 |

---

### security/ - 安全模块

安全框架和模块。

| 子目录 | 说明 |
|--------|------|
| `security/selinux/` | SELinux |
| `security/apparmor/` | AppArmor |
| `security/tomoyo/` | TOMOYO |
| `security/smack/` | SMACK |
| `security/keys/` | 密钥管理 |

---

### ipc/ - 进程间通信

IPC 机制实现。

| 文件 | 说明 |
|------|------|
| `ipc/msg.c` | 消息队列 |
| `ipc/sem.c` | 信号量 |
| `ipc/shm.c` | 共享内存 |
| `ipc/util.c` | IPC 公共函数 |

---

### init/ - 初始化代码

内核启动初始化代码。

| 文件 | 说明 |
|------|------|
| `init/main.c` | 主初始化 |
| `init/Kconfig` | 配置定义 |

---

### virt/ - 虚拟化

虚拟化相关代码。

| 目录 | 说明 |
|------|------|
| `virt/kvm/` | KVM 虚拟化 |
| `virt/vz/` | 容器/虚拟化 |

---

## 崩溃分析常用路径速查

| 崩溃类型 | 源码目录 |
|----------|----------|
| **空指针解引用** | `mm/`, `kernel/`, 对应子系统目录 |
| **内存泄漏/OOM** | `mm/slab.c`, `mm/slub.c`, `mm/page_alloc.c` |
| **死锁** | `kernel/locking/`, `kernel/sched/` |
| **文件系统崩溃** | `fs/ext4/`, `fs/xfs/`, `fs/vfs/` |
| **网络问题** | `net/core/`, `net/ipv4/`, `net/tcp/` |
| **块设备/IO** | `block/`, `drivers/scsi/`, `drivers/block/` |
| **驱动崩溃** | `drivers/` 下对应驱动目录 |
| **VM/KVM** | `virt/kvm/`, `arch/x86/kvm/` |
| **RCU stall** | `kernel/rcu/` |

---

## 常用源码查找命令

### 查找函数定义

```bash
# 在源码中查找函数
grep -rn "function_name" src/

# 查找结构体定义
grep -rn "struct struct_name {" src/include/linux/

# 查找函数定义（带返回类型）
grep -rn "^int function_name" src/
```

### 查找调用关系

```bash
# 查找函数调用点
grep -rn "function_name(" src/ | grep -v "define"

# 查找被调用的函数
grep -rn "called" src/function.c
```

### 查找错误处理

```bash
# 查找返回值检查
grep -rn "if.*NULL" src/
grep -rn "if.*-E" src/

# 查找 goto 错误路径
grep -rn "goto.*error\|goto.*fail" src/
```

### 内存分配相关

```bash
# 查找内存分配
grep -rn "kmalloc\|kzalloc\|kmem_cache_alloc" src/

# 查找内存释放
grep -rn "kfree\|kmem_cache_free" src/
```

---

## 源码版本确认

确认源码版本与 vmcore 匹配：

```bash
# 源码版本
head -5 src/Makefile
cat src/include/generated/uapi/linux/version.h 2>/dev/null

# vmcore 版本
crash> sys | grep "KERNEL"
```

⚠️ **重要**：源码版本必须与 vmcore 的 vmlinux 版本完全匹配，否则分析结论可能无效。
