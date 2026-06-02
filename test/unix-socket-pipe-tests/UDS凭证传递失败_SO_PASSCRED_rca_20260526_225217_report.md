# 🔴 故障诊断报告

> **报告编号**: RCA-20260526-001
> **故障级别**: P2（功能缺陷 — 认证/鉴权失效）
> **报告时间**: 2026-05-26 22:52:17
> **当前状态**: 🟡 待修复（根因已确认，修复方案明确）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | Unix Domain Socket 凭证传递失败 — 子进程未设置 SO_PASSCRED 导致 SCM_CREDENTIALS 被内核丢弃 |
| 影响范围 | 基于 socketpair() 通信且依赖 SCM_CREDENTIALS 进行对端身份认证的进程间通信场景 |
| 故障时段 | 程序首次运行时持续存在（每次 recvmsg 均失败，为确定性行为） |
| 根本原因 | 子进程在 recvmsg() 前未调用 `setsockopt(fd, SOL_SOCKET, SO_PASSCRED, &on, sizeof(on))`，导致内核在接收辅助数据前直接丢弃 SCM_CREDENTIALS |
| 是否恢复 | ❌ 未恢复（代码缺陷，需修改源码后重新编译部署） |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|---------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | 子进程未设置 SO_PASSCRED → 程序输出 + strace + 内核源码路径三重证据链验证 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                                     事件                                                    性质          溯源路径
──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-05-26 22:47:00   父进程 socketpair(AF_UNIX, SOCK_DGRAM, 0, sv) 创建一对 socket              🟢 正常行为     [C:\Users\86135\.witty-diagnosis-agent\dayu\report\kuafu_T1_20260526_225047.md:142]
  │
  ▼
2026-05-26 22:47:00   fork() 创建子进程                                                           🟢 正常行为     [kuafu_T1_20260526_225047.md:143]
  │
  ▼
2026-05-26 22:47:00   父进程 close(sv[0])，保留 sv[1] 作为发送端                                  🟢 正常行为     [kuafu_T1_20260526_225047.md:144]
  │                   子进程 close(sv[1])，保留 sv[0] 作为接收端                                  🟢 正常行为     [kuafu_T1_20260526_225047.md:145]
  │
  ▼
2026-05-26 22:47:00   父进程 sendmsg() 发送 18 字节 + SCM_CREDENTIALS（pid=2863, uid=1000, gid=1000） 🟢 发送成功    [kuafu_T1_20260526_225047.md:40-48]
  │                   msg_controllen=32，凭证数据正确封装
  │
  ▼
2026-05-26 22:47:00   ★ 子进程 recvmsg() 收到 18 字节数据                                        ⚠️ 关键节点     [kuafu_T1_20260526_225047.md:51-56]
  │                   → 但子进程未执行 setsockopt(sv[0], SOL_SOCKET, SO_PASSCRED, &on, sizeof(on))
  │                   → 内核检测 sk_passcred==0，丢弃 SCM_CREDENTIALS 辅助数据
  │                   → msg_controllen=0，凭证丢失
  │
  ▼
2026-05-26 22:47:00   [child] ❌ 没有收到 SCM_CREDENTIALS!                                       🔴 故障爆发     [kuafu_T1_20260526_225047.md:24-28]
  │                   [child] 原因: SO_PASSCRED 未设置, 内核丢弃了辅助数据
  │
  ▼
后续影响                 业务逻辑无法验证对端身份，认证/鉴权完全失效                                 🔴 持续影响     [kuafu_T1_20260526_225047.md:151]
```

### 故障因果链

```text
socketpair() 创建通信对
    └─► fork() 创建父子进程，分持 sv[1]（发）和 sv[0]（收）
            └─► 父进程 sendmsg() 正确构造 SCM_CREDENTIALS（pid/uid/gid）
                    └─► 子进程 recvmsg() 前未设置 SO_PASSCRED
                            └─► 内核 unix_stream_recvmsg() 检查 sk->sk_passcred == 0
                                    └─► scm_recv() → __scm_recv_common() 跳过辅助数据接收
                                            └─► msg_controllen = 0，凭证被内核丢弃
                                                    └─► 🔴 子进程无法获取对端身份，认证/鉴权完全失效
```

---

## 三、排查过程

### 3.1 初始现象

- **程序输出表明**：父进程声明"发送 18 字节 + SCM_CREDENTIALS OK"，子进程声明"收到 18 字节数据"但"没有收到 SCM_CREDENTIALS"
- **子进程明确提示**："SO_PASSCRED 未设置, 内核丢弃了辅助数据"
- **行为确定性**：每次运行均复现，非偶发性问题

### 3.2 假设驱动排查

#### 假设 A：父进程发送的 SCM_CREDENTIALS 构造错误

> 🧪 假设：父进程 sendmsg() 的 msg_control 参数构造有误，导致内核无法解析凭证

| 检查项 | 操作 | 结论 |
|--------|------|------|
| sendmsg 参数验证 | strace 捕获 sendmsg 调用，检查 msg_control 结构 | ✅ 正确：`cmsg_level=SOL_SOCKET, cmsg_type=SCM_CREDENTIALS, cmsg_data={pid=2863, uid=1000, gid=1000}`，`msg_controllen=32` |
| 内核接收路径 | 父进程返回 0（成功），无错误码 | ✅ 发送端无异常 |

**❌ 排除**：父进程发送构造正确，非发送端问题。

---

#### 假设 B：socket 类型不支持凭证传递

> 🧪 假设：socketpair 创建的 socket 类型不支持 SCM_CREDENTIALS

| 检查项 | 操作 | 结论 |
|--------|------|------|
| socket 类型 | socketpair(AF_UNIX, SOCK_DGRAM, 0, sv) — 使用 Unix Domain Socket + DGRAM 类型 | ✅ Unix Domain Socket 原生支持 SCM_CREDENTIALS（af_unix.c 实现） |
| 内核支持 | Linux 内核 unix 模块支持凭证辅助数据传递 | ✅ 标准支持，非定制内核 |

**❌ 排除**：socket 类型原生支持 SCM_CREDENTIALS。

---

#### 假设 C：子进程未设置 SO_PASSCRED ✅ 确认根因

> 🧪 假设：根据 Linux 内核 unix socket 实现，接收方必须在 recvmsg 前通过 SO_PASSCRED 选项告知内核"我需要凭证"

**Step 1 — 程序日志确认**

```
[child  ] ★ 注意: 未设置 SO_PASSCRED!
[child  ] ❌ 没有收到 SCM_CREDENTIALS!
[child  ] 原因: SO_PASSCRED 未设置, 内核丢弃了辅助数据
```

**Step 2 — strace 系统调用级确认**

父进程 sendmsg：
```
2863 sendmsg(4, {msg_control=[{cmsg_len=28, cmsg_level=SOL_SOCKET,
    cmsg_type=SCM_CREDENTIALS, cmsg_data={pid=2863, uid=1000, gid=1000}}],
    msg_controllen=32, ...}, 0) = 18
```

子进程 recvmsg：
```
2864 recvmsg(3, {msg_controllen=0, msg_flags=0}, 0) = 18
                              ^^^^^^^^^^^^^^^^ ← 关键：辅助数据长度为 0！
```

**结论**：父子进程在相同 socketpair 上通信，发送端明确携带 32 字节辅助数据，但接收端 `msg_controllen=0` → 凭证已被内核丢弃。

**Step 3 — 内核源码路径分析**

```c
// net/unix/af_unix.c — unix_stream_recvmsg() / unix_dgram_recvmsg()
// 内核在接收辅助数据前检查：
if (!sock->sk->sk_passcred) {
    // sk_passcred 通过 setsockopt(SO_PASSCRED) 设置
    // 若为 0，内核跳过 SCM_CREDENTIALS 辅助数据的传递
    ...直接丢弃...
}
```

**Step 4 — 缺失的关键代码**

```c
// 子进程 recvmsg 前应当执行：
int on = 1;
setsockopt(sv[0], SOL_SOCKET, SO_PASSCRED, &on, sizeof(on));
```

**✅ 结论：子进程在 recvmsg() 前未设置 SO_PASSCRED 选项，导致内核 unix socket 模块在 scm_recv() 路径中丢弃了 SCM_CREDENTIALS 辅助数据，msg_controllen=0，对端身份无法验证。**

---

### 3.3 排查结论

```text
子进程 recvmsg 未收到 SCM_CREDENTIALS
├─► 假设 A：父进程发送构造错误    → ❌ 排除（strace 证实发送正确）
├─► 假设 B：socket 类型不支持     → ❌ 排除（AF_UNIX + SOCK_DGRAM 原生支持）
└─► 假设 C：SO_PASSCRED 未设置   → ✅ 确认根因
        ├─► 程序日志：子进程明确打印"未设置 SO_PASSCRED"
        ├─► strace：父进程 msg_controllen=32，子进程 msg_controllen=0
        ├─► 内核路径：sk_passcred==0 → scm_recv() 丢弃辅助数据
        └─► 🎯 根因锁定：编码遗漏 setsockopt(SO_PASSCRED)
```

---

## 四、修复方案

### 4.1 应急处置（临时方案）

当前为代码缺陷，**无运行时热修复手段**。短期可考虑以下 workaround：

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 在子进程 recvmsg 前通过 gdb 动态注入 setsockopt 调用（仅调试用） | 开发 | 诊断阶段 | 验证修复方向正确性 |
| 2 | 使用 `socat UNIX-LISTEN:/tmp/test.sock,so-passcred -` 验证 SO_PASSCRED 功能可用性 | 开发 | 诊断阶段 | 确认系统层面支持 |

### 4.2 永久修复计划

| 修复措施 | 负责人 | 完成时间 |
|---------|--------|---------|
| 在子进程 recvmsg() 调用前，添加 `setsockopt(sv[0], SOL_SOCKET, SO_PASSCRED, &on, sizeof(on))` 代码 | 应用开发团队 | 待定 |
| 示例修正代码：<br>`int on = 1;`<br>`setsockopt(fd, SOL_SOCKET, SO_PASSCRED, &on, sizeof(on));` | — | — |
| 验证 selinux/apparmor 策略是否阻断了凭证传递（如有强制访问控制） | 安全运维 | 待定 |
| 对同类型 socketpair 通信代码进行全面代码审查，检查是否存在同样遗漏 | 开发团队 | 待定 |
| 参考 `socat UNIX-LISTEN:/tmp/test.sock,so-passcred -` 进行功能验证 | 测试团队 | 待定 |

### 4.3 预防措施

| 措施 | 说明 |
|------|------|
| 代码静态检查规则 | 增加对 socketpair + SCM_CREDENTIALS 场景的静态分析检查，自动检出缺少 SO_PASSCRED 设置的情况 |
| 代码审查 check list | 在 CR checklist 中明确增加 Unix Domain Socket 凭证传递相关检查项 |
| 单元测试覆盖 | 增加 SCM_CREDENTIALS 收发功能的单元测试，确保 recvmsg 后 msg_controllen 正确 |
| 参考规范 | 在 IPC 通信规范文档中明确标注：使用 SCM_CREDENTIALS 时，接收方必须前置调用 setsockopt(SO_PASSCRED) |
