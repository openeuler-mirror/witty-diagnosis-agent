# NFS 关键错误码与日志关键字参考

## NFS3 错误码

| 错误码 | 值 | 含义 | 可能的根因 |
|--------|----|------|-----------|
| `NFS3ERR_PERM` | 1 | 操作不允许 | 权限不足 |
| `NFS3ERR_NOENT` | 2 | 文件或目录不存在 | 路径错误 |
| `NFS3ERR_IO` | 5 | I/O 错误 | 存储故障、网络问题 |
| `NFS3ERR_NXIO` | 6 | 设备不存在 | 设备未连接 |
| `NFS3ERR_ACCES` | 13 | 权限拒绝 | 文件权限、export 限制 |
| `NFS3ERR_EXIST` | 17 | 文件已存在 | 创建冲突 |
| `NFS3ERR_NOTDIR` | 20 | 不是目录 | 路径错误 |
| `NFS3ERR_ISDIR` | 21 | 是目录 | 操作类型不匹配 |
| `NFS3ERR_FBIG` | 27 | 文件过大 | 文件系统大小限制 |
| `NFS3ERR_NOSPC` | 28 | 设备无空间 | 服务端磁盘满 |
| `NFS3ERR_ROFS` | 30 | 只读文件系统 | export 为只读 |
| `NFS3ERR_STALE` | 70 | Stale file handle | 见分支B |
| `NFS3ERR_NOTSUPP` | 10004 | 操作不支持 | 服务端 NFS 版本不支持 |
| `NFS3ERR_SERVERFAULT` | 10006 | 服务端错误 | 服务端内部错误 |

## NFS4 错误码

| 错误码 | 含义 | 可能的根因 |
|--------|------|-----------|
| `NFS4ERR_ACCESS` | 权限拒绝 | 文件权限、export ACL |
| `NFS4ERR_BADHANDLE` | 文件句柄无效 | 服务端文件系统损坏 |
| `NFS4ERR_BADSESSION` | Session 不合法 | Session 被服务端销毁，需重建 |
| `NFS4ERR_BADXDR` | XDR 编码错误 | 客户端/服务端版本不兼容 |
| `NFS4ERR_CLID_INUSE` | clientid 已被使用 | 多个客户端使用相同 clientid |
| `NFS4ERR_DELAY` | 服务端请求延后处理 | 服务端负载高，客户端应重试 |
| `NFS4ERR_EXPIRED` | Lease 已过期 | 服务端重启、网络长时间中断 |
| `NFS4ERR_FHEXPIRED` | 文件句柄已过期 | 文件系统发生了变化 |
| `NFS4ERR_GRACE` | 服务端在 grace 恢复期 | 服务端重启后的恢复阶段 |
| `NFS4ERR_LEASE_MOVED` | Lease 迁移到其他服务端 | 服务端 IP 变化 |
| `NFS4ERR_LOCKED` | 请求的资源已锁定 | 文件锁冲突 |
| `NFS4ERR_MINOR_VERS_MISMATCH` | 次要版本不匹配 | 4.0/4.1/4.2 协商失败 |
| `NFS4ERR_MOVED` | 文件系统已迁移 | 服务端文件系统 relocated |
| `NFS4ERR_NOENT` | 文件或目录不存在 | 路径错误 |
| `NFS4ERR_NOT_SAME` | 文件句柄指向的不是同一个文件 | rename/delete 导致句柄变化 |
| `NFS4ERR_OPENMODE` | OPEN 模式冲突 | 已有写打开时试图非共享读 |
| `NFS4ERR_PERM` | 操作不允许 | 权限不足 |
| `NFS4ERR_RECLAIM_BAD` | 重新声明 state 失败 | State 无法恢复 |
| `NFS4ERR_RECLAIM_CONFLICT` | 重新声明 state 冲突 | 其他客户端已声明同一 state |
| `NFS4ERR_RESOURCE` | 资源不足 | 服务端内存不足 |
| `NFS4ERR_RESTOREFH` | 恢复文件句柄失败 | 服务端内部错误 |
| `NFS4ERR_SESSION` | Session 错误 | Session 参数不一致 |
| `NFS4ERR_STALE` | Stale file handle | 见分支B |
| `NFS4ERR_STALE_CLIENTID` | clientid 已过期 | 服务端重启 / lease 过期 |
| `NFS4ERR_TOOSMALL` | 响应缓冲区太小 | 客户端/服务端版本协商问题 |
| `NFS4ERR_UNLOCK_ERR` | UNLOCK 内部错误 | 锁状态不一致 |

## /proc/net/rpc/nfs4.0/ 文件结构

| 文件 | 字段说明 | 诊断价值 |
|------|---------|---------|
| `clientid` | `clientid boot verify lease_expired [flags]` | Lease 过期检测 |
| `slot_table` | `slot_nr seqid [rpc_status]` | Slot 耗尽检测 |
| `state` | `[open/lock/delegation/delegreturn] counts` | State 泄漏检测 |
| `callback` | `callback_status cb_ident` | Callback 通道状态 |
| `delegreturn` | `delegreturn stats` | Delegreturn 异常 |

## 内核日志关键字速查

| 日志关键字 | 对应代码位置 | 可能的根因 |
|-----------|-------------|-----------|
| `NFS: nfs4_do_reclaim: reclaim failed` | `nfs4state.c` | NFSv4 state 恢复失败 |
| `NFS: not responding` | `nfsclient.c` | NFS server 网络不可达 |
| `NFS: OK` | `nfsclient.c` | NFS server 恢复可达 |
| `RPC: timed out` | `rpctimer.c` | RPC 请求超时 |
| `lockd: cannot monitor` | `lockd.c` | statd 无法监控远程主机 |
| `NFS: ESTALE` | `nfsproc.c` / `nfs4proc.c` | Stale file handle |
| `NFS: mmap write failed` | `file.c` | NFS 文件映射写入失败 |
| `nfs: server not responding, still trying` | `nfsclient.c` | Hard mount 重试 |
| `NFS: atomic open` | `nfs4proc.c` | NFSv4 OPEN 操作 |
| `NFS: state recovery failed` | `nfs4state.c` | State 恢复失败 |
| `rpc.gssd: ERROR` | `gssd.c` | Kerberos 认证错误 |
| `rpc.idmapd: ERROR` | `idmapd.c` | UID/GID 映射错误 |
| `NFS: reclaim completed` | `nfs4state.c` | State 恢复成功（正常事件） |
| `NFS: read error` | `nfsproc.c` | NFS 读取错误 |
| `NFS: write error` | `nfsproc.c` | NFS 写入错误（EIO） |

## RPC 层错误

| 错误现象 | 含义 | 可能的根因 |
|---------|------|-----------|
| RPC 超时 | RPC 请求未在 timeo 内收到响应 | 网络丢包/服务端不响应 |
| RPC 部分传输 | TCP 连接断开导致数据不完整 | 网络不稳定/中间设备 Reset |
| RPC 认证错误 | AUTH_BADCRED / AUTH_REJECTCRED | Kerberos ticket 过期 |
| RPC 程序未注册 | 程序: 版本不可用 | mountd/NFS 服务未在 rpcbind 注册 |

## mount 错误码

| 错误消息 | 含义 | 可能的根因 |
|---------|------|-----------|
| `mount.nfs: Connection timed out` | 连接 NFS 服务超时 | 网络不通/防火墙/服务端未启动 |
| `mount.nfs: access denied by server` | 服务端拒绝访问 | export 配置/权限/认证 |
| `mount.nfs: Protocol not supported` | 协议版本不支持 | 版本协商失败 |
| `mount.nfs: Operation not permitted` | 操作不允许 | sec=krb5 票据失效 |
| `mount.nfs: RPC: Unable to receive` | RPC 接收失败 | 网络层问题 |
| `mount.nfs: mount to NFS server failed` | 通用挂载失败 | 通常是 network/RPC 层错误 |
| `mount.nfs: failed to create RPC client` | 创建 RPC 客户端失败 | rpcbind 不可用 |
| `mount.nfs: an incorrect mount option was specified` | 挂载参数错误 | 参数拼写/版本不兼容 |

## 时序对齐检查清单

```
故障发生时间 T0
  ├─ dmesg 日志时间戳：T0 ± 5min 内是否有 NFS 相关告警？
  ├─ journalctl 日志：T0 ± 5min 内是否有 NFS/rpc 相关记录？
  ├─ nfsstat 统计：错误计数是 T0 前就存在还是 T0 后增长？
  └─ 系统资源监控：是否有与 T0 吻合的资源耗尽记录？
```

> 所有不在故障时间窗口内的日志记录，应标记为"历史告警"并排除出当前诊断结论。
