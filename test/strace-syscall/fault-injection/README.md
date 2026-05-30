# strace-syscall-diagnosis 故障注入测试套件

针对 7 个故障分支，提供容器隔离的故障注入和环境清理脚本。
用于验证 witty agent 对 syscall 异常的诊断准确性。

## 架构概览

```
fault-injection/
├── README.md                  # 本文档
├── Dockerfile                 # 多阶段构建镜像
├── lib/common.sh              # 共享函数库
├── inject_loop.sh             # 注入故障（持续循环，供 agent attach 诊断）
├── cleanup_loop.sh            # 清理故障容器
└── src/                       # 7 个 C 故障注入源码
    ├── branch_a_errors.c      # 分支 A: 错误码模式
    ├── branch_b_slow.c        # 分支 B: 慢 Syscall
    ├── branch_c_library.c     # 分支 C: 库函数追踪
    ├── branch_d_leak.c        # 分支 D: FD/资源泄漏
    ├── branch_e_network.c     # 分支 E: 网络错误
    ├── branch_f_signal.c      # 分支 F: 信号/中断
    └── branch_g_lifecycle.c   # 分支 G: 进程生命周期
```

## 前置条件

- Docker >= 20.10
- 当前用户有 Docker 执行权限

## 使用方式

### 注入持续故障（供 agent 诊断）

```bash
# 注入 Branch A - ENOENT 故障
./inject_loop.sh a enoent

# 注入 Branch B - futex 锁竞争
./inject_loop.sh b futex

# 注入 Branch D - FD 泄漏
./inject_loop.sh d fd_leak

# 注入 Branch E - ECONNREFUSED
./inject_loop.sh e econnrefused
```

输出包含容器 PID，将 PID 提供给 witty agent 即可开始诊断。

### 清理容器

```bash
./cleanup_loop.sh all          # 清理全部
./cleanup_loop.sh a enoent    # 清理特定故障
./cleanup_loop.sh d           # 清理分支 D 全部
```

## 故障分支表

| 分支 | 子模式 | 注入手法 | 预期 syscall 异常 |
|:----:|--------|---------|-------------------|
| **A** | eacces, enoent, eagain, enomem | 受限文件访问/不存在路径/非阻塞读空管道/RLIMIT_AS 限制 mmap | EACCES/EPERM, ENOENT, EAGAIN, ENOMEM |
| **B** | futex, slowio, slowopen | 4 线程锁竞争 50ms / pipe 延迟写入 / 大量文件遍历 | futex>50ms, read>1s, open 耗时 |
| **C** | mallocfreq, callpath | 500 次/轮高频 malloc/free / 函数指针拦截 | memory churn, 异常调用链 |
| **D** | fd_leak, mmap_leak | open 不 close / mmap 不 munmap | FD 线性增长, mmap 泄漏 |
| **E** | econnrefused, etimedout, econnreset, epipe, eaddrinuse | 连接无服务端口/不可达地址/SO_LINGER=0/写已关闭连接/重复 bind | ECONNREFUSED, ETIMEDOUT, ECONNRESET, EPIPE, EADDRINUSE |
| **F** | eintr, sigpipe | setitimer(100ms)+NO SA_RESTART / 写断管 | EINTR, SIGPIPE |
| **G** | fork_storm, execve_fail, zombie | 快速 fork(50ms) / 执行不存在二进制 / 不 wait 子进程 | clone 高频, execve ENOENT, 僵尸进程 |

## 测试流程（验证 agent 诊断准确性）

```bash
# 1. 启动持续故障
./inject_loop.sh a enoent

# 2. 获取容器 PID
PID=$(docker inspect $(docker ps --filter "name=strace-fi-loop-a-enoent" --format "{{.Names}}") --format '{{.State.Pid}}')

# 3. 将 PID 提供给 witty agent
#    prompt 示例:
#    "有一个正在运行的进程 PID=${PID}，现象是反复 open/stat/access
#     不存在的路径 /tmp/nonexistent_dir_*/nonexistent_file_*.conf，全部返回 ENOENT"

# 4. agent 自动运行诊断（attach strace 采集 → 推荐分支 → 根因分析）
#    bash 01_baseline_info.sh ${PID} 15

# 5. 对比诊断结论与注入故障

# 6. 清理
./cleanup_loop.sh a enoent
```

## 安全设计

- **容器隔离**：所有故障注入在 Docker 容器内运行，与宿主机完全隔离
- **最小权限**：仅添加必要的 capabilities（SYS_PTRACE, NET_ADMIN）
- **自动回收**：容器退出后所有资源（FD、mmap、僵尸进程）由内核自动回收

## 故障注入原理

每个 C 程序通过直接调用 Linux syscall API 触发特定的 syscall 行为模式：
1. **错误码模式**：在预设条件下调用 syscall，内核真实返回 errno
2. **慢 syscall**：通过锁竞争、管道延迟等方式引入人为延迟
3. **资源泄漏**：故意不释放已分配资源，通过 /proc 观察增长趋势
4. **网络异常**：在容器网络命名空间内创建/销毁连接模拟网络故障
5. **信号中断**：通过 setitimer 定时器产生信号中断阻塞中的 syscall
6. **进程异常**：通过 fork/execve 控制子进程生命周期
