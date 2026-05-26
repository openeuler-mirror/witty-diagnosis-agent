# FD 泄漏故障注入测试套件

本目录提供对 [fd-leak-diagnosis](../../skills/fd-leak-diagnosis/SKILL.md) Skill 覆盖的 8 种 FD 泄漏故障场景的注入与验证脚本。

## 故障场景

| # | 目录/脚本 | 故障类型 | 对应诊断分支 |
|---|----------|---------|-------------|
| 1 | `inject_system_fd.sh` | 系统级 FD 耗尽 | `branch_A_system_fd.sh` |
| 2 | `inject_process_fd.sh` | 进程级 Regular File FD 泄漏 | `branch_B_process_fd.sh` |
| 3 | `inject_close_wait.sh` | CLOSE_WAIT Socket 泄漏 | `branch_C_close_wait.sh` |
| 4 | `inject_epoll.sh` | epoll FD 泄漏 | `branch_D_epoll.sh` |
| 5 | `inject_inotify.sh` | inotify watch 泄漏 | `branch_E_inotify.sh` |
| 6 | — (F: syscall FD) | 系统调用级 FD 泄漏 | `branch_F_syscall.sh` |
| 7 | `inject_deleted_file.sh` | 已删除文件 FD 泄漏 | `branch_G_deleted_file.sh` |
| 8 | `inject_mixed.sh` | 混合 FD 泄漏 (多类型叠加) | `branch_H_mixed.sh` |

## 前置条件

- Linux 环境 (测试基于 WSL2 Ubuntu 22.04)
- 预编译的泄漏二进制位于 `~/fd-leak-test-lab/bin/` (需自行编译)
- SSH 服务运行中 (供全链路诊断连接)

## 快速使用

```bash
# 注入故障
bash inject_system_fd.sh run

# 查看状态
bash inject_system_fd.sh status

# 停止注入
bash inject_system_fd.sh stop

# 一键清理所有泄漏
bash cleanup.sh
```

Windows 用户可使用 PowerShell 管理器:

```powershell
.\run_fault.ps1 system_fd run
.\run_fault.ps1 cleanup
```

## 注入 → 诊断流程

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ 1. 运行注入  │    │ 2. 执行诊断  │    │ 3. 验证结果  │
│ bash inject │    │ SSH 进目标   │    │ 检查诊断报告 │
│ _<fault>.sh │    │ 运行分支脚本 │    │ 确认根因     │
│    run      │    │ 查看结果     │    │ 清除泄漏     │
└──────────────┘    └──────────────┘    └──────────────┘
```

## 脚本说明

每个注入脚本支持 `run` / `status` / `stop` 三个动作:

- **run**: 启动泄漏进程，输出当前状态和用于 Xuanyuan 的 Prompt
- **status**: 检查泄漏进程是否存活及当前 FD 状态
- **stop**: 停止泄漏进程

## 泄漏二进制编译

泄漏工具源代码位于 `~/fd-leak-test-lab/src/`，编译方式:

```bash
cd ~/fd-leak-test-lab/src
gcc -o ../bin/leak_system_fd leak_system_fd.c
gcc -o ../bin/leak_process_fd leak_process_fd.c
gcc -o ../bin/leak_close_wait leak_close_wait.c -lpthread
gcc -o ../bin/leak_epoll leak_epoll.c
gcc -o ../bin/leak_inotify leak_inotify.c
gcc -o ../bin/leak_deleted_file leak_deleted_file.c
gcc -o ../bin/leak_mixed leak_mixed.c -lpthread
```

## 清理全部

```bash
bash cleanup.sh
```
