# io_uring memlock 样例诊断报告

## 故障概要

- 案例编号：sample-memlock-fixed-buffer
- 主机：openEuler 测试虚拟机
- 内核版本：由 `uname -a` 采集
- 目标进程/PID：io_uring fault probe
- 故障时间窗口：测试执行窗口
- 故障分类：资源限制
- 置信度：样例为中；同时具备运行日志和 limits 证据时可提升为高

## 用户可见现象

测试程序创建 io_uring 实例后，在低 locked-memory limit 的子 shell 中尝试注册 4 MiB
fixed buffer，`io_uring_register` 返回内存不足类错误。

## 证据链

| 证据 | 来源 | 解释 |
| --- | --- | --- |
| `ulimit -l=64` | `run.sh run memlock` 输出 | 测试进程的 locked memory limit 被约束 |
| `io_uring_register_buffers` 返回 errno | probe 输出 | fixed buffer 注册进入内核资源校验 |
| `registered_buffer_bytes=4194304` | probe 输出 | 注册 buffer 大小高于低 memlock 限制 |

## 根因分析

预期根因是 `RLIMIT_MEMLOCK` 限制 fixed buffer 注册。失败发生在
`io_uring_register` 阶段，而不是 ring setup 或 CQ 消费阶段。

## 排除的替代假设

- `io_uring_setup` 成功时，可排除 ring 创建失败。
- 本场景未提交 SQE，可排除 CQ overflow。
- 本场景不使用 `O_DIRECT` 文件操作，可排除 Direct I/O 对齐问题。

## 修复建议

只读建议：

- 确认故障进程运行时的 `/proc/<pid>/limits` 或 shell `ulimit -l`。
- 对比注册 buffer 总字节数和 locked-memory limit。
- 若 memlock 不是限制项，继续检查 cgroup memory 和系统内存压力。

需要在测试环境审批后执行的操作：

- 使用更高 locked-memory limit 复跑同一 probe。
- 降低注册 buffer 大小，确认注册是否成功。

## 已执行命令

```bash
./run.sh build
./run.sh run memlock
../../skills/kernel-io-uring-diagnosis/scripts/diagnose_io_uring_limits.sh -l ./out/memlock.log
```

## 清理命令

```bash
./run.sh clean
```
