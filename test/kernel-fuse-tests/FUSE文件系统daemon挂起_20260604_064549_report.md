# 🔴 故障诊断报告

> **报告编号**：RCA-FUSE-HANG-20260604-001
> **故障级别**：P2（特定自定义 FUSE 挂载点完全不可用，影响依赖该挂载点的所有应用）
> **报告时间**：2026-06-04 14:45:49（北京时间，UTC+8）
> **当前状态**：🔴 处理中

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | FUSE 文件系统挂载后 daemon 挂起（应用层 hang），挂载点彻底不可用 |
| 影响范围 | 挂载点 `/mnt/fuse_test` 及其关联的 FUSE 用户态 daemon（PID 405），所有访问该挂载点的进程均被阻塞 |
| 故障时段 | 2026-06-04 14:30:00（约）～ 至今（2026-06-04 14:45:49，未恢复） |
| 根本原因 | FUSE daemon 实现缺陷：完成 INIT 握手后未进入主请求处理循环，而是执行了 `pause()` 导致进程永久休眠，不读取 /dev/fuse 上的 VFS 请求 |
| 是否恢复 | ❌ 未恢复 |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|--------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | FUSE daemon pause() 后不处理请求 → 所有访问均阻塞 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

> **FUSE daemon 代码缺陷 → 进程休眠不处理请求 → VFS 请求积压 → 访问进程全部 D 状态阻塞**

### 事故时间线 & 故障传导链路

```text
时间（UTC+8）           事件                                              性质          溯源路径
──────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-06-04 14:30:00   FUSE daemon 启动（/home/wyh/fuse_hang）             🚀 daemon 启动  [kuafu_T1_fuse_hang_20260604.md:33]
  │                   成功完成 INIT 握手（API 7.39），连接 ID=82
  ▼
2026-06-04 14:30:00   daemon 执行 pause() 进入 S+ 睡眠态                     ⚠️  代码缺陷    [kuafu_T1_fuse_hang_20260604.md:35]
  │                   未进入主循环读取 /dev/fuse
  ▼
2026-06-04 14:30:01   用户尝试访问 /mnt/fuse_test                            📈 首次访问    [kuafu_T1_fuse_hang_20260604.md:42]
  │                   (ls -la /mnt/fuse_test) → 生成 FUSE 请求
  ▼
2026-06-04 14:30:01   请求到达内核 FUSE 层，加入 pending 队列                 🟡 请求积压    [kuafu_T1_fuse_hang_20260604.md:21]
  │                   waiting=1（后增至 2）
  ▼
2026-06-04 14:30:01   VFS 等待 daemon 响应超时                              🔴 故障爆发    [kuafu_T1_fuse_hang_20260604.md:38]
  │                   访问进程（PID 417）进入 D 状态（不可中断睡眠）
  ▼
2026-06-04 14:30:02+  任何访问操作（stat/dd/ls）均被阻塞                      🔴 挂载点不可用 [kuafu_T1_fuse_hang_20260604.md:42-44]
  │                   挂载点完全不可用，dmesg 无任何错误输出
  ▼
2026-06-04 14:45:49   诊断报告采集时刻，故障持续中                            ⏹️ 未恢复      [kuafu_T1_fuse_hang_20260604.md:67]
```

### 故障因果链

```text
FUSE daemon 启动
    │
    ├─► 完成 INIT 握手（API 7.39，连接 ID=82）
    │       └─► 内核 FUSE 连接正常建立
    │
    ├─► daemon 执行 pause() 系统调用（代码缺陷）
    │       └─► 进程进入 S+ 睡眠态，不再执行任何用户态逻辑
    │
    ├─► VFS 层通过 /dev/fuse 下发请求到 FUSE 连接
    │       └─► waiting 计数递增（当前 2 个 pending 请求）
    │       └─► daemon 从未调用 read() 读取请求
    │
    ├─► 请求在 pending 队列中无限等待
    │       └─► 发起请求的用户进程进入 D 状态（TASK_UNINTERRUPTIBLE）
    │
    └─► 🔴 所有访问 /mnt/fuse_test 的操作被无限期阻塞
            └─► 挂载点彻底不可用，无法卸载（设备忙）
```

---

## 三、排查过程

> 排查逻辑：**提出假设 → 收集证据 → 验证或排除 → 逐步收敛到根因**

### 3.1 初始现象

- **现象描述**：FUSE 文件系统挂载于 `/mnt/fuse_test`，`mount -t fuse` 显示挂载成功，但任何访问操作（`ls`、`stat`、`dd`）均被无限期阻塞
- **用户侧表现**：执行 `ls -la /mnt/fuse_test` 后进程挂死，无法终止（进入 D 状态），`kill -9` 无效
- **关键报错**：dmesg 无任何错误或异常日志；FUSE 内核模块初始化正常（API 7.39）

---

### 3.2 假设驱动排查

#### 假设 A：内核 FUSE 模块故障或配置错误

> 🧪 假设：内核 FUSE 模块加载失败，或 /dev/fuse 设备权限/配置异常导致无法通信

| 检查项 | 操作 | 结论 |
|--------|------|------|
| /dev/fuse 设备存在性 | 检查 `ls -l /dev/fuse` | ✅ 设备存在，主次号 10,229 标准设备 |
| 设备权限 | 检查权限位 | ✅ 0666（全局读写），权限正常 |
| 内核模块 | dmesg 检查 | ✅ `fuse: init (API version 7.39)` 正常初始化 |
| mount 状态 | `mount -t fuse` | ✅ 挂载表中有条目 |

**❌ 排除**：内核 FUSE 模块和 /dev/fuse 设备均正常，非内核层问题。

---

#### 假设 B：daemon 进程崩溃或异常退出

> 🧪 假设：daemon 启动后因段错误/SIGKILL 等原因异常退出

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 进程存活 | `ps aux | grep fuse_hang` | ✅ 存活，PID 405 存在 |
| 进程状态 | 分析进程状态标识 | ✅ S+（睡眠态，前台进程组），非 Z（僵尸）或 terminated |
| 父子进程链 | 三进程关联分析 | ✅ sudo nohup 父进程（S/Ss）+ daemon 子进程（S+），结构完整 |

**❌ 排除**：daemon 进程未崩溃，但处于不处理请求的**错误睡眠状态**。

---

#### 假设 C：FUSE daemon 死锁或陷入内核态等待

> 🧪 假设：daemon 在处理请求时陷入死锁（如锁竞争、fd 阻塞读等）

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 内核消息 | dmesg 检查 FUSE 相关输出 | ✅ 无死锁/看门狗/软锁等异常消息 |
| 连接状态 | sysfs 检查 waiting 计数 | ✅ waiting=2（VFS 有请求在等），非 0 |
| abort 状态 | 检查连接是否被中止 | ✅ 连接未被 abort |
| daemon 行为 | `pause()` 特征分析 | ✅ daemon 在 INIT 后未调用 `read(/dev/fuse)`，直接进入 sleep |

**✅ 确认根因**：daemon 未进入主请求处理循环，而是执行了 `pause()` 调用。

---

#### 假设 D：WSL2 虚拟化环境导致的 FUSE 兼容性问题

> 🧪 假设：WSL2 (Hyper-V 虚拟化) 的 FUSE 实现有缺陷或限制

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 内核版本 | uname -r | ✅ 6.6.114.1-microsoft-standard-WSL2，标准 WSL2 内核 |
| 标准 FUSE 接口 | /dev/fuse 主次号 | ✅ 10,229 标准 Linux FUSE 设备号，WSL2 兼容 |
| dmesg 错误 | 检查 WSL2 特有 FUSE 限制 | ✅ 无任何错误或告警 |

**❌ 排除**：WSL2 环境下 FUSE 功能正常，非环境兼容性问题导致。

---

### 3.3 排查结论

```text
FUSE 挂载点不可用
├─► 内核 FUSE 模块/设备        → ✅ 正常，排除
│   ├─► /dev/fuse 设备存在      → ✅ 存在，权限 0666
│   ├─► 内核模块初始化          → ✅ API 7.39，正常
│   └─► mount 表条目            → ✅ 存在，类型 fuse
│
├─► daemon 进程存活             → ✅ 存活，排除崩溃
│   ├─► PID 405 存在            → ✅ 是
│   └─► 进程状态                → ✅ S+（非 Z/终止）
│
├─► 无法通信（死锁/阻塞）       → ❌ waiting=2，daemon 不读取
│   └─► daemon 行为分析         → ❌ pause() 不处理请求
│           └─► 🎯 根因确认：实现缺陷
│
└─► WSL2 环境兼容性             → ✅ 正常，排除
```

---

## 四、根因详细分析

### 4.1 技术根因

FUSE daemon（`/home/wyh/fuse_hang`）的实现存在**逻辑缺陷**：

1. **正常 FUSE daemon 流程**：`fuse_init()` → `fuse_loop()` / `while(read(...))` 持续读取 `/dev/fuse` 处理请求
2. **实际行为**：daemon 完成 INIT 握手后，未调用 `read()` 或 `fuse_session_loop()` 进入主循环，而是执行了 `pause()` 系统调用（或类似的永久阻塞调用），导致进程进入 S+ 睡眠态
3. **后果**：内核 FUSE 连接建立成功（Connection ID=82），但当 VFS 下发请求时，daemon 永远不读取 pending 队列，请求无限积压，访问进程全部 D 状态阻塞

### 4.2 为什么 `kill -9` 也无法终止 D 状态进程？

处于 D 状态（TASK_UNINTERRUPTIBLE）的进程在等待内核 I/O 完成，**无法响应任何信号**（包括 SIGKILL）。这是 Linux 内核为保护数据一致性而设计的机制。只有当 FUSE daemon 处理完 pending 请求后，D 状态进程才会被唤醒。

### 4.3 根本原因总结

| 层面 | 结论 |
|------|------|
| 直接原因 | FUSE daemon 不读取 /dev/fuse，pending 请求无法被处理 |
| 深层原因 | daemon 源码在 INIT 后使用 `pause()` 替代了 `fuse_loop()` / `read()` 循环 |
| 代码定位 | `/home/wyh/fuse_hang` 主流程中 INIT 之后的请求处理循环缺失 |
| 根因类型 | 用户态应用编码缺陷（FUSE daemon 实现不完整） |
| 触发条件 | daemon 启动并完成挂载后，首次 VFS 访问即触发 |
| 是否可复现 | ✅ 是的，重启 daemon 后访问挂载点即可稳定复现 |

---

## 五、修复方案

### 5.1 应急处置

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 强制卸载挂载点：`sudo umount -l /mnt/fuse_test`（lazy umount） | 运维 | 立即 | 断开 VFS 与 FUSE 连接，D 状态进程可被唤醒退出 |
| 2 | Kill FUSE daemon：`sudo kill -9 <PID>` | 运维 | 立即 | 清理残留 daemon 进程 |
| 3 | 恢复对挂载点的访问（移除该挂载项或使用备选方案） | 运维 | 立即 | 恢复业务 |

> **注意**：使用 `umount -l`（lazy umount）可立即断开内核 FUSE 连接，使 D 状态进程收到 I/O 错误从而退出。这是唯一不重启的应急方案。

### 5.2 永久修复计划

| 修复措施 | 负责人 | 完成时间 |
|--------|------|--------|
| **修复 daemon 源码**：在 INIT 握手后补充主请求处理循环，使用 `fuse_loop()` 或 `while(read(/dev/fuse))` 循环持续读取和处理 FUSE 请求 | 开发团队 | 待定 |
| 添加超时保护：daemon 应添加看门狗（watchdog）机制，当请求处理超时时自动重启 | 开发团队 | 待定 |
| 完善日志：在 INIT 和主循环入口添加详细日志，便于后续排查 | 开发团队 | 待定 |
| 代码审查：审查所有 FUSE daemon 相关的代码实现，排查其他潜在的类似缺陷 | 开发团队 | 待定 |

### 5.3 修复后的 daemon 伪代码参考

```c
// 正确实现
int main(int argc, char *argv[]) {
    struct fuse_args args = FUSE_ARGS_INIT(argc, argv);
    struct fuse *fuse = fuse_setup(argc, argv, &mount_point, NULL, NULL);
    if (fuse == NULL) {
        fprintf(stderr, "FUSE setup failed\n");
        return 1;
    }
    
    // ✅ 必须进入主循环处理请求
    int ret = fuse_loop(fuse);  // 或 fuse_session_loop()
    
    fuse_teardown(fuse, mount_point);
    return ret;
}
```

---

## 六、附录

### 6.1 关键证据清单

| 证据项 | 内容概要 | 来源 |
|--------|---------|------|
| 挂载状态 | `/dev/fuse on /mnt/fuse_test type fuse (rw,relatime,...)` | `mount` 命令 |
| 连接状态 | Connection ID=82, waiting=2, max_background=12 | `/sys/fs/fuse/connections/82/` |
| Daemon 进程 | PID 405, S+ 状态, `pause()` 循环 | `ps` / 进程状态分析 |
| 阻塞进程 | PID 417, D 状态（`ls -la /mnt/fuse_test`） | 进程状态分析 |
| 内核日志 | `fuse: init (API version 7.39)` 仅启动消息，无错误 | `dmesg` |
| 设备节点 | `/dev/fuse` 10,229, 权限 0666 | `ls -l /dev/fuse` |

### 6.2 涉及环境

| 环境 | 信息 |
|------|------|
| 主机 | 172.29.89.45 |
| 操作系统 | WSL2 Ubuntu 22.04 |
| 内核 | 6.6.114.1-microsoft-standard-WSL2 |
| FUSE 库 | API version 7.39 |
| 挂载点 | /mnt/fuse_test |
| Daemon 路径 | /home/wyh/fuse_hang |

---

> **报告生成**：白泽（Baize）分析与报告 Agent @ 2026-06-04 14:45:49（UTC+8）
> **诊断数据源**：C:\Users\86135\.witty-diagnosis-agent\dayu\report\kuafu_T1_fuse_hang_20260604.md
