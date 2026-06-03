# FD 泄漏故障注入测试套件

基于 `fd-leak-diagnosis` Skill 的 8 种 FD 泄漏场景，每个场景对应一个独立 Docker 容器。

## 故障场景一览

| # | 目录名称 | 故障类型 | 对应诊断分支 |
|---|---------|---------|-------------|
| 1 | `system_fd_exhaustion` | 系统级 FD 耗尽 | `branch_A_system_fd.sh` |
| 2 | `process_fd_leak` | 进程级 Regular File FD 泄漏 | `branch_B_process_fd.sh` |
| 3 | `close_wait_leak` | CLOSE_WAIT Socket 泄漏 | `branch_C_close_wait.sh` |
| 4 | `epoll_leak` | epoll FD 泄漏 | `branch_D_epoll.sh` |
| 5 | `inotify_leak` | inotify watch 泄漏 | `branch_E_inotify.sh` |
| 6 | `syscall_fd_leak` | 系统调用级 FD 泄漏 (strace) | `branch_F_syscall.sh` |
| 7 | `deleted_file_leak` | 已删除文件 FD 泄漏 | `branch_G_deleted_file.sh` |
| 8 | `mixed_fd_leak` | 混合 FD 泄漏 (多类型叠加) | `branch_H_mixed.sh` |

## 快速使用

每个场景独立运行，选择注入的故障后执行：

```bash
# 例：注入进程级 FD 泄漏
cd process_fd_leak
chmod +x run.sh
./run.sh

# 查看容器内状态
docker exec fd_process_leak cat /proc/sys/fs/file-nr
docker exec fd_process_leak ps aux
docker exec fd_process_leak ls -1 /proc/*/fd 2>/dev/null | wc -l

# 停止注入
docker stop fd_process_leak
```

## 注入 → 诊断流程

```
┌──────────────┐    ┌──────────────┐    ┌──────────────┐
│ 1. 运行注入  │    │ 2. 执行诊断  │    │ 3. 验证结果  │
│ cd <场景目录>│    │ SSH 进容器   │    │ 检查报告     │
│ ./run.sh     │    │ 运行分支脚本 │    │ 确认根因     │
└──────────────┘    └──────────────┘    └──────────────┘
```

## 清理全部

```bash
docker stop fd_system_exhaustion fd_process_leak fd_close_wait \
            fd_epoll_leak fd_inotify_leak fd_syscall_leak \
            fd_deleted_leak fd_mixed_leak 2>/dev/null
```

## 容器参数说明

每个 `run.sh` 支持通过修改 `CMD` 参数调整泄漏规模：

| 场景 | 参数 | 默认值 | 说明 |
|------|------|--------|------|
| system_fd_exhaustion | `[max_fds]` | 50000 | 最多打开 FD 数 |
| process_fd_leak | `[children] [fds_per_child]` | 3 200 | 子进程数 × 每进程泄漏数 |
| close_wait_leak | `[port] [target_cw]` | 9999 1000 | 监听端口 × 目标 CLOSE_WAIT 数 |
| epoll_leak | `[target_epoll]` | 5000 | 目标 epoll 实例数 |
| inotify_leak | `[target_instances]` | 500 | 目标 inotify 实例数 |
| syscall_fd_leak | `[ops] [leak_pct] [max_open]` | 10000 80 500 | 操作数 × 泄漏率% × 最大同时打开 |
| deleted_file_leak | `[num_files]` | 500 | 目标已删除文件数 |
| mixed_fd_leak | `[leak_scale]` | 200 | 每种类型泄漏数 |
