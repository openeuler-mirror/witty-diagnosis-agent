# Off-CPU 联合分析增强 — 测试报告

## 测试环境

| 项目 | 说明 |
|------|------|
| 环境 | 本地 Python 3.13 |
| 测试数据 | FlameGraph test/results/ 中的 folded 文件 |
| 测试日期 | 2026-06-17 |

---

## 测试结果

### 1. Off-CPU 模式库增强

**原有**: 8 种模式 (lock, disk_io, network_io, timer, gc_pause, page_fault, thread_mgmt, memory_alloc)

**新增 5 种**:

| 模式 | 匹配函数 | 置信度 |
|------|---------|:------:|
| signal_wait | sigtimedwait, sigwaitinfo, pause, flush_signals | 1.0 ~ 0.6 |
| memory_wait | alloc_pages, kswapd, reclaim_pages, compact_zone | 1.0 ~ 0.7 |
| barrier | pthread_barrier_wait, CyclicBarrier, CountDownLatch | 1.0 ~ 0.7 |
| rcu_wait | synchronize_rcu, call_rcu, rcu_barrier | 1.0 ~ 0.7 |
| net_io_detailed | tcp_connect, tls_handshake, dns_query, ssl_connect | 0.9 ~ 0.8 |

**总计**: 13 种模式 ✅

### 2. 分类器测试

```
Off-CPU Classification - Total Samples: 200

Category                       Samples      Percent
-------------------------------------------------------
Unknown/Other                  194          97.00%       (预期: perf 样本非 off-cpu 数据)
Network I/O                    4            2.00%        (tcp_sendmsg 匹配)
Timer & Sleep                  1            0.50%        (schedule_timeout 匹配)
Memory Wait (Alloc/Reclaim)    1            0.50%        (alloc_pages 匹配)
```

### 3. 联合分析测试

```json
{
  "wall_clock": {
    "total_samples": 369,
    "on_cpu_pct": 45.8,
    "off_cpu_pct": 54.2
  },
  "time_decomposition": {
    "network_io": 2.0%,
    "timer": 0.5%,
    "memory_wait": 0.5%
  }
}
```

### 4. 数据对齐验证

```json
{
  "pid_match_pct": 0.0%,      // 不同进程的样本，正确报告不一致
  "sample_ratio": "1:0.84"
}
```

---

## 新增文件

| 文件 | 行数 | 功能 |
|------|:----:|------|
| `playbooks/joint-on-off-cpu.md` | 200 | 完整联合分析剧本（含对齐验证、时间分解、交叉验证、6 大场景） |
| `scripts/analyzers/offcpu_classifier.py` | 增强 | 新增 5 种阻塞模式，总计 13 种 |
| `scripts/analyzers/joint_analysis.py` | 138 | 联合分析工具（对齐、分解、交叉验证、根因链） |

---

## 设计说明

### 为什么这么做

| 设计决策 | 原因 |
|---------|------|
| 数据对齐验证独立成模块 | On-CPU 和 Off-CPU 采样来自不同事件源，必须先验证时间窗口和 PID 一致性 |
| blocking_ratio 分段判定 | 定量区分"纯计算"到"纯等待"的连续光谱，避免二值化误判 |
| 墙钟时间分解 | 直观展示"时间花在哪"，比纯采样数更易理解 |
| 交叉验证规则 | On-CPU 和 Off-CPU 互相印证，避免单方面误读 |
| 13 种模式分类 | 覆盖常见阻塞场景（锁、I/O、调度、信号、RCU、屏障等） |

### 如何完成

1. **分析现有代码** — 阅读 offcpu_classifier.py、bottleneck_classifier.py 和 playbooks
2. **补充剧本** — 原剧本 118 行 → 扩充到 200 行，增加数据对齐、时间分解、交叉验证、5 个新场景
3. **增强模式库** — 5 个新模式，每个模式 5-10 个匹配函数 + 置信度权重
4. **创建联合分析工具** — `joint_analysis.py` 整合对齐检查、时间分解、blocking_ratio、根因链
5. **验证** — 使用 FlameGraph 标准测试数据进行功能验证
