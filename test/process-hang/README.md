# process-hang-diagnosis 故障注入测试框架

用于对 **process-hang-diagnosis** Skill 的 7 个故障分支进行自动化故障注入、诊断验证和根因分析评测。

## 目录结构

```
test/process-hang/
├── run_all_tests.sh              # 批量运行入口
├── README.md                     # 本文件
├── common/
│   └── Dockerfile                # 基础镜像（Ubuntu 22.04 + gcc/gdb/strace/NFS 服务端...）
├── branches/                     # 7 个故障分支
│   ├── A_futex_wait/             # futex 锁竞争
│   │   ├── inject.sh             #   注入故障
│   │   ├── cleanup.sh            #   清理环境
│   │   └── src/futex_contention.c
│   ├── B_deadlock/               # ABBA 死锁
│   │   ├── inject.sh
│   │   ├── cleanup.sh
│   │   └── src/abba_deadlock.c
│   ├── C_filelock/               # 文件锁竞争
│   │   ├── inject.sh
│   │   ├── cleanup.sh
│   │   └── src/filelock_contention.c
│   ├── D_pipe_socket/            # 管道阻塞
│   │   ├── inject.sh
│   │   ├── cleanup.sh
│   │   └── src/pipe_block.c
│   ├── E_signal_stop/            # 信号停止
│   │   ├── inject.sh
│   │   └── cleanup.sh
│   ├── F_d_state/                # D 状态阻塞（NFS hard mount）
│   │   ├── inject.sh
│   │   └── cleanup.sh
│   └── G_user_loop/              # 用户态死循环
│       ├── inject.sh
│       └── cleanup.sh
├── diagnostics/
│   └── container_diag.sh         # 容器内诊断执行包装器（解决 /proc 不可见问题）
└── reports/
    ├── md/                       # 诊断报告（Markdown）
    └── html/                     # 诊断报告（HTML 可视化）
```

## 快速开始

### 环境要求

- Docker（支持 `--privileged` 模式）
- 基础镜像（首次运行自动构建）

### 一键运行全部分支

```bash
cd test/process-hang
bash run_all_tests.sh
```

### 运行单个分支

```bash
# 指定分支名即可
bash run_all_tests.sh G_user_loop
bash run_all_tests.sh A_futex_wait
bash run_all_tests.sh F_d_state
```

### 手动注入和清理

```bash
# 注入故障
cd branches/G_user_loop
bash inject.sh              # 默认 CPU 100% 模式

# 验证故障容器运行
docker ps | grep process-hang

# 清理
bash cleanup.sh
```

## 故障分支一览

| 分支 | 故障类型 | 诊断特征 |
|:----|---------|---------|
| **A** futex 锁竞争 | 8 线程竞争同一把 mutex，持锁者 sleep | `wchan=futex_wait_queue`, 多线程等同一锁 |
| **B** ABBA 死锁 | 双线程反向加锁形成死锁环 | `wchan=futex_wait_queue`, GDB 显示 ABBA 环 |
| **C** 文件锁竞争 | 父进程持写锁，子进程阻塞等读锁 | `wchan=fcntl_setlk`, `/proc/locks` 显示等待链 |
| **D** 管道阻塞 | 子进程从空管道 read() 阻塞 | `wchan=pipe_read`, fd 指向 `pipe:[inode]` |
| **E** 信号停止 | 子进程被 SIGSTOP 停止 | `State=T`, `wchan=do_signal_stop` |
| **F** D 状态阻塞 | NFS hard mount 服务端断开 | `State=D`, `wchan=xprt_disconnect_done` |
| **G** 用户态死循环 | CPU 100% 死循环 | `State=R`, `wchan=0`, `CPU=100%` |

## 全链路诊断流程

### 方式一：通过 container_diag.sh（推荐）

```bash
# 1. 注入故障
bash branches/G_user_loop/inject.sh

# 2. 用包装器在容器内执行基线诊断
bash diagnostics/container_diag.sh process-hang-branch-g \
  ../../scripts/01_baseline_info.sh 1

# 3. 用包装器执行分支诊断
bash diagnostics/container_diag.sh process-hang-branch-g \
  ../../scripts/branch_G_user_loop.sh 1

# 4. 将诊断结果提交给 Baize 进行根因分析
# ...

# 5. 清理
bash branches/G_user_loop/cleanup.sh
```

### 方式二：通过 CMD_PREFIX 环境变量

```bash
CMD_PREFIX="docker exec process-hang-branch-g" \
  bash ../../scripts/01_baseline_info.sh 1
```

## 诊断评测流程

```
故障注入 → 诊断数据采集 → Baize 根因分析 → 生成 RCA 报告 → 可视化(HTML)
    |            |               |               |              |
 inject.sh  container_diag.sh   task(baize)  report_md.md  report.html
```

每次评测完成后，诊断报告（MD + HTML）会写入 `reports/` 目录，可对照检查诊断结论是否与注入故障类型一致。

## 故障特征速查

```
State   wchan                      → 分支
──────  ─────────────────────────  ──────────────
R       0                          → G_用户态死循环
T       do_signal_stop             → E_信号停止
S       futex_wait_queue           → A_futex锁竞争/B_ABBA死锁
S       fcntl_setlk                → C_文件锁竞争
S       pipe_read                  → D_管道阻塞
D       __probestub_xprt_*         → F_D状态阻塞(NFS)
```

## 注意事项

1. **Branch F（D 状态）**：基于 NFS hard mount，需要约 15 秒等待 D 状态建立
2. **Branch E（信号停止）**：SIGSTOP 发给子进程而非 PID 1，避免容器管理异常
3. **基础镜像**：首次运行会自动构建，内含 gcc/gdb/strace/FUSE/NFS 等服务端工具
4. **资源清理**：所有 `cleanup.sh` 使用 `docker kill` 强制停止容器，确保不残留
