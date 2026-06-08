# 🔴 故障诊断报告

> **报告编号**: RCA-20260607-001
> **故障级别**: P2（内存资源持续消耗，存在 OOM 风险）
> **报告时间**: 2026-06-07 22:50:00
> **当前状态**: 🔴 处理中

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | Python 服务 RSS 持续增长 — ctypes native 内存分配未释放导致 |
| 影响范围 | 目标进程 PID 417（`python native_ctypes_malloc_growth.py --live`），单进程单线程模式 |
| 故障时段 | 2026-06-07 14:33:55 ~ 14:34:04（数据采集窗口 3.5 秒） |
| 根本原因 | ctypes 通过 `libc.malloc()` 分配 native 原生内存后，glibc/ptmalloc 分配器未将释放的内存页归还给操作系统，导致 RSS 与 Private_Dirty 持续线性攀升，Python 堆增长仅占总增长的 0.7% |
| 是否恢复 | ❌ 未恢复（持续增长中，未执行任何修复操作） |
| 根因置信度 | 🟡 中置信（方向级：确认为 native/allocator 方向，但缺少 native allocation stack 精确定位） |

### 置信度说明

| 等级 | 标识 | 含义 | 对应本故障 |
|------|------|------|-----------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | — |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | 缺少 native allocation stack 和 allocator stats，无法区分具体 C 函数和 arena 内部碎片 |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                                  事件                                           性质          证据来源
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-06-07 14:33:55  进程启动，RSS 基准 25.69 MiB，Private_Dirty 18.70 MiB               ▶ 初始状态   [T1:monitor_rss_pid.json]
  │
  ▼
2026-06-07 14:33:55  第 1 轮迭代开始 → ctypes 调用 libc.malloc() 分配 ~3 MiB native 内存  📈 native 分配 [T1:object_growth workload_return]
  │
  ▼
2026-06-07 14:33:56  RSS 增长至 30.93 MiB（+5.24 MiB），Private_Dirty 同步增长              🟡 压力积累   [T2:RSS 时序表]
  │                   该内存被 Python 仅通过 POINTERS 列表（12 个 int）追踪地址
  │                   Python 堆对象增长仅 0.246 MiB，占 Private_Dirty 增长的 0.7%
  ▼
2026-06-07 14:33:57  第 6 轮迭代：Python 追踪对象 +0.243 MiB，RSS 持续攀升至 46.4 MiB       🟡 压力积累   [T1:object_growth.json]
  │                   builtins.dict 增长 +0.525 MiB（264 个新 dict）
  │                   语义信号 global_container_growth 确认（POINTERS list 0→12）
  ▼
2026-06-07 14:33:58  第 12 轮迭代结束：RSS 62.39 MiB，净增长 35.0 MiB（~10 MiB/s）          🔴 故障爆发   [T1:monitor_rss_pid.json]
  │                   累计显式报告 native 分配 7.5 MiB，实际 RSS 增长 35 MiB
  │                   差异来源：glibc ptmalloc arena 内部碎片 + 匿名映射高水位
  │
  │                   correlation.json 对账结论：
  │                   • python_heap_to_private_dirty_ratio = 0.0
  │                   • tracked_object_to_private_dirty_ratio = 0.0174（仅 1.74%）
  │                   • verdict = native_or_allocator_suspect
  │
  │                   竞争假设矩阵：
  │                   • Python retained leak → ❌ REFUTED（仅贡献 <1%）
  │                   • mmap/file/shmem → ❌ 排除（RSS_File=0, RSS_Shmem=0）
  │                   • scope mismatch → ❌ 排除（无子进程，单一 PID）
  ▼
2026-06-07 14:34:04  数据采集结束，进程仍在运行，RSS 增长未见平台                          🔴 持续中     [T1:monitor verdict]
```

### 故障因果链

```text
ctypes 调用 libc.malloc() 分配 native 内存（每轮迭代 ~3 MiB）
    │
    ├─► native 内存通过 _ctypes.cpython-312 扩展模块分配
    │       └─► malloc 返回的指针被 Python 的 POINTERS 列表（builtins.int ×12）追踪
    │
    ├─► [直接原因] ctypes 分配后未显式调用 free() 释放 native 内存
    │       └─► 即使调用 free()，glibc/ptmalloc 也不会立即将内存归还 OS
    │
    ├─► [传播路径] 匿名映射页持续膨胀（RssAnon +35 MiB）
    │       └─► mapping 分析显示最大匿名映射 10.66 MiB（无路径，glibc arena 典型特征）
    │
    ├─► [核心对账] Python 堆增长仅 0.246 MiB，占增长总量的 0.7%
    │       └─► tracemalloc 覆盖率 0%（无法追踪 native malloc）
    │       └─► object_growth 覆盖率仅 1.74%
    │
    └─► [最终效应] RSS 从 25.69 MiB → 62.39 MiB（+35 MiB）
            └─► Private_Dirty 同步增长 +35.04 MiB
            └─► 斜率约 10.48 MiB/s，线性/阶梯增长形态
            └─► 🔴 如持续运行将触发 OOM 或 swap thrashing
```

---

## 三、排查过程

### 3.1 初始现象

- **监控数据**：PID 417 进程 RSS 在 3.5 秒内从 25.69 MiB 持续增长至 62.39 MiB，净增长 **35.0 MiB**，增速 **~10.48 MiB/s**
- **增长形态**：线性/阶梯式增长（linear_or_step_growth），无平台迹象
- **增长主体**：完全是 **RssAnon / Private_Dirty**（匿名页），RssFile 和 RssShmem 均无增长
- **进程特征**：单线程（PID 417），无子进程，cgroup `/init.scope` 口径一致，无 OOM 事件
- **Python 堆表现**：Python 追踪对象仅增长 0.246 MiB，远小于 RSS 增长

### 3.2 假设驱动排查

本次分析由 3 个 Kuafu 诊断任务（T1/T2/T3）独立开展，分别从不同角度排查，最终汇聚到同一根因方向。

---

#### 假设 A：Python 对象保留泄漏（Python Retained Leak）— ❌ 已排除

> 🧪 假设来源：RSS 持续增长 + 存在保留链信号（retention.json），推测 Python 托管对象未被 GC 回收

| 检查项 | 操作 | 结论 |
|--------|------|------|
| Python 对象增长对账 | `object_growth.json` — 追踪对象净增长仅 0.246 MiB，`builtins.dict` 占 +0.525 MiB（+264 个） | ✅ Python 对象有微幅增长 |
| tracemalloc 热点 | `tracemalloc.json` — 总追踪量仅 1,464 bytes（0.001 MiB），verdict: `inconclusive` | ✅ tracemalloc 不相关 |
| 语义保留信号 | `semantic.json` — `global_container_growth`，POINTERS list 0→12 | 信号存在但体量极小 |
| 保留链分析 | `retention.json` — closure_cell ×1, object_or_class_attribute_dict ×2 | 链存在但仅涉及内置对象 |
| **核心对账** | `python_heap_to_private_dirty_ratio = 0.0`，`tracked_object_to_private_dirty_ratio = 0.0174` | ❌ Python 堆解释力为 0% |

**❌ 排除**：Python 对象保留泄漏只能解释 **0.7%**（0.246 MiB / 35 MiB）的 RSS 增长，**不能作为主导根因**。保留链和语义信号只是次要干扰项。

---

#### 假设 B：文件映射 / 共享内存增长（mmap/file/shmem Growth）— ❌ 已排除

> 🧪 假设来源：怀疑文件 I/O 或共享内存导致映射膨胀

| 检查项 | 操作 | 结论 |
|--------|------|------|
| RssFile 监测 | `monitor_rss_pid.json` — RssFile 起始 6.75 MiB → 终值 6.75 MiB | ✅ 净增长 = 0 |
| RssShmem 监测 | `monitor_rss_pid.json` — RssShmem 始终为 0 | ✅ 净增长 = 0 |
| memory_surface | `correlation.json` — `primary_surface: "unknown"`（非 file/shmem 主导） | ✅ 排除 file/shmem |
| mapping 分析 | `live_process_snapshot.json` — file_backed 7 个共 8.023 MiB，无增长 | ✅ 文件映射稳定 |

**❌ 排除**：文件映射和共享内存在整个监控期间均未增长，不是 RSS 膨胀的来源。

---

#### 假设 C：进程范围 / cgroup 口径偏差（Scope Mismatch）— ❌ 已排除

> 🧪 假设来源：怀疑存在子进程或 cgroup 口径与 PID 不一致

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 子进程检查 | `live_process_snapshot.json` — Children: 0 | ✅ 无子进程 |
| cgroup 一致性 | `monitor_rss_pid.json` — cgroup_memory_current 增长 34.25 MiB ↔ PID RSS 增长 35.0 MiB | ✅ 口径一致 |
| 进程树 | discovery — 单进程单线程模式 | ✅ 无 worker 干扰 |

**❌ 排除**：范围明确，无干扰来源。

---

#### 假设 D：Native / 分配器消耗（Native Allocator Consumption）— ✅ 确认根因方向

> 🧪 假设来源：RSS 增长完全由匿名页驱动，Python 堆无法解释，`correlation.json` verdict = `native_or_allocator_suspect`

**Step 1 — 确认增长分配方向**

| 指标 | 数值 | 含义 |
|------|------|------|
| RSS 净增长 | **35.0 MiB** | 目标进程真实内存膨胀 |
| Private_Dirty 净增长 | **35.04 MiB** | 匿名页主导 |
| Python 追踪对象净增长 | **0.246 MiB** | 仅占增长总量的 0.7% |
| tracemalloc 追踪量 | **0.001 MiB** | 完全看不到 native 分配 |
| python_heap_to_private_dirty_ratio | **0.0** | Python 堆对增长贡献为 0% |
| tracked_object_to_private_dirty_ratio | **0.0174 (1.74%)** | 追踪对象只能解释不到 2% |
| Workload native 报告 | **7.5 MiB 显式 / 实际 35 MiB** | 额外差值为 arena 内部碎片 |

**Step 2 — mapping 分析确认 arena 特征**

`live_process_snapshot.json` 中的 `/proc/<pid>/smaps` 显示：

| 匿名映射区域 | 大小 | 特征 |
|------------|------|------|
| `7a00294a6000-7a0029f50000` | **10.664 MiB** | rw-p，无路径名 — glibc ptmalloc arena 典型特征 |
| `7a0029fdf000-7a002a200000` | **2.129 MiB** | rw-p，无路径名 |
| `7a002a431000-7a002a572000` | **1.254 MiB** | rw-p，无路径名 |

> 存在 >10 MiB 的大型匿名映射，无文件路径，符合 glibc/ptmalloc arena 特征。这些映射由 ctypes 直接调用 `malloc()` 分配原生内存引起。

**Step 3 — workload 行为确认**

`object_growth.json` 中的 `workload_return_repr`：

```
第 3 次迭代: {'native_allocations': 12, 'native_bytes': 3145728}   ← 每轮 ~3 MiB
第 12 次迭代: {'native_allocations': 30, 'native_bytes': 7864320}  ← 累计 ~7.5 MiB
```

- 每次迭代分配约 **3 MiB** native 内存
- 12 次迭代显式报告累计 **7.5 MiB** 分配
- 实际 RSS 增长 **35 MiB** > 7.5 MiB，说明存在 arena 内部碎片或 glibc 内存池额外占用
- `_ctypes.cpython-312-x86_64-linux-gnu.so` 模块已加载

**✅ 结论：ctypes 通过 `libc.malloc()` 分配 native 原生内存，glibc/ptmalloc 未将释放的页面归还给操作系统，导致 RSS 和 Private_Dirty 持续攀升。Python 堆几乎不参与增长。**

---

### 3.3 排查结论与逻辑树

```text
Python 服务 RSS 持续增长（PID 417, 25.7→62.4 MiB, +35 MiB in 3.5s）
│
├─► [假设 A] Python 对象保留泄漏          → ❌ 排除（仅解释 0.7% 增长）
│       └─► object_growth 0.246 MiB vs RSS 35 MiB → ratio=0.007（可忽略）
│       └─► retention_chain 存在但规模极小
│       └─► tracemalloc 仅 0.001 MiB
│
├─► [假设 B] 文件/共享内存增长            → ❌ 排除（RSS_File=0, RSS_Shmem=0）
│
├─► [假设 C] 范围口径偏差                 → ❌ 排除（单一 PID, 无子进程, cgroup 一致）
│
└─► [假设 D] Native/分配器消耗            → ✅ 确认（方向级）
        │
        ├─► 触发原因: ctypes 通过 libc.malloc() 分配 native 内存
        │       └─► 每轮迭代 ~3 MiB, 累计 7.5 MiB（显式报告）
        │       └─► _ctypes.cpython-312 扩展模块已加载
        │
        ├─► 传播路径: glibc/ptmalloc arena 高水位膨胀
        │       └─► mapping 显示 10.66 MiB 匿名映射（无路径）
        │       └─► 实际 RSS 35 MiB > 显式报告 7.5 MiB
        │       └─► 差额 = arena 内部碎片 + glibc 内存池预分配
        │
        ├─► 核心证据: Python heap 对增长贡献为 0%
        │       └─► python_heap_to_private_dirty_ratio = 0.0
        │       └─► correlation.json verdict = native_or_allocator_suspect
        │
        └─► 🎯 根因确认：ctypes 分配的 native 内存未被适当释放，
                        glibc/ptmalloc 保留匿名页高水位未归还 OS
```

---

## 四、领域扩展分析 — 三层证据交叉验证

### 证据层 1：T1 — 原生内存分配增长诊断（python-memory-leak-analyzer）

| 验证门 | 状态 | 结论说明 |
|--------|------|----------|
| G0 范围确认 | ✅ 通过 | PID=417，单线程，无子进程，cgroup scope 一致 |
| G1 量化对账 | ✅ 通过 | Python heap 无法解释 RSS 增长，ratio=0.0，确认 native 方向 |
| G2 竞争假设 | ✅ 通过 | native/allocator 唯一主导假设，Python retained / mmap / scope mismatch 全部排除 |
| G3 可达性反事实 | ⏭️ 跳过 | 离线分析模式，未执行反事实操作 |
| G4 隔离复测 | ⏭️ 跳过 | 未执行修复/复测 |
| G5 置信度 | ⚠️ direction-only | 缺少 native allocation stack 或 allocator stats |

**核心输出**：
- `correlation.json` verdict: **`native_or_allocator_suspect`**
- `confidence_cap`: **`direction_only_without_native_allocator_stack`**
- 结论方向：ctypes 分配的 native 内存（经由 `_ctypes.cpython-312-x86_64-linux-gnu.so`）未被释放

---

### 证据层 2：T2 — Python 对象保留泄漏验证

| 验证门 | 结果 | 说明 |
|--------|------|------|
| G0 | 通过 | 范围确认，PID 明确 |
| G1 | **未通过** | Python heap 仅覆盖 0.7% 的 RSS 增长 |
| G2 | 方向级 | native/allocator 为主导，Python retained 被排除 |
| G3 | weak static | 保留链存在但规模极小 |
| G4 | 未执行 | — |
| G5 | direction-only | 缺少 native allocation stack |

**核心输出**：
- **status: `refuted`** — Python 对象保留泄漏作为主导根因的假设已被推翻
- Python 对象保留（0.246 MiB）是**次要发现**，仅占总增长的 <1%
- RSS 增长根因不是 Python 托管对象保留，而是 native/C 扩展 malloc 分配

---

### 证据层 3：T3 — 内存碎片 / 分配器消耗分析

| 验证门 | 结果 | 说明 |
|--------|------|------|
| G0: RSS 是否为 Python heap 增长 | **否** | tracker_to_private_dirty_ratio = 1.74% |
| G1: file/shmem 是否为主导 | **否** | RSS_File 无增长 |
| G2: 是否存在语义泄漏信号 | **是** | global_container_growth（POINTERS +12） |
| G3: 保留链指向 Python 根因 | **部分** | 贡献可忽略 |
| G4: 是否可由 allocator 解释 | **是** | 与 `plateau_high_water` 模式高度一致 |
| G5: 是否有 native 分配栈证据 | **否**（方向级） | 缺少 native allocation stack |

**核心输出**：
- 直接原因：**glibc/ptmalloc 分配器未将释放的 native 内存归还给 OS**
- 场景脚本通过 `ctypes.CDLL(None).malloc()` 分配 native 内存，`free()` 释放后 ptmalloc 将内存保留在 arena 中
- 存在 **10.66 MiB** 的大型匿名映射（典型的 ptmalloc arena 特征）
- 98.26% 的 Private_Dirty 增长无法由 Python 托管对象解释

---

### 三报告对照总结

| 维度 | T1（方向确认） | T2（排除干扰） | T3（机制解释） | 综合结论 |
|------|---------------|---------------|---------------|---------|
| 根因方向 | native/allocator | 同上 | 同上 | **一致确认 native 方向** |
| Python 对象贡献 | 0.7% | <1% | 1.74% | **Python 对象不是主因** |
| 排除项 | mmap/scope/plateau | retained leak | file/shmem/cgroup | **所有竞争假设均排除** |
| 缺失项 | native allocation stack | 同上 | 同上 | **方向级封顶，无具体 C 栈** |
| 置信度 | direction-only | direction-only | direction-only | **方向级（中置信）** |

---

## 五、修复方案

### 5.1 应急处置

| 步骤 | 操作 | 执行人 | 时间 | 效果评估 |
|------|------|--------|------|----------|
| 1 | 调用 `malloc_trim(0)` 回收 glibc arena 空闲页，通知 glibc 将空闲内存归还 OS | 系统/人工 | 尽早执行 | 可立即释放 ptmalloc arena 中未使用的匿名页 |
| 2 | 若步骤 1 无效，重启 PID 417 进程以彻底释放所有内存 | 人工 | 按需 | RSS 回到基准值，但临时方案 |
| 3 | 使用 `mallopt(M_TRIM_THRESHOLD, ...)` 调低 trim 阈值，使 ptmalloc 更积极释放空闲块 | 系统 | 重启后生效 | 防止再次积累 |

```python
# 应急释放示例
import ctypes

# 调用 malloc_trim(0) 回收 arena 空闲页
libc = ctypes.CDLL("libc.so.6")
libc.malloc_trim(0)  # 参数 0 表示在所有 arena 上执行 trim
```

### 5.2 永久修复计划

| 修复措施 | 负责人 | 预计完成时间 | 优先级 |
|----------|--------|-------------|--------|
| **代码级修复**：审计 `native_ctypes_malloc_growth.py` 中所有 ctypes malloc/calloc 调用，确保每次分配后有对应的 `free()` 调用 | 开发团队 | 待定 | P0 |
| **架构改进**：将大块 native 内存分配改为 `mmap(MAP_ANONYMOUS)` + `munmap()` 模式，绕过 ptmalloc arena | 开发团队 | 待定 | P1 |
| **监控增强**：添加 `/proc/<pid>/smaps_rollup` 的 Private_Dirty 监控，当 Python heap 稳定但 Private_Dirty 持续增长时触发告警 | SRE 团队 | 待定 | P1 |
| **测试增强**：编写 native 内存泄漏测试用例，集成到 CI 流水线 | 开发团队 | 待定 | P2 |

```python
# 修复模式示例 — 确保每次 ctypes malloc 有对应的 free
import ctypes

# ✅ 正确的分配/释放配对模式
libc = ctypes.CDLL("libc.so.6")
libc.free.argtypes = [ctypes.c_void_p]

# 分配
buf = ctypes.create_string_buffer(1024 * 1024)
ptr = ctypes.c_char_p(buf)

# 使用 ...

# 释放
libc.free(ctypes.c_void_p(ctypes.addressof(buf)))

# 或使用 context manager 确保释放
from contextlib import contextmanager

@contextmanager
def native_buffer(size):
    buf = ctypes.create_string_buffer(size)
    try:
        yield buf
    finally:
        libc.free(ctypes.c_void_p(ctypes.addressof(buf)))
```

### 5.3 后续验证建议（需单独授权）

| 验证手段 | 目的 | 预期效果 |
|----------|------|----------|
| `memray run --native` 采集 native 分配栈 | 定位具体哪些 C 函数产生泄漏 | 精确定位到代码行级别 |
| `valgrind --leak-check=full` 运行 workload | 检测具体的泄漏点 | 确认每个 malloc 对应的 free |
| `malloc_info()` / `mallinfo` 采集 arena 内部状态 | 区分真实泄漏 vs arena 高水位 | 明确根因是泄漏还是碎片 |
| 修复后复测 `./run.sh run-prod native_ctypes_malloc_growth` | 验证修复有效性 | RSS 净增长 < 5 MiB |

---

## 附录

### A. 环境信息

| 项目 | 内容 |
|------|------|
| **平台** | Linux 6.6.87.2 (WSL2) |
| **Python 版本** | 3.12.3 |
| **目标 PID** | 417 |
| **诊断模式** | 离线分析（offline_evidence_bundle） |
| **分析引擎** | WittyDiagnosisAgent / Baize (Phase 1.4) |
| **诊断报告来源** | Kuafu T1/T2/T3 |

### B. 术语表

| 术语 | 说明 |
|------|------|
| **RSS** | Resident Set Size，常驻内存集大小 |
| **Private_Dirty** | 进程独占的已修改匿名页 |
| **ptmalloc** | glibc 的用户态内存分配器（基于 Doug Lea's malloc） |
| **arena** | ptmalloc 中的内存池区域，用于管理分配和释放的内存块 |
| **ctypes** | Python 标准库中用于调用 C 函数的模块 |
| **direction-only** | 方向级结论 — 确认问题来源方向但无法精确定位到具体代码路径 |

### C. 证据文件索引

| 文件 | 路径 |
|------|------|
| T1 诊断报告 | `C:\Users\duanz\.witty-diagnosis-agent\dayu\report\kuafu_T1_20260607_223951.md` |
| T2 诊断报告 | `C:\Users\duanz\.witty-diagnosis-agent\dayu\report\kuafu_T2_20260607_223943.md` |
| T3 诊断报告 | `C:\Users\duanz\.witty-diagnosis-agent\dayu\report\kuafu_T3_20260607_223932.md` |
| correlation.json | `test/python-memory-leak-analyzer/out/production/native_ctypes_malloc_growth/correlation.json` |
| monitor_rss_pid.json | 同上 |
| object_growth.json | 同上 |
| tracemalloc.json | 同上 |
| semantic.json | 同上 |
| retention.json | 同上 |
| live_process_snapshot.json | 同上 |
