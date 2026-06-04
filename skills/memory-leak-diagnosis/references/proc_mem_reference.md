# /proc 内存诊断参考

## 1. /proc/meminfo 关键字段

| 字段 | 说明 | 正常值参考 |
|------|------|-----------|
| MemTotal | 物理内存总量 | 固定值 |
| MemFree | 空闲内存 | 随负载变化 |
| MemAvailable | 可用内存（含可回收缓存） | MemFree + 可回收部分 |
| Buffers | 块设备缓存 | 一般较小 |
| Cached | page cache + tmpfs | 通常数百 MB~数 GB |
| Slab | Slab 分配器总使用 | 通常 < 1GB |
| SReclaimable | 可回收 Slab | Slab 的一部分 |
| SUnreclaim | 不可回收 Slab | Slab 的另一部分 |
| VmallocTotal | vmalloc 虚拟地址总量 | 通常 256TB (x86_64) |
| VmallocUsed | vmalloc 已用 | 通常 < 256MB |
| VmallocChunk | vmalloc 最大连续可用 | 远小于 VmallocUsed 时指示碎片 |
| AnonPages | 匿名页总量 | 与进程 RSS 相关 |
| Unevictable | 不可换出页 | 通常较小 |
| PageTables | 页表占用 | 与进程数相关 |
| KernelStack | 内核栈 | 与进程数相关 |
| Shmem | 共享内存 + tmpfs | 包含在 Cached 中 |
| Committed_AS | 已承诺内存 | 可能超 MemTotal（overcommit）|

## 2. /proc/[pid]/status 内存字段

| 字段 | 说明 |
|------|------|
| VmPeak | 虚拟内存峰值 |
| VmSize | 虚拟内存总量 |
| VmLck | 锁定的内存 |
| VmPin | 固定的内存 |
| VmHWM | RSS 峰值 |
| VmRSS | 实际物理内存 |
| RssAnon | 匿名 RSS |
| RssFile | 文件映射 RSS |
| RssShmem | 共享内存 RSS |
| VmData | 数据段（heap） |
| VmStk | 栈 |
| VmExe | 可执行代码 |
| VmLib | 共享库 |
| VmPTE | 页表条目 |

## 3. /proc/[pid]/smaps 关键行说明

| 行前缀 | 含义 | 关注点 |
|--------|------|--------|
| Size | 映射区域大小 | 虚拟内存 |
| Rss | 驻留物理内存 | 物理内存占用 |
| Pss | 比例集大小（共享页均分） | 精确内存占用 |
| Anonymous | 匿名页 | **泄漏关键指标** |
| Swap | 换出到 swap 的页 | 换出量 |
| Locked | 锁定页 | 是否 mlock |
| VmFlags | 标志位 | rd/wr/ex/sh/may… |

## 4. /proc/slabinfo 关键概念

| 概念 | 说明 |
|------|------|
| cache_name | slab 缓存名称，如 `kmalloc-128`、`dentry`、`inode_cache` |
| active_objs | 当前活跃对象数 |
| num_objs | 总对象数（含空闲） |
| objsize | 每个对象大小 |
| objperslab | 每个 slab 有多少对象 |
| pagesperslab | 每个 slab 占多少页 |

**泄漏识别**：`active_objs` 持续增长且不回落，或 `num_objs` 不断增加（系统持续分配新 slab）。

## 5. kmemleak 使用方法

```bash
# 启用 kmemleak
echo scan > /sys/kernel/debug/kmemleak

# 查看泄漏报告
cat /sys/kernel/debug/kmemleak

# 清除已扫描记录
echo clear > /sys/kernel/debug/kmemleak
```

kmemleak 输出示例：
```
unreferenced object 0xffff888123456780 (size 128):
  comm "kworker/0:1", pid 1234, jiffies 4295123456
  backtrace:
    [<ffffffff81111111>] kmem_cache_alloc+0x...
    [<ffffffff82222222>] alloc_netdev_mqs+0x...
    [<ffffffff83333333>] e1000_probe+0x...
```
