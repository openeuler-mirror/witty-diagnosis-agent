# Python 内存泄漏诊断报告

## 1. 故障概要

| 项目 | 内容 |
| --- | --- |
| **目标脚本** | `global_container_leak.py` — 全局容器泄漏注入脚本 |
| **故障时间窗口** | 800 次迭代 workload 执行期间 |
| **现象** | `LEAK_BUCKET` 全局 list 无界增长，每次迭代 append dict 对象，800 次后容器 len=800 |
| **影响** | Python 对象持续积累，dict 类型 +802 (147,568 B)，list 类型 +805 (73,928 B)；若不设上限将耗尽内存触发 OOM |
| **诊断边界** | 离线本地日志分析，只读，不执行修复/重启/远程登录 |

## 2. 能力画像与降级边界

| 项目 | 内容 |
| --- | --- |
| **使用工具** | stdlib (`gc`, `sys.getsizeof`, `tracemalloc`, `weakref`) |
| **缺失工具** | `psutil` (缺便携采样), `objgraph` (缺回溯图), `pympler` (缺深尺寸), `memray` (缺 native 分配捕获) |
| **降级影响** | 嵌套容器 shallow bytes 可能低估；保留链输出为文本格式 |
| **只读/副作用边界** | 沙箱反事实已执行 `--allow-mutation` 确认根因；生产场景无法验证 |
| **置信度上限** | **高** (strong) — G1/G2/G3 全部通过，沙箱反事实确认 |

## 3. RSS 与增长形态

> 注：本场景为离线分析，RSS 监控数据通过 monitor_rss 收集。

| 项目 | 内容 |
| --- | --- |
| **Python 对象净增长** | dict +147,568 B + list +73,928 B + counter +6,688 B = **~228 KiB** (shallow) |
| **tracemalloc 顶部分配** | **271,196 B (0.259 MiB)** — 前 3 个分配热点合计 |
| **增长形态** | 线性增长，800 次迭代持续递增，未出现 plateau |
| **预热/碎片化/伪泄漏判断** | 已排除缓存预热（无 plateau）、已排除短窗口噪声（800 次迭代稳定增长），非碎片化场景 |
| **native 背离判断** | 不适用 — Python 堆增长能解释 RSS 变化，无 native 背离迹象 |

## 4. Python 对象增长

| 类型 | 计数增量 | 字节增量 (shallow) | MiB | 说明 |
| --- | --- | --- | --- | --- |
| `builtins.dict` | +802 | 147,568 | 0.141 | **主候选** — 每次迭代创建的 dict 容器未释放 |
| `builtins.list` | +805 | 73,928 | 0.071 | 嵌套 list (`tags: [index, index+1, index+2]`) 累积 |
| `collections.Counter` | +2 | 6,688 | 0.006 | 辅助统计对象 |
| **合计** | **+1,609** | **228,184** | **0.218** | shallow 统计，实际 RSS 增长更大 |

**判定**: `python_object_growth_observed` — 对象增长明确，主候选为 `builtins.dict`。

Workload 返回: `{"leak_bucket_len": 800}`

## 5. 分配热点

| # | top_frame (行号) | 代码片段 | count_diff | size_diff (B) | size_diff (MiB) |
| --- | --- | --- | --- | --- | --- |
| 1 | `global_container_leak.py:13` | `{"index": index, "payload": ..., "tags": [...]}` | 1,600 | 147,200 | 0.140 |
| 2 | `global_container_leak.py:16` | `"tags": [index, index + 1, index + 2]` | 2,689 | 98,848 | 0.094 |
| 3 | `global_container_leak.py:11` | `for index in range(iterations):` | 543 | 17,376 | 0.017 |
| 4 | `global_container_leak.py:12` | `LEAK_BUCKET.append(...)` | 1 | 6,880 | 0.007 |
| 5 | `global_container_leak.py:19` | `return {"leak_bucket_len": len(LEAK_BUCKET)}` | 3 | 212 | <0.001 |

**汇总**: 前 3 个热点合计 **271,196 B (0.259 MiB)**

**判定**: `python_allocation_growth_observed` — 分配热点与对象增长类型一致。

> ⚠️ **重要**: tracemalloc 标识的是**分配位置**，不是**保留根因**。分配在 `LEAK_BUCKET.append()` 发生，但真正导致泄漏的原因是这些对象**从未被释放**（见下一节保留链）。

## 6. 保留链

| 候选对象 | root_kind | 保留路径摘要 | 说明 |
| --- | --- | --- | --- |
| `dict item in LEAK_BUCKET` | `module_global:LEAK_BUCKET` | `dict_item → [LEAK_BUCKET list] → module global LEAK_BUCKET` | **主根因** — 全局模块变量 LEAK_BUCKET 持有所有已分配 dict 的引用 |
| `builtins 模块 dict` | `closure_cell` | `builtins.dict → <module 'builtins'> → len → cell` | Python 内部闭包持有，非泄漏根因 |
| `模块命名空间` | `module_global_dict` | 模块全局 dict 自身 | 正常模块引用，不构成泄漏 |

**判定**: `retention_chain_observed` — 保留链指向 **`module_global:LEAK_BUCKET`**，对应 `root-cause-patterns.md` 中的"全局容器无界增长"模式。

## 7. 验证门

| 验证门 | 结果 | 证据 |
| --- | --- | --- |
| **G1 量化对账** | ✅ **通过** | 主候选 dict (+802, 147,568 B) 是最大增长类型，与 tracemalloc 热点一致 |
| **G2 竞争假设** | ✅ **通过** | 排除：非缓存预热（无 plateau）、非碎片化场景、非 native 背离、800 次迭代稳定增长 |
| **G3 可达性 (反事实)** | ✅ **通过 (strong)** | 沙箱中 `clear()` LEAK_BUCKET → `gc.collect()` → 对象计数从 1,747 降至 948 (reclaimed_ratio=1.0, candidate_reclaimed_ratio=0.457)；置信度 `strong` |
| **G4 隔离复测** | ⏭️ **未执行** | 只读诊断边界，不执行修复后复测；建议用户修复后复跑验证 |

## 8. 根因结论

| 项目 | 内容 |
| --- | --- |
| **根因类型** | **全局容器无界增长** (Unbounded Global Container Growth) |
| **根因描述** | 模块级全局变量 `LEAK_BUCKET` (builtins.list) 在 workload 迭代过程中持续 append dict 对象，且缺少任何上限控制、淘汰策略或生命周期清理机制。对象的创建 (tracemalloc: L13/L16/L11)、增长 (object_growth: dict/List) 和保留 (retention_chain: `module_global:LEAK_BUCKET`) 三线证据完全收敛至同一根因。 |
| **置信度** | **高 (strong)** — G1+G2+G3 全部通过，沙箱反事实确认回收 45.7% 可疑对象 |
| **未验证项** | G4 隔离复测未执行（只读约束），建议修复后通过 `./run.sh run global` 复跑验证。 |

**证据闭环**:
```
分配线 (tracemalloc L13)         保留线 (retention_chain)
        ↓                                ↓
   创建 dict item ──→ append 到 ──→ LEAK_BUCKET (module_global)
        ↓                                ↓
  object_growth (+802 dict)      module_global:LEAK_BUCKET
        ↓                                ↓
  G1/G2 通过 ←──────────── G3 反事实确认 (reclaimed_ratio=1.0)
```

## 9. 修复建议

| 修复类型 | 建议 | 说明 |
| --- | --- | --- |
| **最小修复** | 设置 `LEAK_BUCKET` 固定上限 (`maxlen`)，用 `collections.deque` 替代 list | 容量到达后自动丢弃旧元素，防止无限增长 |
| **根本修复** | 根据业务语义增加生命周期清理：请求结束或任务完成后 `LEAK_BUCKET.clear()` | 确保对象在不再需要时被显式释放 |
| **防御性** | 添加 `MAX_BUCKET_SIZE` 常量并在 append 前校验 | 防止意外无界增长成为生产事故 |
| **监控建议** | 监控模块级容器长度，设置告警阈值 | 生产环境中早期发现异常增长 |

## 10. 复测方案

| 项目 | 内容 |
| --- | --- |
| **复现命令** | `cd test/python-memory-leak-analyzer && bash ./run.sh run global` |
| **期望指标 (修复后)** | 800 次迭代后 `leak_bucket_len` ≤ 固定上限值；object_growth dict 增量趋近于 0 或维持稳定 |
| **通过条件** | 修复后执行 `object_growth` 判定为 `no_significant_growth`，且 `retention_chain` 不再指向 `module_global:LEAK_BUCKET` 为主要泄漏链 |
