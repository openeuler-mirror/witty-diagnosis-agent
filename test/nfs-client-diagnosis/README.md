# NFS 客户端故障诊断 — 故障注入测试套件

基于 Docker 容器的 NFS 故障注入测试环境及诊断报告集合，用于验证 NFS 客户端诊断脚本的故障检测能力。

---

## 目录结构

```
test/nfs-client-diagnosis/
├── README.md                         # 本文件
├── reports/                          # 6 个分支的 RCA 诊断报告
│   ├── BranchA_mount挂载失败_RCA.{md,html}
│   ├── BranchB_StaleFileHandle_RCA.{md,html}
│   ├── BranchC_NFSv4Lease_RCA.{md,html}
│   ├── BranchD_rpcStatd锁服务_RCA.{md,html}
│   ├── BranchE_网络延迟tc注入_RCA.{md,html}
│   └── BranchF_hardMount超时_RCA.{md,html}
│
└── test-env/                         # 故障注入测试环境
    ├── docker-compose.yaml           # NFS Server + Client 容器编排
    ├── setup.sh                      # 启动测试环境
    ├── teardown.sh                   # 停止并清理环境
    ├── lib/common.sh                 # 通用函数库
    ├── container/server/             # NFS Server 容器
    ├── container/client/             # NFS Client 容器
    ├── inject/                       # 6 个故障注入脚本
    └── clean/                        # 6 个清理脚本
```

---

## 架构

```
┌─────────────────────────┐     ┌─────────────────────────┐
│   nfs-fault-server      │     │   nfs-fault-client      │
│   (Ubuntu 22.04)        │     │   (Ubuntu 22.04)        │
│                         │     │                         │
│   ┌───────────────────┐ │     │  ┌──────────────────┐   │
│   │  /exports/        │◄├─────┼──┤  /mnt/nfs-test   │   │
│   │   stale-test/     │ │ NFS │  │                   │   │
│   │   perf-test/      │ │     │  │  诊断脚本:         │   │
│   │   mount-test/     │ │     │  │  /diagnosis-scripts│   │
│   └───────────────────┘ │     │  └──────────────────┘   │
│                         │     │                         │
│   iptables: 端口阻断     │     │  tc: 网络延迟/丢包      │
│   rpc.nfsd: 服务重启     │     │  iptables: 端口阻断     │
│   rm: 文件删除           │     │  pkill: 进程终止        │
└─────────────────────────┘     └─────────────────────────┘
        172.31.254.0/24
```

---

## 故障场景清单

| 分支 | 场景 | 注入方式 | 诊断关键证据 |
|:----:|------|---------|-------------|
| **A** | Mount 挂载失败 | Server 侧 iptables 阻断 2049/111 | 端口不可达, rpcinfo 失败, mount 超时 |
| **B** | Stale File Handle | 后台进程持有 fd + Server 删除文件并重启 NFSD | /proc/PID/fd/ 访问返回 "Stale file handle" |
| **C** | NFSv4 Lease 过期 | Server 侧重启 rpc.nfsd + mountd | reclaim_comp > 0, create_session 重建 |
| **D** | rpc.statd/lockd 异常 | Client 侧 pkill -9 rpc.statd | statd 消失, lockd 模块未加载 |
| **E** | 性能退化 | Client 侧 tc netem delay 400ms jitter 100ms loss 2% | ping RTT 0.07→696ms, tc 规则确认 |
| **F** | Hard Mount 超时 | Client 侧 iptables 阻断出站 2049 | D 状态进程, "nfs: server not responding" |

---

## 前提条件

- Docker Engine 20.10+
- Linux 宿主机（容器共享宿主内核，需要 NFS 内核模块支持）
- 宿主机已加载 NFS 内核模块: `lsmod | grep nfsd`
- 宿主机已加载 NFS 客户端模块: `lsmod | grep nfs`

## 快速开始

### 1. 启动测试环境

```bash
cd test-env
bash setup.sh
```

首次启动会自动构建 Docker 镜像。如需强制重新构建：

```bash
bash setup.sh build
```

### 2. 注入故障并运行诊断

对每个故障场景，先运行注入脚本，再运行诊断脚本（在容器内）：

```bash
# 示例: 注入 stale file handle 故障
bash inject/branch_B_stale_handle.sh

# 运行诊断（手动或通过 witty-agent）
# witty-agent 会调用 /diagnosis-scripts/branch_B_stale_handle.sh

# 诊断完成后清理故障
bash clean/branch_B_stale_handle.sh
```

### 3. 停止测试环境

```bash
bash teardown.sh
```

如需同时删除数据卷：

```bash
bash teardown.sh --volumes
```

---

## 故障场景详细说明

### Branch A: Mount 挂载失败

- **注入**: Server 侧 iptables 阻断 TCP/UDP 2049 + 111 端口
- **效果**: 客户端 mount 命令超时或连接拒绝
- **诊断**: `branch_A_mount_failure.sh` 检测到端口不可达、rpcinfo 失败
- **清理**: 删除 iptables 阻断规则

### Branch B: Stale File Handle (v2 改进版)

- **注入**: 
  1. 客户端后台进程通过 `exec 200>` 打开并持有文件 fd
  2. 服务端执行 `rm -f` 删除文件
  3. 服务端重启 NFS 服务（`rpc.nfsd 0` + `rpc.nfsd 8`），彻底释放 inode
  4. 客户端通过 `/proc/PID/fd/200` 跨进程访问旧句柄
- **效果**: 内核返回 `ESTALE`（Stale file handle）错误
- **诊断**: `branch_B_stale_handle.sh` 检测到 ESTALE 错误
- **清理**: 终止 holder 进程、重置目录、确保 NFS 服务运行

> **v2 改进说明**: 原方法因跨 `docker exec` session 无法保持 fd 且仅重建目录未释放 inode，ESTALE 不可靠触发。
> v2 使用后台进程持有 fd + 服务端删除文件并重启 NFSD，通过 `/proc/PID/fd/` 跨进程访问，可稳定触发 ESTALE。

### Branch C: NFSv4 Lease 过期

- **注入**: Server 侧重启 `rpc.nfsd` + 杀死 `rpc.mountd`
- **效果**: 客户端 NFSv4 会话（lease/state）过期，需要重新声明
- **诊断**: `branch_C_nfs4_lease.sh` 检测到 `reclaim_comp`、`create_session` 等 NFSv4 状态恢复操作
- **清理**: 确保 NFS Server 服务运行

### Branch D: rpc.statd/lockd 异常

- **注入**: Client 侧 `pkill -9 rpc.statd`（rpcbind 随之终止）
- **效果**: NFS 锁服务（NLM）不可用，statd/nlockmgr 从 rpcinfo 注册中消失
- **诊断**: `branch_D_rpc_lockd.sh` 检测到 statd 进程消失、rpcinfo 无注册
- **清理**: 重启 rpcbind 和 rpc.statd

### Branch E: 性能退化

- **注入**: Client 侧 `tc qdisc add dev eth0 root netem delay 400ms 100ms loss 2%`
- **效果**: NFS 操作 RTT 从 0.07ms 飙升至平均 696ms，出现延迟和丢包
- **诊断**: `branch_E_perf_degradation.sh` 检测到 retrans 率升高、RTT 增大
- **清理**: 删除 tc qdisc 规则

### Branch F: Hard Mount 超时

- **注入**: Hard mount 后 client 侧 iptables 阻断出站 2049 端口
- **效果**: 文件操作卡住，进程进入 D 状态（TASK_UNINTERRUPTIBLE）
- **诊断**: `branch_F_mount_timeout.sh` 检测到 D 状态进程、RPC 超时统计
- **清理**: 删除 iptables 规则、强制卸载、清理 D 状态进程

---

## 诊断报告

`reports/` 目录包含各分支的全链路诊断报告（Markdown + HTML 双格式），由 witty-agent 的 Baize 模块生成。

| 报告文件 | 对应分支 | 诊断结论 |
|---------|:--------:|---------|
| BranchA_mount挂载失败_RCA | A | iptables 阻断 port 111/2049 → RPC 通信失败 → mount 超时 |
| BranchB_StaleFileHandle_RCA | B | 服务端 rm + NFSD restart → filehandle 过期 → ESTALE |
| BranchC_NFSv4Lease_RCA | C | NFSD 重启 → lease 过期 → reclaim_comp 状态自动恢复 |
| BranchD_rpcStatd锁服务_RCA | D | pkill statd → rpcbind 终止 → NLM 锁服务不可用 |
| BranchE_网络延迟tc注入_RCA | E | tc netem 注入 → ping RTT 696ms → NFS 操作性能退化 |
| BranchF_hardMount超时_RCA | F | iptables 阻断 → hard mount 持续重试 → D 状态进程 |

---

## 故障注入原则

1. **容器隔离** — 所有操作在 Docker 容器内执行，不影响宿主机
2. **真实故障** — 使用内核级工具（iptables/tc/rpc.nfsd）注入真实网络/系统故障
3. **零依赖三方工具** — 全部使用 Linux 内核/系统自带工具
4. **幂等清理** — 每个 clean 脚本可重复执行，不会造成残留

## 诊断验证流程

```
注入故障 → 运行 witty-agent 诊断 → 清理故障 → 对比结果
```

1. 运行 `bash inject/branch_X_*.sh` 注入故障
2. 使用 witty-agent 运行诊断（诊断脚本位于 `/diagnosis-scripts/`）
3. 运行 `bash clean/branch_X_*.sh` 清理故障
4. 对比注入的故障与诊断结论是否一致（参考 `reports/` 中的 RCA 报告）

## 常见问题

**Q: NFS Server 启动失败**
A: 检查宿主机是否加载了 NFS 内核模块: `lsmod | grep nfsd`

**Q: tc 规则添加失败**
A: 确认容器以 privileged 模式运行（已配置）

**Q: iptables 操作被拒绝**
A: 确认容器以 privileged 模式运行（已配置）

**Q: 客户端 mount 报错 "Protocol not supported"**
A: 尝试指定不同 NFS 版本: `vers=3` 或 `vers=4.0`
