# 内核 VMA 子系统参考资料

## 1. 关键内核参数速查

| 参数 | 路径 | 说明 | 默认值 | 建议值(ES) |
|------|------|------|--------|------------|
| vm.max_map_count | `/proc/sys/vm/max_map_count` | 进程最大 VMA 数量 | 65530 | 262144 |
| vm.overcommit_memory | `/proc/sys/vm/overcommit_memory` | 内存超额分配策略 | 0 | 1(ES) |
| vm.overcommit_ratio | `/proc/sys/vm/overcommit_ratio` | overcommit 比例(overcommit=2) | 50 | - |
| vm.mmap_min_addr | `/proc/sys/vm/mmap_min_addr` | 用户 mmap 最小地址 | 65536 | - |
| kernel.shmall | `/proc/sys/kernel/shmall` | 共享内存页总数上限 | 2^63-1 | - |
| kernel.shmmax | `/proc/sys/kernel/shmmax` | 单共享内存段大小上限 | 2^63-1 | - |
| kernel.shmmni | `/proc/sys/kernel/shmmni` | 系统最大共享内存段数 | 4096 | - |
| vm.legacy_va_layout | `/proc/sys/vm/legacy_va_layout` | 地址空间布局 | 0(随机) | 0 |
| kernel.randomize_va_space | `/proc/sys/kernel/randomize_va_space` | ASLR 级别 | 2 | - |

## 2. 关键 /proc 文件

| 文件 | 用途 | 命令示例 |
|------|------|---------|
| `/proc/<PID>/maps` | 进程 VMA 列表（每行一个 VMA） | `cat /proc/<PID>/maps \| wc -l` |
| `/proc/<PID>/smaps` | 每段 VMA 的详细内存占用 | `grep -A5 "^[0-9a-f]" /proc/<PID>/smaps` |
| `/proc/<PID>/smaps_rollup` | VMA 汇总（内核 4.14+） | `cat /proc/<PID>/smaps_rollup` |
| `/proc/<PID>/numa_maps` | VMA 的 NUMA 分布 | `cat /proc/<PID>/numa_maps` |
| `/proc/<PID>/status` | 进程内存统计 | `grep Vm /proc/<PID>/status` |
| `/proc/<PID>/limits` | 进程资源限制 | `cat /proc/<PID>/limits` |
| `/proc/<PID>/fd/` | 进程打开的文件描述符 | `ls -la /proc/<PID>/fd/` |
| `/proc/meminfo` | 系统内存信息 | `grep -E "(MemTotal|MemFree|Mlocked|Shmem)"` |
| `/proc/buddyinfo` | 伙伴系统页面分配情况 | `cat /proc/buddyinfo` |
| `/proc/pagetypeinfo` | 页面类型分布 | `cat /proc/pagetypeinfo` |

## 3. mmap 系统调用关键参数

```c
#include <sys/mman.h>

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset);
```

### prot（保护标志）

| 标志 | 值 | 说明 |
|------|-----|------|
| PROT_NONE | 0 | 页面不可访问 |
| PROT_READ | 1 | 页面可读 |
| PROT_WRITE | 2 | 页面可写 |
| PROT_EXEC | 4 | 页面可执行 |

### flags（映射标志）

| 标志 | 说明 | 使用场景 |
|------|------|---------|
| MAP_SHARED | 共享映射，写入回文件 | 文件映射，进程间共享 |
| MAP_PRIVATE | 私有映射，写时复制 | 加载程序/库，匿名映射 |
| MAP_ANONYMOUS | 匿名映射，忽略 fd | 内存分配（替代 malloc for large） |
| MAP_FIXED | 固定地址映射 | 需要特定地址（JVM） |
| MAP_FIXED_NOREPLACE | 固定地址不覆盖已有映射 | 安全替代 MAP_FIXED |
| MAP_HUGETLB | 使用大页 | 大数据集、HPC |
| MAP_LOCKED | 映射后立即锁入内存 | 实时应用 |
| MAP_POPULATE | 预填充页表 | 减少缺页异常 |
| MAP_NORESERVE | 不预先保留交换空间 | overcommit 场景 |
| MAP_GROWSDOWN | 栈式增长（向下扩展） | 线程栈 |
| MAP_DENYWRITE | 忽略 | 不再使用 |
| MAP_EXECUTABLE | 忽略 | 不再使用 |

## 4. mmap 常见 errno 原因生成代码示例

### 4.1 触发 max_map_count 耗尽

```c
#include <sys/mman.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main() {
    int page_size = getpagesize();
    int count = 0;
    while (1) {
        void *addr = mmap(NULL, page_size, PROT_NONE,
                          MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (addr == MAP_FAILED) {
            perror("mmap failed");
            printf("Created %d mappings before ENOMEM\n", count);
            break;
        }
        count++;
        if (count % 10000 == 0)
            printf("Created %d mappings\n", count);
    }
    return 0;
}
```

### 4.2 触发 SIGBUS

```c
#include <sys/mman.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <signal.h>

void sigbus_handler(int sig) {
    write(2, "Caught SIGBUS!\n", 15);
    _exit(1);
}

int main() {
    signal(SIGBUS, sigbus_handler);

    int fd = open("/tmp/test_mmap", O_RDWR | O_CREAT, 0666);
    write(fd, "hello world", 12);
    fsync(fd);

    void *addr = mmap(NULL, 4096, PROT_READ, MAP_SHARED, fd, 0);
    close(fd);

    ftruncate(fd, 4); // 截断文件到 4 字节
    char c = ((char *)addr)[1000]; // 访问映射但文件外区域 → SIGBUS
    return 0;
}
```

### 4.3 触发 mlock 超限

```c
#include <sys/mman.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/resource.h>

int main() {
    struct rlimit lim;
    getrlimit(RLIMIT_MEMLOCK, &lim);
    printf("RLIMIT_MEMLOCK: soft=%ld  hard=%ld\n",
           (long)lim.rlim_cur, (long)lim.rlim_max);

    // 尝试锁定超过限制的内存
    size_t size = (lim.rlim_cur == RLIM_INFINITY) ?
                  1024 * 1024 * 1024 : // 1GB if unlimited
                  lim.rlim_cur + 4096; // 否则刚好超过限制

    void *addr = mmap(NULL, size, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (addr == MAP_FAILED) {
        perror("mmap failed");
        return 1;
    }

    if (mlock(addr, size) == -1) {
        perror("mlock failed (expected)");
        printf("Failed to lock %zu bytes\n", size);
    } else {
        printf("mlock succeeded (unexpected)\n");
        munlock(addr, size);
    }

    munmap(addr, size);
    return 0;
}
```

## 5. VMA 类型分类参考

VMA（Virtual Memory Area）是 Linux 内核中描述进程虚拟地址空间连续区域的数据结构。常见 VMA 类型：

| VMA 类型 | maps 输出特征 | 典型用途 |
|---------|--------------|---------|
| 可执行文件映射 | `r-xp` + 文件路径 | 代码段 |
| 共享库映射 | `r-xp` + `/usr/lib/xxx.so` | 动态库 (.text) |
| 数据段 | `rw-p` + 文件路径或堆 | 已初始化数据/BSS |
| 堆 | `rw-p` + `[heap]` | malloc / brk |
| 栈 | `rw-p` + `[stack]` / `[stack:<tid>]` | 函数调用栈 |
| 匿名映射 | `rw-p` + 空文件列 | 匿名 mmap、大 malloc |
| 文件匿名映射 | `rw-s` + `/SYSVxxxxxxxx` | System V 共享内存 |
| vdso/vvar | `r-xp` + `[vdso]` | 用户态系统调用代理 |
| vsyscall | 特定地址 | 遗留系统调用 |
| hugepage | 匿名或文件 + 大页特征 | 大页映射 |

## 6. 诊断工具参考

| 工具 | 命令 | 用途 |
|------|------|------|
| pmap | `pmap -x <PID>` | 进程内存映射 + RSS/PSS/Dirty |
| lsof | `lsof -p <PID>` | 进程打开的文件列表 |
| strace | `strace -e mmap -p <PID>` | 实时追踪 mmap 调用 |
| ltrace | `ltrace -e mmap <cmd>` | 追踪库调用级别的 mmap |
| gdb | `gdb <binary> --ex "info proc mappings"` | 查看进程内存布局 |
| /proc 直接读取 | `cat /proc/<PID>/maps` | 轻量级 VMA 列表 |
| perf | `perf record -e syscalls:sys_enter_mmap` | 统计 mmap 调用频率 |
| valgrind | `valgrind --tool=massif <cmd>` | 分析 mmap 内存分配 |
| heaptrack | `heaptrack <cmd>` | 堆分析 + mmap 追踪 |
