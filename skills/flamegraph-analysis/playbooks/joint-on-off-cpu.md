# Joint On/Off-CPU Analysis - 联合分析剧本 (完整版)

## 触发条件

用户问题包含以下关键词：
- "为什么慢" / "性能问题" / "响应延迟"
- 提供 On-CPU 和 Off-CPU 两份采样
- "阻塞" / "等待" / "CPU 不高但慢"

## 场景说明

- **On-CPU**: CPU 真正执行代码的时间
- **Off-CPU**: 线程等待（I/O、锁、调度、信号、内存等）的时间

联合分析帮助理解：
- 纯计算瓶颈 vs 纯等待瓶颈
- 计算+等待的混合瓶颈
- 端到端墙钟时间分解

---

## Step 1: 数据对齐验证

在开始分析前，必须验证两份采样是否对齐。

### 1.1 时间窗口一致性

```bash
# On-CPU 采样时间范围
head -1 oncpu.folded | grep -oP '\d+$' || echo "no timestamp"
tail -1 oncpu.folded | grep -oP '\d+$' || echo "no timestamp"

# Off-CPU 采样时间范围
head -1 offcpu.folded | grep -oP '\d+$' || echo "no timestamp"
```

**一致性判定**：

| 条件 | 结论 |
|------|------|
| 时间窗口重叠 ≥ 80% | 直接可用 |
| 时间窗口重叠 50-80% | 部分可用，注意偏差 |
| 时间窗口重叠 < 50% | 重新采样 |

### 1.2 进程 ID 一致性

```bash
# 提取进程名
cat oncpu.folded | head -5 | cut -d';' -f1 | sort -u
cat offcpu.folded | head -5 | cut -d';' -f1 | sort -u
```

**一致性判定**：两份采样的进程名和 PID 应匹配。

### 1.3 输出对齐报告

```bash
python scripts/analyzers/joint_analysis.py --align oncpu.folded offcpu.folded --report
```

输出：
```
对齐验证报告:
  时间窗口重叠: 95.2% ✅
  进程ID匹配:  3/3 ✅
  采样比例:    1:2.3 (on:off)
  质量评分:    良好
```

---

## Step 2: 各自独立分析

```bash
# On-CPU 热点分析
python scripts/analyzers/hotspot.py oncpu.folded --top 20 --json

# Off-CPU 等待分类
python scripts/analyzers/offcpu_classifier.py offcpu.folded --json

# 联合瓶颈分类
python scripts/analyzers/bottleneck_classifier.py oncpu.folded --off-cpu offcpu.folded --json

# 完整联合分析
python scripts/analyzers/joint_analysis.py --on-cpu oncpu.folded --off-cpu offcpu.folded --output /tmp/joint_report.json
```

---

## Step 3: 瓶颈类型判定

根据 `bottleneck_classifier.py` 输出判定：

| 分类 | On-CPU | Off-CPU | blocking_ratio |
|------|--------|---------|----------------|
| cpu_bound | 高 | 低（计算类） | < 0.1 |
| io_bound | 低 | 高（I/O类） | > 0.7 |
| lock_bound | 正常 | 高（锁类） | > 0.5 |
| gc_bound | 波动 | GC相关 | - |
| mixed | 中等 | 中等 | 0.3-0.7 |

---

## Step 4: 联合热点分析

### 4.1 blocking_ratio 计算

对于出现在两侧的栈路径：
```
blocking_ratio = off_samples / (on_samples + off_samples)
```

| ratio | 含义 | 优化方向 |
|-------|------|----------|
| < 0.1 | 纯计算 | 优化算法，减少 CPU 密集操作 |
| 0.1-0.3 | 略偏计算 | 兼顾计算优化和等待减少 |
| 0.3-0.7 | 混合型 | 需要同时优化计算和等待 |
| 0.7-0.9 | 略偏等待 | 主要减少等待时间 |
| > 0.9 | 纯等待 | 定位阻塞原因，减少等待 |

### 4.2 墙钟时间分解

```
墙钟时间 = On-CPU 时间 + Off-CPU 等待时间
                  |
                  ├── 计算时间 (CPU执行)
                  ├── 锁等待 (mutex/futex/rwlock)
                  ├── I/O 等待 (disk/network)
                  ├── 信号等待 (signal/rcu)
                  ├── 内存等待 (alloc/fault/swap)
                  ├── GC 暂停 (gc_pause)
                  ├── 调度等待 (schedule)
                  └── 其他 (timer/sleep/unknown)
```

### 4.3 交叉验证规则

| On-CPU 现象 | Off-CPU 现象 | 交叉验证结论 |
|-------------|-------------|-------------|
| spin_lock 高 | futex_wait 高 | 锁竞争严重 ✅ |
| 系统调用高 | io_schedule 高 | I/O 瓶颈 ✅ |
| 无热点 | 大量 sleep | 空闲等待 ✅ |
| GC 线程忙碌 | safepoint 等待 | GC 压力 ✅ |
| 计算密集 | 无等待 | 纯计算瓶颈 ✅ |

---

## Step 5: 输出根因链

```
瓶颈分析链:

[原始帧] → [模式分类] → [瓶颈类型] → [根因描述] → [优化建议]
--------------------------------------------------------------------------------
pg.acquireConn → lock → lock_bound → 数据库连接池耗尽 → 增大连接池或使用异步
cache.lookup → disk_io → io_bound → 缓存未命中频繁 → 增大缓存或预加载
crypto.verifySignature → cpu → cpu_bound → RSA4096 计算开销大 → 升级硬件或改用 ECDSA
```

---

## 典型场景

### 场景 1: CPU 计算瓶颈
- On-CPU: 高占比, Off-CPU: 低占比
- `blocking_ratio < 0.1`
- 建议：优化算法, 减少不必要计算

### 场景 2: I/O 等待瓶颈
- On-CPU: 低占比, Off-CPU: 高占比（I/O类）
- 建议：异步 I/O, 增加并发

### 场景 3: 锁竞争瓶颈
- On-CPU: 正常, Off-CPU: 高占比（锁类）
- 建议：减少锁粒度, 优化锁策略

### 场景 4: 混合瓶颈
- On-CPU: 中等, Off-CPU: 中等
- `blocking_ratio ≈ 0.5`
- 建议：系统性优化, 计算和等待同时处理

### 场景 5: 信号等待瓶颈
- On-CPU: 低, Off-CPU: 信号类高
- 建议：减少信号使用频率, 使用事件驱动替代

### 场景 6: 内存等待瓶颈
- On-CPU: 低, Off-CPU: 内存类高
- 建议：减少分配频率, 使用对象池

---

## 配套脚本

| 脚本 | 功能 |
|------|------|
| `offcpu_classifier.py` | Off-CPU 等待原因分类 |
| `bottleneck_classifier.py` | 瓶颈类型判定 + 根因链 |
| `joint_analysis.py` | 联合分析 + 数据对齐 + 时间分解 |
| `hotspot.py` | On-CPU 热点分析 |
