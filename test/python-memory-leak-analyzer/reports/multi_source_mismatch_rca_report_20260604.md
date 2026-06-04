# Python 内存泄漏根因分析报告：multi_source_mismatch

## 1. 故障概要与影响

| 项目 | 内容 |
|------|------|
| **场景** | multi_source_mismatch（多源竞争泄漏） |
| **Workload** | 600 次迭代 |
| **摘要** | 小 global 泄漏作为干扰项，同时存在更大的 listener 和无界缓存泄漏来源 |
| **诊断边界** | 离线本地日志只读诊断，不执行修复、重启、远程登录或配置写入 |
| **工作目录** | `D:\develop\Trae\OpenEuler\witty-diagnosis-agent\skills\python-memory-leak-analyzer` |

### 三源竞争概览

| 泄漏源 | 类型 | 增长量 | 语义分数 | 占比评估 |
|---------|------|--------|---------|---------|
| **LISTENERS** 🔴 | 全局 registry 持有 bound method | 600 → 600 个 bound method | **645** | **主导泄漏源** |
| **tenant_lookup** 🟠 | 无界缓存 (maxsize=None) | 0 → 600 条目 | **600** | 次要泄漏源 |
| **SMALL_GLOBAL** 🟢 | 小全局容器增长 | 0 → 30 条目 (312 bytes) | **30** | 干扰项 |

---

## 2. 能力画像与降级边界

| 探测项 | 可用性 | 影响 |
|--------|--------|------|
| psutil | ❌ 缺失 | monitor_rss 使用 /proc-only RSS 采集 |
| objgraph | ❌ 缺失 | retention_chain 使用 stdlib gc.get_referrers 文本链 |
| pympler | ❌ 缺失 | object_growth 使用 sys.getsizeof 浅层字节 |
| memray | ❌ 缺失 | native 泄漏路径保持方向级判断 |
| dot/binaries | ❌ 缺失 | 无 graphviz 图渲染 |
| gdb/ptrace | ❌ 不可用 | 无法附加线上进程 |
| /proc/smaps_rollup | ✅ 可用 | RSS 外部观测可行 |
| Python 版本 | 3.12.3 | stdlib 工具链完整 |

**降级结论**: 本轮分析基于 stdlib-only 工具链（gc + sys.getsizeof + tracemalloc），浅层字节可能低估嵌套容器；native/arena 方向仅能做方向级推断。

---

## 3. 对象增长证据（object_growth）

### 类型增长 Top 5

| 类型 | count_after | count_before | delta | 浅层字节增量 | 占比 |
|------|------------|-------------|-------|------------|------|
| **builtins.method** | 602 | 2 | **+600** | 38,400 (0.037 MiB) | 37.5% |
| **mlda_workload.LargeTenant** | 600 | 0 | **+600** | 28,800 (0.027 MiB) | 28.1% |
| builtins.dict | 945 | 941 | +4 | 19,064 (0.018 MiB) | 18.6% |
| builtins.list | 241 | 236 | +5 | 8,680 (0.008 MiB) | 8.5% |
| collections.Counter | 4 | 2 | +2 | 6,688 (0.006 MiB) | 6.5% |

**Verdict**: `python_object_growth_observed`

**Primary Candidate**: `builtins.method`（增长 600 个，delta 最大）

### 大容器（Workload 后）

| 容器 | 长度 | 浅层字节 | 说明 |
|------|------|---------|------|
| `builtins.list` (2965 items) | 2,965 | 26,040 | 模块内部符号表 |
| `builtins.dict` (600 entries) 🔴 | 600 | 18,512 | **tenant_lookup 缓存** |
| `builtins.list` (600 items) 🔴 | 600 | 5,432 | **LISTENERS 全局 registry** |

**对账**: `builtins.method` +600 和 `mlda_workload.LargeTenant` +600 完美对应 LISTENERS 的 600 个 bound method 及其实例。tracemalloc 总分配增长 ~22.54 MiB 远大于浅层字节，说明 **LargeTenant 的深层 payload（profile 字符串）是真正的 RSS 消耗大头**。

---

## 4. 语义保留信号（semantic_probe）

### 主导信号排行

| 信号 | 名称 | 分数 | 标签 | 增长量 |
|------|------|------|------|-------|
| **#1** 🔴 | **LISTENERS** | **645** | `global_registry_retains_bound_methods` | 0 → 600 items |
| **#2** 🟠 | **tenant_lookup** | **600** | `unbounded_cache_growth` | 0 → 600 entries |
| #3 🟢 | SMALL_GLOBAL | 30 | `global_container_growth` | 0 → 30 items (312 B) |

### LISTENERS 详情

```
名称:     LISTENERS
类型:     builtins.list
增长:     0 → 600 (delta=600)
浅层字节:  5,432 (0.005 MiB)
角色计数:  bound_method × 20 (抽样)
标签:     global_registry_retains_bound_methods
评分:     645
```

抽样 bound method 示例：
- `<bound method LargeTenant.callback of <mlda_workload.LargeTenant object at 0x78cb75522330>>`
- `<bound method LargeTenant.callback of <mlda_workload.LargeTenant object at 0x78cb74adb860>>`

**结论**: 全局 LISTENERS 列表用于注册回调，但 never cleaned up —— 600 个 LargeTenant 实例各有一个 bound method 被 LISTENERS 持有，形成一个 `global → list → bound_method → LargeTenant` 的强可达保留链。

### tenant_lookup 缓存详情

```
名称:     tenant_lookup
类型:     cache_function (lru_cache wrapper)
增长:     currsize 0 → 600 (delta=600)
maxsize:  None (无界!)
命中率:   0/600 (miss=600, hits=0)
标签:     unbounded_cache_growth
评分:     600
```

**结论**: `@lru_cache(maxsize=None)` 的无界缓存。600 次调用全部 miss，缓存永远不会淘汰，所有 key-value 永久保留。

### SMALL_GLOBAL 详情

```
名称:     SMALL_GLOBAL
类型:     builtins.list
增长:     0 → 30 (delta=30)
浅层字节:  312 (0.000 MiB)
标签:     global_container_growth
评分:     30 (远低于其他信号)
```

**结论**: 仅 30 条小字典，312 bytes —— 虽在增长但量级极小，**不应被误判为主根因**。

---

## 5. 分配热点证据（tracemalloc_probe）

| 排名 | 位置 | 分配次数 | 字节增量 | MiB | 对应泄漏源 |
|------|------|---------|---------|-----|-----------|
| #1 | `multi_source_mismatch.py:23` | 600 | 12,312,600 | **11.74** | tenant_lookup value |
| #2 | `multi_source_mismatch.py:13` | 600 | 11,083,800 | **10.57** | LargeTenant 实例 |
| #3 | `multi_source_mismatch.py:21` | 1,200 | 110,400 | 0.105 | tenant_lookup key |
| #4 | `multi_source_mismatch.py:37` | 1,200 | 51,168 | 0.049 | SMALL_GLOBAL |
| #5 | `multi_source_mismatch.py:38` | 601 | 43,776 | 0.042 | LISTENERS |
| … | 其余小项 | … | … | <0.05 | — |
| **合计** | | | **23,638,084** | **22.54** | |

**Verdict**: `python_allocation_growth_observed`

**分配点 ≠ 保留点**：tracemalloc 准确捕获了分配热点（`:23` 缓存 value、`:13` 对象实例），但根因在 **为什么这些对象不被回收**，而不是在哪里分配。

**对账**: 
- `tenant_lookup` 的 value 分配 + LargeTenant 实例分配 = ~22.31 MiB，占全部增长的 99%
- 分配热点与语义信号的 **LISTENERS + tenant_lookup** 完美吻合
- SMALL_GLOBAL 的分配增量 < 0.05 MiB，可忽略

---

## 6. 保留链证据（retention_chain）

对 3 个 LargeTenant 候选的保留链采样：

```
LargeTenant@0x7e1dd0a630e0
  → bound method LargeTenant.callback
    → LISTENERS (builtins.list) ←  module_global:LISTENERS
```

```
LargeTenant@0x7e1dd0a621e0
  → bound method LargeTenant.callback
    → LISTENERS (builtins.list) ←  module_global:LISTENERS
```

```
LargeTenant@0x7e1dd0a621b0
  → bound method LargeTenant.callback
    → LISTENERS (builtins.list) ←  module_global:LISTENERS
```

**Root Kind 统计**:

| Root Kind | 采样数 | 占比 |
|-----------|--------|------|
| `module_global:LISTENERS` | 3 | **100%** |

**Verdict**: `retention_chain_observed`

**结论**: 所有采样的 LargeTenant 实例的保留链一致 —— 通过 bound method → 全局 LISTENERS 列表 → module global。**LISTENERS 是唯一的保留根**。

---

## 7. 验证门结果

| 验证门 | 结果 | 说明 |
|--------|------|------|
| **G1 量化对账** | ✅ 通过 | 分配热点 ~22.54 MiB = tenant_lookup value (11.74 MiB) + LargeTenant (10.57 MiB)，浅层对象增长对账一致；LISTENERS 保留 600 实例，tenant_lookup 保留 600 value |
| **G2 竞争假设** | ✅ 通过 | 排除 SMALL_GLOBAL（30 items, 312 B, score=30，仅为干扰项）；排除预热（miss=600, hits=0）；排除碎片化/native 背离（tracemalloc 可解释大部增长） |
| **G3 可达性** | ✅ 通过（反事实确认） | 清除 LISTENERS 后 100% 对象被回收（reclaimed_ratio=1.0），反事实确认 |
| **G4 隔离复测** | 🟡 建议执行 | 建议分别设置 maxsize 和清理 LISTENERS 后复测 |
| **G5 置信度** | 🔵 强 (strong) | `counterfactual_confirmed` → confidence_cap=strong，三条独立证据链汇聚 |

---

## 8. 根因结论与置信度

### 已确认事实

1. **主根因 — LISTENERS 全局 registry 泄漏**（置信度: **强**）
   - global registry 在每次迭代向 LISTENERS 列表追加 bound method
   - 每个 bound method 强引用其 LargeTenant 实例（self）
   - 600 次迭代后，600 个 LargeTenant 实例及其 profile 数据全部不可回收
   - 反事实验证：清除 LISTENERS 后 100% 对象回收

2. **次根因 — tenant_lookup 无界缓存**（置信度: **强**）
   - `@lru_cache(maxsize=None)` 导致缓存永无上限
   - 600 次调用全部 miss，600 个 key-value 永久驻留
   - tracemalloc 显示 value 分配 11.74 MiB 为单最大分配源

3. **干扰项 — SMALL_GLOBAL**（置信度: ✅ 已排除）
   - 仅增长 30 items、312 bytes，score=30
   - 在三源中占比 < 0.1%，不影响整体泄漏

### 诊断结论

```
泄漏总分配:  ~22.54 MiB（600 次迭代后）
LISTENERS 贡献: 10.57 MiB（LargeTenant 实例 + profile）
tenant_lookup 贡献: 11.74 MiB（缓存 value）
SMALL_GLOBAL 贡献: < 0.01 MiB（干扰）
```

---

## 9. 修复建议

### 建议一（必须）：清理 LISTENERS registry

```python
# 修复前：无限追加，永不清理
LISTENERS.append(bound_method)

# 修复后：使用后移除，或改用弱引用
LISTENERS.remove(bound_method)  # 确保在生命周期结束时清理
```

**或改用 WeakSet/WeakValueDictionary** 避免强引用：

```python
import weakref
LISTENERS = weakref.WeakSet()  # 不阻止实例回收
```

### 建议二（必须）：限制 tenant_lookup 缓存

```python
# 修复前：无界缓存
@lru_cache(maxsize=None)
def lookup(tenant_id):
    ...

# 修复后：设置合理上限
@lru_cache(maxsize=128)  # 或根据实际访问模式设定
def lookup(tenant_id):
    ...
```

### 建议三（可选）：关闭 SMALL_GLOBAL

```python
# 最小影响，但建议移除测试代码
# SMALL_GLOBAL 对业务无意义，仅增长 30 items
```

---

## 10. 复测方案

1. **实施修复后**：清除 LISTENERS registry + 设置 maxsize
2. **再次运行**：`bash ./run.sh run-stress multi_source_mismatch`
3. **验证指标**：
   - tracemalloc 总增长应降至 < 0.1 MiB
   - object_growth 中 builtins.method 和 LargeTenant 应无增长
   - cache_growth 中 tenant_lookup.currsize 应停在 ≤ maxsize
4. **预期结果**：RSS 不再随迭代次数增长

---

## 附录：证据文件索引

| 证据模块 | 对应日志段落 | 状态 |
|---------|-------------|------|
| detect_capabilities | 日志行 11–134 | ✅ success |
| object_growth | 日志行 137–444 | ✅ success |
| semantic_probe | 日志行 447–845 | ✅ success |
| tracemalloc_probe | 日志行 848–1257 | ✅ success |
| retention_chain | 日志行 1260–1409 | ✅ success |
| reachability_probe (static) | 日志行 1412–1465 | ⚠️ partial (static_only) |
| reachability_probe (counterfactual) | 日志行 1468–1551 | ✅ success (counterfactual_confirmed) |

---

📁 **输出文件路径**：
- 诊断报告：`C:\Users\duanz\.witty-diagnosis-agent\baize\reports\multi_source_mismatch_rca_report_20260604.md`
- 原始证据：`D:\develop\Trae\OpenEuler\witty-diagnosis-agent\test\python-memory-leak-analyzer\out\stress\multi_source_mismatch\multi_source_mismatch.log`
- 目标 Skill：`D:\develop\Trae\OpenEuler\witty-diagnosis-agent\skills\python-memory-leak-analyzer`
