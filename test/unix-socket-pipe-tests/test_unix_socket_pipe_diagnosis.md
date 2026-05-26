# Unix Socket & Pipe 故障注入测试套件

本目录提供对 Unix Socket 和 Pipe 相关故障场景的注入与验证脚本。

## 故障场景

| # | 脚本 | 故障类型 | 对应诊断分支 |
|---|------|---------|-------------|
| A | `inject_uds_backlog.sh` | UDS backlog 满 | `branch_A_uds_backlog.sh` |
| B | `inject_abstract_conflict.sh` | Abstract 地址冲突 | `branch_B_abstract_conflict.sh` |
| C | `inject_passcred.sh` | PASSCRED 传输失败 | `branch_C_passcred.sh` |
| D | `inject_socket_perms.sh` | socket 权限错误 | `branch_D_socket_perms.sh` |
| E | `inject_pipe_buf.sh` | pipe buffer 满 | `branch_E_pipe_buf.sh` |
| F | `inject_sigpipe.sh` | SIGPIPE 未处理退出 | `branch_F_sigpipe.sh` |
| G | `inject_socketpair.sh` | socketpair 泄漏 | `branch_G_socketpair.sh` |

## 前置条件

- Linux 环境 (测试基于 WSL2 Ubuntu 22.04)
- 预编译的泄漏二进制位于 `~/unix-pipe-test-lab/bin/` (需自行编译)
- SSH 服务运行中 (供全链路诊断连接)

## 快速使用

```bash
# 注入故障
bash scripts/inject_uds_backlog.sh run

# 查看状态
bash scripts/inject_uds_backlog.sh status

# 停止注入
bash scripts/inject_uds_backlog.sh stop

# 一键清理所有泄漏
bash scripts/cleanup.sh
```

Windows 用户可使用 PowerShell 管理器:

```powershell
.\run_fault.ps1 start A
.\run_fault.ps1 status A
.\run_fault.ps1 stop all
```

## 注入 → 诊断流程

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ 1. 运行注入  │    │ 2. 执行诊断  │    │ 3. 验证结果  │
│ bash inject  │    │ SSH 进目标   │    │ 检查诊断报告 │
│ _<fault>.sh  │    │ 运行分支脚本 │    │ 确认根因     │
│    run       │    │ 查看结果     │    │ 清除泄漏     │
└──────────────┘    └──────────────┘    └──────────────┘
```

## 脚本说明

每个注入脚本支持 `run` / `status` / `stop` 三个动作:

- **run**: 启动泄漏进程，输出当前状态和用于 Xuanyuan 的 Prompt
- **status**: 检查泄漏进程是否存活及当前状态
- **stop**: 停止泄漏进程

## 泄漏二进制编译

泄漏工具源代码位于 `~/unix-pipe-test-lab/src/`，编译方式:

```bash
cd ~/unix-pipe-test-lab/src
gcc -o ../bin/uds_backlog uds_backlog.c
gcc -o ../bin/abstract_conflict abstract_conflict.c
gcc -o ../bin/passcred_fail passcred_fail.c
gcc -o ../bin/socket_perms socket_perms.c
gcc -o ../bin/pipe_buf_full pipe_buf_full.c
gcc -o ../bin/sigpipe_unhandled sigpipe_unhandled.c
gcc -o ../bin/socketpair_leak socketpair_leak.c
```

## 清理全部

```bash
bash scripts/cleanup.sh
```

## 测试场景总览表

| 故障 | 注入脚本 | 诊断分支 | 泄漏程序 | 参数 |
|------|---------|---------|---------|------|
| A: UDS backlog 满 | `inject_uds_backlog.sh` | `branch_A` | `uds_backlog` | `[backlog] [clients]` |
| B: Abstract 地址冲突 | `inject_abstract_conflict.sh` | `branch_B` | `abstract_conflict` | `[addr]` |
| C: PASSCRED 失败 | `inject_passcred.sh` | `branch_C` | `passcred_fail` | — |
| D: socket 权限错误 | `inject_socket_perms.sh` | `branch_D` | `socket_perms` | `[perm]` |
| E: pipe buffer 满 | `inject_pipe_buf.sh` | `branch_E` | `pipe_buf_full` | `[size_kb] [speed_kbps]` |
| F: SIGPIPE 退出 | `inject_sigpipe.sh` | `branch_F` | `sigpipe_unhandled` | — |
| G: socketpair 泄漏 | `inject_socketpair.sh` | `branch_G` | `socketpair_leak` | `[pairs] [rounds]` |

## 各场景测试步骤

### 场景 A: UDS backlog 满

**注入:**
```bash
bash scripts/inject_uds_backlog.sh run 2 10
```

**验证 (预期输出):**
```bash
ss -xl | grep uds_test_A
# 应有 10 个 CLOSE_WAIT 或 ESTAB 状态的连接
```

**诊断流程:**
运行诊断脚本 `scripts/branch_A.sh`。

**清理:**
```bash
bash scripts/inject_uds_backlog.sh stop
```

---

### 场景 B: Abstract 地址冲突

**注入:**
```bash
bash scripts/inject_abstract_conflict.sh run @uds_test
```

**验证 (预期输出):**
```bash
ss -xl | grep @uds_test
# 应显示有进程已绑定 @uds_test，第二个进程应报 EADDRINUSE
```

**诊断流程:**
运行诊断脚本 `scripts/branch_B.sh`。

**清理:**
```bash
bash scripts/inject_abstract_conflict.sh stop
```

---

### 场景 C: PASSCRED 失败

**注入:**
```bash
bash scripts/inject_passcred.sh run
```

**验证 (预期输出):**
```bash
ss -xlp | grep passcred
# 应显示 passcred_fail 进程监听 unix socket
# 测试客户端连接后 sendmsg() 返回 ENODATA
```

**诊断流程:**
运行诊断脚本 `scripts/branch_C.sh`。

**清理:**
```bash
bash scripts/inject_passcred.sh stop
```

---

### 场景 D: socket 权限错误

**注入:**
```bash
bash scripts/inject_socket_perms.sh run 0000
```

**验证 (预期输出):**
```bash
ls -la /tmp/uds_test_perms
# 权限应为 ----------
# 客户端连接应返回 EACCES
```

**诊断流程:**
运行诊断脚本 `scripts/branch_D.sh`。

**清理:**
```bash
bash scripts/inject_socket_perms.sh stop
```

---

### 场景 E: pipe buffer 满

**注入:**
```bash
bash scripts/inject_pipe_buf.sh run 64 1024
```

**验证 (预期输出):**
```bash
# 查看 pipe 缓冲区状态
cat /proc/sys/fs/pipe-max-size
# 写入测试应出现阻塞或 EAGAIN
```

**诊断流程:**
运行诊断脚本 `scripts/branch_E.sh`。

**清理:**
```bash
bash scripts/inject_pipe_buf.sh stop
```

---

### 场景 F: SIGPIPE 退出

**注入:**
```bash
bash scripts/inject_sigpipe.sh run
```

**验证 (预期输出):**
```bash
# 进程启动后向已关闭的 pipe 写入
# 应触发 SIGPIPE 导致进程退出
ps aux | grep sigpipe_unhandled | grep -v grep
# 注入进程应检测到子进程因 SIGPIPE 退出
```

**诊断流程:**
运行诊断脚本 `scripts/branch_F.sh`。

**清理:**
```bash
bash scripts/inject_sigpipe.sh stop
```

---

### 场景 G: socketpair 泄漏

**注入:**
```bash
bash scripts/inject_socketpair.sh run 10 100
```

**验证 (预期输出):**
```bash
# 查看进程 FD 数量
ls -1 /proc/$(pgrep -f socketpair_leak)/fd/ | wc -l
# 应 > 200 (10 pairs × 100 rounds × 2 fd/pair = 2000, 实际与 GC 有关)
# 随 rounds 增加 FD 数应持续上升
```

**诊断流程:**
运行诊断脚本 `scripts/branch_G.sh`。

**清理:**
```bash
bash scripts/inject_socketpair.sh stop
```

## 全量回归测试流程

依次测试 A → B → C → D → E → F → G:

```bash
# A: UDS backlog 满
bash scripts/inject_uds_backlog.sh run 2 10
bash scripts/inject_uds_backlog.sh status
bash scripts/inject_uds_backlog.sh stop

# B: Abstract 地址冲突
bash scripts/inject_abstract_conflict.sh run @uds_test
bash scripts/inject_abstract_conflict.sh status
bash scripts/inject_abstract_conflict.sh stop

# C: PASSCRED 失败
bash scripts/inject_passcred.sh run
bash scripts/inject_passcred.sh status
bash scripts/inject_passcred.sh stop

# D: socket 权限错误
bash scripts/inject_socket_perms.sh run 0000
bash scripts/inject_socket_perms.sh status
bash scripts/inject_socket_perms.sh stop

# E: pipe buffer 满
bash scripts/inject_pipe_buf.sh run 64 1024
bash scripts/inject_pipe_buf.sh status
bash scripts/inject_pipe_buf.sh stop

# F: SIGPIPE 退出
bash scripts/inject_sigpipe.sh run
bash scripts/inject_sigpipe.sh status
bash scripts/inject_sigpipe.sh stop

# G: socketpair 泄漏
bash scripts/inject_socketpair.sh run 10 100
bash scripts/inject_socketpair.sh status
bash scripts/inject_socketpair.sh stop

# 最终清理
bash scripts/cleanup.sh
```

## 故障模式对照表

| 症状 | 注入类型 | 说明 |
|------|---------|------|
| `connect()` 返回 EAGAIN/EWOULDBLOCK | A: UDS backlog 满 | 服务端 backlog 队列满 |
| `bind()` 返回 EADDRINUSE | B: Abstract 地址冲突 | abstract socket 地址已被占用 |
| `sendmsg()` 返回 ENODATA | C: PASSCRED 失败 | 对端未设置 SO_PASSCRED |
| `connect()` 返回 EACCES | D: socket 权限错误 | socket 文件权限不足 |
| `write()` 阻塞或返回 EAGAIN | E: pipe buffer 满 | pipe 写入端 buffer 填满 |
| `write()` 触发 SIGPIPE | F: SIGPIPE 退出 | 读端已关闭且未处理 SIGPIPE |
| FD 持续增长不释放 | G: socketpair 泄漏 | socketpair 创建后未关闭一端 |
