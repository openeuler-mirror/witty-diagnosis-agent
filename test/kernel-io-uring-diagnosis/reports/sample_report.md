# 🔴 故障诊断报告

> **报告编号**：SAMPLE-IOURING-MEMLOCK-001
> **故障级别**：P3（测试环境资源限制）
> **报告时间**：YYYY-MM-DD HH:MM:SS
> **当前状态**：🔴 处理中（样例未执行修复）

---

## 一、故障概览

| 项目 | 内容 |
| --- | --- |
| 故障标题 | io_uring fixed buffer 注册失败，疑似 RLIMIT_MEMLOCK 不足 |
| 影响范围 | `io_uring_fault_probe` 的 memlock 场景 |
| 故障时段 | 测试执行窗口 |
| 根本原因 | 测试进程 locked memory limit 低于 fixed buffer 注册需要锁定的页面大小 |
| 是否恢复 | ❌ 未恢复，样例仅展示诊断报告结构 |
| 根因置信度 | 🟢 高置信；同时具备运行日志和 limits 证据时成立 |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
run.sh run memlock
  -> 子 shell 降低 locked memory limit
  -> io_uring_setup 成功
  -> io_uring_register(IORING_REGISTER_BUFFERS) 尝试注册 4 MiB fixed buffer
  -> 内核检查 RLIMIT_MEMLOCK 失败
  -> 返回 ENOMEM
```

### 故障因果链

```text
ulimit -l=64
  -> 可锁定内存约 64 KiB
  -> fixed buffer 注册请求 4 MiB
  -> 请求量超过 locked memory 上限
  -> io_uring_register_buffers 返回 ENOMEM
```

---

## 三、排查过程

### 3.1 初始现象

测试程序创建 io_uring 实例后，在低 locked-memory limit 的子 shell 中尝试注册
4 MiB fixed buffer，`io_uring_register` 返回内存不足类错误。

### 3.2 关键证据

| 证据 | 来源 | 解释 |
| --- | --- | --- |
| `ulimit -l=64` | `run.sh run memlock` 输出 | 测试进程的 locked memory limit 被约束 |
| `io_uring_register_buffers` 返回 errno | probe 输出 | fixed buffer 注册进入内核资源校验 |
| `registered_buffer_bytes=4194304` | probe 输出 | 注册 buffer 大小高于低 memlock 限制 |

### 3.3 替代假设排除

| 替代假设 | 排除依据 |
| --- | --- |
| ring 创建失败 | `io_uring_setup` 成功 |
| CQ overflow | 本场景未提交 SQE |
| O_DIRECT 对齐问题 | 本场景不使用 `O_DIRECT` 文件操作 |

### 3.4 io_uring 领域深度分析

故障发生在 `io_uring_register(IORING_REGISTER_BUFFERS)` 阶段，而不是
setup、submit、complete、worker、SQPOLL 或 Direct I/O 阶段。fixed buffer
注册需要 pin 用户态页面，因此必须同时检查注册字节数、页数和进程
`RLIMIT_MEMLOCK`。

---

## 四、修复方案

| 类型 | 建议 |
| --- | --- |
| 只读建议 | 确认 `/proc/<pid>/limits` 或 shell `ulimit -l`，对比注册 buffer 总字节数和 locked-memory limit。 |
| 需审批操作 | 使用更高 locked-memory limit 复跑同一 probe，或降低注册 buffer 大小确认注册是否成功。 |
| 风险 | 修改 limits、systemd unit 或容器资源限制会改变运行环境，需单独审批。 |

---

## 五、验证建议

```bash
./run.sh build
./run.sh run memlock
../../skills/kernel-io-uring-diagnosis/scripts/diagnose_io_uring_limits.sh -l ./out/memlock.log
./run.sh clean
```

通过条件：提高 memlock 后复跑，`io_uring_register_buffers` 不再返回 `ENOMEM`。

---

## 诊断质量自查

- [ ] 运行证据与内核语义均有对应来源；缺失证据已标注置信度影响。
- [ ] 结论没有越过当前证据强度。
- [ ] 修复建议与已执行动作已明确区分。
- [ ] HTML 报告应从同名 Markdown 生成。
