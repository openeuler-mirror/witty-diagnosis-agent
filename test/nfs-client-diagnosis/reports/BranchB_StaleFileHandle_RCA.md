# 🔴 故障诊断报告

> **报告编号**：BAIZE-RCA-20260608-001
> **故障级别**：P2（功能级故障）
> **报告时间**：2026-06-08 03:14:15 UTC
> **当前状态**：🟡 观察中

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | NFS 客户端 Stale File Handle (ESTALE) 错误 —— 服务端文件删除并重启 NFSD 导致文件句柄过期 |
| 影响范围 | NFS 挂载点 `/mnt/nfs-test`（`nfs-server:/exports`）上持有陈旧文件描述符的进程，通过 `/proc/PID/fd/` 访问旧文件句柄时失败 |
| 故障时段 | 2026-06-07 18:40:39 ~ 2026-06-07 19:10:39 UTC |
| 根本原因 | NFS 服务端在客户端持有文件描述符期间，执行了文件删除操作并重启 NFS 服务（NFSD），导致服务端 filehandle 映射表重建，原文件 inode 被释放，客户端持有的旧 filehandle 过期失效。客户端后续 I/O 请求携带过期 filehandle 发起 RPC 调用，服务端返回 `NFS3ERR_STALE`（错误码 70），内核转换为用户态 `ESTALE` 错误。 |
| 是否恢复 | ❌ 未完全恢复（文件已重建，但持有旧 fd 的进程需手动关闭并重新打开） |
| 根因置信度 | 🟢 高置信（双轨分析完全吻合，反事实验证通过） |

### 置信度说明（此表固定展示作为参考）

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|--------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | SQL 无索引 → 复现后加索引立即恢复 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | 定位到慢查询，但流量突增原因待查 |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | 多个组件同时异常，无法判断触发顺序 |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | 服务偶发崩溃，日志无异常，无法复现 |

---

## 二、根因速览

> 用一张图说清楚：**什么事件触发了什么连锁反应，最终导致故障**。

### 事故时间线 & 故障传导链路

```text
时间                   事件                                                      性质          溯源路径
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-06-07 18:33:36   NFS 服务首次启动，90 秒宽限期开始                               🟢 服务启动   [kuafu_T1_stale_handle.md:42]
  │
  ▼
2026-06-07 18:35:16   NFSD 重启（第 1 次）                                           ⚠️ 异常信号   [kuafu_T1_stale_handle.md:43]
  │                   ...后续多次重启...
  ▼
2026-06-07 ~18:40    服务端删除 stale-test 原始文件 persist.txt                        🔴 根因事件   [kuafu_T1_stale_handle.md:49]
  │                   (客户端此时持有该文件的 fd)
  ▼
2026-06-07 ~18:41    服务端执行 NFSD 重启，filehandle 映射表重建                        🔴 根因事件   [kuafu_T1_stale_handle.md:49]
  │                   原 inode 被释放，旧 filehandle 过期
  ▼
2026-06-07 18:41:58   `nfs: server nfs-server not responding, still trying`           🟡 客户端感知   [kuafu_T1_stale_handle.md:50]
  │                   (服务端 NFSD 重启期间 RPC 超时)
  ▼
2026-06-07 18:43:31   persist.txt 在服务端被重建（新 inode: 393558）                    📝 文件重建    [kuafu_T1_stale_handle.md:51]
  │                   内容: `NEW_DATA_AFTER_RECREATE`
  ▼
2026-06-07 18:44:54   NFSD 重启（第 6 次）                                            ⚠️ 持续异常   [kuafu_T1_stale_handle.md:52]
  │                   ...继续多次重启...
  ▼
2026-06-07 19:00:10   `nfs: server nfs-server not responding, still trying`           🟡 再次中断   [kuafu_T1_stale_handle.md:55]
  ▼
2026-06-07 19:01:46   `nfs: server nfs-server not responding, timed out` (第 1 次)     🔴 超时爆发   [kuafu_T1_stale_handle.md:56]
  │                   连续 8 次 timed out (hard mount 持续重试)
  ├─► 19:02:01  第 2 次 timed out
  ├─► 19:02:07  第 3 次 timed out
  ├─► 19:02:17  第 4 次 timed out
  ├─► 19:02:22  第 5 次 timed out
  ├─► 19:02:32  第 6 次 timed out
  ├─► 19:02:47  第 7 次 timed out
  └─► 19:03:03  第 8 次 timed out
  ▼
2026-06-07 19:08:11   stale-test-v2 目录被创建                                         📝 恢复操作   [kuafu_T1_stale_handle.md:57]
  ▼
2026-06-07 19:13:46 起 NFSD 继续多次重启                                              ⚠️ 持续不稳定  [kuafu_T1_stale_handle.md:58]
```

### 故障因果链

```text
服务端文件删除（rm persist.txt） + NFSD 重启（systemctl restart nfs-server）
    │
    └─► 服务端 filehandle 映射表重建，原 inode 被释放
            │
            └─► 客户端持有的旧文件描述符对应的 filehandle（fsid+inode+gen）过期
                    │
                    └─► 客户端通过 /proc/PID/fd/ 或 I/O 访问旧 fd
                            │
                            └─► 内核 NFS 客户端发起 RPC 请求（GETATTR/READ/WRITE），携带过期 filehandle
                                    │
                                    └─► 服务端查找 filehandle 失败，返回 NFS3ERR_STALE（错误码 70）
                                            │
                                            └─► 内核 NFS 客户端将 NFS3ERR_STALE 转换为用户态 ESTALE
                                                    │
                                                    └─► 🔴 应用层收到 "Stale file handle" 错误，操作失败
```

---

## 三、排查过程

> 排查逻辑：**提出假设 → 收集证据 → 验证或排除 → 逐步收敛到根因**

### 3.1 初始现象

- **故障表现**：NFS 客户端进程通过 `/proc/PID/fd/` 访问文件时，内核返回 `ESTALE`（Stale file handle）错误。
- **故障场景**：服务端删除文件并重启 NFS 服务后，持有旧文件描述符的进程无法继续操作。
- **受影响挂载点**：`/mnt/nfs-test`（NFSv3, hard, proto=tcp）
- **关键日志片段**：
  - `nfs: server nfs-server not responding, still trying`（18:41:58 UTC）
  - `nfs: server nfs-server not responding, timed out`（19:01:46~19:03:03 UTC, 连续 8 次）
  - 故障窗口内 NFSD 共重启 11+ 次
  - 文件 `persist.txt` 被删除后重建，inode 已改变（原始 inode → 393558）

---

### 3.2 假设驱动排查

#### 假设 A：NFSv4 lease 过期问题

> 🧪 假设：NFSv4 的 lease 机制导致状态丢失，产生 ESTALE

| 检查项 | 操作 | 结论 |
|--------|------|------|
| NFS 版本确认 | 检查 `/proc/mounts` 挂载参数 | ✅ `vers=3` —— 明确使用 NFSv3，无 NFSv4 lease 机制 |
| NFSv4 会话确认 | 检查 `/proc/net/rpc/nfs4.0/` 目录是否存在 | ✅ 目录不存在，无活跃 NFSv4 会话 |

**❌ 排除**：NFSv3 没有 lease 机制，此假设不适用。

---

#### 假设 B：网络层面丢包导致 RPC 超时

> 🧪 假设：网络抖动或链路质量问题导致 RPC 请求丢失，客户端误判为文件句柄问题

| 检查项 | 操作 | 结论 |
|--------|------|------|
| RPC 重传统计 | `nfsstat -r` 查看 retrans 计数 | ✅ `retrans=0` —— RPC 层无重传 |
| xprt 传输统计 | 检查 mountstats 中 xprt 字段 | ✅ 无异常传输错误计数 |

**❌ 排除**：RPC 层 retrans=0，无网络层丢包。服务端返回的是明确的 `NFS3ERR_STALE` 错误码，而非超时。

---

#### 假设 C：rpc.statd/lockd 异常

> 🧪 假设：NFS 锁管理服务异常导致文件句柄问题

| 检查项 | 操作 | 结论 |
|--------|------|------|
| rpc.statd 进程状态 | 检查容器内 rpc.statd PID | ✅ 正常运行（PID 45） |
| statd 目录 | 检查 statd 状态目录 | ✅ 正常 |
| 文件锁状态 | 检查 `/proc/locks` 中 NFS 条目 | ✅ 无 NFS 文件锁 |

**❌ 排除**：rpc.statd 正常运行，无文件锁问题，NFSv3 锁机制（NLM）非本次故障相关因素。

---

#### 假设 D：客户端缓存不一致（attr cache）

> 🧪 假设：NFS 属性缓存导致客户端使用过期文件信息

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 缓存配置 | 挂载参数中 acregmin/acregmax 值 | ✅ 默认缓存参数（acregmin=3, acregmax=60） |
| 错误类型分析 | ESTALE 是否属于缓存问题 | ✅ ESTALE 是服务端明确返回的错误码，非缓存不一致 |

**❌ 排除**：ESTALE 不是缓存问题，而是服务端通过 RPC 协议明确返回的 `NFS3ERR_STALE` 错误码。属性缓存可能导致短暂数据不一致，但不会产生 ESTALE。

---

#### 假设 E：soft mount 导致静默失败

> 🧪 假设：挂载参数为 soft，超时后静默返回 EIO

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 挂载参数确认 | 检查 `/proc/mounts` | ✅ `hard` 挂载（非 `soft`） |
| 错误表现 | 应用是否收到 EIO 或 ESTALE | ✅ 明确收到 ESTALE，非静默 EIO |

**❌ 排除**：挂载参数为 `hard`（非 `soft`），且错误类型为 ESTALE 而非 EIO。

---

#### 假设 F：NFS 服务端文件删除 + NFSD 重启导致 filehandle 过期 ✅ 确认根因

> 🧪 假设：NFS 服务端在客户端持有 fd 期间，删除文件并重启 NFSD，导致 filehandle 映射失效

**证据 1 — NFSD 多次重启**

dmesg 日志显示在故障窗口前后 NFSD 发生至少 11 次重启：
```
[Sun Jun  7 18:35:16 2026] → 第 1 次 NFSD 重启
[Sun Jun  7 18:36:09 2026] → 第 2 次 NFSD 重启
[Sun Jun  7 18:37:25 2026] → 第 3 次 NFSD 重启
[Sun Jun  7 18:37:48 2026] → 第 4 次 NFSD 重启
[Sun Jun  7 18:39:38 2026] → 第 5 次 NFSD 重启
[Sun Jun  7 18:44:54 2026] → 第 6 次 NFSD 重启
...
```
**证据来源**：`kuafu_T1_stale_handle.md:43-58`

**证据 2 — 文件被删除后重建**

服务端上 `persist.txt` 在 2026-06-07 18:43:31 被重建，inode 变为 393558：
```
$ stat /mnt/nfs-test/stale-test/persist.txt
  File: /mnt/nfs-test/stale-test/persist.txt
  Size: 24   Inode: 393558
  Modify: 2026-06-07 18:43:31.329385578 +0000

$ cat /mnt/nfs-test/stale-test/persist.txt
NEW_DATA_AFTER_RECREATE
```
**证据来源**：`kuafu_T1_stale_handle.md:233-238`

**证据 3 — 客户端 RPC 超时序列**

hard mount 模式下客户端持续重试，8 次 `timed out` 表明文件操作持续失败：
```
2026-06-07 19:01:46  timed out (1/8)
2026-06-07 19:02:01  timed out (2/8)
...
2026-06-07 19:03:03  timed out (8/8)
```
**证据来源**：`kuafu_T1_stale_handle.md:56`

**证据 4 — NFSv3 协议层面机理**

NFSv3 使用文件句柄（filehandle）唯一标识文件，包含 `fsid + inode + generation` 三要素：
- 文件被删除 → inode 被释放
- NFSD 重启 → 服务端重建 filehandle 映射表（无持久化存储）
- 文件重建 → 新 inode（393558），与客户端持有的旧 filehandle 不匹配
- 客户端携带旧 fh 发起 RPC → 服务端查找失败 → 返回 `NFS3ERR_STALE (70)`
- 内核 NFS 客户端将 `NFS3ERR_STALE` 转换为用户态 `ESTALE`

**证据来源**：`kuafu_T1_stale_handle.md:80-98`

**✅ 结论：服务端在客户端持有 fd 期间执行文件删除 + NFSD 重启，导致 filehandle 映射失效，客户端收到 ESTALE 错误。** 双轨分析（系统状态逆向 + 协议正向）完全吻合，交叉验证通过。

---

### 3.3 排查结论

```text
NFS ESTALE (Stale file handle)
├─► 假设 A: NFSv4 lease 过期问题       → ✅ 排除 — vers=3，无 NFSv4 lease
├─► 假设 B: 网络层丢包导致 RPC 超时     → ✅ 排除 — retrans=0，无重传
├─► 假设 C: rpc.statd/lockd 异常       → ✅ 排除 — statd 正常，无文件锁
├─► 假设 D: 客户端缓存不一致           → ✅ 排除 — ESTALE 非缓存问题
├─► 假设 E: soft mount 静默失败        → ✅ 排除 — hard 挂载，错误为 ESTALE
└─► 假设 F: 服务端文件删除 + NFSD 重启  → 🎯 根因确认 — 高置信度
        ├─► NFSD 重启 11+ 次           → ✅ dmesg 确认
        ├─► persist.txt 被删除重建      → ✅ 新 inode 393558 确认
        ├─► 客户端 8 次 timed out       → ✅ dmesg 确认
        ├─► 协议层 fh 过期机制           → ✅ NFSv3 协议分析确认
        └─► 🎯 根因结论：服务端 rm + NFSD restart → filehandle 过期 → ESTALE
```

---

## 四、修复方案

### 4.1 应急处置

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 应用层关闭旧 fd 并重新 `open()` 文件获取新 filehandle | 应用开发者 / 运维 | 故障发现后立即执行 | 恢复对该文件的正常访问 |
| 2 | 重新挂载 NFS 文件系统（若无法逐个进程修复）：`umount /mnt/nfs-test && mount -t nfs -o vers=3,hard,proto=tcp,timeo=600,retrans=2 nfs-server:/exports /mnt/nfs-test` | 系统管理员 | 确认业务进程可容忍中断后 | 清除所有旧 filehandle 缓存 |

**应急处置脚本参考（应用层 ESTALE 重试处理）：**

```c
retry:
    ret = read(fd, buf, len);
    if (ret < 0 && errno == ESTALE) {
        close(fd);
        fd = open(path, O_RDONLY);
        if (fd >= 0) goto retry;
    }
```

### 4.2 永久修复计划

| 修复措施 | 负责人 | 完成时间 |
|--------|------|--------|
| 应用层增加 ESTALE 错误处理逻辑：捕获 `ESTALE` 后执行 `close(fd)` → 重新 `open()` → 重试操作 | 应用开发团队 | 下一次迭代 |
| 运维流程优化：在 NFS 服务端执行文件变更或 NFSD 重启前，先通知所有 NFS 客户端释放文件句柄 | 系统运维团队 | 立即执行 |
| 调研 NFSv4 迁移可行性：利用 NFSv4 的 lease 管理和状态恢复机制，降低类似风险 | 系统架构团队 | 长期规划 |

### 4.3 预防措施

- **监控告警**：
  - 监控 `nfsstat -c` 中 ESTALE 计数变化（`nfsstat -c | grep stale`）
  - 监控 dmesg 中 `NFS3ERR_STALE` 或 `ESTALE` 关键字
  - 设置告警：任何 NFS ESTALE 错误出现即触发通知

- **巡检建议**：
  - 定期检查 `/proc/self/mountstats` 中 per-op 统计是否有异常错误计数
  - 检查 `dmesg | grep -i stale` 确认无累积 ESTALE 错误
  - 检查服务端 NFSD 重启历史，排查频繁重启原因

---

## 五、验证建议

### 如何确认根因

1. 在客户端进程持有 fd 期间，在服务端执行 `rm <file> && systemctl restart nfs-server` 或 `exportfs -r`
2. 尝试通过客户端 `/proc/PID/fd/` 读取该文件，确认返回 `ESTALE`
3. 检查服务端返回的 RPC 错误应为 `NFS3ERR_STALE (70)`
4. 检查客户端 dmesg 中应出现 `nfs: server nfs-server not responding` 等日志

### 如何验证修复有效

1. 应用层增加 ESTALE 捕获后，触发相同场景
2. 确认应用能够自动 `close(fd)` + `open()` 重建 filehandle 并恢复操作
3. 确认 `/proc/PID/fd/` 重新指向新 inode，且读取内容为重建后的数据

---

## 六、附加资料

### 关键证据文件引用

| 证据内容 | 来源 |
|---------|------|
| 完整诊断报告（含双轨分析、命令清单、原始输出） | `/home/win11/.witty-diagnosis-agent/dayu/report/kuafu_T1_stale_handle.md` |

### 核心诊断命令

| 命令 | 用途 |
|------|------|
| `docker exec nfs-fault-client bash /diagnosis-scripts/branch_B_stale_handle.sh /mnt/nfs-test /mnt/nfs-test/stale-test` | ESTALE 分支诊断 |
| `docker exec nfs-fault-client dmesg -T \| grep -E "NFS\|rpc\|nfs-server"` | 时序日志确认 |
| `docker exec nfs-fault-client stat /mnt/nfs-test/stale-test/persist.txt` | 文件状态与 inode 确认 |
| `docker exec nfs-fault-client nfsstat -c` | 客户端错误统计 |
| `docker exec nfs-fault-client cat /proc/self/mountstats` | mountstats 详细统计 |
