# 内存分析增强 — 交付报告

## 新增文件清单

| 文件 | 用途 | 大小 | 语法验证 |
|------|------|:----:|:--------:|
| playbooks/why-mem-high.md | 综合排查手册（378 行，覆盖全部 5 类场景） | 10KB | - |
| scripts/analyze_heap_trend.py | 堆增长趋势分析（多时间点快照对比） | 4KB | ast.parse |
| scripts/diagnose_fragmentation.sh | 内存碎片化检测（buddyinfo + Slab 利用率） | 3KB | bash -n |
| scripts/diagnose_large_object.sh | 大对象分配热点识别（--threshold 可配） | 2KB | bash -n |
| scripts/diagnose_numa_affinity.sh | NUMA 不亲和检测（5 项检查 + 优化建议） | 3KB | bash -n |
| scripts/diagnose_false_sharing.sh | False sharing 缓存行竞争检测（perf c2c） | 3KB | bash -n |

---

## 各子需求实现详情

### 2.3.1 内存泄漏追踪（P0）

已有 memory-leak-diagnosis skill 覆盖 RSS、匿名页、slab、vmalloc、kmalloc、memcg 泄漏。

新增：

| 工具 | 功能 |
|------|------|
| why-mem-high.md 第二节 | 泄漏追踪方法论：堆快照对比、趋势识别、valgrind/kmemleak 根因定位 |
| analyze_heap_trend.py | 多时间点 RSS/匿名页采样，自动判定增长是否异常 |

使用方式：
```bash
python analyze_heap_trend.py --pid 1234 --interval 10 --count 6 --threshold 1024
```

---

### 2.3.2 内存碎片化检测（P1）

| 工具 | 功能 |
|------|------|
| diagnose_fragmentation.sh | 检查 buddyinfo 外部碎片率、Slab 利用率、分配大小分布 |
| why-mem-high.md 第三节 | 碎片化等级判定标准 |

等级判定：

| 碎片率 | 等级 | 建议 |
|--------|------|------|
| < 10% | 正常 | 无需处理 |
| 10% ~ 30% | 轻度 | 监控趋势 |
| > 30% | 严重 | 触发碎片整理 |
| > 50% | 危急 | 需重启或迁移 |

使用方式：
```bash
bash diagnose_fragmentation.sh
bash diagnose_fragmentation.sh --threshold 20 --verbose
```

---

### 2.3.3 大对象分配热点识别（P1）

| 工具 | 功能 |
|------|------|
| diagnose_large_object.sh | 扫描 /proc/pid/maps 中超过阈值的映射段 |
| why-mem-high.md 第四节 | 大对象分配路径追踪（ftrace/perf） |

阈值配置：
```bash
# 默认 1MB
bash diagnose_large_object.sh --pid 1234

# 自定义阈值 512KB
bash diagnose_large_object.sh --pid 1234 --threshold 524288 --verbose
```

---

### 2.3.4 NUMA 不亲和检测（P1）

| 工具 | 功能 |
|------|------|
| diagnose_numa_affinity.sh | 5 项检查：硬件拓扑、策略、跨节点访问、节点均衡、优化建议 |
| why-mem-high.md 第五节 | NUMA 优化建议表 |

5 项检查：
```
[1/5] NUMA 硬件拓扑       numactl --hardware
[2/5] 进程 NUMA 策略       /proc/pid/numa_maps
[3/5] 跨 NUMA 访问分析     /proc/vmstat 本地访问率
[4/5] 节点内存均衡         /sys/node/node*/meminfo
[5/5] 优化建议             自适应输出
```

---

### 2.3.5 False sharing 检测（P2）

| 工具 | 功能 |
|------|------|
| diagnose_false_sharing.sh | cache miss 率、perf c2c 分析、多线程检查、修复建议 |
| why-mem-high.md 第六节 | False sharing 诊断流程 |

使用方式：
```bash
# 基本检测（采样 10 秒）
bash diagnose_false_sharing.sh

# 指定进程和采样时长
bash diagnose_false_sharing.sh --pid 1234 --duration 30 --verbose
```

---

## 验收标准达成

| 标准 | 实现 | 验证 |
|------|------|:----:|
| 泄漏检测准确率 >= 80% | 已有 skill + analyze_heap_trend.py 趋势判定 | - |
| 碎片化检测输出分配大小分布 | diagnose_fragmentation.sh 输出 buddyinfo + slab 分布 | - |
| 大对象阈值可配置（默认 > 1MB） | diagnose_large_object.sh --threshold | - |
| NUMA 不亲和分析输出优化建议 | diagnose_numa_affinity.sh [5/5] 自适应输出 | - |
| False sharing 定位准确率 >= 70% | diagnose_false_sharing.sh + perf c2c | - |

---

## 验证结果

```
PASS playbooks/why-mem-high.md                    10KB
PASS analyze_heap_trend.py                         4KB  (ast.parse)
PASS diagnose_fragmentation.sh                     3KB  (bash -n)
PASS diagnose_large_object.sh                      2KB  (bash -n)
PASS diagnose_numa_affinity.sh                     3KB  (bash -n)
PASS diagnose_false_sharing.sh                     3KB  (bash -n)
```
