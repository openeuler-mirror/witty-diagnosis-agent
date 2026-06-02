# kernel-io-uring-diagnosis 测试套件

本目录提供 `kernel-io-uring-diagnosis` skill 的可复现测试材料，用于在 Linux/openEuler
测试主机上验证 io_uring 诊断分支。测试会调整子 shell 的进程资源限制、创建临时文件、
启动短生命周期测试程序；所有产物默认位于本目录的 `out/` 下。

## 目录结构

```text
test/kernel-io-uring-diagnosis/
├── README.md
├── cleanup.sh
├── run.sh
├── fault-injection/
│   └── src/
│       └── io_uring_fault_probe.c
└── reports/
    └── sample_report.md
```

## 前置条件

- Linux 内核支持 io_uring。
- 已安装 `gcc`。
- 系统头文件包含 `linux/io_uring.h`。
- 可选：安装 `strace`，用于补充 syscall 证据。

测试程序直接使用 raw syscall，不依赖 liburing。

## 覆盖场景

| 场景 | 命令 | 预期信号 |
| --- | --- | --- |
| 基线探测 | `./run.sh run baseline` | 内核支持 io_uring 时 setup 成功 |
| memlock/fixed buffer | `./run.sh run memlock` | 低 `ulimit -l` 与 fixed buffer 注册失败证据 |
| ring 压力 | `./run.sh run ring` | queue depth 和 enter/submit 相关证据 |
| SQPOLL | `./run.sh run sqpoll` | SQPOLL setup 成功或返回 errno |
| O_DIRECT 对齐 | `./run.sh run odirect` | 支持 Direct I/O 的文件系统上未对齐写入返回 `EINVAL` |
| feature 兼容 | `./run.sh run compat` | 内核、header 和 probe 证据 |

## 使用流程

```bash
cd test/kernel-io-uring-diagnosis

# 构建 raw syscall 测试程序
./run.sh build

# 运行一个场景并保存日志
./run.sh run memlock

# 查看生成的日志
./run.sh status

# 使用 skill 分支脚本分析采集日志
../../skills/kernel-io-uring-diagnosis/scripts/diagnose_io_uring_limits.sh \
  -l ./out/memlock.log
../../skills/kernel-io-uring-diagnosis/scripts/diagnose_io_uring_compat.sh \
  -l ./out/memlock.log

# 清理测试产物
./run.sh clean
```

## 安全边界

- 测试程序只在 `test/kernel-io-uring-diagnosis/out/` 下生成产物。
- `memlock` 场景只在子 shell 中降低 `ulimit -l`。
- `odirect` 场景写入临时文件，清理流程会删除测试产物。
- 测试不修改 sysctl、systemd、cgroup 或系统服务配置。

## 预期诊断映射

- `memlock`：fixed buffer 注册失败且日志包含有限 locked-memory limit 时，skill 应分类为资源限制。
- `ring`：skill 应识别 ring 容量和完成事件流相关证据；若 probe 未复现真实 CQ overflow，
  应要求补充 queue depth 和消费线程证据。
- `sqpoll`：根据 setup errno 和线程状态，分类为 worker/SQPOLL 或兼容性/权限问题。
- `odirect`：`O_DIRECT` 场景出现 `EINVAL` 时，应分类为 Direct I/O 对齐候选，并要求补充
  buffer 地址、长度和 offset 证据。
- `compat`：只有 runtime syscall errno 和 feature 参数完整时，才能给出高置信度兼容性结论。
