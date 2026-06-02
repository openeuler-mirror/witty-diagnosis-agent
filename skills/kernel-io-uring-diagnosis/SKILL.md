---
name: kernel-io-uring-diagnosis
description: >
  Linux io_uring asynchronous I/O diagnosis skill. Use this skill when
  io_uring_setup/io_uring_enter/io_uring_register fails, completion events are
  delayed or missing, SQ/CQ rings overflow, io-wq workers are busy, SQPOLL
  behaves abnormally, fixed buffer registration fails, O_DIRECT returns EINVAL,
  or an application uses io_uring features that may be unsupported by the
  running kernel.
version: 1.0.0
category: analysis
author: duanzhoutao
created: 2026-06-02
updated: 2026-06-02
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

# io_uring 异步 I/O 故障诊断

## 概述

本 skill 用于诊断 Linux io_uring 异步 I/O 子系统相关故障。诊断对象包括
io_uring 实例创建失败、提交队列或完成队列异常、io-wq worker 异常繁忙、
SQPOLL 调度异常、fixed buffer 注册失败、O_DIRECT 对齐错误，以及应用使用的
io_uring feature 与当前内核不兼容。

诊断阶段只做信息收集和证据分析，不执行修复、重启服务、删除文件、修改
sysctl、调整 ulimit 或触发压力测试。需要复现、故障注入、资源限制调整或清理
动作时，应把这些动作作为测试步骤单独列出并等待用户确认。

## 使用时机

当用户描述或日志中出现以下线索时使用本 skill：

- `io_uring_setup`、`io_uring_enter`、`io_uring_register` 返回 `EPERM`、
  `ENOMEM`、`EAGAIN`、`EINVAL`、`EBUSY`、`EFAULT` 或 `ENOSYS`。
- 应用日志提到 submission queue full、completion queue overflow、CQE
  missing、completion latency、request timeout、short read/write。
- 进程中存在 `iou-wrk-*`、`iou-sqp-*`、`io_wq_worker`、`io_uring-sq` 等线程，
  且线程数、阻塞状态或 CPU 使用异常。
- 使用 `IORING_SETUP_SQPOLL`、fixed files、fixed buffers、registered buffers、
  `IOSQE_FIXED_FILE`、`IORING_OP_*` 新操作码后异常。
- 使用 `O_DIRECT` 时出现 `EINVAL`、短 I/O、对齐错误或文件系统/块设备路径不一致。
- 旧内核或发行版内核 backport 环境下，应用开启新 io_uring feature 后失败。

## 输入要求

### 必需输入

- 故障时间或复现时间窗口。
- 受影响进程、PID、服务名、容器名或测试程序路径。
- 用户可提供的错误日志、命令输出或复现描述。

### 推荐输入

- 系统版本和内核版本：`cat /etc/os-release`、`uname -a`。
- 进程资源限制：`ulimit -a`、`/proc/<pid>/limits`、`/proc/<pid>/status`。
- 进程线程状态：`ps -eLf`、`top -H`、`/proc/<pid>/task/*/status`。
- 内核日志：`dmesg -T`、`journalctl -k`。
- 调用轨迹：`strace -f -e trace=io_uring_setup,io_uring_enter,io_uring_register`。
- 可选源码、复现程序、perf/ftrace/bpftrace 输出或 vmcore。

### 输入格式示例

```json
{
  "session_id": "diag-io-uring-001",
  "target": "linux-process",
  "parameters": {
    "pid": 12345,
    "failure_window": "2026-06-02 10:00:00 ~ 2026-06-02 10:30:00",
    "symptom": "io_uring_register fixed buffers returns -ENOMEM",
    "log_path": "/tmp/io_uring_case/app.log"
  }
}
```

## 执行步骤

### Step 1: 建立基线和证据目录

优先执行只读基线采集：

```bash
bash scripts/collect_io_uring_context.sh -p <pid> -o /tmp/io_uring_diag_<case>
```

记录以下信息：

- 内核版本、发行版版本、架构、CPU 和内存概要。
- 目标进程状态、线程、limits、FD、maps、cgroup。
- io_uring 相关日志和 syscall 轨迹线索。
- 当前可用命令、权限限制和无法读取的证据。

没有 PID 时仍可执行系统级采集：

```bash
bash scripts/collect_io_uring_context.sh -o /tmp/io_uring_diag_<case>
```

### Step 2: 按症状选择分支

使用以下分支脚本进行只读分析：

```bash
bash scripts/diagnose_io_uring_limits.sh -p <pid> -l <log_file>
bash scripts/diagnose_io_uring_rings.sh -p <pid> -l <log_file>
bash scripts/diagnose_io_uring_workers.sh -p <pid>
bash scripts/diagnose_io_uring_compat.sh -l <log_file>
```

分支推荐表：

| 线索 | 优先分支 | 目标结论 |
| --- | --- | --- |
| `io_uring_setup`/`io_uring_register` 返回 `ENOMEM`、`EPERM`、`EAGAIN` | limits | memlock、nofile、nproc、cgroup 或权限限制 |
| `SQ full`、`CQ overflow`、`CQE missing`、提交失败或完成延迟 | rings | queue 深度、消费速度、backlog 和 timeout |
| `iou-wrk` 线程很多、线程 D 状态、CPU 高或 I/O 阻塞 | workers | io-wq worker 耗尽、阻塞 I/O、调度或 cgroup 限制 |
| `IORING_SETUP_SQPOLL`、`iou-sqp`、CPU 绑定或权限异常 | workers | SQPOLL 权限、CPU 亲和性、调度和 busy polling |
| fixed buffer/file 注册失败、`IOSQE_FIXED_FILE` 异常 | limits + compat | memlock、生命周期错误、注册表耗尽或 feature 不支持 |
| `O_DIRECT` 返回 `EINVAL` 或短 I/O | rings + references | 地址、长度、offset、文件系统或块设备对齐问题 |
| `ENOSYS`、`EINVAL` 出现在新 opcode 或新 flag | compat | 当前内核缺少 feature 或 backport 差异 |

### Step 3: 构建证据链

每个候选根因都要记录：

- 现象：用户看到的错误码、延迟、超时、吞吐下降或线程异常。
- 直接证据：日志、strace、进程状态、limits、线程状态、内核版本。
- 机制解释：io_uring 哪个阶段触发了该现象。
- 排除项：哪些常见原因已被当前证据排除。
- 置信度：`high`、`medium`、`low`，并说明缺失证据。

### Step 4: 需要源码或内核语义时交叉验证

如果用户提供应用源码、复现程序或内核源码，按以下路径交叉验证：

1. 定位应用创建 ring、提交 SQE、消费 CQE、注册 buffer/file 的代码路径。
2. 对照 strace 参数和错误码，确认失败发生在 setup、submit、complete 还是 register。
3. 对照当前内核版本和 feature 表，判断是参数错误、资源不足还是 feature 不支持。
4. 若涉及 `O_DIRECT`，核对 buffer 地址、长度、file offset 和文件系统约束。
5. 若涉及 worker/SQPOLL，核对线程状态、CPU affinity、cgroup、调度策略和 I/O 后端。

### Step 5: 输出诊断报告

报告应包含：

- 故障分类：资源限制、ring 容量、worker/SQPOLL、fixed buffer、O_DIRECT、内核兼容性或待补证据。
- 根因结论和置信度。
- 证据链和排除项。
- 影响范围和风险。
- 只读建议、复现建议和需要用户审批的操作边界。

## 输出格式

### 成功输出

```json
{
  "status": "success",
  "session_id": "diag-io-uring-001",
  "results": {
    "classification": "resource-limit",
    "root_cause": "fixed buffer registration is constrained by RLIMIT_MEMLOCK",
    "confidence": "high",
    "evidence": [
      "io_uring_register returned ENOMEM",
      "/proc/<pid>/limits shows Max locked memory = 64 KB",
      "application attempts to register 4 MB buffers"
    ],
    "excluded_causes": [
      "kernel supports io_uring",
      "no CQ overflow evidence in logs"
    ],
    "recommendations": [
      "Reproduce with higher memlock limit in a test environment",
      "Reduce registered buffer size or avoid fixed buffers for this workload"
    ]
  }
}
```

### 部分输出

```json
{
  "status": "partial",
  "session_id": "diag-io-uring-001",
  "results": {
    "classification": "pending-evidence",
    "confidence": "low",
    "available_evidence": [
      "kernel version and process limits collected"
    ],
    "missing_evidence": [
      "strace output for io_uring syscalls",
      "application log around failure time"
    ],
    "next_checks": [
      "collect io_uring syscall errors during reproduction",
      "confirm ring depth and CQ consumption logic"
    ]
  }
}
```

### 错误输出

```json
{
  "status": "error",
  "session_id": "diag-io-uring-001",
  "error_code": "VALIDATION_PARAMETER_INVALID",
  "error_message": "pid is not a running process",
  "suggestions": [
    "provide a running PID",
    "provide offline logs with -l <log_file> for partial analysis"
  ]
}
```

## 示例

### fixed buffer 注册失败

```bash
bash scripts/collect_io_uring_context.sh -p 12345 -o /tmp/iouring_case
bash scripts/diagnose_io_uring_limits.sh -p 12345 -l /tmp/iouring_case/kernel_io_uring_logs.txt
```

预期关注：

- `/proc/12345/limits` 中 `Max locked memory`。
- `io_uring_register` 错误码。
- 应用注册 buffer 的总大小。

### 完成事件延迟或丢失

```bash
bash scripts/diagnose_io_uring_rings.sh -p 12345 -l /tmp/app.log
bash scripts/diagnose_io_uring_workers.sh -p 12345
```

预期关注：

- ring depth 是否过小。
- CQ 消费线程是否阻塞。
- `iou-wrk` 线程是否大量 D 状态或集中在同一 I/O 后端。

### 内核 feature 兼容性

```bash
bash scripts/diagnose_io_uring_compat.sh -l /tmp/io_uring_strace.log
```

预期关注：

- 当前内核版本。
- `io_uring_setup` 参数、flags 和返回错误码。
- `io_uring_register` opcode 或 `IORING_OP_*` 是否可能超出当前内核支持范围。

## 注意事项

### 安全边界

- 诊断脚本默认只读。
- 不自动修改 `ulimit`、sysctl、systemd unit、cgroup、CPU affinity 或文件系统配置。
- 不自动 kill 进程、不删除业务文件、不触发压力测试。
- 故障注入材料只用于测试环境；运行前必须确认环境可清理。

### 性能边界

- `strace`、perf、ftrace、bpftrace 可能影响目标进程性能；对生产环境需先说明风险。
- 长时间采样需要用户确认采样时长和影响窗口。
- 在高负载机器上读取大量 `/proc/<pid>/task/*` 信息可能产生额外开销，脚本默认限制输出规模。

### 降级策略

- 无 PID：只做系统级和日志级分析。
- 无 root：跳过不可读的内核日志、线程栈、perf/ftrace，并标注权限缺口。
- 无 strace/perf/bpftrace：使用应用日志、`/proc`、`ps` 和内核版本继续分析。
- 无复现：基于离线日志形成候选根因，并明确置信度边界。
