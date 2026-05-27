# 内核页缓存与回收子系统参考资料

## 1. 关键内核参数速查

| 参数 | 路径 | 说明 | 默认值 | 建议值 |
|------|------|------|--------|--------|
| vm.dirty_ratio | `/proc/sys/vm/dirty_ratio` | 脏页占总内存百分比上限（同步回写阈值） | 20 | 10-20 |
| vm.dirty_background_ratio | `/proc/sys/vm/dirty_background_ratio` | 脏页占总内存百分比（后台回写触发阈值） | 10 | 3-10 |
| vm.dirty_writeback_centisecs | `/proc/sys/vm/dirty_writeback_centisecs` | flusher 线程唤醒间隔（百分之一秒） | 500 | 100-500 |
| vm.dirty_expire_centisecs | `/proc/sys/vm/dirty_expire_centisecs` | 脏页过期时间（百分之一秒） | 3000 | 500-3000 |
| vm.vfs_cache_pressure | `/proc/sys/vm/vfs_cache_pressure` | 缓存回收倾向（越高越积极回收） | 100 | 50-200 |
| vm.swappiness | `/proc/sys/vm/swappiness` | 匿名页交换倾向（越高越倾向 swap） | 60 | 0-100 |
| vm.min_free_kbytes | `/proc/sys/vm/min_free_kbytes` | 最低空闲内存（影响 watermark 计算） | 动态 | 67584(4%) |
| vm.watermark_scale_factor | `/proc/sys/vm/watermark_scale_factor` | watermark 间距缩放因子 | 10 | 10-50 |
| vm.zone_reclaim_mode | `/proc/sys/vm/zone_reclaim_mode` | NUMA 节点回收模式 | 0 | 0-3 |

## 2. 关键 /proc 文件

| 文件 | 用途 | 命令示例 |
|------|------|---------|
| `/proc/meminfo` | 系统内存使用详情 | `grep -E "MemFree|Cached|Dirty|Writeback" /proc/meminfo` |
| `/proc/vmstat` | 虚拟内存统计（回收/分配/缺页） | `grep -E "pgscan|allocstall|pgsteal" /proc/vmstat` |
| `/proc/zoneinfo` | 内存 zone 详细状态（LRU/watermark） | `cat /proc/zoneinfo` |
| `/proc/buddyinfo` | 伙伴系统页面分配情况 | `cat /proc/buddyinfo` |
| `/proc/pressure/memory` | 内存压力 PSI 统计 | `cat /proc/pressure/memory` |
| `/proc/sys/vm/` | 所有 VM 调优参数 | `ls /proc/sys/vm/` |
| `/sys/devices/system/node/node*/vmstat` | NUMA 节点 vmstat | `cat /sys/devices/system/node/node0/vmstat` |

## 3. 关键 /proc/vmstat 计数器

| 计数器 | 含义 | 正常范围 | 异常信号 |
|--------|------|---------|---------|
| pgscan_kswapd | kswapd 扫描的页面数 | 缓慢增长 | 陡增 |
| pgscan_direct | direct reclaim 扫描的页面数 | 0 或接近 0 | > 0 |
| pgsteal_kswapd | kswapd 回收的页面数 | 接近 pgscan_kswapd | 远低于 pgscan |
| pgsteal_direct | direct reclaim 回收的页面数 | 0 | > 0 |
| allocstall | 分配停滞次数 | 0 | > 0 |
| pgmajfault | 主要缺页异常数 | 低 | 飙升 |
| compact_stall | 内存碎片整理停滞次数 | 0 | > 0 |
| compact_fail | 内存碎片整理失败次数 | 低 | 高 |
| nr_dirty | 当前脏页数 | 低 | 接近阈值 |
| nr_writeback | 正在回写页数 | 0 | > 0 |
| nr_dirty_threshold | dirty_ratio 计算的实际阈值 | — | — |
| nr_dirty_background_threshold | dirty_background_ratio 计算的实际阈值 | — | — |

## 4. 内存回收水位线（Watermark）

Linux 内存管理使用三段式水位线控制回收：

```
  内存用量 ↑
      │
高水位 ── normal
      │    (不需要回收)
      │
低水位 ── min → kswapd 唤醒，开始后台回收
      │
      │    (kswapd 回收不足时，进程进入 direct reclaim)
      │
最低   ── OOM → 触发 OOM killer
```

- **min**: 由 `vm.min_free_kbytes` 决定
- **low**: `min + (min * watermark_scale_factor / 10000)`
- **high**: `min + 2 * (min * watermark_scale_factor / 10000)`
- `watermark_scale_factor` 默认 10，增大可扩大 low-high 间距

## 5. LRU 链表类型

```
Active(anon)    — 活跃匿名页（进程堆栈）
Inactive(anon)  — 非活跃匿名页（可 swap 换出）
Active(file)    — 活跃文件页（频繁访问的 page cache）
Inactive(file)  — 非活跃文件页（可回收的 page cache）
Unevictable     — 不可回收页面（mlock 锁定等）
```

kswapd 的扫描顺序：`Inactive(file)` → `Active(file)` → `Inactive(anon)` → `Active(anon)`
