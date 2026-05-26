# sysctl vm 参数调优指南

## 一、脏页回写相关

### dirty_ratio vs dirty_background_ratio

```text
dirty_background_ratio (默认 10%)
    ↓ 脏页达到此阈值 → 后台 flusher 线程开始回写（非阻塞）
    ↓
dirty_ratio (默认 20%)
    ↓ 脏页达到此阈值 → 写入进程被阻塞（同步回写，产生延迟）
```

**调优建议**：

| 场景 | dirty_ratio | dirty_background_ratio | 说明 |
|------|------------|----------------------|------|
| 通用服务器 | 20 | 10 | 默认值，均衡 |
| 写密集型（数据库） | 10-15 | 3-5 | 减少脏页积累，降低 writeback 延迟 |
| 读密集型（CDN/静态） | 30-50 | 20-30 | 容忍更多脏页，减少 flusher 唤醒 |
| SSD 场景 | 20-30 | 10-15 | SSD 写 IO 快，可接受更高阈值 |

### dirty_writeback_centisecs

flusher 线程唤醒频率。默认 500（5 秒一次）。降低到 100（1 秒）可让回写更平滑，但增加 CPU 开销。

### dirty_expire_centisecs

脏页最长逗留时间。默认 3000（30 秒）。超过此时间的脏页会被 flusher 强制回写。

## 二、缓存回收相关

### vfs_cache_pressure

| 值 | 行为 |
|----|------|
| 0 | 不回收 dentries/inode 缓存（可能导致内存不足） |
| < 100 | 回收倾向降低 |
| 100 | 默认值，均衡 |
| > 100 | 回收倾向增高 |
| 10000 | 紧急回收模式 |

### swappiness

| 值 | 行为 |
|----|------|
| 0 | 除非内存极度不足，否则不 swap |
| 1 | 最小 swap（RHEL8 推荐） |
| 10-30 | 服务器场景推荐（倾向于回收 page cache 而非 swap） |
| 60 | 默认值 |
| 100 | 积极 swap |

## 三、内存分配相关

### min_free_kbytes

影响 watermark（水位线）计算。增大此值：
- 优点：保留更多空闲内存，降低 direct reclaim 概率
- 缺点：可用内存减少，page cache 可用空间变小

计算建议：MemTotal * 0.4% ~ 4%（视 workload 而定）

### watermark_scale_factor

控制 low 和 high 水位线之间的间距。默认 10。
- 增大（如 50）：low-high 间距扩大 → kswapd 更早启动 → 减少 direct reclaim，但 kswapd CPU 增加
- 减小（如 5）：low-high 间距缩小 → kswapd 更晚启动 → 减少 kswapd CPU，但增加 direct reclaim 风险

## 四、NUMA 相关

### zone_reclaim_mode

| 值 | 行为 |
|----|------|
| 0 | 关闭，允许跨节点分配（默认） |
| 1 | 优先本地节点回收，再考虑跨节点分配 |
| 3 | 本地节点回收 + 脏页回写后回收 |
| 4 | 随机分配 |

## 五、PSI（Pressure Stall Information）

内核 5.4+ 提供的 `/proc/pressure/memory`：

```
some avg10=0.00 avg60=0.00 avg300=0.00 total=0
full avg10=0.00 avg60=0.00 avg300=0.00 total=0
```

- **some**: 至少一个任务因内存而 stall 的时间百分比
- **full**: 所有任务都 stall 的时间百分比
- **avg10/60/300**: 过去 10/60/300 秒的平均值
- 当 `full avg10 > 10` 时表示内存已严重不足
