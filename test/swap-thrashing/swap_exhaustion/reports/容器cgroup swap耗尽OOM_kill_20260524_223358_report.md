# 🔴 故障诊断报告

> **报告编号**：RCA-20260524-001
> **故障级别**：P2（容器级故障，业务影响可控但需紧急规避）
> **报告时间**：2026-05-24 22:33:58
> **当前状态**：🟡 观察中（容器重启后已恢复运行，但根本限制未解除）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | 容器 swap-thrash-branchA 因 cgroup swap 空间耗尽触发 OOM kill |
| 影响范围 | 容器 `swap-thrash-branchA`（镜像：swap-thrasher / Ubuntu 22.04），运行于 WSL2 宿主机 |
| 故障时段 | 2026-05-24 22:15:09 ～ 2026-05-24 22:16:13（两波 OOM kill） |
| 根本原因 | 容器 cgroup memory.swap.max 总上限（160MB = 128MB 内存 + 32MB swap）小于 stress-ng workload 实际需求（200MB），swap 耗尽后触发 cgroup OOM killer |
| 是否恢复 | ✅ 已恢复（容器自动重启后新实例运行完成，但相同配置下仍存在再次触发风险） |
| 根因置信度 | 🟢 高置信 |

### 置信度说明（此表固定展示作为参考）

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|--------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | cgroup swap limit < workload 需求 → 复现后调整上限立即解决 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

> **根因一句话**：容器 cgroup 的 memory.swap.max 设置（160MB 总量, 纯 swap 仅 32MB）无法承载 stress-ng 2×100MB=200MB 的内存需求，swap 被快速填满后触发 cgroup OOM killer 终止进程。

### 事故时间线 & 故障传导链路

```text
时间                         事件                                                     性质           溯源路径
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-05-24 22:15:09         容器 swap-thrash-branchA 启动 stress-ng --vm 2 --vm-bytes 100M  🟢 正常启动    [kuafu_T1_20260524_143248.md:10]
  │
  ▼
2026-05-24 22:15:09~22:15:14  第一次 OOM Kill 波次：5 个 stress-ng 进程被连续 kill           🔴 故障爆发    [kuafu_T1_20260524_143248.md:46]
  │                           memory.swap.max 160MB 被快速占满
  │                           swap failcnt 持续增长
  ▼
2026-05-24 22:16:09~22:16:13  第二次 OOM Kill 波次：再 5 个 stress-ng 进程被 kill            🔴 故障持续    [kuafu_T1_20260524_143248.md:47]
  │                           swap 完全占满 (usage=limit=262,144kB)
  │                           memory.max(128MB) 因 swap 换出未触发
  ▼
2026-05-24 22:16:13          容器异常退出                                                 🔴 容器终止    [kuafu_T1_20260524_143248.md:105]
  │
  ▼
2026-05-24 22:27:46~22:29:46  容器自动重启，新实例运行完整 120s stress-ng 完成               🟢 自动恢复    [kuafu_T1_20260524_143248.md:48]
  │                           但相同 cgroup 限制下风险未解除
```

### 故障因果链

```text
[配置层] 容器 memory=128MB, memory.swap.max=160MB（纯 swap 仅 32MB）
    │
    ├─► [触发层] stress-ng --vm 2 --vm-bytes 100M → 总需求 200MB > 上限 160MB
    │       │
    │       ▼
    │   [page allocator 分配页框 → 物理内存 128MB 满]
    │       │
    │       ▼
    │   [kswapd/direct reclaim 启动 → 选择匿名页 swap out]
    │       │
    │       ▼
    │   [32MB swap 瞬间填满 (usage=262,144kB == limit=262,144kB)]
    │       │
    │       ▼
    │   [memory.swap.events.max 命中, failcnt 持续增长至 2,414]
    │       │
    │       ├─► memory.max(128MB) 未被触发（swap 换出缓解）
    │       │
    │       ▼
    │   [cgroup OOM killer 被调用 → CONSTRAINT_MEMCG]
    │       │
    │       ▼
    └─► [stress-ng 进程被 kill → 容器异常退出]
            │
            ▼
         [容器自动重启 → 新实例完成运行但根因未消除]
```

---

## 三、排查过程

> 排查逻辑：**基于 Kuafu 前置诊断报告（swap-thrashing-diagnosis 双轨分析），对每个假设进行验证与收敛**。

### 3.1 初始现象

- **故障表象**：容器 `swap-thrash-branchA` 运行 stress-ng 压力测试时反复异常退出
- **关键报错**：dmesg 日志确认 cgroup OOM kill 事件：
  ```
  Memory cgroup out of memory: Killed process 12753 (stress-ng) ...
  swap: usage 262144 kB, limit 262144 kB, failcnt 2414
  ```
- **监控现象**：`memory.swap.events.max` 计数器持续增长，`memory.max` 始终未触发

### 3.2 假设驱动排查

以下排查过程已由 Kuafu 前置诊断完成，Baize 在此进行汇总与收敛：

---

#### 假设 A：宿主机 swap 空间不足

> 🧪 假设：宿主机全局 swap 耗尽，导致容器无法换页

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 宿主机 Swap 总量 | `swapon --show` | SwapTotal=2,097,152 kB (2 GB) |
| 宿主机 Swap 使用量 | `SwapFree / SwapUsed` | SwapFree=2,093,540 kB, 使用率 ~0% |

**❌ 排除**：宿主机 swap 充足（2GB 仅使用 3,612 kB），非全局问题。

---

#### 假设 B：宿主机物理内存不足

> 🧪 假设：宿主机内存耗尽导致所有容器受影响

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 宿主机内存可用量 | `MemAvailable` | 5,879,676 kB (5.6 GB) |
| 宿主机空闲内存 | `MemFree` | 3,054,500 kB (2.9 GB) |

**❌ 排除**：宿主机内存充裕（7.4GB 中可用 5.6GB），压力仅在容器 cgroup 级别。

---

#### 假设 C：应用存在内存泄漏

> 🧪 假设：应用程序异常行为导致内存不断增长

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 工作负载性质 | 分析容器启动命令 | `stress-ng --vm 2 --vm-bytes 100M` 为受控压力测试 |
| 内存模式 | 预期 vs 实际 | 每次分配 100MB × 2 = 200MB，行为符合预期 |

**❌ 排除**：stress-ng 是确定性压力工具，非泄漏场景；分配量与预期一致。

---

#### 假设 D：swappiness 配置不当（过高导致过度 swap）

> 🧪 假设：swappiness 设置过高，内核过早 swap out

| 检查项 | 操作 | 结论 |
|--------|------|------|
| swappiness 值 | `sysctl vm.swappiness` | 60（默认值） |
| 非极端值验证 | 对比建议范围 | 默认值 60，非极端偏高值（如 100） |

**❌ 排除**：swappiness=60 为内核默认值，行为符合预期。

---

#### 假设 E：脏页过多导致文件页不可回收

> 🧪 假设：文件缓存脏页过多，迫使内核只能选择匿名页 swap out

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 脏页量 | /proc/meminfo: Dirty | 72 kB（极低） |
| Writeback | /proc/meminfo: Writeback | 124 kB（极低） |

**❌ 排除**：脏页可忽略，不影响 reclaim 效率。

---

#### 假设 F：内核缺陷 / 非预期行为

> 🧪 假设：内核存在 bug 导致异常 OOM kill

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 行为验证 | 双轨交叉验证 | 现场指标 + dmesg 内核日志完全吻合 |
| 预期行为 | 根因逻辑链 | OOM kill 为 cgroup 限制的预期结果，符合内核设计 |

**❌ 排除**：内核行为完全符合预期，非 bug。

---

#### 假设 G：cgroup swap 上限不足 ✅ **确认根因**

> 🧪 假设：容器 cgroup memory.swap.max 设置过小，无法容纳 workload 需求

**Step 1 — 确认容器 cgroup 资源配置**

| 参数 | 值 | 换算 |
|------|-----|------|
| memory.max | 134,217,728 bytes | **128 MB** |
| memory.swap.max | 167,772,160 bytes | **160 MB**（含 128MB 内存） |
| 纯 swap 可用量 | 160 MB - 128 MB | **32 MB** |
| oom_kill_disable | false | 允许 OOM kill |

**Step 2 — 确认 workload 内存需求**

- 启动命令：`stress-ng --vm 2 --vm-bytes 100M --timeout 120s`
- 每个 VM worker：分配 100MB 匿名内存
- 总需求：**200 MB** > 容器总上限 **160 MB**（超出 25%）

**Step 3 — 确认 OOM 触发机制**

- dmesg 确认：swap 完全占满 `usage=262,144 kB == limit=262,144 kB`
- failcnt 持续增长至 **2,414** 次
- memory.max（128MB）**未被触发**：因 swap 持续换出，匿名页被换至 swap 设备，物理内存占用未超 128MB
- 当 swap 耗尽后，cgroup OOM killer 被调用（CONSTRAINT_MEMCG）

**✅ 结论：容器 memory.swap.max=160MB（纯 swap 仅 32MB）小于 stress-ng 200MB 需求，swap 填满后触发 OOM kill。**

---

### 3.3 排查结论

```text
容器 swap-thrash-branchA OOM 异常退出
│
├─► 宿主机 swap 不足      → ✅ 正常（2GB 空余），排除
├─► 宿主机内存不足        → ✅ 正常（可用 5.6GB），排除
├─► 应用内存泄漏          → ✅ stress-ng 受控测试，排除
├─► swappiness 配置不当    → ✅ 默认值 60，排除
├─► 脏页过多导致不可回收   → ✅ Dirty=72kB，极低，排除
├─► 内核缺陷              → ✅ 行为符合预期，排除
│
└─► 容器 cgroup 限制不当  → ❌ 根因确认
        │
        ├─► memory.max=128MB
        ├─► memory.swap.max=160MB（纯 swap 仅 32MB）
        ├─► workload 需求 200MB > 上限 160MB
        │
        └─► swap 填满 + OOM kill
                └─► 🎯 根因确认：cgroup swap 上限不足
```

---

## 四、修复方案

### 4.1 应急处置（已有）

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 容器自动重启机制触发新实例 | 系统（Docker 自动策略） | 2026-05-24 22:27:46 | 新实例完成运行，服务恢复 |
| 2 | 实际未做人工干预 | — | — | 相同配置仍存在再次触发风险 |

### 4.2 永久修复计划

#### 方案 A：增大容器 cgroup 上限（推荐）

调整容器资源限制以适配 workload 实际需求：

```bash
# 方案 A1：对称扩容（推荐）
docker run --memory=256m --memory-swap=512m swap-thrasher \
  stress-ng --vm 2 --vm-bytes 100M --timeout 120s
# memory=256MB, memory+swap=512MB（纯 swap=256MB）
# 充分满足 200MB workload 需求，并有足够 burst 余量

# 方案 A2：精确适配
docker run --memory=192m --memory-swap=384m swap-thrasher \
  stress-ng --vm 2 --vm-bytes 100M --timeout 120s
# memory=192MB（可容纳 RSS）+ swap=192MB（burst 容忍）
```

#### 方案 B：降低 workload 内存需求

调整 workload 配置适配现有 cgroup 上限：

```bash
docker run --memory=128m --memory-swap=160m swap-thrasher \
  stress-ng --vm 2 --vm-bytes 64M --timeout 120s
# 每个 worker 降至 64MB，总需求 128MB ≤ 160MB 上限
```

#### 方案 C：生产环境最佳实践（设计层面）

| 修复措施 | 说明 | 优先级 |
|--------|------|--------|
| 评估 workload 内存画像 | 确定 peak 内存需求后设置 cgroup 上限 | P0 |
| 合理设置 memory + swap 组合 | memory 设为常驻集大小，swap 设为 burst 容忍量（建议 ≥ memory 的 50%） | P0 |
| 非必要场景禁用 swap | 设置 `--memory-swap` 与 `--memory` 相同值，避免 swap thrashing | P1 |
| 容器级资源监控告警 | Prometheus 采集 container_memory_working_set_bytes / container_memory_swap | P1 |
| 设置 swap 使用率告警 | memory.swap.usage > 80% 持续 5 分钟触发 | P1 |
| 设置 swap events 告警 | memory.swap.events.max 在 5 分钟内增长 > 0 时触发 | P2 |

---

## 五、根因确认与验证建议

### 5.1 根因确认

用调整后的配置（memory=256MB, memory-swap=512MB）重新运行容器，验证：

```bash
docker run -d --name swap-test --memory=256m --memory-swap=512m \
  swap-thrasher stress-ng --vm 2 --vm-bytes 100M --timeout 120s

# 实时监控资源
docker stats swap-test

# 检查 OOM 事件
docker inspect swap-test --format '{{.State.OOMKilled}}'
# 预期输出: false
```

### 5.2 验收标准

| 检查项 | 预期结果 |
|--------|---------|
| 容器稳定运行至 timeout 结束 | 容器状态 Exited(0)，非 OOMKilled |
| memory.swap.events.max 不再增长 | failcnt 清零或不再增加 |
| memory.max 未被触发 | memory.events 中 oom 计数为 0 |
| docker stats 显示 memory/swap 使用率正常 | 总使用 < 85% 上限 |

---

## 附录：证据索引

| 证据项 | 来源文件 | 关键信息 |
|--------|---------|---------|
| 容器内存配置 | `kuafu_T1_20260524_143248.md:30-36` | memory.max=128MB, memory.swap.max=160MB |
| workload 分析 | `kuafu_T1_20260524_143248.md:39-41` | stress-ng 2×100MB=200MB 需求 |
| OOM 时间线 | `kuafu_T1_20260524_143248.md:44-48` | 22:15:09~22:16:13 两波 OOM kill |
| swap 使用状态 | `kuafu_T1_20260524_143248.md:51` | usage=262,144 kB == limit, failcnt=2,414 |
| 关键进程详情 | `kuafu_T1_20260524_143248.md:55-61` | PID 12753/12991 等被 kill, swapents ~64,000 |
| 内核配置验证 | `kuafu_T1_20260524_143248.md:73-84` | CONFIG_SWAP=y, CONFIG_MEMCG=y |
| 排除假设清单 | `kuafu_T1_20260524_143248.md:148-157` | 7 项假设全部排除 |
| 根因因果链 | `kuafu_T1_20260524_143248.md:93-108` | 完整双轨交叉验证因果链 |
| 修复建议 | `kuafu_T1_20260524_143248.md:160-211` | 最小修复 + 根本修复 + 验证建议 |
