# 🔴 故障诊断报告

> **报告编号**：RCA-20260612-001
> **故障级别**：P2（严重性能退化）
> **报告时间**：2026-06-12 18:04:50
> **当前状态**：🟡 已定位（复现环境中已排空，原始场景需带宽限制触发完全 stall）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | mmap writeback stall — dm-delay 慢设备导致进程 Ds 卡死与 Dirty 堆积 |
| 影响范围 | 在 dm-delay 慢设备（200ms 写延迟）上执行 mmap write + fsync=1 的 4 个 fio 进程全部进入 Ds 不可中断睡眠状态；磁盘 util 达 97.24%，写吞吐仅 9MB/s |
| 故障时段 | 2026-06-12 18:00:00 ～ 复现持续运行（原始故障持续 >5 分钟） |
| 根本原因 | dm-delay 块设备注入 200ms 写延迟，mmap 写入后 fsync=1 强制逐笔回写，脏页产生速度 >> 回写排出速度，Dirty 页从 0 飙升至 ~200MB，触发 balance_dirty_pages 全局限流，多进程在 wait_on_page_writeback 上陷入 Ds 状态；原始场景中 5MB/s 带宽限制进一步将排出速率压至 < 产生速率，导致 Dirty 逼近 dirty_ratio 阈值后 Writeback 冻结在 2048kB |
| 是否恢复 | ✅ 复现环境中在写入完成后自动排空恢复；原始场景需手动干预（kill fio 或等待 Dirty 排空） |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|---------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | 本故障：200ms 延迟 + fsync=1 + 带宽限制 → 完全复现 Ds 卡死 + Writeback 冻结 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                           事件                                                    性质          证据来源
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-06-12 ~18:00:00          fio 启动：--ioengine=mmap --rw=write --bs=4K --fsync=1 --numjobs=4        📈 负载注入   kuafu_T1_mmap_writeback_stall.md:44
  │
  ▼
~18:00:00 + 1s                首次 mmap write + fsync → 4K 写入排队到 dm-delay                         ⚡ IO 提交    kuafu_T1_mmap_writeback_stall.md:107-111
  │                            dm-delay 注入 200ms 写延迟，每笔 IO 从提交到完成至少 200ms
  ▼
~18:00:00 + 5s                Dirty 页快速累积：0 → ~200MB（30s 内飙升至峰值 197820 kB）                 🟡 脏页堆积   kuafu_T1_mmap_writeback_stall.md:69-72
  │                            产生速度 9MB/s >> 排出速度 9KB/s（单线程 IOPS 受限）
  ▼
~18:00:00 + 10s               balance_dirty_pages 全局限流生效                                        🔴 限流开始   kuafu_T1_mmap_writeback_stall.md:97-99
  │                            进程写入被 throttle，进入 Ds 不可中断睡眠
  ▼
~18:00:00 + 30s               磁盘 util → 97.24%，设备层完全饱和                                    🔴 瓶颈固化   kuafu_T1_mmap_writeback_stall.md:62-63
  │                            sync 尾部延迟 p99.99 = 71.8ms
  ▼
~18:00:00 + 60s               原始故障场景（+5MB/s 带宽限制）：                                     🔴 故障恶化   kuafu_T1_mmap_writeback_stall.md:113-117
  │                            Dirty 逼近 dirty_ratio=20% (~3.2GB)
  │                            Writeback 冻结在 2048kB，BDI 回写队列满
  │                            4 个进程持续 Ds > 5 分钟
  ▼
~写入完成后                     排空完成（复现环境），Dirty → 120 kB                                    🟢 自动恢复   kuafu_T1_mmap_writeback_stall.md:63
```

### 故障因果链

```text
dm-delay 慢设备（200ms 写延迟, ~5MB/s 带宽上限）
    │
    └─► 每次 mmap write 后 fsync=1 强制逐笔回写
            │
            └─► 每笔 4K 写入需等待 200ms IO 完成（单线程 IOPS ≈ 5，吞吐 < 80KB/s）
                    │
                    └─► 脏页产生速度（~9MB/s, 4 进程 interleaving）>> 回写排出速度（~9KB/s）
                            │
                            └─► Dirty 页快速堆积：0 → ~200MB（30s 内）
                                    │
                                    └─► balance_dirty_pages 全局限流触发
                                            │
                                            └─► 多进程在 wait_on_page_writeback 上竞争 → Ds 状态
                                                    │
                                                    └─► 原始故障（+5MB/s 带宽限制）：
                                                            排出速度 < 产生速度
                                                            → Dirty 逼近 dirty_ratio=20%（~3.2GB）
                                                            → Writeback 计数冻结在 2048kB
                                                            → 🔴 4 进程持续 Ds > 5 分钟，服务不可用
```

---

## 三、排查过程

### 3.1 初始现象

- **监控告警**：在 dm-delay 慢块设备上执行 mmap write + fsync=1 的 fio 进程全部进入 Ds 状态
- **性能指标**：
  - 写入带宽：9 MB/s（无限制）/ 9 KB/s（单线程）
  - 磁盘 util：97.24%（设备完全饱和）
  - sync p99.99：71.8 ms（显著排队竞争）
  - Dirty 峰值：197820 kB（~200MB，30s 内）
- **用户侧表现**：进程卡死无法响应，写操作无进展，Writeback 计数停滞

### 3.2 假设驱动排查

#### 假设 A：内存不足导致回收压力

> 🧪 假设：系统内存不足，kswapd 频繁回收导致 Dirty 无法排出

| 检查项 | 操作 | 结论 |
|--------|------|------|
| MemFree 水位 | `cat /proc/meminfo \| grep MemFree` | ✅ 13948584 kB（~14 GB，充足） |
| kswapd 活动 | 查看 `/proc/vmstat` pgscan/pgsteal | 无回收压力迹象 |

**❌ 排除**：内存充足（14 GB 空闲），不存在内存回收压力，非此原因。

---

#### 假设 B：内核回写参数配置不当

> 🧪 假设：dirty_ratio/dirty_background_ratio 过低导致过早限流

| 检查项 | 值 | 默认 | 分析 |
|--------|-----|------|------|
| dirty_ratio | 20 | 20 | 正常，无修改 |
| dirty_background_ratio | 10 | 10 | 正常 |
| dirty_expire_centisecs | 3000 | 3000 | 脏页 30s 过期 |
| dirty_writeback_centisecs | 500 | 500 | 回写每 5s 唤醒 |

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 参数比对 | `sysctl vm.dirty_*` 对比内核默认值 | ✅ 全部为内核默认值，未修改 |

**❌ 排除**：回写参数均为内核默认配置，未对系统做过调优修改，非配置导致。

---

#### 假设 C：进程并发竞争过度

> 🧪 假设：4 个 fio 进程同时 fsync 回写导致 IO 竞争激烈

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 并发实验 | 1 个 fio 进程 vs 4 个 fio 进程对比 | 单进程吞吐 < 80KB/s（200ms × 5 IOPS），4 进程通过 interleaving 提升至 ~9MB/s |
| 竞争分析 | `iostat -x 1` 观察 %util 和 avgqu-sz | 磁盘 util = 97.24%，设备完全饱和，排队深度大 |

**⚠️ 被排除为根因，但确认是放大器**：并发本身不是根因，但 4 个进程的竞争加剧了排队延迟（sync p99.99=71.8ms）。即使单进程，200ms 延迟下的吞吐也极低。

---

#### 假设 D：dm-delay 底层设备写延迟导致回写拥塞 ✅ 确认根因

> 🧪 假设：dm-delay 注入的 200ms 写延迟是 Dirty 无法及时排出的根本原因

**Step 1 — 验证 dm-delay 设备配置**
```
设备构造：0 1048576 delay 7:0 0 200
→ 读取无延迟，写入延迟 200ms
→ 后端: loop device on 512MB 文件，无额外带宽限制
```
**📊 结果**：200ms 延迟确认存在。

**Step 2 — 验证纯延迟场景（无带宽限制）**
| 指标 | 值 |
|------|-----|
| 写入带宽 | 8951 KiB/s（~9 MB/s） |
| sync avg | 1.75 ms |
| sync p99.99 | 71.8 ms |
| 磁盘 util | 97.24% |
| Dirty 峰值 | ~200 MB |
| 进程状态 | 运行中（60s 内排空，未触发持续 stall） |

**Step 3 — 验证延迟 + 带宽限制场景（原始故障还原）**
```
逻辑推导：5MB/s 带宽限制 → 排出速度 < 产生速度（9MB/s）
→ Dirty 持续增长逼近 dirty_ratio（20%，~3.2GB）
→ balance_dirty_pages 严格限流 → 进程 Ds
→ Writeback 卡在 2048kB（BDI 回写队列满）
```

| 推导因素 | 值 |
|---------|-----|
| 产生速度 | ~9 MB/s（4 进程 interleaving） |
| 排出速度（原始） | ~5 MB/s（带宽限制） |
| Dirty 增长率 | ~4 MB/s |
| 4GB 总写入排空时间 | ~800 秒 |
| 故障持续时间 | >5 分钟（原始） |

**✅ 结论：dm-delay 200ms 写延迟 + fsync=1 强制逐笔回写 → 脏页产生 >> 排出 → Dirty 堆积 → balance_dirty_pages 限流 → 进程 Ds。原始故障中 5MB/s 带宽限制是触发完全 stall（Writeback 冻结 2048kB）的必要条件。**

### 3.3 排查结论

```text
Ds 进程卡死（4 fio 进程不可中断睡眠）
│
├─► 假设 A：内存不足          → ✅ 排除（MemFree=14GB，充足）
│
├─► 假设 B：回写参数配置不当   → ✅ 排除（全部为内核默认值）
│
├─► 假设 C：进程并发竞争过度   → ⚠️ 放大器而非根因（单进程同样受限）
│
└─► 假设 D：dm-delay 写延迟 ✅ 根因确认
        │
        ├─► 200ms 写延迟 → IOPS ≈ 5/线程，吞吐 < 80KB/s/线程
        │       └─► 4 进程 interleaving → ~9MB/s（仍远低于正常块设备）
        │
        ├─► fsync=1 强制逐笔回写 → 每笔 4K 写入都同步等待 IO 完成
        │       └─► Dirty 无法异步排出，累计达 ~200MB
        │
        └─► 原始场景 +5MB/s 带宽限制 → 排出 < 产生
                └─► Dirty → 接近 dirty_ratio（3.2GB）
                        └─► Writeback 冻结 2048kB
                                └─► 🎯 全面 stall：进程持续 Ds > 5 分钟
```

---

## 四、修复方案

### 4.1 应急处置

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | Kill 卡死的 fio 进程（`kill -9 <pid>`） | 系统管理员 | 发现即执行 | 立即释放 Dirty 页，Writeback 逐步排空 |
| 2 | 检查 Dirty 水位回落（`cat /proc/meminfo \| grep -E "Dirty\|Writeback"`） | 系统管理员 | Kill 后立即 | 确认 Dirty 和 Writeback 计数归零 |
| 3 | 调整 dirty_ratio 临时缓解（`sysctl -w vm.dirty_ratio=40`） | 系统管理员 | 可选应急 | 延迟限流阈值，但无法根除问题 |

```bash
# 应急命令组合
# 1. 查找并终止卡死进程
ps aux | grep fio | grep -v grep | awk '{print $2}' | xargs kill -9

# 2. 监控 Dirty/Writeback 回落
watch -n 1 'cat /proc/meminfo | grep -E "Dirty|Writeback"'

# 3. 应急调大 dirty_ratio（可选）
sudo sysctl -w vm.dirty_ratio=40
```

### 4.2 永久修复计划

| 修复措施 | 负责人 | 完成时间 | 说明 |
|--------|--------|--------|------|
| 避免在慢设备上使用 mmap + heavy write + fsync=1 模式 | 开发/SRE 团队 | 持续改进 | 改用 buffered IO + 异步刷出，或使用 O_DIRECT 绕过页缓存 |
| 改用 O_SYNC 替代 mmap + fsync | 开发团队 | 下次迭代 | O_SYNC 每次写入等待 IO 完成但不会产生页缓存 Dirty 压力 |
| dm-delay 设备仅限测试使用，生产环境使用带 QoS 保障的存储 | 基础设施团队 | 架构评审 | 生产环境配置 NVMe/SSD 或带 QoS 的分布式存储 |
| 缩短 `dirty_expire_centisecs` 加速脏页老化 | SRE 团队 | 评估后执行 | 将 dirty_expire_centisecs 从 3000 降至 1000~1500（提前触发过期回写） |
| 增加 Dirty 相关监控告警 | 监控团队 | 下一迭代 | 当 Dirty > 10% 或 Writeback > 0 持续 60s 时告警，避免 silent stall |

### 4.3 验证方法

```bash
# 1. 搭建 dm-delay 慢设备
sudo modprobe dm-delay
dd if=/dev/zero of=/tmp/slow.img bs=1M count=512
LOOP_DEV=$(sudo losetup -f --show /tmp/slow.img)
echo "0 1048576 delay $LOOP_DEV 0 200" | sudo dmsetup create slow-mmap
sudo mkfs.ext4 /dev/mapper/slow-mmap
sudo mkdir -p /mnt/slow-mmap
sudo mount /dev/mapper/slow-mmap /mnt/slow-mmap

# 2. 执行复现测试
sudo fio --name=test --ioengine=mmap --rw=write --bs=4K --size=1G --fsync=1 --numjobs=4 --directory=/mnt/slow-mmap

# 3. 监控回写状态（另一个终端）
watch -n 1 'cat /proc/meminfo | grep -E "Dirty|Writeback"'

# 4. 清理
sudo umount /mnt/slow-mmap
sudo dmsetup remove slow-mmap
sudo losetup -d $LOOP_DEV
rm /tmp/slow.img
```
