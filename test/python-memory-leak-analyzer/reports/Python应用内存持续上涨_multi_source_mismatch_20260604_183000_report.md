# 🔴 故障诊断报告

> **报告编号**：RCA-20260604-001
> **故障级别**：P2（开发/测试环境内存泄漏，上生产可达 P1）
> **报告时间**：2026-06-04 18:30:00
> **当前状态**：🟡 观察中（根因已确认，待修复）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | Python 应用 multi_source_mismatch 场景下 RSS 持续上涨 — 双来源并发内存泄漏 |
| 影响范围 | `multi_source_mismatch.py` 工作负载运行环境（沙箱复现），600 次迭代 RSS 增长 ~22.5 MiB |
| 故障时段 | 2026-06-04 09:20:57 ~ 2026-06-04 09:20:58（证据生成窗口） |
| 根本原因 | **LISTENERS 全局注册表无界增长** + **tenant_lookup 无界缓存** 双来源并发内存泄漏 |
| 是否恢复 | ❌ 未恢复（代码层面未修复，泄漏在持续运行下将继续恶化） |
| 根因置信度 | 🟢 高置信（五线证据对齐，反事实验证通过） |

### 置信度说明

| 等级 | 标识 | 含义 | 当前场景对照 |
|------|------|------|-------------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | 三个独立 Kuafu 报告证据完全一致，反事实验证 100% 回收 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                                                   事件                                            性质       证据来源
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-06-04 09:20:57    Python 应用 multi_source_mismatch 启动，run_workload(iterations=600)        🟢 执行开始  [discovery.json]
  │
  ▼ (每迭代一次，以下三个操作同时发生)
2026-06-04 09:20:57    LargeTenant.__init__() 创建 profile 字符串（~20KB/次）                        📦 分配增长  [tracemalloc.json]
  │                    ↳ tenant_lookup() 被调用，@lru_cache 写入缓存条目（maxsize=None）
  │                    ↳ LISTENERS.append(callback_bound_method) 注册回调
  │                    ↳ SMALL_GLOBAL.append({'index': i}) 小全局列表（干扰项）
  │
  ▼ (600 次迭代后)
2026-06-04 09:20:58    证据采集完成                                                                    🔍 证据冻结  [collect time]
  │
  │  ┌── 对象增长结果：
  │  │   builtins.method:  +600 (38,400 bytes)
  │  │   LargeTenant:      +600 (28,800 bytes)
  │  │   tenant_lookup:    currsize 0→600 (maxsize=None)
  │  │   LISTENERS:         len=600
  │  │   SMALL_GLOBAL:      len=30 (312 bytes, 干扰项)
  │  └──
  │
  ▼
2026-06-04 09:21:02    Kuafu T1 诊断开始（全局分析 + 量化对账）                                      📋 诊断     [kuafu_T1_*.md:1-281]
  │                    LISTENERS + tenant_lookup 联合解释 99% 分配增长 ✅ G1 PASS
  │                    语义信号 score: LISTENERS=645, tenant_lookup=600, SMALL_GLOBAL=30 ✅ G2 PASS
  │                    反事实: clear(LISTENERS) → 100% 回收 ✅ G3 PASS
  │                    整体置信度: HIGH
  │
  ▼
2026-06-04 09:21:02    Kuafu T3 诊断开始（G2 专项验证 — SMALL_GLOBAL 干扰项排除）                    🧪 验证     [kuafu_T3_*.md:1-296]
  │                    score 比: 645:30 = 21.5x, 大小比: 312 bytes : 22.543 MiB ≈ 1:75,000
  │                    结论: SMALL_GLOBAL 确认干扰项 ✅ G2 PASSED strong
  │
  ▼
2026-06-04 17:25:15    Kuafu T2 诊断完成（完整双来源 RCA 报告）                                      📋 诊断     [kuafu_T2_*.md:1-425]
  │                    LISTENERS 52.5% + tenant_lookup 46.9% = 99.5% 分配增长被解释
  │                    保留链 100% 指向 module_global:LISTENERS
  │                    整体置信度: 高（可确认）
  │
  ▼
2026-06-04 18:30:00    Baize 综合 RCA 报告生成（本报告）                                              📝 报告     本文件
```

### 故障因果链

```text
故障现象: Python 应用 RSS 持续上涨（600 次迭代 +22.543 MiB）
    │
    ├─► 来源 #1 (52.5%): LISTENERS 全局注册表
    │       └─► 每次 LargeTenant 构造 → callback bound method 追加到 LISTENERS 列表
    │             └─► bound method.__self__ 强引用持有 LargeTenant 实例（含 ~20KB profile 字符串）
    │                   └─► module_global:LISTENERS 是唯一保留根，600 个实例不可被 GC 回收
    │                         └─► 反事实验证: clear(LISTENERS) → 100% 回收 (strong confidence)
    │
    ├─► 来源 #2 (46.9%): tenant_lookup 无界缓存
    │       └─► @lru_cache(maxsize=None) 装饰 tenant_lookup 函数
    │             └─► 每次查找 unique tenant_id → 新增缓存条目（profile 字符串）
    │                   └─► currsize: 0 → 600，hits=0（永不命中已有缓存）
    │                         └─► 无淘汰机制，每条 ~18KB，持续堆积
    │
    └─► 干扰项: SMALL_GLOBAL (0.01%)
            └─► 30 个 {'index': N} 小 dict，浅层 312 字节
            └─► score 30 vs 645/600，显眼但量级完全不可比
```

---

## 三、排查过程

### 3.1 初始现象

| 现象 | 来源 | 证据 |
|------|------|------|
| RSS 持续增长信号 | `discovery.json` 日志信号 | `rss_growth_observed` |
| Tracemalloc 追踪到分配增长 | `tracemalloc.json` | 总计 22.543 MiB (23,638,084 bytes) |
| 应用层对象增长 | `object_growth.json` | `builtins.method` +600, `LargeTenant` +600 |
| 语义泄漏信号 | `semantic.json` | `semantic_leak_signals_observed`, 2 个主导信号 |
| 保留链确认 | `retention.json` | root_kind 均为 `module_global:LISTENERS` |

### 3.2 假设驱动排查

#### 假设 A：SMALL_GLOBAL 全局列表泄漏 —— 干扰项 ✅ 排除

> 🧪 假设：SMALL_GLOBAL 全局列表明显增大（在代码中显眼），可能是泄漏主因。

| 检查项 | 操作（基于真实诊断数据） | 结论 |
|--------|--------------------------|------|
| 语义 score 对比 | `semantic.json` — LISTENERS score=645 vs SMALL_GLOBAL score=30 | score 差距 21.5x |
| 对象增长量化 | `object_growth.json` — SMALL_GLOBAL len=30, shallow≈312 bytes vs 总增长 22.543 MiB | 差距 ~75,000x (312:22.5M) |
| 分配热点 | `tracemalloc.json` — SMALL_GLOBAL 分配完全不可见于 top 分配栈 | 分配量 <0.01% |
| 保留链指向 | `retention.json` — 100% 采样指向 LISTENERS, 未命中 SMALL_GLOBAL | 非保留根 |

**✅ 排除**：SMALL_GLOBAL 确认为干扰项（Distractor），其 30 个小型 dict 条目（~312 bytes）完全无法解释 22.543 MiB 的主泄漏。详细验证记录参见 `C:\Users\duanz\.witty-diagnosis-agent\dayu\report\kuafu_T3_20260604_092102.md`。

---

#### 假设 B：Native 内存泄漏（C 扩展/Python 堆外泄漏）

> 🧪 假设：内存增长发生在 Python 堆之外，由 native 代码分配导致。

| 检查项 | 操作（基于真实诊断数据） | 结论 |
|--------|--------------------------|------|
| tracemalloc vs RSS | tracemalloc 22.543 MiB ≈ Python 堆总增长 | 无背离信号 |
| 对象增长形态 | `object_growth.json` 方法+实例增量可完整解释 | Python 层已覆盖 |
| memray 可用性 | memray 缺失，但不需要 | native 方向无背离 |

**✅ 排除**：RSS 增长 ≈ tracemalloc 总量，Python 层已能解释主要增长，无需追踪 native 分配。

---

#### 假设 C：碎片化或预热伪泄漏

> 🧪 假设：内存增长可能是堆碎片化或缓存预热后的稳定状态 plateau。

| 检查项 | 操作（基于真实诊断数据） | 结论 |
|--------|--------------------------|------|
| hits 统计 | `tenant_lookup` hits=0, misses=600 | 每次都是新 key，非预热 |
| 增长形态 | 600 次迭代持续增长 | 无 plateau 迹象 |
| 缺失 GC 循环 | `garbage_len=0, debug_saveall_active=false` | 无循环引用泄漏 |

**✅ 排除**：每次迭代均为唯一 key，不存在预热 plateau。增长持续，非碎片化。

---

#### 假设 D：LISTENERS 全局注册表泄漏 —— 根因 A ✅ 确认

> 🧪 假设：基于语义信号 score=645 和 retention 链 100% 指向，LISTENERS 为主保留泄漏源。

**Step 1 — 量级确认**
```text
语义 score: 645（排名 #1，远高于 #3 干扰项 30）
对象增长: builtins.method +600, LargeTenant +600
分配占比: ~52.5% (11.847 MiB / 22.543 MiB)
```

**Step 2 — 保留链追踪**
```text
LargeTenant object (#0)
    ↓ self.__self__
bound method LargeTenant.callback
    ↓ list element
builtins.list (module_global:LISTENERS)
```
- 100% 的保留链采样（3/3）指向 `module_global:LISTENERS`
- 每个 bound method 通过 `self` 引用持有完整的 `LargeTenant` 实例

**Step 3 — 反事实验证**
- 干预操作：`clear(LISTENERS)` 清空全局列表
- before_count: 600 → after_count: 0
- 回收比例: **100%** (confidence: **strong**)

**✅ 结论**：LISTENERS 全局注册表是无界增长泄漏源 A，每次 workload 迭代绑定的 callback bound method 永不清理，导致关联的 LargeTenant 实例无法被 GC 回收。

---

#### 假设 E：tenant_lookup 无界缓存泄漏 —— 根因 B ✅ 确认

> 🧪 假设：基于语义信号 score=600 和 tracemalloc 分配热点 #2，`@lru_cache(maxsize=None)` 是无界缓存泄漏源。

**Step 1 — 缓存配置确认**
```text
@lru_cache(maxsize=None)   # 无上限！
currsize: 0 → 600
hits: 0                    # 永不命中已有缓存
maxsize: None              # 无淘汰
```

**Step 2 — 分配量化**
```text
tracemalloc 分配 #2 (line 13): 10.570 MiB, 占比 46.9%
对应: tenant_lookup 返回的 profile 字符串缓存
```

**Step 3 — 语义确认**
```text
semantic.json verdict: unbounded_cache_growth (score=600)
标签明确指示为无界缓存增长
```

**✅ 结论**：`@lru_cache(maxsize=None)` 导致 tenant_lookup 缓存条目永不淘汰，每次 unique tenant_id 产生新缓存，是泄漏源 B（占比 ~46.9%）。

---

### 3.3 排查结论与逻辑树

```text
Python 应用 RSS 持续上涨 (+22.543 MiB / 600 iter)
│
├─► 假设 A: SMALL_GLOBAL 全局列表 → ✅ score=30 (21.5x < LISTENERS), 312 bytes (75,000x < 总增长) → 排除为干扰项
│       [证据: kuafu_T3_*.md — G2 PASSED, 语义信号 score 对比, tracemalloc 不可见]
│
├─► 假设 B: Native 内存泄漏 → ✅ tracemalloc 22.543 MiB ≈ RSS 增长, 无背离 → 排除
│       [证据: kuafu_T1_*.md §2 — 无 native 背离信号]
│
├─► 假设 C: 碎片化/预热伪泄漏 → ✅ hits=0, 持续增长无 plateau, garbage_len=0 → 排除
│       [证据: kuafu_T2_*.md §5.4 — GC 语义正常]
│
├─► 假设 D: LISTENERS 全局注册表 → ✅ 根因 A (52.5%) 🎯
│       ├─ evidence: semantic score=645, retention 链 100% 指向, counterfactual 100% 回收
│       ├─ mechanism: LargeTenant.callback → LISTENERS.append → bound method.__self__ → LargeTenant retained
│       └─ 修复: 改用 WeakSet / 设置容量上限 / 绑定生命周期注销
│
└─► 假设 E: tenant_lookup 无界缓存 → ✅ 根因 B (46.9%) 🎯
        ├─ evidence: semantic score=600, tracemalloc line 13 = 10.570 MiB, maxsize=None
        ├─ mechanism: @lru_cache(maxsize=None) → 每查询新 key 新增缓存 → currsize=600, hits=0
        └─ 修复: 设置 maxsize / 改用 TTL 缓存
```

---

## 四、详细诊断证据（三报告交叉验证）

### 4.1 G1 量化对账：双来源联合解释 99%+ 分配增长

| 来源 | Tracemalloc 分配量 (MiB) | 占比 | 语义 Score | 对象增长 (count) | 保留链确认 | 反事实验证 |
|------|:------------------------:|:----:|:----------:|:-----------------:|:----------:|:----------:|
| **LISTENERS 注册表** (line 23) | 11.742 | 52.1% | **645** | method +600, LargeTenant +600 | 100% 采样指向 | 100% 回收 ✅ |
| **tenant_lookup 缓存** (line 13) | 10.570 | 46.9% | **600** | currsize 0→600 | 独立第二来源 | N/A |
| **其他** | 0.231 | 1.0% | — | — | — | — |
| **合计** | **22.543** | **100%** | — | — | — | — |

### 4.2 G2 干扰项排除：SMALL_GLOBAL 验证结论

| 对比维度 | LISTENERS | tenant_lookup | SMALL_GLOBAL |
|----------|:---------:|:-------------:|:------------:|
| 语义 Score | 645 | 600 | **30**（21.5x 差距） |
| 元素数量 | 600 | 600 | **30**（20x 差距） |
| 占总量比 | ~52.5% | ~46.9% | **<0.01%**（75,000x 差距） |
| Tracemalloc 可见性 | ✅ 行23, 11.742 MiB | ✅ 行13, 10.570 MiB | ❌ 不可见 |
| 保留链 | ✅ 100% | N/A | ❌ 未命中 |
| **结论** | **主泄漏源** | **主泄漏源** | **干扰项** |

### 4.3 G3 证据链一致性矩阵

| 证据维度 | 文件 | Verdic | LISTENERS | tenant_lookup | SMALL_GLOBAL |
|----------|------|--------|:---------:|:-------------:|:------------:|
| **对象增长** | `object_growth.json` | growth_observed | +600 method, +600 Tenant | 缓存内部增长 | +30 dict, 312 bytes |
| **语义信号** | `semantic.json` | leak_signals_observed | score=645, global_registry | score=600, unbounded_cache | score=30, global_container |
| **分配热点** | `tracemalloc.json` | allocation_growth_observed | line 23, 11.742 MiB | line 13, 10.570 MiB | 不可见 |
| **保留链** | `retention.json` | chain_observed | 3/3 采样 | N/A | 0/3 采样 |
| **反事实** | `reachability_counterfactual.json` | counterfactual_confirmed | 100% 回收 (strong) | N/A | 未测试 |

### 4.4 T1、T2、T3 报告验证门汇总

| 验证门 | T1 判定 | T2 判定 | T3 判定 | 综合判定 |
|--------|:-------:|:-------:|:-------:|:--------:|
| **G1 量化对账** (>80%) | ✅ PASS (99%) | ✅ PASS (99.5%) | ✅ 隐式确认 | ✅ **PASS** |
| **G2 竞争假设排除** | ✅ PASS | ✅ PASS | ✅ PASS strong | ✅ **PASS** |
| **G3 可达性/反事实** | ✅ PASS(100%回收) | ✅ PASS(100%回收) | ✅ PASS(100%回收) | ✅ **PASS** |
| **G4 双来源报告** | — | ✅ PASS | — | ✅ **PASS** |
| **整体置信度** | **高（可确认）** | **高（可确认）** | **strong** | **🟢 高置信** |

---

## 五、修复方案

### 5.1 应急处置

当前为沙箱复现环境，无线上生产影响。若需立即释放内存：

| 步骤 | 操作 | 执行人 | 效果 |
|------|------|--------|------|
| 1 | 终止运行中的 Python 进程 | 人工 | 立即释放所有内存 |
| 2 | 清除 `LISTENERS` 列表：`LISTENERS.clear()` | 代码 | 释放 600 个 bound method 及相关实例 |
| 3 | 清除 `tenant_lookup` 缓存：`tenant_lookup.cache_clear()` | 代码 | 释放 600 条缓存条目 |

### 5.2 永久修复计划

#### 修复 A：LISTENERS 全局注册表 — 增加上限或按生命周期清理

```python
# 方案 A1: 改用 WeakSet（不阻止 GC 回收）
import weakref
LISTENERS = weakref.WeakSet()

# 方案 A2: 设置固定上限 + FIFO 淘汰
from collections import deque
MAX_LISTENERS = 1000
LISTENERS = deque(maxlen=MAX_LISTENERS)

# 方案 A3: 绑定 tenant 生命周期，显式注销
LISTENERS = {}  # tenant_id → callback
def register(tenant_id, cb):
    LISTENERS[tenant_id] = cb
def unregister(tenant_id):
    LISTENERS.pop(tenant_id, None)
```

#### 修复 B：tenant_lookup 缓存 — 设置上限

```python
# 方案 B1: 设置 maxsize
@lru_cache(maxsize=1000)  # 根据实际租户数设定
def tenant_lookup(tenant_id):
    ...

# 方案 B2: 使用带 TTL 的缓存
from cachetools import TTLCache, cached
cache = TTLCache(maxsize=1000, ttl=300)  # 5分钟过期
@cached(cache)
def tenant_lookup(tenant_id):
    ...
```

#### 修复 C：综合修复（推荐）

同时应用**修复 A** + **修复 B** 以彻底消除两路泄漏源。

| 修复措施 | 负责人 | 完成时间 |
|---------|--------|---------|
| LISTENERS 注册表增加上限或改用 WeakSet | 开发团队 | 待定 |
| tenant_lookup 设置缓存 maxsize 或改用 TTL 淘汰 | 开发团队 | 待定 |
| SMALL_GLOBAL 设置上限（可选，当前非阻塞） | 开发团队 | 待定 |

---

## 六、复测方案

```bash
# 修复后运行相同 workload
cd test/python-memory-leak-analyzer
bash ./run.sh run-stress multi_source_mismatch

# 验证指标
# 1. listener_count 不再超过 MAX_LISTENERS
# 2. tenant_lookup 缓存 currsize 不超过设定 maxsize
# 3. RSS 增长趋平（plateau），不再线性上涨
# 4. tracemalloc diff 不再持续增长（预期从 22.543 MiB 降至 < 1 MiB）

# 长期观测
# 扩大迭代次数至 10000+，确认增长曲线趋于水平
```

---

## 七、未验证项与下一步

| 项目 | 说明 |
|------|------|
| `tenant_lookup` 保留链 | retention 分析以 method 为入口，未独立追踪 cache dict；语义+分配线已提供充分证据 |
| native/allocator 方向 | RSS 增长 ≈ 22.543 MiB ≈ tracemalloc 总量，Python 层已能解释主要增长，不需要追踪 native |
| 生产环境差异 | 本例使用沙箱复现脚本；生产环境需确认 LISTENERS 和 tenant_lookup 的使用模式是否一致 |
| **下一步** | 应用修复后运行复测，验证修复有效性；确认 SMALL_GLOBAL 在长期运行下不会成为新泄漏源 |

---

## 诊断质量自查

- ✅ **领域透传**：三份 Kuafu 报告证据已完整交叉验证并结构化展示
- ✅ **标题对齐**：章节标题对应分析任务场景
- ✅ **路径溯源**：所有核心结论均附带了 `[证据来源]`
- ✅ **逻辑闭环**：故障传导链路逻辑自洽，可解释所有观测到的证据

---

**报告引用证据文件**：
- `C:\Users\duanz\.witty-diagnosis-agent\dayu\report\kuafu_T1_20260604_092102.md`
- `C:\Users\duanz\.witty-diagnosis-agent\dayu\report\kuafu_T2_20260604_172515.md`
- `C:\Users\duanz\.witty-diagnosis-agent\dayu\report\kuafu_T3_20260604_092102.md`
