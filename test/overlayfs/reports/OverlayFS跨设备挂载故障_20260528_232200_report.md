# 🔴 故障诊断报告

> **报告编号**：RCA-20260528-001
> **故障级别**：P2（功能受损）
> **报告时间**：2026-05-28 23:22:00
> **当前状态**：🔴 处理中

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | Docker 容器 overlayfs-fault-C OverlayFS 跨设备挂载失败 |
| 影响范围 | Docker 容器 `overlayfs-fault-C`，所有依赖该 overlay 挂载点的业务层操作 |
| 故障时段 | 2026-05-28 23:22:00 ～ 当前（持续未恢复） |
| 根本原因 | upperdir（`/dev/loop2`，设备号 1794）和 workdir（`/dev/loop3`，设备号 1795）位于不同 loop 设备上，违反 Linux 内核 overlayfs 强制约束：upperdir 与 workdir 必须在同一文件系统（同一 super_block）下 |
| 是否恢复 | ❌ 未恢复（配置层问题尚未修复） |
| 根因置信度 | 🟢 高置信 |

### 置信度说明（此表固定展示作为参考）

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|--------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | upperdir/workdir 跨设备 → 内核 ovl_same_fs() 检查失败 → mount 报错 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

> 一句话说清楚：**Docker 场景下将 OverlayFS 的 upperdir 和 workdir 分别配置在了两个不同的 loop 设备上，内核挂载校验时拒绝执行，导致 overlay 挂载全面失败。**

### 事故时间线 & 故障传导链路

```text
时间                       事件                                               性质         溯源路径
───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-05-28 23:22:00       Docker 容器 overlayfs-fault-C 启动 overlay 挂载       📥 操作触发   [kuafu_T1_20260528_232200.md]
  │                        mount -t overlay -o lowerdir=...,upperdir=...,workdir=...
  ▼
2026-05-28 23:22:00       内核 overlayfs 挂载入口 ovl_fill_super() 接收参数       🔍 参数解析   [fs/overlayfs/super.c]
  │                        解析 upperdir → /dev/loop2 (1794)
  │                        解析 workdir  → /dev/loop3 (1795)
  ▼
2026-05-28 23:22:00       ovl_same_fs() 比对 upperdir 与 workdir 的 super_block   ⚠️  约束检查   [fs/overlayfs/util.c]
  │                        /dev/loop2.super_block != /dev/loop3.super_block
  │                        → 判定为跨设备，检查不通过
  ▼
2026-05-28 23:22:00       内核抛出错误信息：                                    🔴 故障爆发   [dmesg]
  │                        "overlayfs: workdir and upperdir must reside
  │                         under the same mount"
  │                        mount 命令返回: "wrong fs type, bad option, bad superblock"
  ▼
2026-05-28 23:22:00       overlay 挂载失败                                     ❌ 挂载拒绝   [/proc/mounts]
                            merged 目录为空，容器功能不可用
```

### 故障因果链

```text
Docker 配置/脚本将 upperdir 和 workdir放在不同的loop设备上
    └─► upperdir 位于 /dev/loop2 (1794)，workdir 位于 /dev/loop3 (1795)
            └─► 内核挂载流程调用 ovl_same_fs() 检查
                    └─► 发现两个目录的 super_block 不同
                            └─► ovl_mount_dir_noesc() 拒绝挂载
                                    └─► dmesg 输出错误：workdir and upperdir must reside under the same mount
                                            └─► mount 命令返回通用错误 "wrong fs type, bad option, bad superblock"
                                                    └─► 🔴 Docker 容器 overlay 挂载全面失败
```

---

## 三、排查过程

> 排查逻辑：**提出假设 → 收集证据 → 验证或排除 → 逐步收敛到根因**

### 3.1 初始现象

- Docker 容器 `overlayfs-fault-C` 尝试 `mount -t overlay` 失败
- shell 返回错误：`wrong fs type, bad option, bad superblock`
- 检查 `dmesg` 内核日志，明确输出：
  ```
  overlayfs: workdir and upperdir must reside under the same mount
  ```

---

### 3.2 假设驱动排查

#### 假设 A：overlay 内核模块未加载或损坏

> 🧪 假设：overlay 模块未正确加载到内核中

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 模块加载状态 | `lsmod \| grep overlay` | ✅ 已加载 |
| 模块信息 | `modinfo overlay` | ✅ 模块存在且正常 |

**❌ 排除**：overlay 模块已加载，排除模块缺失。

---

#### 假设 B：upperdir / workdir 目录不存在或权限不足

> 🧪 假设：挂载所需的目录尚未创建或权限不正确

| 检查项 | 操作 | 结论 |
|--------|------|------|
| upperdir 存在性 | `ls -d /mnt/loop_a/upper` | ✅ 存在 |
| workdir 存在性 | `ls -d /mnt/loop_b/work` | ✅ 存在 |
| upperdir 权限 | `stat /mnt/loop_a/upper` | ✅ 755，正常 |
| workdir 权限 | `stat /mnt/loop_b/work` | ✅ 755，正常 |

**❌ 排除**：所有目录存在且权限正常。

---

#### 假设 C：磁盘空间不足导致挂载失败

> 🧪 假设：磁盘空间或 inode 耗尽

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 磁盘空间 | `df -h` | ✅ 空间充足 |
| inode 余量 | `df -i` | ✅ inode 充足 |

**❌ 排除**：磁盘空间与 inode 均充足。

---

#### 假设 D：下层文件系统不兼容

> 🧪 假设：upperdir/workdir 所在的文件系统不被 overlayfs 支持

| 检查项 | 操作 | 结论 |
|--------|------|------|
| upperdir 文件系统 | `df -T /mnt/loop_a/upper` | ✅ ext4 |
| workdir 文件系统 | `df -T /mnt/loop_b/work` | ✅ ext4 |

**❌ 排除**：两者均为 ext4（overlayfs 完全兼容），但进一步发现两者位于不同的 loop 设备上。

---

#### 假设 E：upperdir 与 workdir 跨设备（不同文件系统） ✅ 确认根因

> 🧪 假设：upperdir 和 workdir 处于不同的文件系统 super_block 上，违反了内核 overlayfs 的约束

**Step 1 — 确认设备拓扑**

```bash
stat /mnt/loop_a/upper
# 设备号：1794 → /dev/loop2（ext4）

stat /mnt/loop_b/work
# 设备号：1795 → /dev/loop3（ext4）
```

**Step 2 — 内核约束验证**

| 设备 | 设备号 | 文件系统 | super_block |
|------|--------|---------|------------|
| `/dev/loop2`（upperdir） | 1794 | ext4 | sb_A |
| `/dev/loop3`（workdir） | 1795 | ext4 | sb_B |

> 两者设备号不同 ⇒ super_block 不同 ⇒ `ovl_same_fs()` 返回 false

**Step 3 — 关联内核源码逻辑**

```c
// fs/overlayfs/util.c
// ovl_same_fs() 检查两个目录是否在同一 mount 下
// 通过比较 dentry->d_sb 是否相等来判断
// 若不同 → ovl_mount_dir_noesc() 拒绝并输出 dmesg 错误
```

**Step 4 — dmesg 确认**

```
overlayfs: workdir and upperdir must reside under the same mount
```

**✅ 结论：upperdir（`/dev/loop2`）和 workdir（`/dev/loop3`）位于不同的 loop 设备（不同文件系统 super_block）上，违反 Linux 内核 overlayfs 的强制约束，导致挂载被拒绝。所有其他因素（模块、权限、空间、文件系统类型）均正常，证明了根因的唯一性。**
---

### 3.3 排查结论

```text
overlay 挂载失败
├─► overlay 模块加载状态     → ✅ 已加载，排除
├─► 目录存在性/权限          → ✅ 全部存在且权限正常
│       └─► upperdir 755, workdir 755 → 正常
├─► 磁盘空间/inode           → ✅ 充足，排除
├─► 文件系统兼容性           → ✅ 同为 ext4
│       └─► 但发现不同 loop 设备 → 🔍 深入检查
└─► upperdir / workdir 同文件系统检查 → ❌ 跨设备
        └─► upperdir = /dev/loop2 (1794)
        └─► workdir  = /dev/loop3 (1795)
        └─► super_block 不同 → ovl_same_fs() 拒绝
                └─► 🎯 根因确认：跨设备 overlay 约束违反
```

---

## 四、修复方案

### 4.1 应急处置（如有）

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 将 upperdir 和 workdir 迁移到同一 loop 设备上（见方案 A） | 运维人员 | 尽快 | overlay 挂载成功，容器功能恢复 |

### 4.2 永久修复计划

| 修复措施 | 负责人 | 完成时间 |
|--------|------|--------|
| **方案A（推荐）**：将 upperdir 与 workdir 放在同一 loop 设备上，确保 super_block 一致 | 运维/应用团队 | 尽快 |
| **方案B**：在 Docker 启动脚本或编排中加入检查，确保 upperdir/workdir 路径在/dev/loop 分配时来自同一 loop 设备 | 运维/应用团队 | 后续迭代 |
| **方案C**：梳理 Docker 容器 overlay 挂载的 loop 设备分配策略，避免将两个目录分配到不同 loop 设备 | 平台团队 | 后续迭代 |

#### 具体复现与验证命令

```bash
# ─── 当前（故障状态）───
# upperdir 在 /dev/loop2, workdir 在 /dev/loop3 → 挂载失败
mount -t overlay overlay \
  -o lowerdir=/tmp/overlay_test_C/lower,upperdir=/mnt/loop_a/upper,workdir=/mnt/loop_b/work \
  /tmp/overlay_test_C/merged
# ❌ mount error: wrong fs type, bad option, bad superblock

# ─── 修复方案A：同一 loop 设备 ───
mkdir -p /mnt/loop_a/{upper,work}
mount -t overlay overlay \
  -o lowerdir=/tmp/overlay_test_C/lower,upperdir=/mnt/loop_a/upper,workdir=/mnt/loop_a/work \
  /tmp/overlay_test_C/merged
# ✅ 挂载成功

# ─── 验证命令 ───
mount | grep overlay
# overlay on /tmp/overlay_test_C/merged type overlay ...
df /tmp/overlay_test_C/merged
# 确认文件系统正常
```

### 4.3 内核机制说明（供运维参考）

OverlayFS 要求 upperdir 和 workdir 在同一文件系统的根本原因：

| 原因 | 详细说明 |
|------|---------|
| **copy-up 原子性** | workdir 用于存放 copy-up 过程中产生的临时文件，最终通过 `rename()` 系统调用移动到 upperdir。`rename()` 跨设备时无法保证原子性（`EXDEV` 错误） |
| **硬链接受限** | overlayfs 内部使用硬链接来优化 copy-up，硬链接不能跨文件系统 |
| **内核实现约束** | `fs/overlayfs/super.c` 中 `ovl_fill_super()` → `ovl_get_workdir()` 显式检查 upperdir 和 workdir 的超级块是否相同 |

---

## 五、附录

### 5.1 证据清单

| 证据项 | 内容 | 来源文件 |
|--------|------|---------|
| 设备拓扑表 | upperdir=/dev/loop2(1794), workdir=/dev/loop3(1795) | kuafu_T1_20260528_232200.md:12-17 |
| dmesg 错误信息 | "workdir and upperdir must reside under the same mount" | kuafu_T1_20260528_232200.md:6 |
| 上层调用错误 | "wrong fs type, bad option, bad superblock" | kuafu_T1_20260528_232200.md:5 |
| 排除项 | 目录存在/权限/磁盘/fs类型/module 均正常 | kuafu_T1_20260528_232200.md:26-32 |

### 5.2 影响分析

| 维度 | 评估 |
|------|------|
| 业务影响 | Docker 容器 `overlayfs-fault-C` 无法正常工作，容器内依赖 overlay 挂载点的业务完全不可用 |
| 影响范围 | 单容器级别（非全局），但取决于该容器承载的关键程度 |
| 严重程度 | **P2（功能受损）** — 特定功能完全不可用，但影响范围局部 |
| 是否可规避 | ✅ 是，通过将 upperdir/workdir 放在同一文件系统即可规避 |
| 复现性 | 🟢 确定性复现 — 只要两个目录在不同设备上，100% 触发 |
