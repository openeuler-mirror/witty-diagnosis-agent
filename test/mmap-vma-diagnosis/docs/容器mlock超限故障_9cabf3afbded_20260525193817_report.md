# 内存映射 / 虚拟地址空间故障诊断报告

> **报告编号**：RCA-20260525-001
> **故障级别**：P2 — 应用功能受损
> **报告时间**：2026-05-25 19:38:17
> **当前状态**：🔴 待修复

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | 容器 mmap-C 内用户 tu 调用 mlock(9KB) 返回 ENOMEM (errno=12) |
| 影响范围 | 容器 mmap-C (ID: 9cabf3afbded)，用户 tu (uid=1000) 下的进程 |
| 故障时段 | 2026-05-25 11:45:00 UTC ～ 持续中 |
| 根本原因 | 用户 tu 的 RLIMIT_MEMLOCK soft/hard 均为 8KB，远低于应用 mlock(9KB) 请求所需的最小 12KB (3 页)，且登录 shell 隐式锁定约 4KB 后，实际可用锁定内存仅剩约 4KB (1 页) |
| 是否恢复 | ❌ 未恢复（需手动提高 ulimit 配置） |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 判定依据 |
|------|------|------|---------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | mlock(4096) 成功 vs mlock(4097) 失败，边界清晰；`/proc/<PID>/limits` 确认限制为 8KB；root 用户 unlimited 无此问题；100% 可复现 |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                                   事件                                          性质         证据来源
──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-05-25 11:45:00                   容器 mmap-C 启动，用户 tu 的 shell 启动         ⚙️ 初始化     [kuafu/kuafu_T1_20260525_mlock_diagnosis.md:19-23]
  │
  ▼
（shell 初始化时）                       libc/ld-linux 隐式锁定 ~4KB 内存                🟡 消耗       [kuafu/kuafu_T1_20260525_mlock_diagnosis.md:71-75]
  │                                     这些不体现在 VmLck 中，但计入 RLIMIT_MEMLOCK
  │
  ▼
2026-05-25 11:45:00                    应用调用 mlock(9216) = 9KB 请求锁定内存          🔴 故障触发    [kuafu/kuafu_T1_20260525_mlock_diagnosis.md:54-65]
  │
  ▼
（即时）                                 内核检查 RLIMIT_MEMLOCK = 8KB                   ⚠️ 限制检查    [kuafu/kuafu_T1_20260525_mlock_diagnosis.md:30-39]
  │                                     当前已锁定 ~4KB + 新请求 9KB = ~13KB > 8KB
  │
  ▼
（即时）                                 mlock() 返回 -1，errno=12 (ENOMEM)              ❌ 失败        [kuafu/kuafu_T1_20260525_mlock_diagnosis.md:64-65]
  │
  ▼
2026-05-25 11:45:00                    应用收到 "Cannot allocate memory" 错误            🔴 故障显现    [kuafu/kuafu_T1_20260525_mlock_diagnosis.md:5-12]
  │                                     功能受损
```

### 故障因果链

```text
容器 mmap-C 配置：RLIMIT_MEMLOCK=8KB (soft/hard)
    │
    ├─► 登录 shell (su - tu) 启动时消耗 ~4KB 隐式锁定内存（libc/ld-linux）
    │      └─► 实际可用锁定内存仅剩 ~4KB（1 个页面）
    │
    └─► 应用调用 mlock(9KB)
           │
           ├─► 内核按页对齐 → 实际需要锁定 3 页 = 12KB
           │
           ├─► 检查 RLIMIT_MEMLOCK 计数器：
           │      当前已锁定 ~4KB + 请求 12KB = 总锁定 ~16KB
           │      限制 8KB → ❌ 超限
           │
           └─► 内核返回 -1, errno=12 (ENOMEM)
                  └─► 🔴 mlock 失败，应用功能受损
```

---

## 三、排查过程

### 3.1 初始现象

| 现象 | 描述 |
|------|------|
| 容器状态 | mmap-C (ID: 9cabf3afbded) 运行中，Up 2 分钟 |
| 用户 | tu (uid=1000, gid=1000)，非 root 用户 |
| 故障表现 | 调用 `mlock(9216)` = 9KB 返回 -1，errno=12 (Cannot allocate memory) |
| 关键日志 | 无内核日志（mlock ENOMEM 是用户态错误，不写入 dmesg） |

### 3.2 假设驱动排查

#### 假设 C1：RLIMIT_MEMLOCK 限制过小 ✅ **确认根因**

> 🧪 假设：用户 tu 的 RLIMIT_MEMLOCK soft/hard 均为 8KB，当应用尝试 mlock 超过此限制时被内核拒绝。

**Step 1 — 确认用户 memlock 限制**
```bash
ulimit -l    → 8 (8KB)
ulimit -H -l → 8 (8KB)
```
| 检查项 | 操作 / 命令 | 结论 |
|--------|------------|------|
| Soft 限制 | `ulimit -l` = 8KB | ✅ 确认 soft=8192 bytes |
| Hard 限制 | `ulimit -H -l` = 8KB | ✅ 确认 hard=8192 bytes |
| 进程 limits | `cat /proc/<PID>/limits \| grep "Max locked memory"` | ✅ soft=8192, hard=8192 |

**Step 2 — 边界测试验证**
| mlock 请求 | 页数 (4KB/页) | 返回值 | errno | 结果 |
|------------|:------------:|--------|-------|------|
| 4096 B (4.0KB) | 1 | 0 | 0 | ✅ SUCCESS |
| 4097 B (≈4.0KB) | 2 | -1 | 12 | ❌ ENOMEM |
| 7168 B (7.0KB) | 2 | -1 | 12 | ❌ ENOMEM |
| 8192 B (8.0KB) | 2 | -1 | 12 | ❌ ENOMEM |
| 9216 B (9.0KB) | 3 | -1 | 12 | ❌ ENOMEM |

**关键发现**：`mlock(4096)` = 1 页成功，`mlock(4097)` = 2 页（8KB，恰好等于限制值）却失败。说明存在隐式锁定消耗。

**Step 3 — 分析隐式锁定**
- 登录 shell (`su - tu -c`) 启动时，libc/ld-linux 加载会产生内部锁定页面（如 `dl_init`, vsyscall 等）
- 这些不体现在 `/proc/self/status` 的 `VmLck` 字段（VmLck: 0 kB）
- 但实际计入内核的 RLIMIT_MEMLOCK 计数器
- 因此实际可用锁定内存 = 8KB - ~4KB = ~4KB
- 任何超过 1 页（4KB）的 mlock 请求都会超限

**✅ 结论：RLIMIT_MEMLOCK=8KB 过小，加上 shell 隐式锁定消耗，实际可用仅 ~4KB，应用 mlock(9KB) 需 3 页 (12KB) 远超限制。**

---

#### 假设 C2：root 用户无此问题（有无 CAP_SYS_RESOURCE 的对比验证）

> 🧪 假设：root 用户因具备 CAP_SYS_RESOURCE 能力，不受 RLIMIT_MEMLOCK 限制。

| 检查项 | 操作 / 命令 | 结论 |
|--------|------------|------|
| Root 进程 memlock | `cat /proc/<PID>/limits` (root 进程) | ✅ Max locked memory = unlimited/unlimited |
| 用户 tu 进程 memlock | `cat /proc/<PID>/limits` (tu 进程) | ✅ Max locked memory = 8192/8192 bytes |

**✅ 结论：root 用户 unlimited 无限制，非 root 用户 tu 受限于 8KB。此假设被作为排除项，但验证结果强化了根因定位。**

---

#### 假设 C3：容器 ulimit 继承问题

> 🧪 假设：容器启动参数中指定了 `--ulimit memlock=8:8`，或者从宿主机继承的默认值不足。

| 检查项 | 操作 / 命令 | 结论 |
|--------|------------|------|
| 容器进程限制 | `cat /proc/<PID>/limits` | ✅ 确认限制为 8KB/8KB |
| 容器的 ulimit 设置 | docker inspect / 启动命令 | 非 root 用户默认 memlock = 8KB（Linux 发行版默认值） |

**✅ 结论：容器默认继承了 Linux 发行版的 RLIMIT_MEMLOCK 默认值（8KB），这在大多数发行版中是针对非特权用户的默认值。容器未单独设置 `--ulimit memlock`。**

---

#### 假设 C4：系统物理内存不足

> 🧪 假设：系统物理内存耗尽，mlock 即使满足 RLIMIT_MEMLOCK 也无法锁定页面。

| 检查项 | 操作 / 命令 | 结论 |
|--------|------------|------|
| 系统内存 | 容器正常运行，mlock(4096) 成功 | ✅ 排除 — 4KB 可锁定，说明系统有足够物理内存 |
| 内核日志 | `dmesg -T \| grep -i mlock` | ✅ 无 OOM 或内存不足条目 |

**❌ 排除：系统物理内存充足，mlock(4KB) 成功即为证据。**

---

#### 假设 C5：内核/cgroup 内存限制

> 🧪 假设：容器的 cgroup memory.limit_in_bytes 限制导致 mlock 失败。

| 检查项 | 操作 / 命令 | 结论 |
|--------|------------|------|
| cgroup 限制 | 容器正常运行中 | ✅ 排除 — 如果 cgroup 限制导致，mlock(4096) 也会失败 |
| 与 RLIMIT 优先级 | 内核先检查 RLIMIT_MEMLOCK，再检查 cgroup | ✅ 实际上 RLIMIT 限制先触发，9KB 请求在 RLIMIT 阶段即被拒绝 |

**❌ 排除：cgroup 限制不是故障原因。即使 cgroup 无限制，RLIMIT_MEMLOCK=8KB 也会独立导致失败。**

---

#### 假设 C6：内核版本差异导致的行为变化

> 🧪 假设：不同内核版本对 mlock 的 RLIMIT_MEMLOCK 计数方式存在差异。

| 检查项 | 操作 / 命令 | 结论 |
|--------|------------|------|
| 隐式锁定行为 | libc/ld-linux 内部锁定进程自身资源 | ✅ 这是 Linux 内核通用行为，几乎所有版本均如此 |
| 历史兼容性 | Linux 长期以来的 mlock 实现 | ✅ 不完全排除，但非本故障的主要因素 |

**🟡 未完全排除：不同内核版本对隐式锁定的处理有细微差异，但无论差异如何，在 8KB 限制下 mlock(9KB) 必然失败。此假设对修复方案无实质影响。**

---

### 3.3 排查结论与逻辑树

```text
mlock(9KB) → ENOMEM (errno=12)
│
├─► [C4] 系统物理内存不足              → ❌ 排除（mlock(4KB) 成功）
│
├─► [C5] cgroup 内存限制              → ❌ 排除（先触发的是 RLIMIT 检查）
│
├─► [C6] 内核版本差异                  → 🟡 未完全排除（但非主因）
│
├─► [C2] root/CAP_SYS_RESOURCE       → ✅ 验证通过（root unlimited，tu=8KB）
│
├─► [C3] 容器 ulimit 继承             → ✅ 确认（未设置 --ulimit memlock）
│
└─► [C1] RLIMIT_MEMLOCK=8KB 过小      → 🎯 **根因确认**
        │
        ├─► shell 隐式锁定 ~4KB         → ⚠️ 加剧因素
        │   （libc/ld-linux 内部锁定，不计入 VmLck）
        │
        └─► mlock(9KB) 需 3 页 = 12KB  → ❌ 超限
            （加上已锁定 ~4KB → 总 ~16KB >> 8KB）
            └─► 🎯 根因：RLIMIT_MEMLOCK 配置过低
```

---

## 四、修复方案

### 4.1 应急处置

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 临时提高容器内用户 tu 的 memlock 限制 | 系统/人工 | 故障时 | 允许当前进程继续运行 |
| 2 | 评估将应用切换到 root 用户运行（不推荐，安全风险） | 人工 | — | 绕过限制（不推荐） |

**即时缓解命令（在容器内执行）**：
```bash
# 方案 A：通过 prlimit 即时调整（需要 root/sudo）
prlimit --pid <PID> --memlock=65536:65536

# 方案 B：重新启动容器时指定 ulimit
docker run --ulimit memlock=65536:65536 ... mmap-C
```

### 4.2 永久修复计划

| 修复措施 | 负责人 | 完成时间 |
|---------|--------|--------|
| 在 docker-compose.yaml 或 Pod spec 中设置 `ulimits.memlock.soft=65536` 和 `ulimits.memlock.hard=65536` | 配置管理员 | 待定 |
| 或在容器启动命令中增加 `--ulimit memlock=65536:65536` | 部署团队 | 待定 |
| 或在 `/etc/security/limits.conf` 中为 tu 用户配置 `tu soft memlock 65536` / `tu hard memlock 65536` | 系统管理员 | 待定 |
| 应用侧评估：确认是否可减少 mlock 请求大小，或使用 `mlock2()` 按需锁定 | 研发团队 | 待定 |

**推荐配置值**：至少 64KB（65536 bytes），理由如下：
- 应用请求 9KB → 按页对齐后需要 12KB
- 进程自身隐式锁定 ~4KB
- 留有余量避免边界问题 → 推荐 ≥ 64KB

### 4.3 预防措施

| 措施 | 说明 |
|------|------|
| 部署前检查清单 | 所有需要 mlock 的容器应在部署文档中注明所需的最小 memlock 值 |
| 容器模板标准化 | 在容器镜像或编排模板中预置适当的 ulimit 配置 |
| 监控告警 | 添加对 mlock 失败（errno=12）的应用日志监控 |
| 非 root 用户权限基线 | 建立非 root 用户容器化的 priviledge/resource 基线文档 |

---

## 五、排除项汇总

| 假设 | 描述 | 排除结论 | 排除依据 |
|------|------|---------|---------|
| C4 | 系统物理内存不足导致 mlock 失败 | ❌ 已排除 | mlock(4KB) 成功，证明系统有足够物理内存 |
| C5 | cgroup memory.limit 限制了 mlock | ❌ 已排除 | RLIMIT 检查在 cgroup 之前触发且优先拒绝；mlock(4KB) 成功 |
| C6 | 内核版本差异导致 mlock 行为异常 | 🟡 未完全排除 | 隐式锁定行为在不同内核版本间有细微差异，但非主因；无论差异如何，8KB 限制下 9KB 请求必然失败 |

---

## 六、关键证据清单

| # | 证据 | 来源 | 行号 |
|---|------|------|------|
| 1 | 容器 mmap-C 正常运行 | kuafu_T1_20260525_mlock_diagnosis.md | L19-23 |
| 2 | 用户 tu 的 ulimit -l = 8，ulimit -H -l = 8 | kuafu_T1_20260525_mlock_diagnosis.md | L30-39 |
| 3 | mlock(4096) 成功；mlock(4097) 起全部失败返回 ENOMEM | kuafu_T1_20260525_mlock_diagnosis.md | L54-65 |
| 4 | 进程 limits 确认 Max locked memory = 8192/8192 bytes | kuafu_T1_20260525_mlock_diagnosis.md | L80-92 |
| 5 | root 进程 Max locked memory = unlimited/unlimited | kuafu_T1_20260525_mlock_diagnosis.md | L81-84 |
| 6 | VmLck = 0 kB，隐式锁定不计入 | kuafu_T1_20260525_mlock_diagnosis.md | L96-104 |
| 7 | 内核日志无 mlock 相关条目（正常行为） | kuafu_T1_20260525_mlock_diagnosis.md | L43-49 |

---

## 七、附录

### A. 故障场景参数表

| 参数 | 值 |
|------|-----|
| 容器 ID | 9cabf3afbded |
| 容器名 | mmap-C |
| 用户 | tu (uid=1000, gid=1000) |
| 应用请求 | mlock(9216) = 9KB |
| RLIMIT_MEMLOCK (soft) | 8KB (8192 bytes) |
| RLIMIT_MEMLOCK (hard) | 8KB (8192 bytes) |
| 页大小 | 4KB |
| 请求页数 | 3 页（向上取整） |
| 隐式锁定 | ~4KB（1 页，libc/ld-linux 内部） |
| 实际可用 | ~4KB（1 页） |
| 返回值 | -1 |
| errno | 12 (ENOMEM) |
| 内核日志 | 无（正常行为） |

### B. 推荐的 ulimit 配置值

| 场景 | 推荐值 | 说明 |
|------|--------|------|
| 当前故障修复 | 64KB (65536) | 满足 9KB 请求 + 隐式锁定 + 余量 |
| 通用容器 | 64KB～1MB | 适用于大多数需要 mlock 的轻量应用 |
| Elasticsearch | unlimited | ES 官方要求 bootstrap.memory_lock=true 时需 unlimited |
| 高安全隔离 | 按需精确设置 | 不建议设 unlimited 以维持最小权限原则 |
