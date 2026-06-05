---
name: python-memory-leak-analyzer
description: >
  Python 进程内存泄漏根因分析技能。当用户提到 Python 服务或脚本 RSS 持续上涨、
  内存降不下来、疑似 memory leak、被 OOM kill、缓存持续膨胀、tracemalloc 线索、
  gc/objgraph/memray 诊断、C 扩展或 native 内存增长时，必须使用本技能。覆盖 Python
  托管对象泄漏、全局容器/无界缓存、闭包/回调/线程局部保留、引用循环、分配点与保留点分离、
  RSS 与 Python 堆背离、碎片化或缓存预热伪泄漏。支持从目录、PID、服务名或日志包自动发现证据。
  默认采用只读和可复现路径，不默认 attach 线上进程或执行副作用干预。
---

# Python 内存泄漏根因分析 Skill

## 第一节：使用时机与输入

当问题涉及 Python 进程内存持续增长、RSS 居高、OOM、疑似泄漏、native/C 扩展内存、mmap/file/shmem 增长或“内存降不下来”时使用本 skill。用户只给目录、PID、服务名、日志包或模糊范围时，先自动发现证据，不要求用户手工枚举 JSON 或日志。

可接受输入：

- 目录、日志包、测试输出目录、报告目录或源码范围。
- PID、服务名、容器名、cgroup 线索。
- 可复现 workload 脚本，要求定义 `run_workload(iterations)`，可选 `setup()`。
- 已有 `tracemalloc`、memray、RSS、OOM、monitor、`/proc` 或 Witty 报告产物。

本 skill 内置脚本：

```text
scripts/
├── detect_capabilities.py
├── discover_evidence.py
├── live_process_snapshot.py
├── monitor_rss.py
├── object_growth.py
├── semantic_probe.py
├── tracemalloc_probe.py
├── retention_chain.py
├── reachability_probe.py
├── correlate_evidence.py
└── parse_memray.py
```

## 第二节：核心原则

- **范围先行**：先确认当前诊断范围、PID、worker、cgroup 和 mapping 口径；历史报告不能替代当前范围内的结构化证据。
- **先证伪再归因**：RSS 高水位、短窗口、缓存预热、allocator high-water、mmap/file/shmem 或 worker skew 都可能不是 Python retained leak。
- **分配点不等于根因**：tracemalloc 只回答“在哪里分配”，根因通常在保留者和生命周期缺陷。
- **报告前必须对账**：最终结论先读 `correlation.json`，再按 `references/evidence-analysis.md` 和 `references/validation-gates.md` 控制措辞。
- **线上默认只读**：不默认 attach、ptrace、安装依赖、清缓存、置空全局、注销回调、重启或修改配置。

## 第三节：统一流程

### 1. 能力预检

```bash
python scripts/detect_capabilities.py
```

读取 `capabilities`、`recommended_path`、`degraded_capabilities` 和 `next_steps`。依赖缺失不阻塞，按当前可用能力继续，unknown 按缺失处理。

### 2. 范围定界与证据发现

```bash
python scripts/discover_evidence.py /path/to/scope
python scripts/discover_evidence.py pid:<PID>
python scripts/discover_evidence.py service-or-process-name
```

按 `recommendation.recommended_path` 路由：

- `offline_evidence_bundle`：进入 `primary_evidence_dir` 读结构化证据。
- `reproducible_workload`：运行完整 Python heap 路径。
- `live_pid_external_readonly`：只做 PID/RSS/mapping/cgroup 定界；没有 heap/retention 证据不得确认 Python 根因。
- `correlated_evidence_bundle`：先读 `correlation.json`。
- `diagnosis_report`：只作背景，必须与当前场景结构化证据一致才可引用。

故障时间窗口不是离线证据包的阻塞条件；缺失时在报告中列为上下文缺口。

### 3. 采集证据

真实 PID 或服务名：

```bash
python scripts/live_process_snapshot.py --pid <PID> --output live_process_snapshot.json
python scripts/monitor_rss.py --pid <PID> --interval 1 --duration 30 --output monitor_rss_pid.json
```

可复现 workload：

```bash
python scripts/object_growth.py --script /path/to/leak_case.py --iterations 1000 --output object_growth.json
python scripts/semantic_probe.py --script /path/to/leak_case.py --iterations 1000 --output semantic.json
python scripts/tracemalloc_probe.py --script /path/to/leak_case.py --iterations 1000 --nframe 15 --output tracemalloc.json
python scripts/retention_chain.py --script /path/to/leak_case.py --iterations 1000 --type-filter "<candidate>" --output retention.json
```

生产或非沙箱环境只做静态可达性：

```bash
python scripts/reachability_probe.py --script /path/to/leak_case.py --type-filter "<candidate>" --output reachability_static.json
```

只有用户明确确认沙箱或可承受副作用时，才允许 `--allow-mutation`。

### 4. 分析证据

报告前运行或读取 evidence correlation：

```bash
python scripts/correlate_evidence.py \
  --monitor monitor_rss_pid.json \
  --snapshot live_process_snapshot.json \
  --object-growth object_growth.json \
  --tracemalloc tracemalloc.json \
  --semantic semantic.json \
  --retention retention.json \
  --output correlation.json
```

随后按顺序读取：

1. `references/evidence-analysis.md`：证据读取顺序、字段判读、竞争假设矩阵和 verdict 措辞。
2. `references/root-cause-patterns.md`：把 semantic label 与 root_kind 映射到根因模式。
3. `references/validation-gates.md`：填写 G0-G5，确定 confirmed/strong/weak/direction-only。
4. `references/native-leaks.md` 或 `references/live-process.md`：处理 native/mmap/allocator 或只读 PID 边界。

禁止绕过 `correlation.json` 直接写“已确认 Python 根因”。`readonly_insufficient`、`native_or_allocator_suspect`、`mmap_or_file_backed_growth`、`allocator_reuse_or_fragmentation_possible` 只能输出方向级或边界结论。

## 第四节：报告要求

按 `assets/report-template.md` 输出，至少包含：

```text
1. 故障概要与影响
2. 能力画像与降级边界
3. Live PID 只读定界
4. 证据对账总闸门
5. RSS/堆增长定界
6. 对象增长证据
7. 语义保留信号
8. 分配热点证据
9. 保留链证据
10. 验证门结果
11. 根因结论与置信度
12. 修复建议
13. 复测方案
```

报告必须明确区分：

- 已确认事实。
- 主导假设。
- 次要来源或干扰项。
- 未验证项。
- 因权限、依赖、线上风险或证据缺失导致的置信度上限。

低输入或只读验证场景中，不要在报告尾部发起“是否执行修复”的交互选择；自动源码修复和修复后验证需要独立授权。

## 第五节：安全边界

- 只读或离线解析：`detect_capabilities.py`、`discover_evidence.py`、`live_process_snapshot.py`、`monitor_rss.py`、`correlate_evidence.py`、`parse_memray.py`。
- 会执行 workload：`object_growth.py`、`semantic_probe.py`、`tracemalloc_probe.py`、`retention_chain.py`。仅用于可信离线样例、测试目录或用户确认的沙箱复现。
- 有副作用：`reachability_probe.py --allow-mutation`，只能在沙箱或用户明确批准的可承受环境执行。
- 线上 PID 默认不 attach、不 ptrace、不安装包、不清缓存、不置空全局、不注销回调、不重启服务。

## 第六节：参考文件

- `references/methodology.md`：阶段化方法论。
- `references/evidence-analysis.md`：证据判读、竞争假设和结论措辞。
- `references/tool-selection.md`：工具能力和降级路径。
- `references/validation-gates.md`：G0-G5 可填写验证门。
- `references/root-cause-patterns.md`：常见根因模式卡片。
- `references/live-process.md`：线上不可重启 PID 边界。
- `references/native-leaks.md`：native、allocator、mmap 与 Python 堆背离路径。
- `assets/report-template.md`：最终报告模板。
