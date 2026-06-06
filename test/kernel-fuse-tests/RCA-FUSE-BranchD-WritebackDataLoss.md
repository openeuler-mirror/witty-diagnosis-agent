# 🔴 故障诊断报告 — FUSE Writeback Cache 静默数据丢失

> **报告编号**：RCA-FUSE-BranchD-20260604-001
> **故障级别**：P1 / Critical
> **报告时间**：2026-06-04 00:00:00
> **当前状态**：🔴 未恢复（故障场景为注入态，需人工修复 daemon 代码后重新挂载）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | FUSE 用户态 daemon 声明 Writeback Cache 能力后静默丢弃写入数据，导致读回全零静默数据损坏 |
| 影响范围 | 挂载点 `/mnt/fuse_test` 下的所有读写操作 |
| 故障时段 | 自 daemon 启动并挂载之时起持续存在（持续性故障） |
| 根本原因 | FUSE daemon `fuse_branch_D_writeback` 在 INIT 阶段声明 `FUSE_WRITEBACK_CACHE` 标志，但 write 回调仅记录长度未实际存储 payload，read 回调固定返回零填充缓冲区 |
| 是否恢复 | ❌ 未恢复（daemon 行为是代码级缺陷，不会自愈） |
| 根因置信度 | 🟢 高置信 — 缺陷代码路径清晰，且所有异常现象均可由单一根因完全解释 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|--------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | 本场景：daemon write handler 缺失 memcpy，属实锤 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                              事件                                                             性质        证据来源
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-06-04 T~00:00:00            daemon fuse_branch_D 启动                                          🚀 进程启动  Kuafu 报告: 9-10
2026-06-04 T~00:00:01            daemon 向内核 INIT 回复中设置 flags |= FUSE_WRITEBACK_CACHE         ⚠️ 隐患植入  Kuafu 报告: 13
                                 告知内核：本 daemon 支持 writeback cache 模式
  │
  ▼
2026-06-04 T~00:00:02            挂载点 /mnt/fuse_test 建立，mount options: rw,relatime              📎 环境准备  Kuafu 报告: 17-18
  │                               Connection ID=80, max_background=12
  ▼
[用户态应用程序开始对挂载点进行文件读写操作]

2026-06-04 T~00:00:XX            应用层 write() 调用 → 内核 FUSE 层                                   📝 写操作
  │                                  由于 FUSE_WRITEBACK_CACHE 启用，内核可能缓存写入
  │                                  同时通过 FUSE 协议将写请求下发给 daemon
  ▼
2026-06-04 T~00:00:XX            daemon write handler 被调用                                          🟡 关键节点  Kuafu 报告: 14
  │                                  handler 记录写入 size，但未执行 memcpy 将 payload
  │                                  复制到后端存储（fake storage）
  │                                  立即返回成功（无错误码）
  ▼
2026-06-04 T~00:00:XX            应用层收到 write() 返回成功                                          ❌ 错误信号
  │                                  应用层确信数据已被持久化
  ▼
2026-06-04 T~00:00:XX            应用层 read() 调用 → 内核 FUSE 层                                   📖 读操作
  │                                  内核可能返回自己缓存的脏数据 (writeback cache 特性)
  │                                  或请求 daemon 读取
  ▼
2026-06-04 T~00:00:XX            daemon read handler 被调用                                          🔴 故障爆发  Kuafu 报告: 15
  │                                  read handler 返回零填充缓冲区（fake storage 从未被写入）
  │                                  无论之前 write 过什么内容，都读到全零
  │                                  同时 FOPEN_KEEP_CACHE 使内核可能返回更早的缓存
  ▼
2026-06-04 T~00:00:XX            `ls -la` / `stat` 超时（TIMEOUT）                                    🔴 故障外显  Kuafu 报告: 26-27
  │                                  readdir 返回空，waiting 计数为 1
  ▼
[持续]                            任何写入 → 静默丢弃 → 读回零/脏缓存                                  🔴 数据全量损坏
```

### 故障因果链

```text
daemon 在 INIT 中声明 FUSE_WRITEBACK_CACHE（告知内核启用写回缓存模式）
    └─► 内核信任此能力声明，启用 writeback cache 路径
            │
            ├─► write handler 被调用时，记录 size 但不复制 payload 到存储
            │       └─► write() 返回成功（无错误码）
            │               └─► 应用层误信数据已持久化
            │
            ├─► FOPEN_KEEP_CACHE|FOPEN_CACHE_DIR 在 open 时设置
            │       └─► 内核可能返回本地缓存的脏数据，与 daemon 真实存储不一致
            │
            └─► read handler 被调用时，无视所有已写内容，固定返回零填充缓冲区
                    └─► 应用层读取到全零数据或过期脏缓存
                            └─► 🔴 静默数据损坏 — 无任何内核/应用层错误日志
```

---

## 三、排查过程

> 排查逻辑：**提出假设 → 收集证据 → 验证或排除 → 逐步收敛到根因**

### 3.1 初始现象

- **挂载点访问异常**：`ls -la /mnt/fuse_test` 返回 TIMEOUT
- **stat 超时**：`stat /mnt/fuse_test` 同样返回 TIMEOUT
- **FUSE 连接 waiting 计数为 1**：表明内核正在等待 daemon 响应某个请求（卡在 readdir 等操作上）
- **无 D 状态进程**：daemon 处于 S 睡眠态，正常响应请求（只是响应内容错误）
- **内核日志正常**：无错误或异常消息，OS 层面无任何告警
- **daemon 日志为空**：daemon 自身未实现日志记录

### 3.2 假设驱动排查

#### 假设 A：FUSE 连接中断或 daemon 异常退出

> 🧪 假设：daemon 崩溃或 FUSE 连接断开导致请求无法处理

| 检查项 | 操作 | 结论 |
|--------|------|------|
| daemon 进程状态 | 查看 Kuafu 报告 "Daemon State" | ✅ S 状态（sleeping），正常存活 |
| FUSE 连接属性 | 查看 sysfs connection ID 80 | ✅ `waiting: 1`，连接存在，仅表明有未完成请求 |
| 内核消息 | 查看 kernel messages | ✅ 无错误，无 panic，无设备移除记录 |

**❌ 排除**：daemon 存活，连接正常，非连接中断问题。

---

#### 假设 B：内核 FUSE 模块异常或挂载参数错误

> 🧪 假设：内核侧 FUSE 实现或挂载参数导致请求无法正确路由

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 挂载选项 | 查看 Kuafu 报告 "Mount Information" | ✅ `rw,relatime,user_id=0,group_id=0` 为标准挂载参数 |
| 内核日志 | 查看 kernel messages | ✅ 正常，无 FUSE 相关错误 |

**❌ 排除**：内核 FUSE 模块工作正常，挂载参数正确。

---

#### 假设 C：Daemon Writeback Cache 实现缺陷 ✅ 确认根因

> 🧪 假设：daemon 声明了 writeback cache 能力，但实际存储实现有缺陷

**Step 1 — 确认 daemon 能力声明**

查看 INIT 阶段行为（Kuafu 报告第 13 行）：
```c
flags |= FUSE_WRITEBACK_CACHE;
```
✅ daemon 明确向内核声明支持 writeback cache 模式。

**Step 2 — 验证 write handler 实现**

查看 write 回调行为（Kuafu 报告第 14 行）：
- 记录写入 size（表明 write 请求已到达 daemon）
- **未执行 memcpy 等数据复制操作**：payload 未被复制到后端 fake storage
- 立即返回成功

**Step 3 — 验证 read handler 实现**

查看 read 回调行为（Kuafu 报告第 15 行）：
- 返回零填充缓冲区
- 无论之前是否发生过 write，数据均为全零

**Step 4 — 验证数据一致性**

- write 返回成功 → 应用认为数据已落盘
- 同一文件 read → 返回全零（或内核缓存脏数据）
- 两次 read 结果可能与预期完全不同 → **无声的数据损坏**

**Step 5 — 确认 open flags 的影响**

Kuafu 报告第 13 行隐含 `FOPEN_KEEP_CACHE | FOPEN_CACHE_DIR`：
- `FOPEN_KEEP_CACHE`：打开文件时不使能内核缓存，即使 daemon 数据已变，内核仍返回旧缓存
- `FOPEN_CACHE_DIR`：对目录内容也启用缓存 → 解释了 `ls -la` 和 `stat` 超时（readdir 返回空导致内核等待/超时）

**✅ 结论：daemon 在 INIT 中声明 `FUSE_WRITEBACK_CACHE`，但 write handler 静默丢弃 payload、read handler 固定返回全零，导致静默数据损坏。根本原因是 daemon 的 write/read 回调实现与能力声明不匹配。**

---

### 3.3 排查结论

```text
挂载点 /mnt/fuse_test 访问异常（ls/stat TIMEOUT）
├─► daemon 存活           → ✅ S 状态，进程正常
├─► 内核 FUSE 连接正常     → ✅ connection ID 80，waiting=1
├─► 内核日志无异常         → ✅ 无报错
├─► 挂载参数正确           → ✅ rw,relatime 标准参数
│
└─► daemon 行为异常        → 🔍 深入分析 daemon 代码逻辑
        │
        ├─► INIT 回复标志   → ❌ 声明了 FUSE_WRITEBACK_CACHE
        ├─► write handler   → ❌ 记录 size，未存储 payload，返回成功
        ├─► read handler    → ❌ 固定返回零填充缓冲区
        └─► open flags      → ❌ FOPEN_KEEP_CACHE | FOPEN_CACHE_DIR 加剧不一致
                │
                └─► 🎯 根因确认：daemon 代码缺陷 — 能力声明与行为严重不匹配
```

---

## 四、修复方案

### 4.1 应急处置

本故障为代码级缺陷，无法通过运维操作在线恢复。需停服后修复 daemon 并重新挂载。

| 步骤 | 操作 | 执行人 | 预期效果 |
|------|------|--------|---------|
| 1 | 卸载挂载点：`umount -f /mnt/fuse_test` | SRE | 断开 FUSE 连接，应用无法继续访问损坏数据 |
| 2 | 检查已写入文件的数据完整性，必要时从备份恢复 | SRE | 确认损坏范围 |
| 3 | 修正 daemon 代码后重新编译、挂载 | 开发 | 恢复服务 |

### 4.2 永久修复计划

#### 修复点 A：Write Handler 补充实际数据存储

```c
// 修复前：仅记录 size，不复制数据
static void my_write(fuse_req_t req, fuse_ino_t ino, const char *buf,
                     size_t size, off_t off, struct fuse_file_info *fi)
{
    // ❌ 仅记录 size，无 memcpy
    recorded_size = size;
    fuse_reply_write(req, size);  // 返回成功但数据已丢
}

// 修复后：将 buf 内容复制到后端存储
static void my_write(fuse_req_t req, fuse_ino_t ino, const char *buf,
                     size_t size, off_t off, struct fuse_file_info *fi)
{
    if (off + size > STORAGE_SIZE) {
        fuse_reply_err(req, ENOSPC);
        return;
    }
    memcpy(fake_storage + off, buf, size);  // ✅ 实际存储数据
    recorded_size = size;
    fuse_reply_write(req, size);
}
```

#### 修复点 B：Read Handler 从实际存储读取

```c
// 修复前：直接返回零填充缓冲区
static void my_read(fuse_req_t req, fuse_ino_t ino, size_t size,
                    off_t off, struct fuse_file_info *fi)
{
    // ❌ 固定返回全零
    fuse_reply_buf(req, zeros, size);
}

// 修复后：从已写入的 fake_storage 读取
static void my_read(fuse_req_t req, fuse_ino_t ino, size_t size,
                    off_t off, struct fuse_file_info *fi)
{
    size_t available = (off < stored_size) ? min(size, stored_size - off) : 0;
    fuse_reply_buf(req, fake_storage + off, available);  // ✅ 返回真实数据
}
```

#### 修复点 C：确认 Writeback Cache 旗标真实性

- 如果 daemon 的真实后端存储**不支持回写语义**（如简单内存缓冲区），**不应**声明 `FUSE_WRITEBACK_CACHE`
- 仅在 daemon 能正确处理 writeback 的异步刷新、page 失效等语义时才启用该标志

#### 修复点 D：增加 Daemon 侧日志与监控

- 建议在 daemon 中添加操作日志（syslog 或文件日志），记录每次 write/read 的 ino、offset、size
- 便于排查后续一致性问题和性能问题

### 修复优先级总表

| 修复措施 | 负责人 | 完成时间 | 优先级 |
|---------|--------|---------|-------|
| Write handler 补充 `memcpy` 存储数据 | 开发 | 立即 | P0 |
| Read handler 返回实际存储内容 | 开发 | 立即 | P0 |
| 确认是否需保留 `FUSE_WRITEBACK_CACHE` 声明 | 开发/架构 | 代码发布前 | P1 |
| 增加 daemon 操作日志 | 开发 | 下一个迭代 | P2 |

---

## 五、检测指标与告警建议

### 后续如何提前发现此类故障

| 检测层面 | 检测手段 | 预期信号 |
|---------|---------|---------|
| 应用层校验 | 写后读校验（write + fsync + read + compare） | 数据不一致，读到全零或乱码 |
| 文件校验和 | 定期对挂载点下文件计算并比对 checksum | checksum 与预期不符 |
| FUSE 协议审计 | 使用 BPF/tracepoint 拦截 FUSE 消息，对比 write 请求 payload 与 read 返回数据 | payload 在传输过程中丢失 |
| Daemon 行为监控 | 监控 daemon 堆内存写入量 vs 应用层写入量 | 长期不增长表明数据未被存储 |
| 故障注入测试 | CI/CD 中注入本类故障场景（声明能力但不实现） | 测试应捕获数据不一致 |
