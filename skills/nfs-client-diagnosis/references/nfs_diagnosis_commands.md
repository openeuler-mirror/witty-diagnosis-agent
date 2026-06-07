# NFS 客户端诊断命令速查手册

## 基础状态查询

| 命令 | 用途 | 示例 |
|------|------|------|
| `mount -t nfs,nfs4` | 查看 NFS 挂载列表 | `mount -t nfs,nfs4` |
| `findmnt -t nfs,nfs4` | 结构化 NFS 挂载信息 | `findmnt -t nfs,nfs4 -o TARGET,SOURCE,OPTIONS` |
| `nfsstat -m` | 挂载参数详情 | `nfsstat -m` |
| `cat /proc/self/mountstats` | 逐挂载点详细统计 | `cat /proc/self/mountstats` |
| `nfsstat -c` | 客户端操作统计 | `nfsstat -c` |
| `nfsstat -4 -c` | NFSv4 客户端统计 | `nfsstat -4 -c` |
| `nfsstat -r` | RPC 统计（retrans/时间） | `nfsstat -r` |
| `nfsstat -l` | NFS 锁统计 | `nfsstat -l` |

## RPC 与服务

| 命令 | 用途 | 示例 |
|------|------|------|
| `rpcinfo -p <server>` | 查询远程 RPC 端口映射 | `rpcinfo -p 192.168.1.100` |
| `rpcinfo -p localhost` | 查询本地 RPC 端口映射 | `rpcinfo -p localhost` |
| `showmount -e <server>` | 查询 NFS export 列表 | `showmount -e 192.168.1.100` |
| `systemctl status rpcbind` | rpcbind 服务状态 | `systemctl status rpcbind` |
| `systemctl status rpc-statd` | rpc.statd 服务状态 | `systemctl status rpc-statd` |
| `systemctl status nfs-client` | NFS 客户端服务状态 | `systemctl status nfs-client` |

## NFSv4 状态（/proc/net/rpc/nfs4.0/*）

| 文件 | 内容 | 诊断价值 |
|------|------|---------|
| `clientid` | NFSv4 clientid、lease 信息 | Lease 过期检测 |
| `slot_table` | slot 使用情况（seqid/状态） | Slot 耗尽检测 |
| `state` | open/lock/delegation 状态计数 | State 泄漏检测 |
| `callback` | 回拨通道状态 | Callback 异常检测 |
| `delegreturn` | delegreturn 统计 | Delegreturn 异常检测 |
| `freeslot` | 空闲 slot 数量 | Slot 资源检测 |

## 网络诊断

| 命令 | 用途 | 示例 |
|------|------|------|
| `ping -c N <server>` | RTT 统计 | `ping -c 10 192.168.1.100` |
| `nc -zv <server> <port>` | 端口可达性 | `nc -zv 192.168.1.100 2049` |
| `mtr --report <server>` | 路径质量分析 | `mtr --report -c 10 192.168.1.100` |
| `tracepath <server>` | MTU 路径探测 | `tracepath 192.168.1.100` |
| `ip route get <server>` | 路由路径确认 | `ip route get 192.168.1.100` |
| `ss -tnp dst <server>` | 到 server 的 TCP 连接 | `ss -tnp dst 192.168.1.100` |

## 锁诊断

| 命令 | 用途 | 示例 |
|------|------|------|
| `cat /proc/locks` | 查看所有文件锁 | `cat /proc/locks \| grep NFS` |
| `lslocks` | 锁统计（结构化） | `lslocks` |
| `nfsstat -l` | NFS 锁统计 | `nfsstat -l` |
| `cat /var/lib/nfs/sm/*` | statd 监控的主机列表 | `ls -la /var/lib/nfs/sm/` |

## 进程分析

| 命令 | 用途 | 示例 |
|------|------|------|
| `ps -eo pid,stat,wchan,cmd` | 查看进程状态（D 状态） | `ps -eo pid,stat,wchan,cmd \| grep " D "` |
| `cat /proc/<pid>/stack` | 进程内核栈 | `cat /proc/1234/stack` |
| `fuser -v <mountpoint>` | 使用挂载点的进程 | `fuser -v /mnt/nfs_data` |
| `lsof +D <mountpoint>` | 挂载点上打开的文件 | `lsof +D /mnt/nfs_data` |

## 性能分析

| 命令 | 用途 | 示例 |
|------|------|------|
| `cat /proc/self/mountstats` | RTT/retrans 详细统计 | `grep -E "RPC\|rtt\|retrans" /proc/self/mountstats` |
| `nfsstat -c -o all 2 5` | 实时操作统计（2s间隔） | `nfsstat -c -o all 2 5` |
| `iostat -x 1 3` | 磁盘 IO 性能 | `iostat -x 1 3` |
| `netstat -s` | 网络统计（丢包/重传） | `netstat -s \| grep -iE "drop\|retrans"` |

## dmesg 日志过滤模式

```bash
# NFS 所有日志
dmesg -T | grep -iE "nfs|NFS|rpc|RPC"

# 错误和警告
dmesg -T | grep -iE "NFS:.*error|NFS:.*fail|RPC:.*error"

# 超时
dmesg -T | grep -iE "timed out|timeout|not responding"

# 状态恢复
dmesg -T | grep -iE "reclaim|state|lease|clientid|session"

# ESTALE
dmesg -T | grep -iE "stale|ESTALE"

# lockd/statd
dmesg -T | grep -iE "lockd|statd|nfslock"
```

## NFS 挂载参数含义速查

| 参数 | 默认值 | 说明 | 诊断意义 |
|------|--------|------|---------|
| `soft` | (不使用) | RPC 超时后返回错误给应用 | 应用需处理 EIO，否则数据静默丢失 |
| `hard` | 默认 | RPC 无限重试直到 server 恢复 | 进程进入 D 状态不可杀 |
| `timeo=N` | 600 (60s) | RPC 超时时间（1/10 秒） | 调小加速故障检测，调大降低网络抖动影响 |
| `retrans=N` | 3 | RPC 超时重试次数 | soft mount: N 次后返回 EIO |
| `rsize=N` | 1048576 (1M) | NFS 读缓冲区大小 | 大文件传输性能关键参数 |
| `wsize=N` | 1048576 (1M) | NFS 写缓冲区大小 | 大文件传输性能关键参数 |
| `actimeo=N` | (不设置) | 文件属性缓存时间（秒） | 缓存一致性关键参数 |
| `noac` | (不使用) | 禁用属性缓存 | 强一致性但低性能 |
| `proto=tcp` | tcp | 传输协议 | NFSv4 必须 tcp |
| `vers=N` | 4.2 | NFS 协议版本 | 版本协商故障 |
| `sec=mode` | sys | 安全模式 (sys/krb5p/krb5i/krb5) | Kerberos 认证问题 |
| `nordirplus` | (不使用) | 禁用 READDIRPLUS | 大量文件目录读取优化 |
| `lookupcache=all` | all | 目录查找缓存模式 | 缓存一致性 |

## NFS 内核模块

| 模块 | 用途 |
|------|------|
| `nfs` | NFS 客户端核心模块 |
| `nfsv4` | NFSv4 客户端支持 |
| `nfsv3` | NFSv3 客户端支持 |
| `lockd` | NLM（网络锁管理器） |
| `nfs_acl` | NFS ACL 支持 |
| `rpcsec_gss_krb5` | Kerberos 认证支持 |
| `sunrpc` | Sun RPC 核心层 |

## /proc/net/rpc/ 文件结构

| 文件 | 对应子系统 | NFS 版本 |
|------|-----------|---------|
| `/proc/net/rpc/nfs` | NFSv3 操作统计 | NFSv3 |
| `/proc/net/rpc/nfsd` | NFS 服务端操作统计 | NFSv3 |
| `/proc/net/rpc/nfs4.0/` | NFSv4 状态目录 | NFSv4.x |
| `/proc/net/rpc/auth.rpcsec` | RPC 安全认证统计 | NFSv4 (Kerberos) |
| `/proc/net/rpc/rpcrmt` | RPC 传输层统计 | 通用 |

## 关键错误码速查

| 错误码 | 含义 | 可能的根因 |
|--------|------|-----------|
| `ESTALE` | Stale file handle | 服务端文件被删除，export 路径变化 |
| `NFS4ERR_EXPIRED` | Lease 已过期 | Server 重启、网络长时间中断 |
| `NFS4ERR_STALE_CLIENTID` | Clientid 已过期 | Server 重启后 clientid 需重新确认 |
| `NFS4ERR_BADSESSION` | Session 不合法 | Session 被 server 销毁 |
| `NFS4ERR_DELAY` | Server 请求延后处理 | Server 过载，通常自动重试 |
| `NFS4ERR_OPENMODE` | OPEN 模式冲突 | 已有写打开时试图非共享读打开 |
| `NFS4ERR_LOCKED` | 文件已加锁 | 锁冲突 |
| `NFS4ERR_GRACE` | Server 在 grace 周期 | Server 重启后恢复阶段 |
| `NFS4ERR_RECLAIM_BAD` | 重新声明 state 失败 | State 无法恢复 |
| `NFS4ERR_RECLAIM_CONFLICT` | 重新声明 state 冲突 | State 已被其他 client 声明 |

## 日志关键字速查

| 关键字 | 可能的根因 |
|--------|-----------|
| `NFS: nfs4_do_reclaim: reclaim failed` | NFSv4 state 恢复失败 |
| `NFS: `server_ip` not responding` | NFS server 网络不可达 |
| `NFS: `server_ip` OK` | NFS server 恢复可达 |
| `RPC: timed out` | RPC 请求超时 |
| `lockd: cannot monitor `host`` | statd 无法监控远程主机 |
| `NFS: ESTALE` | Stale file handle |
| `NFS: `file` layout recall` | pNFS layout 回拨 |
| `nfs: server `server_ip` not responding, still trying` | Hard mount 重试状态 |
| `rpc.gssd` 错误 | Kerberos 认证问题 |
| `rpc.idmapd` 错误 | UID/GID 映射问题 |
