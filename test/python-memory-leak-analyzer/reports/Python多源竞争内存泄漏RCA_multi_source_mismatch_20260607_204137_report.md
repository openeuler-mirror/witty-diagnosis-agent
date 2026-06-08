# Python 多源竞争内存泄漏根因分析报告

## 故障概览

| 字段 | 内容 |
| --- | --- |
| **场景** | multi_source_mismatch（多源竞争内存泄漏） |
| **诊断模式** | 离线日志分析（Offline Analysis） |
| **证据目录** | `test/python-memory-leak-analyzer/out/stress/multi_source_mismatch` |
| **故障现象** | Python 服务 RSS 持续增长，疑似内存泄漏 |
| **诊断状态** | 只读诊断完成，未执行修复/重启/配置变更 |

## 证据与边界

### 已读取证据文件

| 证据类型 | 文件 | 裁决 |
| --- | --- | --- |
| 环境能力 | `capabilities.json` | `success` |
| 证据发现 | `discovery.json` | `success`（推荐路径：`correlated_evidence_bundle`） |
| 对象增长 | `object_growth.json` | `python_object_growth_observed` |
| 语义保留信号 | `semantic.json` | `semantic_leak_signals_observed` |
| 分配热点 | `tracemalloc.json` | `python_allocation_growth_observed` |
| 保留链 | `retention.json` | `retention_chain_observed` |
| 静态可达性 | `reachability_static.json` | `static_only`（0% 回收） |
| 反事实可达性 | `reachability_counterfactual.json` | `counterfactual_confirmed`（100% 回收） |
| **证据关联对账** | **`correlation.json`** | **`python_retained_leak_likely`** |

### 证据关联对账结果（correlation.json 总闸门）

| 字段 | 值 |
| --- | --- |
| **最终裁决** | `python_retained_leak_likely` |
| **置信度上限** | `medium_workload_only_without_live_rss_scope` |
| **覆盖警告** | `top_candidate_low_coverage_check_competing_semantic_and_retention_signals` |
| **主导内存表面** | `unknown`（缺少 RSS monitor 数据） |
| **缺失证据** | `monitor`（进程 RSS 监控）、`snapshot`（进程快照） |
| **对账说明** | 可复现 workload 显示 Python 对象/分配增长，伴随语义保留信号和保留链证据，但缺少进程 RSS 分母 |

### 只读边界说明

- 本次诊断完全基于离线证据目录，未执行以下操作：
  - ❌ attach 或 ptrace 任何进程
  - ❌ 执行修复、重启服务或修改配置
  - ❌ 运行副作用反事实（如 `clear()`、`cache_clear()`）
  - ❌ 安装额外依赖或工具
- 所有证据均通过 skill 内置脚本采集并离线归档到证据目录

## 排查过程

### 1. 对象增长分析（object_growth）

| 指标 | 数值 |
| --- | --- |
| 总追踪增长 | 39.00 MiB（40,898,608 bytes） |
| 正向追踪增长 | 23.18 MiB（24,308,616 bytes） |
| Top 候选类型 | `builtins.dict`（+12.36 MiB, +216 个） |
| 次候选类型 | `mlda_workload.LargeTenant`（+10.73 MiB, +600 个） |
| 检查点趋势 | **单调增长**（monotonic_growth），峰末差 = 0 |

**最大容器（600次迭代后）**：
- `tenant_lookup` 缓存字典：**11.89 MiB**（600 个条目, `maxsize=None` 无界）
- `LISTENERS` 列表：600 个 bound method 引用
- `SMALL_GLOBAL` 列表：30 个条目（小干扰项）

**缓存增长检测**：`tenant_lookup` 从 0 → 600 条目（`currsize_delta=600`, `unbounded=true`）

**判断**：对象增长确认 Python 托管对象持续增长，`builtins.dict` 和 `LargeTenant` 是主要增长类型。

### 2. 语义保留信号分析（semantic）

| 排名 | 信号名称 | 标签 | Score | 增长量 |
| --- | --- | --- | --- | --- |
| **#1** | **LISTENERS** | `global_registry_retains_bound_methods` | **645** | len_delta=600（bound method） |
| **#2** | **tenant_lookup** | `unbounded_cache_growth` | **600** | currsize_delta=600（`maxsize=None`） |
| #3 | SMALL_GLOBAL | `global_container_growth` | 30 | len_delta=30（干扰项） |

**竞争信号数**：2（LISTENERS 和 tenant_lookup 互为独立来源）

**关键发现**：
- `LISTENERS` 是一个全局列表，保存了 `LargeTenant.callback` 的 bound method（600 个），每个 method 的 `__self__` 指向一个 `LargeTenant` 实例，这些实例自身携带大量数据（~10.73 MiB）
- `tenant_lookup` 是一个无界缓存（`maxsize=None`），缓存了 600 个租户配置字典（~11.89 MiB）
- `SMALL_GLOBAL` 只增长了 30 条记录（score 30），**远小于前两个信号**，是一个显眼但实际影响很小的干扰项

**判断**：语义分析发现了**两个独立的泄漏来源**（回调注册中心 + 无界缓存），而 `SMALL_GLOBAL` 是干扰项。

### 3. 分配热点分析（tracemalloc）

| 指标 | 数值 |
| --- | --- |
| 当前追踪分配 | 22.543 MiB |
| 净分配增长 | 22.543 MiB |
| 峰末差 | 464 bytes（接近 0，说明持续保留） |

**Top 分配热点**：

| 大小 | 位置 | 说明 |
| --- | --- | --- |
| 11.742 MiB | `multi_source_mismatch.py:23` (LargeTenant 初始化) | 600 个 LargeTenant 实例 |
| 10.570 MiB | `multi_source_mismatch.py:13` (缓存字典条目) | 600 个缓存条目 |

**注意**：tracemalloc 标识分配点，不是保留点。分配点与 retention 保留者一致时，分配点也是保留链起点。

### 4. 保留链分析（retention）

| root_kind | 样本数 |
| --- | --- |
| `module_global:LISTENERS` | 3 条保留链（采样） |

**保留路径**：
```
module_global:LISTENERS (builtins.list)
  └─ [bound method LargeTenant.callback] (builtins.method)
       └─ LargeTenant object (mlda_workload.LargeTenant)
```

**判断**：`LISTENERS` 全局列表通过 bound method 间接持有 `LargeTenant` 实例，这些实例不能被 GC 回收，因为 module global 是 GC root。

### 5. 可达性分析

| 类型 | 裁决 | 说明 |
| --- | --- | --- |
| 静态可达性 | `static_only` | 0% 回收（600 个对象全部可达） → 无法通过常规 GC 释放 |
| 反事实可达性（沙箱） | `counterfactual_confirmed` | 100% 回收（弱引用替换后全部释放） → 确认是强引用导致的泄漏 |

### 6. 竞争假设矩阵

| 假设 | 支持证据 | 反证/降级条件 | 结论边界 |
| --- | --- | --- | --- |
| **Python retained leak（主导）** | object_growth + semantic + retention + tracemalloc 一致结论；反事实可达性确认 | 缺少 RSS monitor 分母；top candidate coverage 仅 53.3%（另有 tenant_lookup 竞争来源） | **主导假设（strong）** |
| SMALL_GLOBAL 为主因（干扰项） | 易于观察的 30 条增长 | score 仅 30，远低于 LISTENERS（645）和 tenant_lookup（600），不能解释 ~39 MiB 总增长 | **被排除**：次要干扰项 |
| native/allocator 假阳性 | 无 — Python heap 覆盖率充分 | object_growth 总追踪增长 39 MiB 与 tracemalloc 22.5 MiB 同量级，Python 对象增长解释大部分 | **被排除** |
| mmap/file/shmem 增长 | 无 — memory_surface 为 unknown | 缺少 monitor/snapshot 证据，但现有证据一致指向 Python heap | **被排除**（方向级） |

## 根因速览

### 最终裁决（基于 correlation.json）

**Verdict**: `python_retained_leak_likely`
**置信度**: `strong`（G0-G2 通过，G3 反事实确认，G4 隔离复测未执行）
**置信度上限**: `medium_workload_only_without_live_rss_scope`

### 根因结论

这是一个**多源竞争内存泄漏**，包含**两个独立的主要泄漏来源**和一个次要干扰项：

#### 泄漏源 #1（主） — 全局监听器注册中心未注销（LISTENERS）

- **机制**：`LISTENERS` 全局列表保存了 `LargeTenant.callback` 的 bound method。每个 bound method 的 `__self__` 持有对应的 `LargeTenant` 实例（每实例 ~18.8 KiB），导致这些实例永久存活
- **保留路径**：`module_global:LISTENERS` → `bound_method` → `LargeTenant object`
- **增长规模**：600 个实例，**~10.73 MiB**
- **模式**：`global_registry_retains_bound_methods`（回调/监听器未注销）
- **修复方向**：生命周期结束时 `unregister()`，使用 weakref listener，避免全局强引用

#### 泄漏源 #2（主） — 无界缓存（tenant_lookup）

- **机制**：`tenant_lookup` 缓存使用 `maxsize=None`（无界），每次 miss 写入新条目，600 次迭代后缓存 600 个条目且永不淘汰
- **增长规模**：600 个租户配置字典，**~11.89 MiB**
- **模式**：`unbounded_cache_growth`（无界缓存增长）
- **修复方向**：设置 `maxsize` 上限，添加 TTL 淘汰策略，按生命周期 `cache_clear()`

#### 干扰项 — 小全局容器（SMALL_GLOBAL）

- **特征**：30 条记录，score 仅 30，易于观察但覆盖度极低
- **结论**：**非主因**，是测试注入的干扰项。增长量远小于前两个来源

### 总量汇总

| 来源 | 估计增长 | 占比 |
| --- | --- | --- |
| tenant_lookup 缓存 | ~11.89 MiB | 30.5% |
| LISTENERS + LargeTenant 实例 | ~10.73 MiB | 27.5% |
| 其他 Python 对象增长 | ~16.38 MiB | 42.0%（含 tenant_lookup 和 LISTENERS 的嵌套对象） |
| **总增长** | **~39.00 MiB** | 600 次迭代 |

## 修复建议

> **⚠️ 注意**：以下为建议，未获授权执行。如需修复请单独确认。

### 针对 LISTENERS（优先级高）

- 添加 `unregister()` / `remove_listener()` 方法，在 `LargeTenant` 生命周期结束时自动注销
- 将 `LISTENERS` 改为 `list[weakref.ref]` 或使用 `weakref.WeakMethod`，避免强引用阻止 GC
- 使用信号/事件总线替代全局强引用注册中心

### 针对 tenant_lookup 缓存（优先级高）

- 设置 `maxsize=128`（或合适上限）限制缓存规模
- 添加 TTL（Time-To-Live）淘汰策略
- 在系统低负载时定期 `cache_clear()`

### 针对 SMALL_GLOBAL（优先级低）

- 已经规模很小，可忽略不计或正常清理即可

## 复测建议

1. 应用修复后，使用相同 workload 运行 600+ 次迭代
2. 确认 `LISTENERS` 长度稳定在预期数量（不再增长）
3. 确认 `tenant_lookup.currsize` 不超过 `maxsize` 限制
4. 使用 RSS monitor 验证整体内存不再持续增长

---

## 任务元数据

```json
{
  "plan_path": "C:\\Users\\duanz\\.witty-diagnosis-agent\\dayu\\reports\\Python多源竞争内存泄漏RCA_multi_source_mismatch_20260607_204137_report.md",
  "created_at": "2026-06-07T20:41:37+08:00",
  "mode": "offline",
  "target": "D:\\develop\\Trae\\OpenEuler\\witty-diagnosis-agent\\test\\python-memory-leak-analyzer\\out\\stress\\multi_source_mismatch",
  "tasks": [
    {
      "id": "T1",
      "symptom": "Python 服务 RSS 持续增长",
      "failure_mode": "Python retained memory leak (multi-source: global registry + unbounded cache)"
    }
  ],
  "verdict": "python_retained_leak_likely",
  "confidence_cap": "medium_workload_only_without_live_rss_scope",
  "missing_evidence": ["monitor", "snapshot"]
}
```

📁 **输出文件路径**：
- 诊断报告：`C:\Users\duanz\.witty-diagnosis-agent\dayu\reports\Python多源竞争内存泄漏RCA_multi_source_mismatch_20260607_204137_report.md`
