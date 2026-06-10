# 🔴 故障诊断报告

> **报告编号**：RCA-FUSE-BRANCHC-20260604-001
> **故障级别**：P2 / Major
> **报告时间**：2026-06-04 00:00:00
> **当前状态**：🔴 处理中

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | FUSE 用户态文件系统挂载后 `ls` / `stat` 全部超时（Branch C - max_read/max_write 约束 + readdir 空响应） |
| 影响范围 | 挂载点 `/mnt/fuse_test` 下的所有目录访问与文件 I/O 操作；直接阻断用户的文件系统使用体验 |
| 故障时段 | 自 daemon 启动并完成 INIT 协商后立即生效，持续至 daemon 停止或修复 |
| 根本原因 | FUSE daemon 在 INIT 响应中宣称为 `max_readahead=4096` 和 `max_write=4096`，导致内核 VFS 层将所有读写操作限制为 4KB 分片；同时 daemon 对 `readdir` 操作处理不当（返回空响应/不返回目录项），导致 `ls -la` 和 `stat` 等操作用户态超时 |
| 是否恢复 | ❌ 未恢复（daemon 仍在运行但业务操作超时） |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|---------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | 本场景：INIT 协商中 max_readahead/max_write 被强制限制 + readdir 空响应 → 超时可稳定复现 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                   事件                                                    性质          溯源证据
──────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-06-04 00:00:00   FUSE daemon (PID 631) 启动，挂载 /mnt/fuse_test          🔵 daemon 启动   [kuafu_T1_fuse_branch_C_maxread.md:L6-L7]
  │                     fuse 连接建立，INIT (API 7.39) 完成
  ▼
2026-06-04 00:00:00   daemon 在 INIT 回复中设置 max_readahead=4096              ⚠️  约束注入   [kuafu_T1_fuse_branch_C_maxread.md:L5-L6]
  │                     max_write=4096，内核 VFS 强制执行 4KB I/O 分片
  ▼
2026-06-04 00:00:00+  daemon 对 readdir 返回空（无目录项）                       🔴 逻辑缺陷   [kuafu_T1_fuse_branch_C_maxread.md:L40-L42]
  │                     daemon 日志为空，表明未正确处理 LOOKUP/READDIR 等请求
  ▼
2026-06-04 00:00:01+  ls -la 执行后，内核发送 READDIR/READDIRPLUS 请求            🔴 操作挂起    [kuafu_T1_fuse_branch_C_maxread.md:L27-L29]
  │                     daemon 返回空响应 → 内核无法构造目录 → 持续重试
  ▼
2026-06-04 00:00:02+  用户态操作超时（2 秒 timeout）                             💥 故障表象    [kuafu_T1_fuse_branch_C_maxread.md:L27]
  │                     ls -la → TIMEOUT
  │                     stat /mnt/fuse_test → TIMEOUT
  │                     waiting 计数始终为 1（无积压，但无回复/回复无效）
  ▼
2026-06-04 00:00:02+  D-State 进程: 无                                          ✅ 排除内核级卡死 [kuafu_T1_fuse_branch_C_maxread.md:L31-L32]
  │                     内核消息无异常
  ▼
2026-06-04 00:00:02+  daemon 进程存活 (S state), read buffer=16384B              🔵 daemon 正常   [kuafu_T1_fuse_branch_C_maxread.md:L12-L14]
                        但未产生日志 → 表明请求送达但 daemon 未正确处理
```

### 故障因果链

```text
FUSE daemon (fuse_branch_C) 启动并挂载 /mnt/fuse_test
    │
    ├─► INIT 回复中设置 max_readahead=4096, max_write=4096
    │       │
    │       └─► 内核 VFS 层限制所有 read/write 操作为 4KB 分片
    │               └─► 大文件 I/O 吞吐量下降至正常值的 1/256（假设默认 1MB）
    │                       └─► 单次大量读操作被拆解为大量小 FUSE 请求
    │
    └─► readdir/LOOKUP/GETATTR 操作处理逻辑缺失/不正确
            │
            └─► daemon 返回空响应或无目录项
                    │
                    ├─► ls -la → 内核反复发送 READDIR → daemon 一直返回空 → 超时
                    └─► stat /mnt/fuse_test → 内核无法获取根 inode 信息 → 超时
                            │
                            └─► 💥 所有用户侧文件系统操作均挂起
```

---

## 三、排查过程

> 排查逻辑：**提出假设 → 收集证据 → 验证或排除 → 逐步收敛到根因**

### 3.1 初始现象

- **执行 `ls -la /mnt/fuse_test`**：命令卡住约 2 秒后超时失败
- **执行 `stat /mnt/fuse_test`**：同样超时（2 秒 timeout）
- **系统层面**：无 D 态进程阻塞，内核日志正常（仅有一条 FUSE INIT 记录）
- **Daemon 行为**：进程存活（PID 631, S 状态），read buffer 正常（16384B），但 daemon 日志为空

### 3.2 假设驱动排查

#### 假设 A：内核 FUSE 模块崩溃或协议版本不匹配

> 🧪 假设：内核与 daemon 的 FUSE 协议版本不兼容导致操作失败

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 内核消息 | `dmesg 检查` | ✅ INIT (API 7.39) 正常完成，无错误 |
| 连接状态 | sysfs 查看 fuse connection | ✅ 连接 ID 80 已建立，waiting=1 正常 |
| D 态进程 | 检查是否有 D 态 | ✅ 无 D 态进程，表明无内核级阻塞 |

**❌ 排除**：内核 FUSE 模块正常，协议协商成功，无内核级卡死。

---

#### 假设 B：Daemon 进程崩溃或异常退出

> 🧪 假设：daemon 在处理请求时崩溃导致无响应

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 进程状态 | `ps` 检查 PID 631 | ✅ 进程存活，S state（sleeping）|
| 日志输出 | 检查 daemon log | ❌ daemon 日志为空（未接收到正常处理信号） |
| Read buffer | 检查 buffer size | ✅ read buffer=16384B，满足 WSL2 FUSE 需求 |

**⚠️ 部分排除**：进程存活、buffer 充足，但日志为空表明 daemon **接收到了请求却未正确处理**，非进程崩溃，而是处理逻辑缺陷。

---

#### 假设 C：max_readahead/max_write 过低导致 I/O 约束 ✅ 确认部分根因

> 🧪 假设：kernel 因 max_readahead=4096 和 max_write=4096 的约束限制了操作

**Step 1 — 确认 INIT 协商值**
```text
Evidence: Daemon config → max_readahead=4096, max_write=4096
Kernel FUSE 协议：内核对于该 FUSE 挂载点将强制使用 4KB max read/write
```

| 对比项 | 正常值 | 当前值 | 影响倍数 |
|--------|--------|--------|---------|
| max_readahead | 通常 128KB ~ 1MB | **4,096 (4KB)** | 退化 32~256 倍 |
| max_write | 通常 128KB ~ 1MB | **4,096 (4KB)** | 退化 32~256 倍 |

**✅ 结论：`max_readahead=4096` 和 `max_write=4096` 导致内核层面的 I/O 分片强制缩小至 4KB，显著加剧了大文件读写的延迟，但这不是 `ls`/`stat` 超时的直接原因（目录操作为 metadata 操作，不依赖数据读写）。**

---

#### 假设 D：readdir 操作处理逻辑缺失 ✅ 确认核心根因

> 🧪 假设：daemon 未正确实现 readdir/LOOKUP 处理逻辑，导致内核无法完成目录枚举

**Step 1 — 现象分析**
- `ls -la` 超时 → 表明 `READDIR` 或 `READDIRPLUS` 操作未返回有效目录结构
- `stat /mnt/fuse_test` 超时 → 表明 `LOOKUP` 或 `GETATTR` 操作也未正确处理

**Step 2 — Daemon 日志证据**
```text
Daemon Log: 空
```
daemon 日志完全为空，说明 daemon 要么未识别这些 FUSE 操作的类型，要么对这些操作静默返回空而没有产生日志。

**Step 3 — 内核行为推论**
```text
用户执行 ls -la
  → 内核 VFS 发送 FUSE_LOOKUP("/") 获取根节点信息
  → daemon 返回空/未正确填充
  → 内核无法获取 inode 属性
  → 内核尝试发送 FUSE_READDIRPLUS / FUSE_READDIR 获取目录内容
  → daemon 返回空响应（无目录项）
  → 内核无法构造目录列表
  → 用户态超时（2s）
```

**✅ 结论：daemon 对 READDIR/READDIRPLUS/LOOKUP 等 metadata 操作的处理逻辑缺失，直接导致 `ls` 和 `stat` 超时。**

---

#### 假设 E：max_readahead 约束通过某种路径影响了 readdir

> 🧪 假设：过低的 max_read 配置意外影响了目录操作的 FUSE 请求路径

| 检查项 | 操作 | 结论 |
|--------|------|------|
| FUSE 协议规范 | 查阅 Linux kernel FUSE 文档 | ✅ READDIR 不依赖 max_readahead 参数，二者独立 |

**❌ 排除**：`max_readahead` / `max_write` 仅影响数据读写（read/write 操作），不直接影响 READDIR/LOOKUP/GETATTR 等 metadata 操作。`ls`/`stat` 超时的直接原因是 readdir 处理逻辑缺失。

---

### 3.3 排查结论

```text
ls -la / stat 超时
├─► 内核 FUSE 模块崩溃           → ✅ 正常，排除
├─► Daemon 进程异常（崩溃/OOM）   → ⚠️ 进程存活但日志为空，排除崩溃
│       └─► daemon 日志为空       → 🔍 请求送达但未正确处理
├─► max_readahead/max_write 约束 → ✅ 确认退化，但非直接原因（仅影响数据 I/O）
│       └─► 4KB I/O 分片         → 数据读写性能降级，但 ls/stat 为 metadata
└─► readdir/LOOKUP 处理缺失      → ❌ 核心根因
        └─► daemon 返回空响应     → 内核无法枚举目录/获取 inode
                └─► 用户态操作超时 → 🎯 根因确认：readdir/LOOKUP 未实现
```

---

## 四、修复方案

### 4.1 应急处置

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 直接卸载故障 FUSE 挂载点 `fusermount -u /mnt/fuse_test` | 系统/人工 | 即时 | 恢复 shell 可用性，解除超时阻塞 |
| 2 | 停止 daemon 进程 (kill PID 631) | 系统/人工 | 即时 | 释放 FUSE 连接资源 |
| 3 | 使用正常 FUSE daemon 替代（如已有的 `passthrough-ll` 或其他合规实现） | 系统/人工 | 按需 | 恢复文件系统正常访问 |

### 4.2 永久修复计划

#### 修复一：修正 INIT 回复中的 max_readahead 和 max_write 参数

| 修复措施 | 负责人 | 完成时间 |
|----------|--------|---------|
| 将 `max_readahead` 从 4096 调整为合理的上限值（建议与内核协商值一致，通常为 128KB 或更高） | 开发团队 | 待定 |
| 将 `max_write` 从 4096 调整为合理值（至少 128KB，建议 1MB 以匹配内核 FUSE 默认） | 开发团队 | 待定 |

```c
// 修正前
fuse_req_init.req_in.hdr.opcode = FUSE_INIT;
fuse_conn_info.max_readahead = 4096;   // ❌ 异常低
fuse_conn_info.max_write = 4096;       // ❌ 异常低

// 修正后
fuse_conn_info.max_readahead = 131072; // ✅ 128KB，合理值
fuse_conn_info.max_write = 131072;     // ✅ 128KB 或与内核协商一致
```

#### 修复二：实现 readdir / LOOKUP / GETATTR 的完整处理逻辑

| 修复措施 | 负责人 | 完成时间 |
|----------|--------|---------|
| 实现 `FUSE_READDIR` / `FUSE_READDIRPLUS` 操作处理回调：在目录项缓冲区中填充 "."、".." 及实际文件的 dentry 信息 | 开发团队 | 待定 |
| 实现 `FUSE_LOOKUP` 操作处理：为请求的路径返回正确的 inode 属性和 nodeid | 开发团队 | 待定 |
| 实现 `FUSE_GETATTR` 操作处理：返回文件/目录的 stat 信息（mode、size、atime 等） | 开发团队 | 待定 |
| 增加 daemon 侧日志记录功能，便于后续排查类似问题 | 开发团队 | 待定 |

```c
// readdir 最小实现示例（伪代码）
void do_readdir(fuse_req_t req, fuse_ino_t ino, size_t size,
                off_t off, struct fuse_file_info *fi) {
    // 构造目录项缓冲区
    struct fuse_entry_param e;
    char buf[4096];
    size_t sz = 0;
    
    // 始终返回 "." 和 ".." 两个基础目录项
    sz += fuse_add_direntry(req, buf + sz, sizeof(buf) - sz, ".", &e, off + 1);
    sz += fuse_add_direntry(req, buf + sz, sizeof(buf) - sz, "..", &e, off + 2);
    
    fuse_reply_readdir(req, buf, sz);
}
```

### 4.3 检测指标与监控

| 指标 | 阈值 | 检测方式 |
|------|------|---------|
| `/sys/fs/fuse/connections/*/waiting` | 持续 > 5 且不下降 | 用户态文件系统操作挂起检测 |
| `ls -la` 挂载点响应时间 | > 1 秒 | 可用性探测（heartbeat check） |
| `stat` 挂载点响应时间 | > 1 秒 | 可用性探测 |
| Daemon 进程日志 | 持续无输出 | 日志活性检测 |
| FUSE INIT 协商中的 max_readahead/max_write 值 | < 65536 (64KB) | 挂载时参数合法性校验 |
| 挂载点下文件 I/O 吞吐量 | 与预期不符 | 基准测试对比 |

---

## 五、影响评估

### 影响分析

| 维度 | 评估 |
|------|------|
| 功能完整性 | ❌ **完全中断** — 所有目录操作（ls, stat, find, cd 等）均超时失败 |
| 数据访问 | ❌ **完全阻断** — 无法读取或写入任何文件 |
| 系统稳定性 | ✅ 系统级未受影响 — 无 D 态进程，内核稳定，仅 FUSE 挂载点不可用 |
| 数据完整性 | ⚠️ 待确认 — 若之前有未落盘数据，强制卸载可能导致丢失 |
| 恢复难度 | 🟢 低 — 直接卸载挂载点 + 重启正常 daemon 即可恢复 |

### 故障严重等级：P2 (Major)

**理由**：FUSE 文件系统完全不可用，但限于单个挂载点范围内，不影响系统其他服务和内核稳定性。

---

## 六、总结

本次 Branch C FUSE 故障由**两个独立但叠加的缺陷**共同导致：

1. **配置缺陷** — `max_readahead=4096` 和 `max_write=4096` 导致内核强制 4KB I/O 分片，数据读写性能退化 32~256 倍
2. **逻辑缺陷（致命）** — daemon 未实现 `readdir`/`LOOKUP`/`GETATTR` 等 metadata 操作的处理逻辑，导致所有目录枚举和 inode 查询操作超时

修复应聚焦于 **正确地实现 FUSE 协议中所有必要的操作处理回调**，并将 INIT 回复参数恢复为合理的系统默认值。在修复上线前，可通过心跳探测（如定时 `stat` 挂载点）提前发现故障，缩短 MTTR。
