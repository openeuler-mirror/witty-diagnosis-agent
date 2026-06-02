---
name: kernel-io-uring-diagnosis
description: >
  Linux io_uring 异步 I/O 子系统故障诊断技能。当用户提到 io_uring_setup、
  io_uring_enter、io_uring_register、提交队列/完成队列异常、CQE 丢失、
  completion 延迟、io-wq worker 繁忙、SQPOLL 异常、fixed buffer 注册失败、
  O_DIRECT EINVAL、或高版本 io_uring feature 在旧内核不可用时，必须使用本技能。
  覆盖场景：资源限制、ring 容量、worker/SQPOLL、fixed buffer、O_DIRECT 对齐、
  内核兼容性和待补证据分支。
version: 1.0.0
category: analysis
author: duanzhoutao
created: 2026-06-02
updated: 2026-06-03
tags:
  - linux-kernel
  - io-uring
  - async-io
  - system-call
  - openEuler
scripts:
  - scripts/collect_io_uring_context.sh
  - scripts/diagnose_io_uring_limits.sh
  - scripts/diagnose_io_uring_rings.sh
  - scripts/diagnose_io_uring_workers.sh
  - scripts/diagnose_io_uring_compat.sh
---

# io_uring 异步 I/O 故障深度诊断（双轨：运行证据 + 内核语义）

## 第一节：故障目录结构

```text
io_uring_case/                  # 故障材料目录
├── src/                         # 【可选，优先】应用或内核源码路径
│   ├── app/                     # 应用 io_uring 调用路径
│   └── kernel/                  # 内核源码或相关 backport patch
├── logs/                        # 应用日志、dmesg、journalctl、strace 输出
│   ├── app.log
│   ├── kernel.log
│   └── io_uring_strace.log
├── proc_snapshot/               # /proc/<pid> 快照（limits、status、task、fd）
├── perf_data/                   # 【可选】perf/ftrace/bpftrace 采样
└── reproduction/                # 【可选】复现程序或测试命令
```

```bash
# 典型信息采集方式（运行时）：
bash scripts/collect_io_uring_context.sh -p <pid> -l <log_file> -o /tmp/io_uring_diag_<case>
```

---

## 第二节：分析策略（并行双轨，交叉验证）

**运行证据分析和内核语义分析应同时推进，而非二选一。** 运行证据轨道从
日志、strace、/proc、线程状态和测试输出出发，回答“发生了什么”；内核语义
轨道从 io_uring syscall、注册资源、worker、SQPOLL、O_DIRECT 和 feature 约束
出发，回答“为什么会这样”。最终通过两轨交叉验证收敛根因。

```
┌─────────────────────────────────────────────────────────────────┐
│                    并行双轨分析模型                               │
│                                                                 │
│  轨道一：运行证据分析（逆向）       轨道二：内核语义分析（正向）    │
│  ──────────────────────────       ────────────────────────      │
│  从日志/strace/proc/线程状态出发，  从 io_uring API 和内核约束出发，│
│  识别 errno、队列、worker 和时序     追踪资源、参数、feature 和代码 │
│                                                                 │
│  回答：哪个阶段异常？              回答：为什么该阶段会返回       │
│        证据是否足够？                    该 errno 或出现延迟？    │
│                                                                 │
│            ↓                                   ↓                │
│            └────────────── 交叉验证 ────────────┘                │
│                                                                 │
│  见：第三节（统一分析流程：分支决策→双轨并行→交叉验证→输出）       │
└─────────────────────────────────────────────────────────────────┘
```

**两条轨道的分工与互补**：

| | 运行证据轨道 | 内核语义轨道 |
|--|------------|------------|
| **优势** | 真实 errno、时间窗口、线程状态、ring/worker 现象可见 | io_uring 参数语义、资源限制、feature 支持和生命周期可解释 |
| **局限** | 日志可能缺少 setup/register 参数；strace 可能影响性能 | 需要内核版本和应用源码匹配；发行版 backport 可能改变判断 |
| **典型盲区** | 只能看到结果，无法直接看到内核内部队列状态 | 只看代码可能忽略真实运行限制、cgroup 或调度状态 |

**何时两条轨道都必须做**：有源码、复现程序、strace 或完整日志时，两条轨道都要推进，
最终用运行证据校正语义推断。

**何时只能走运行证据轨道**：无源码或无法复现时，基于日志、/proc 快照和测试输出形成
候选根因，并在结论中标注缺失证据和置信度边界。

---

## 第三节：统一分析流程（分支决策 → 双轨并行 → 交叉验证 → 输出）

> 执行约束：所有诊断脚本默认只读，不修改系统配置、不 kill 进程、不删除业务文件。

### Step 1：启动（基线信息收集 + 分支推荐）

运行：

```bash
bash scripts/collect_io_uring_context.sh -p <pid> -l <log_file> -o /tmp/io_uring_diag_<case>
```

没有 PID 时可做系统级和日志级分析：

```bash
bash scripts/collect_io_uring_context.sh -l <log_file> -o /tmp/io_uring_diag_<case>
```

记录输出中的五类关键信息（后续所有步骤都围绕它们推进）：

- **内核和发行版**：`uname -a`、`/etc/os-release`、io_uring header 线索。
- **目标进程状态**：PID、线程、`/proc/<pid>/limits`、`/proc/<pid>/status`、fd、cgroup。
- **错误阶段**：setup、enter、register、submit、complete、worker、SQPOLL 或 O_DIRECT。
- **关键 errno**：`ENOMEM`、`EPERM`、`EAGAIN`、`EINVAL`、`EBUSY`、`EFAULT`、`ENOSYS`。
- **证据缺口**：缺少 strace、缺少 PID、权限不足、日志时间窗口不完整等。

### Step 2：故障类型定界（选择分支脚本一键跑）

按 Step 1 输出推荐，执行对应分支脚本：

```bash
bash scripts/diagnose_io_uring_limits.sh -p <pid> -l <log_file>
bash scripts/diagnose_io_uring_rings.sh -p <pid> -l <log_file>
bash scripts/diagnose_io_uring_workers.sh -p <pid> -l <log_file>
bash scripts/diagnose_io_uring_compat.sh -l <log_file>
```

若同一案例命中多个分支，必须按推荐顺序全部执行，不可只选其一。

脚本对应执行参考如下：

```
分析结果
  ├─ io_uring_setup/register 返回 ENOMEM/EPERM/EAGAIN
  │   → 分支A：资源限制与权限（limits）
  ├─ SQ full / CQ overflow / CQE missing / completion latency
  │   → 分支B：ring 容量与完成事件流（rings）
  ├─ iou-wrk 线程多、D 状态、CPU 高、I/O 阻塞
  │   → 分支C：io-wq worker 耗尽或阻塞（workers）
  ├─ IORING_SETUP_SQPOLL、iou-sqp、CPU 绑定或调度异常
  │   → 分支D：SQPOLL 权限、调度与亲和性（workers）
  ├─ fixed buffer/file 注册失败、IOSQE_FIXED_FILE 异常
  │   → 分支E：注册资源与生命周期（limits + compat）
  ├─ O_DIRECT EINVAL、短 I/O、对齐错误
  │   → 分支F：Direct I/O 对齐与文件系统约束（rings）
  ├─ ENOSYS / 新 opcode / 新 flag / 旧内核失败
  │   → 分支G：内核 feature 兼容性（compat）
  └─ 证据不足但症状疑似 io_uring
      → 分支H：待补证据（先补 strace、应用日志、PID 快照）
```

### Step 3：运行证据逆向（回答“哪个阶段异常 + errno/线程/队列如何”）

在分支脚本输出基础上，完成并固化四步证据链：

- **R1 调用现场还原**：确认异常发生在 `io_uring_setup`、`io_uring_enter`、
  `io_uring_register`、提交路径、完成路径、worker 或 SQPOLL。
- **R2 错误码与参数重建**：记录 entries、flags、register opcode、buffer 大小、
  O_DIRECT 地址/长度/offset、返回 errno 和触发时间。
- **R3 进程级归因**：定位目标进程、线程、`iou-wrk`/`iou-sqp` 状态、limits、
  cgroup、fd 和内存状态。
- **R4 独立归因**：仅基于客观运行数据，给出“异常阶段是什么、直接证据是什么、
  当前是否能支撑根因”的判断。

运行证据轨道输出格式：

```
异常阶段：<setup | enter | register | submit | complete | worker | SQPOLL | O_DIRECT>
关键 errno：<errno>  含义：<strerror>
目标进程：PID=<pid>  Name=<name>  Threads=<count>
资源状态：memlock=<value>  nofile=<value>  cgroup=<summary>
线程状态：iou-wrk=<summary>  iou-sqp=<summary>
运行证据归因假设：<一句话>
缺失证据：<strace/PID/源码/日志窗口等>
```

### Step 4：内核语义正向（有源码或参数时必做；回答“为什么会这样”）

#### S0：内核版本与 feature 验证

```bash
uname -a
cat /etc/os-release
grep -R "IORING_FEAT_" /usr/include/linux/io_uring.h 2>/dev/null
grep -R "IORING_SETUP_" /usr/include/linux/io_uring.h 2>/dev/null
```

版本判断原则：

- header 中存在某个符号不等于运行内核支持该 feature。
- 应用可能用新 header 编译，但运行在旧内核或 backport 不完整的发行版内核上。
- `ENOSYS` 是 syscall 不可用的强证据；单独 `EINVAL` 只能说明“参数无效或 feature 不支持”，
  需要解码参数后再下结论。

#### S1–S2：以异常阶段为入口，完成“API-内核语义对齐”

- **S1 锚定入口**：取 Step 3 的异常阶段和 errno，定位到 setup、enter、register、
  worker、SQPOLL 或 direct I/O 对应语义。
- **S2 对齐确认**：用运行参数校验该 errno 是否可能由资源限制、参数非法、feature 不支持、
  生命周期错误或后端 I/O 阻塞触发。

典型理解陷阱与处理：

| 认知误区 | 实际情况 | 应对方式 |
|---------|---------|---------|
| `ENOMEM` 一定是系统内存不足 | fixed buffer 注册常见于 memlock 或 pinned page 限制 | 对比注册字节数与 `Max locked memory` |
| `EINVAL` 一定是内核不支持 | 也可能是 entries、flags、opcode、O_DIRECT 对齐参数错误 | 解码 syscall 参数再分类 |
| worker 数多就是耗尽 | worker 数多可能是正常并发，也可能是后端 I/O 阻塞 | 结合线程状态、wchan、I/O 日志判断 |
| SQPOLL CPU 高就是异常 | SQPOLL 本身会 busy polling | 结合 CPU 绑定、cgroup 和完成延迟判断 |
| O_DIRECT 失败就是 io_uring 问题 | 很多 O_DIRECT `EINVAL` 来自文件系统/块设备对齐要求 | 核对地址、长度、offset 和 block size |

#### S3：资源生命周期追踪

围绕异常对象追踪：

```
ring 创建 → 资源注册 → SQE 提交 → worker/SQPOLL 执行 → CQE 消费 → 资源注销
```

重点审查：

- ring entries 和 CQ size 是否匹配 workload。
- fixed buffer/file 是否在仍有 in-flight 请求时注销。
- 应用是否及时 drain CQE。
- SQPOLL 是否受权限、CPU 亲和性或 cgroup 限制。
- O_DIRECT 是否满足 buffer 地址、长度、文件 offset 和设备 block size 约束。

#### S4：反事实验证（强制；不能止步于“找到可疑 errno”）

用根因假设正向推演，并与运行证据逐条对齐：

```
✓ 推演的异常阶段 == 运行日志中的异常阶段？
✓ 推演的 errno == strace/应用日志中的 errno？
✓ 推演的资源状态 == /proc 或测试输出中的限制？
✓ 推演的修正动作在测试环境中能改变结果？
```

四条全 ✓ 才能判定“根因确认”。无法运行反事实验证时，必须标注为中/低置信度。

内核语义轨道输出格式：

```
内核版本：<version>
异常阶段：<setup/register/enter/worker/SQPOLL/O_DIRECT>
根因类型：[资源限制 | 参数错误 | ring容量 | worker阻塞 | SQPOLL调度 | O_DIRECT对齐 | feature兼容]
语义解释：<为什么该参数/资源状态会触发该 errno 或延迟>
因果链：[触发条件] → [内核/应用行为] → [errno/延迟] → [系统表现]
```

### Step 5：交叉验证（双轨汇合，冲突仲裁，置信度收敛）

对每条证据做对齐检查：

| 验证维度 | 运行证据结论 | 内核语义结论 | 是否吻合？ |
|---------|-------------|-------------|-----------|
| 异常阶段 | setup/register/enter/worker 等 | 对应 io_uring 语义路径 | □ 吻合 □ 不符 |
| 关键 errno | 日志/strace/test 输出 | 内核返回该 errno 的原因 | □ 吻合 □ 不符 |
| 资源状态 | limits、cgroup、线程、fd | 资源限制或生命周期解释 | □ 吻合 □ 不符 |
| 时间序列 | 故障窗口与线程状态 | 触发条件与 I/O 后端状态 | □ 吻合 □ 不符 |
| 修正方向 | 测试环境变更结果 | 根因假设推演结果 | □ 吻合 □ 不符 |

不一致时的仲裁原则：

```
errno/时间/参数：优先信任 strace、应用日志和测试输出
feature 支持：优先信任运行时 probe，不只看 header
根因层不符：保留多假设并补证据（PID 快照、线程栈、复现日志、源码路径）
```

置信度收敛：

- **高**：两轨完全吻合 + 反事实验证通过。
- **中**：两轨基本吻合，但有 1 个关键维度依赖推断；或仅完成运行证据轨道。
- **低**：关键参数、线程状态、错误日志或复现结果缺失。
- **需进一步排查**：症状疑似 io_uring，但无法定位异常阶段或 errno。

### Step 6：最终输出（按第九节模板落盘）

将 Step 3/4/5 的输出填入第九节报告结构，并显式写清：故障分类、证据链、
排除项、风险、修复建议和验证建议。

---

## 第四节：轨道一 —— 运行证据分析（逆向推理）

本节已合并进第三节的统一流程（Step 3）。

---

## 第五节：轨道二 —— 内核语义分析（正向追踪）

本节已合并进第三节的统一流程（Step 4）。

---

## 第六节：交叉验证与结论收敛（双轨汇合）

本节已合并进第三节的统一流程（Step 5）。

---

## 第七节：故障类型决策树（两条轨道共用）

本节内容已合并进第三节的统一流程（Step 2）。

---

## 第八节：注意事项与置信度评级

- 诊断脚本默认只读，不修改 `ulimit`、sysctl、systemd unit、cgroup、CPU affinity
  或文件系统配置。
- 不自动 kill 进程、不删除业务文件、不触发压力测试。
- `strace`、perf、ftrace、bpftrace 会影响目标进程性能；生产环境采集前必须说明风险。
- 无 PID 时只做系统级和日志级分析。
- 无 root 时跳过不可读的内核日志、线程栈和 perf/ftrace，并标注权限缺口。
- 无 strace/perf/bpftrace 时，使用应用日志、`/proc`、`ps` 和内核版本继续分析。
- 无复现时，基于离线日志形成候选根因，并明确置信度边界。

---

## 第九节：最终报告结构

```
## 故障概要
  故障模式：<资源限制 / ring容量 / worker阻塞 / SQPOLL异常 / fixed buffer / O_DIRECT对齐 / feature兼容>
  置信度：<高/中/低/需进一步排查>
  分析轨道：[双轨（运行证据 + 内核语义）| 单轨（仅运行证据）]
  内核版本：<版本号>
  目标对象：PID=<pid>  服务=<service>  时间窗口=<time window>

## 运行证据轨道结论
  异常阶段：<setup/register/enter/submit/complete/worker/SQPOLL/O_DIRECT>
  关键 errno：<errno>  含义：<strerror>
  关键日志：<日志行或摘要>
  资源状态：memlock=<value>  nofile=<value>  cgroup=<summary>
  线程状态：iou-wrk=<summary>  iou-sqp=<summary>
  运行证据归因假设：<一句话>

## 内核语义轨道结论（有源码、参数或 feature 证据时填写）
  根因类型：[资源限制 | 参数错误 | ring容量 | worker阻塞 | SQPOLL调度 | O_DIRECT对齐 | feature兼容]
  语义解释：<为什么当前参数、资源或 feature 状态会触发该现象>
  触发条件：<需要什么前置状态>
  因果链：[触发事件] → [内核/应用行为] → [errno/延迟] → [系统表现]

## 交叉验证结果
  异常阶段吻合：    □ 是  □ 否（差异说明：<...>）
  关键 errno 吻合： □ 是  □ 否（差异说明：<...>）
  资源状态吻合：    □ 是  □ 否（差异说明：<...>）
  时间序列吻合：    □ 是  □ 否（差异说明：<...>）
  综合判断：<两轨结论是否一致，若有矛盾如何解释>

## 完整因果链（双轨收敛后）
  [触发条件] → [根因] → [io_uring 阶段]
  → [errno/延迟/队列异常] → [系统表现]

## 排除的替代假设
  - <假设X>：排除原因 <...>

## 风险与影响
  数据一致性风险：<...>
  性能风险：<...>
  影响范围：<...>

## 修复建议
  只读建议：
    <进一步采集或确认方式>
  需要审批的操作：
    <调整限制、复现压力、修改配置、重启服务等>

## 验证建议
  <如何确认根因 + 如何验证修复有效>
```

---

## 第十节：参考文件

- `references/io_uring_fault_patterns.md`：io_uring 故障模式、证据和分支判断。
- `references/io_uring_commands.md`：常用采集、strace、线程、日志和 O_DIRECT 检查命令。
- `references/io_uring_kernel_features.md`：内核 feature、runtime probe 和兼容性判断规则。
- `examples/report_template.md`：最终诊断报告模板。
