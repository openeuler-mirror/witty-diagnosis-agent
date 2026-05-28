# strace-syscall-diagnosis 故障注入测试报告

> 测试时间: 2026-05-28
> 测试目标: 验证 witty agent (strace-syscall-diagnosis skill) 对 7 个故障分支的诊断准确性

---

## 目录结构

```
test/strace-syscall/
├── test_summary.md                  # 本文件 — 测试总览
├── reports/                         # 诊断报告（保留 Baize 原始文件名）
│   ├── 容器内进程四类系统调用异常综合分析_branch_a_errors_20260528_baize_report.{md,html}
│   ├── 多线程futex锁竞争分析_20260528_195404_report.{md,html}
│   ├── 高频内存抖动诊断_C1_20260528_report.{md,html}
│   ├── FD泄漏分析_branch_d_leak_20260528_report.{md,html}
│   ├── ECONNREFUSED-本地端口连接失败循环_20260528_report.{md,html}
│   ├── EINTR信号中断故障_F1_eintr_20260528_report.{md,html}
│   └── 进程创建风暴fork_storm_20260528_report.{md,html}
└── fault-injection/                 # 故障注入工具集
    ├── Dockerfile                   # 容器镜像构建
    ├── README.md                    # 使用说明
    ├── inject_loop.sh               # 持续循环注入（供 agent attach）
    ├── cleanup_loop.sh              # 环境清理
    ├── lib/common.sh                # 共享函数库
    └── src/                         # 7 个 C 故障注入源码
        ├── branch_a_errors.c
        ├── branch_b_slow.c
        ├── branch_c_library.c
        ├── branch_d_leak.c
        ├── branch_e_network.c
        ├── branch_f_signal.c
        └── branch_g_lifecycle.c
```

---

## 测试结果

| 分支 | 子模式 | 注入故障 | 诊断结论 | 匹配 |
|:----:|--------|---------|---------|:----:|
| **A** | all | EACCES/EPERM + ENOENT + EAGAIN + ENOMEM | 识别4种异常，EPERM→缺少CAP_SYS_NICE，ENOMEM→RLIMIT_AS 32MB，EAGAIN→忙等 | ✅ |
| **B** | futex | 4线程mutex竞争，50ms临界区 | futex(FUTEX_WAIT)>50ms，惊群效应，Amdahl定律量化 | ✅ |
| **C** | mallocfreq | 500次/轮高频malloc/free | memory churn内存抖动 | ✅ |
| **D** | fd_leak | open/dup不close，每轮+3FD | FD线性增长，缺少close()调用 | ✅ |
| **E** | econnrefused | connect未监听端口 | ECONNREFUSED模式，目标无服务监听 | ✅ |
| **F** | eintr | setitimer(100ms)+NO SA_RESTART | EINTR信号中断syscall，SA_RESTART缺失 | ✅ |
| **G** | fork_storm | 快速fork(50ms间隔) | fork/clone高频调用，进程创建风暴 | ✅ |

**总体匹配率: 7/7 (100%)**

---

## 测试方法

1. **故障注入**: 使用 `inject_loop.sh <分支> <模式>` 启动持续循环的故障容器（PID=1 为故障进程本身）
2. **PID 提取**: 获取容器进程在宿主机上的 PID
3. **诊断流程**: 全链路 witty agent (Fuxi-Sub → Dayu/Kuafu → Baize)
4. **结论验证**: 对比诊断结论与注入故障参数
5. **环境清理**: `cleanup_loop.sh <分支> <模式>` 销毁容器

---

## 故障注入设计

每个故障分支的 C 程序通过直接调用 Linux syscall API 产生真实的系统调用异常:

| 分支 | 实现手法 | 真实性 |
|:----:|---------|:------:|
| A | open(/etc/shadow)/sched_setscheduler/pipe非阻塞read/mmap超限 | 内核真实返回 errno |
| B | 4×pthread mutex竞争，50ms忙等临界区 | 内核真实 futex 调度 |
| C | 循环 malloc/free 500次/轮 | glibc 真实内存操作 |
| D | open()后不close()，每轮+3FD | 内核 FD 表真实增长 |
| E | connect()到无服务端口 | 内核 TCP 栈真实返回 ECONNREFUSED |
| F | setitimer+NO SA_RESTART，中断 blocking read | 内核信号机制真实中断 |
| G | fork()循环创建子进程 | 内核真实进程创建 |

---

## 已知限制

- 宿主机 `kernel.yama.ptrace_scope=1` 阻止 strace attach 到容器 PID 1
- Dayu/Kuafu 的在线 strace 采集在 ptrace 受限时降级为日志和 /proc 分析
- EACCES 子模式在 root 容器中表现为 open 成功（root 可访问一切文件）
