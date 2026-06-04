# 🔴 故障诊断报告

> **报告编号**：RCA-20260604-001
> **故障级别**：P1（内存持续泄漏，存在 OOM 风险）
> **报告时间**：2026-06-04 21:20:00
> **当前状态**：🔴 处理中（根因已定位，需修复验证）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | Python 服务进程 RSS 持续线性上涨 — ctypes native 内存泄漏 |
| 影响范围 | 目标进程 PID 425（`python native_ctypes_malloc_growth.py --live`），单线程，无子进程；若持续运行将触发系统 OOM Killer |
| 故障时段 | 2026-06-04 12:55:00 ~ 持续中（诊断采样窗口 3.5 秒） |
| 根本原因 | Python ctypes 通过 `libc.malloc()` 分配 native 内存，每次迭代约 3 MiB，指针存入 `POINTERS` 全局列表但从未调用 `libc.free()` 释放，导致匿名 Private_Dirty 页面持续线性增长 |
| 是否恢复 | ❌ 未恢复（需代码修复后复测验证） |
| 根因置信度 | 🟡 中置信（方向级证据 — direction-only；缺少 native allocator 栈追踪确认具体调用点） |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|----------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | — |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | ✅ 当前状态 — native 方向已排除所有竞争假设，但缺少 memray 栈追踪 |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
证据采集窗口 2026-06-04 12:55:22 ~ 12:55:28 (UTC)
────────────────────────────────────────────────────────────────────────────────────────────────────
t=0.0s   PID 425 (python3.12) 启动 workload，RSS = 24.5 MiB          📈 基线
  │       native_ctypes_malloc_growth.py 通过 ctypes.CDLL 加载 libc
  │
  ├── 每轮迭代 12 次 ctypes malloc，分配 ~3 MiB native 内存
  │   workload 返回 {'native_allocations': 12, 'native_bytes': 3145728}
  │       ↓                                                          🔴 每次迭代持续增长
  │   ctypes malloc 返回的指针以整数形式存入全局 POINTERS 列表
  │       但从未调用 libc.free() 释放
  │
  ├── RSS 每 0.5 秒增长 ~5 MiB                                        🟡 线性斜坡
  │   斜率 ≈ 10 MB/s
  │
  ├── Python gc/tracemalloc 对此完全不可见                            🔍 证据背离
  │   Python tracked 对象增长 = 0.017 MiB（仅 0.05%）
  │   tracemalloc 增长 = 0.001 MiB
  │
  └── 全部增长集中在 Anonymous / Private_Dirty 页面                    🔴 Native 区域
      Private_Dirty 净增长 = 35.04 MiB / 3.5s
```

### 故障因果链

```text
native_ctypes_malloc_growth.py 调用 ctypes.CDLL libc.malloc(size)
    │
    ├── 每次迭代分配 ~262 KB native 内存（C 堆 glibc arena）
    │       │
    │       ├── 指针地址被转换为整数并追加到全局列表 POINTERS
    │       └── POINTERS 不负责释放内存，仅作为地址簿
    │
    ├── malloc 分配的 native 内存以 Private_Dirty 匿名页面形式存在
    │       │
    │       └── Python gc / tracemalloc 完全不可见（仅追踪 PyObject 堆）
    │
    ├── 12 次迭代 / 轮 → ~3 MiB native 分配
    │       │
    │       └── 无 free() 调用 → 内存永不释放
    │
    ├── 3.5 秒内累积 35 MiB RSS 增长（线性无平台）
    │       │
    │       └── Python tracked 对象仅贡献 0.017 MiB（占 0.05%）
    │
    └── 🔴 根因确认：ctypes native malloc 内存泄漏（direction-only）
         └── 若持续运行 → 系统内存耗尽 → OOM Killer 触发
```

---

## 三、排查过程

### 3.1 初始现象

- **现象**: PID 425 进程 RSS 在 3.5 秒内从 **24.5 MiB 线性增长至 59.5 MiB**，净增 **35.0 MiB**，斜率约 **10 MB/s**，呈持续阶梯上升无平台迹象。
- **影响判断**: 若该模式持续，进程将在数分钟内耗尽系统内存，触发 OOM Killer。

---

### 3.2 假设驱动排查

以下排查基于三份 Kuafu 诊断报告的综合分析：

#### 假设 A：Python 托管对象保留泄漏

> 🧪 假设：Python 对象（如 collections.Counter、list、dict）持续增长且无法被 GC 回收，导致 RSS 上涨。

| 检查项 | 操作（基于证据文件） | 结论 |
|--------|---------------------|------|
| 对象增长量化 | `object_growth.json` 确认 Python tracked 对象净增 **17,648 B (0.017 MiB)**，主要来自 `collections.Counter` (+6,688 B) | ❌ 与 35 MiB RSS 增长完全不成比例 |
| tracemalloc 追踪 | `tracemalloc.json` 显示 Python 堆分配净增 **1,464 B (0.001 MiB)** | ❌ 微不足道 |
| Python heap / Private_Dirty 比率 | = **0.0** — Python 栈堆对 RSS 增长无贡献 | ❌ 严重背离 |
| tracked object / Private_Dirty 比率 | = **0.0003（0.03%）** | ❌ 无法解释 99.97% 增长 |
| GC 循环引用 | garbage_len = 0，无循环引用残留 | ✅ 无泄漏性 GC 问题 |

**❌ 排除**：Python 托管对象保留仅能解释 0.03% 的 RSS 增长，**不是主因**。

---

#### 假设 B：无界容器 / 全局引用增长

> 🧪 假设：全局容器（如 `POINTERS` 列表）无界增长，持有对象引用导致内存无法释放。

| 检查项 | 操作（基于证据文件） | 结论 |
|--------|---------------------|------|
| 全局容器增长 | `semantic.json` 检测到 `global_container_growth` 信号，`POINTERS` 列表 len_delta = +12 | ⚠️ 信号存在但规模极小 |
| 容器浅层大小 | 12 个 int 对象仅 **184 字节** | ❌ 远不足以解释 35 MiB 增长 |
| 保留链分析 | retention chain 指向 `builtins`/`os`/`time` 模块 dict 和闭包 cell | ✅ 但属于标准运行时架构，非应用层泄漏 |
| 无界增长趋势 | checkpoint 追踪显示 net_tracked_growth 在迭代 6-12 后趋于平稳（2,145,642 → 2,145,770 仅 +128 B） | ❌ 不是无界增长 |

**❌ 排除**：全局容器 `POINTERS` 仅增长 184 字节，**不是主因**。

---

#### 假设 C：Native / C 扩展内存泄漏 ✅ 根因确认（方向级）

> 🧪 假设：ctypes 通过 `libc.malloc()` 分配的 native 内存未被释放，导致 Private_Dirty 匿名页面持续增长。

| 检查项 | 操作（基于证据文件） | 结论 |
|--------|---------------------|------|
| RSS 增长形态 | RSS 净增 **35.0 MiB**，全部为 **Private_Dirty / RssAnon**，RssFile / RssShmem 持平 | ✅ 符合 native malloc 匿名页面特征 |
| 增长线性度 | 8 个采样点显示斜率一致 (~10 MB/s)，无 plateau | ✅ 排除 allocator high-water 假设 |
| ctypes 库已加载 | mapping 中包含 `_ctypes.cpython-312-x86_64-linux-gnu.so` | ✅ ctypes 路径确认 |
| workload 自报告 | 每次迭代返回 `native_bytes: 3,145,728`（~3 MiB/轮） | ✅ 与 RSS 增长量级一致 |
| Python 堆背离 | Python heap / Private_Dirty ratio = **0.0**；tracemalloc 仅 1.4 KB | ✅ 增长完全在 Python GC 视野之外 |
| 全局 POINTERS 角色 | `POINTERS` 列表存储 ctypes malloc 返回的指针地址（整数表示） | ✅ 指针被持有但从未调用 `free()` |

**✅ 结论：ctypes native malloc 内存泄漏为根因。** 但由于 memray 缺失，无法获取 native allocator 栈追踪，置信度限制为 direction-only 级别。

---

#### 假设 D：短窗口/临时峰值

> 🧪 假设：3.5 秒采样窗口过短，可能只是瞬时峰值。

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 增长持续性 | 8 个采样点每 0.5 秒间隔，增量稳定在 4.7~5.5 MiB | ✅ 持续线性，非瞬态 |
| 有无回落 | 全程无下降趋势 | ❌ 排除瞬态峰值 |

**❌ 排除**：增长持续线性稳定，非短窗口噪点。

---

#### 假设 E：mmap/文件映射/共享内存增长

| 检查项 | 操作 | 结论 |
|--------|------|------|
| RssFile | 全程持平 7.0 MiB，无增长 | ❌ 排除 |
| RssShmem | = 0 | ❌ 排除 |

**❌ 排除**：无文件映射或共享内存增长。

---

### 3.3 排查结论与逻辑树

```text
进程 RSS 持续线性增长（35 MiB / 3.5s）
│
├── 假设 A：Python 对象保留泄漏
│   ├── tracked object = 0.017 MiB（占 RSS 0.05%）  → ❌ 规模严重不匹配
│   ├── tracemalloc = 0.001 MiB                      → ❌ 微不足道
│   └── Python heap / Private_Dirty ratio = 0.0     → ❌ 完全背离
│   → ❌ 排除为主因
│
├── 假设 B：无界容器/全局引用
│   ├── POINTERS 仅 +12 ints（184 字节）             → ❌ 远不足以解释
│   └── retention chain 为标准运行时结构             → ✅ 非应用层泄漏
│   → ❌ 排除为主因
│
├── 假设 C：Native / ctypes 内存泄漏
│   ├── Private_Dirty 增长 35.04 MiB（100% 匿名）    → ✅ Native 特征
│   ├── _ctypes.so 已加载                           → ✅ ctypes 路径
│   ├── workload 报告 3 MiB native/轮                → ✅ 量级匹配
│   ├── POINTERS 持指针但无 free()                   → ✅ 泄漏路径
│   └── Python 堆完全不可见                          → ✅ 解释背离
│   → ✅ 根因确认（direction-only）
│
├── 假设 D：短窗口峰值
│   └── 8 点持续线性，无回落                         → ❌ 排除
│
├── 假设 E：mmap/文件/共享内存
│   └── RssFile/RssShmem 均无增长                    → ❌ 排除
│
└── 🎯 根因：ctypes native malloc 未释放
        置信度：🟡 direction-only（需 memray 升级验证）
```

---

## 四、关键证据对账表

以下使用标准 Markdown 表格形式汇总三份 Kuafu 报告的核心对账数据：

### 4.1 三任务结论汇总

| 任务 ID | 诊断方向 | Verdict | 关键证据 | 结论 |
|---------|---------|---------|----------|------|
| T1 | Python 对象保留 | `native_or_allocator_suspect` | tracked 对象 / Private_Dirty ratio = **0.0003** | ❌ **REFUTED** — 0.03% 无法解释主因 |
| T2 | Native 内存泄漏 | `native_or_allocator_suspect` | workload `native_bytes=3,145,728`/轮；Private_Dirty 净增 35.04 MiB；ctypes 库已加载 | ✅ **CONFIRMED**（direction-only） |
| T3 | 无界容器增长 | `native_or_allocator_suspect` | POINTERS 全局列表仅 +12 ints（184 字节），retention chain 为标准运行时结构 | ❌ **REFUTED** — 非无界容器泄漏 |

### 4.2 RSS 增长对账

| 维度 | 数值 | 占 RSS 增长比例 |
|------|------|----------------|
| RSS 净增长 | **35.0 MiB** (36,700,160 B) | 100% |
| Private_Dirty 净增长 | **35.04 MiB** (36,745,216 B) | 100% |
| Python tracked 对象增长 | **0.017 MiB** (17,648 B) | **0.05%** |
| tracemalloc 追踪增长 | **0.001 MiB** (1,464 B) | **0.004%** |
| Python heap / Private_Dirty ratio | **0.0** | — |
| tracked object / Private_Dirty ratio | **0.0003** | — |
| 剩余未解释增长 | ~35 MiB | **99.95%** → 指向 native 分配 |

### 4.3 竞争假设排除矩阵

| 假设 | 状态 | 排除依据 |
|------|------|---------|
| Python 托对象保留泄漏 | ❌ 排除 | tracked 对象仅 17 KB vs 35 MiB RSS，ratio=0.0003 |
| 无界容器/全局引用增长 | ❌ 排除 | POINTERS 仅 +12 ints（184 字节） |
| Native/ctypes malloc 泄漏 | ✅ **根因** | Private_Dirty 100% 增长，workload 自报告 3 MiB/轮，ctypes 库已加载 |
| mmap/文件映射/共享内存 | ❌ 排除 | RssFile/RssShmem 均无增长 |
| Short-window 瞬态峰值 | ❌ 排除 | 3.5s 内 8 点持续线性，斜率一致 |
| Allocator high-water/plateau | ❌ 排除 | 增长为持续阶梯形，无平台期 |

---

## 五、修复方案

### 5.1 应急处置

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 设置 cgroup memory limit 防止 OOM 扩散至其它进程 | 系统/人工 | 立即 | 进程本身会被 OOM kill，但不影响兄弟进程 |
| 2 | 在 `POINTERS` 列表增长逻辑中增加阈值和淘汰策略 | 开发 | 紧急修复 | 减少累积量，但非根本方案 |

### 5.2 永久修复计划

| 优先级 | 修复措施 | 负责人 | 完成时间 |
|--------|---------|--------|---------|
| P0 | **代码级修复**: 确保 `ctypes.CDLL` 分配的每个 `libc.malloc()` 返回值有对应的 `libc.free()` 调用，建议采用 RAII 封装或 `weakref.finalize` 注册自动释放回调 | 开发团队 | 待定 |
| P0 | **诊断增强**: 安装 `memray` (`pip install memray`)，采集 native 分配栈，确认具体未释放的 malloc 调用点和调用链 | 运维/SRE | 修复前 |
| P1 | **可观测性提升**: 对进程 RSS / Private_Dirty 设置告警阈值（如超过基线 200%） | 运维 | 修复后 |
| P1 | **复测验证**: 修复后执行 `./run.sh run-prod native_ctypes_malloc_growth`，验证 `correlation.json` verdict 从 `native_or_allocator_suspect` 变为 `no_growth` 或 `python_heap_explains_growth` | QA/开发 | 修复后 |

### 5.3 修复风险提示

- 若 native 内存由 C 库内部管理（如缓存池），外部调用 `free()` 可能导致 **double-free 或 use-after-free**
- 建议在源代码级审查 `ctypes.CDLL` 调用的 C 函数的生命周期契约
- 修复后建议用 `memray run` + valgrind 做回归验证

---

## 诊断质量自查

- [x] **路径溯源**：所有核心结论均基于三份 Kuafu 报告的标准路径引用
- [x] **逻辑闭环**：故障传导链路从 workload 自报告 native_bytes → Private_Dirty 增长 → Python 堆背离 → 根因确认，逻辑自洽
- [x] **置信度边界**：明确标注方向级（direction-only），指出 memray 缺失是置信度封顶原因
- [x] **竞争假设完整**：涵盖 Python retained leak、无界容器、native、mmap、short-window、plateau 六大假设
- [x] **表格格式规范**：所有表格均使用标准 Markdown 表格语法

---

**报告生成路径**: `C:\Users\duanz\.witty-diagnosis-agent\baize\reports\Python服务内存持续上涨_RCA_native_ctypes_malloc_growth_20260604_212000_report.md`
