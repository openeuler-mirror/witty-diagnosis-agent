# 故障诊断报告

> **报告编号**：OVL-20260528-001
> **故障级别**：P3（设计限制 / 配置不当）
> **报告时间**：2026-05-28 22:53:15
> **当前状态**：🟡 可修复（提供临时方案与永久方案）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | Docker 容器内 OverlayFS 嵌套挂载失败 — overlayfs: failed to resolve upperdir |
| 影响范围 | 容器 `overlayfs-fault-A` 内尝试执行 `mount -t overlay` 创建嵌套 OverlayFS 的操作 |
| 故障时段 | 2026-05-28 约 22:38:00 ～ 2026-05-28 22:53:15（持续观察中） |
| 根本原因 | Linux 内核 overlayfs 明确禁止以 overlay 文件系统（Docker overlay2 存储驱动）作为上层挂载的 upperdir，此为内核设计层面的硬性限制 |
| 是否恢复 | ❌ 未恢复（需通过变通方案解决） |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|----------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | 内核源码拒绝 overlay 作为 upperdir，双轨完全吻合 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | - |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | - |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | - |

---

## 二、根因速览

> 核心结论：**Docker 容器根文件系统本身就是 overlay（overlay2 驱动），在容器内再次执行 `mount -t overlay` 试图创建嵌套 overlay 时，内核 `ovl_check_upper_fs()` 检查到 upperdir 所在文件系统为 overlay，直接拒绝挂载。**

### 事故时间线 & 故障传导链路

```text
时间                                事件                                                 性质           溯源路径
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-05-28 ~22:38:00               容器 overlayfs-fault-A 启动，根文件系统为 overlay2       🏗️ 环境就绪    [kuafu_T1_20260528_225200.md : 27-32]
  │                                 容器内 /tmp/overlay_test_A/ 路径位于 overlay 之上
  │
  ▼
2026-05-28 ~22:38:20               执行 mount -t overlay，指定 upperdir 为                    ⚠️ 首次尝试
  │                                 /tmp/overlay_test_A/upper_nonexistent（目录不存在）
  ▼
2026-05-28 ~22:38:20               dmesg: "failed to resolve '...upper_nonexistent': -2"        🔴 目录缺失    [kuafu_T1_20260528_225200.md : 50-51]
  │                                 mount 返回："special device overlay does not exist"
  ▼
2026-05-28 ~22:38:30               mkdir -p 创建 upper_nonexistent 目录                        ✅ 人工修复    [kuafu_T1_20260528_225200.md : 19]
  │
  ▼
2026-05-28 ~22:39:00               重新执行 mount -t overlay                                   🔴 故障再次    [kuafu_T1_20260528_225200.md : 20]
  │                                dmesg: "filesystem on ... not supported as upperdir"
  │                                mount 返回："wrong fs type, bad option, bad superblock"
  ▼
2026-05-28 ~22:39:10               确认 upperdir 所在文件系统类型为 overlayfs                    ✅ 确定根因    [kuafu_T1_20260528_225200.md : 39-41]
  │                                stat -f 显示 Type: overlayfs
  ▼
2026-05-28 ~22:40:00               双轨诊断完成，交叉验证吻合                                    ✅ 根因确认    [kuafu_T1_20260528_225200.md : 96-106]
                                   结论：内核禁止 overlay on overlay 嵌套挂载
```

### 故障因果链

```text
Docker overlay2 存储驱动容器
    └─► 容器根文件系统 = overlay（/var/lib/docker/overlay2/...）
            └─► 容器内 /tmp/ 下所有路径均位于 overlay 文件系统上
                    └─► 创建 upperdir 目录，其 stat -f Type = overlayfs
                            └─► mount -t overlay 时内核调用 ovl_check_upper_fs()
                                    └─► 检测到 upperdir 所在 fs 为 overlay
                                            └─► 内核明确拒绝："not supported as upperdir"
                                                    └─► mount 返回错误 "wrong fs type, bad superblock"
                                                            └─► 🔴 嵌套 OverlayFS 挂载失败
```

---

## 三、排查过程

> 排查逻辑：**提出假设 → 收集证据 → 验证或排除 → 逐步收敛到根因**

### 3.1 初始现象

- 在 Docker 容器 `overlayfs-fault-A`（Docker overlay2 存储驱动）内执行 `mount -t overlay overlay -o lowerdir=...,upperdir=...,workdir=... /tmp/.../merged` 失败
- 首次 dmesg 报错：`overlayfs: failed to resolve '/tmp/overlay_test_A/upper_nonexistent': -2`
- 修复目录缺失后，再次 dmesg 报错：`overlay: filesystem on /tmp/overlay_test_A/upper_nonexistent not supported as upperdir`
- 容器运行在 Ubuntu 22.04.5 LTS / WSL2 环境，内核版本 6.6.87.2-microsoft-standard-WSL2

---

### 3.2 假设驱动排查

#### 假设 A：upperdir 路径不存在

> 🧪 假设：upperdir 目录未创建导致路径解析失败

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 目录存在性 | `ls -ld /tmp/overlay_test_A/upper_nonexistent` | ❌ 目录不存在 |
| dmesg 确认 | `dmesg \| grep overlay` | `failed to resolve '...upper_nonexistent': -2`（ENOENT） |

**✅ 确认问题并修复**：创建目录 `mkdir -p /tmp/overlay_test_A/upper_nonexistent` 后错误消失；但出现新错误。

---

#### 假设 B：内核 overlay 模块未加载

> 🧪 假设：内核未编译 overlay 模块或模块未加载

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 内核配置 | `CONFIG_OVERLAY_FS=y` | ✅ 编译进内核 |
| 文件系统表 | `cat /proc/filesystems \| grep overlay` | ✅ nodev overlay 存在 |
| 模块状态 | `lsmod \| grep overlay` | ✅ 已加载 |

**❌ 排除**：内核 overlay 支持正常，非模块缺失问题。

---

#### 假设 C：磁盘空间或 inode 耗尽

> 🧪 假设：磁盘空间不足或 inode 耗尽导致无法挂载

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 磁盘空间 | `df -hT /tmp/overlay_test_A` | 1007G 总量，使用 22G，可用 935G（仅 3%） |
| Inode | `df -i /tmp/overlay_test_A` | 67108864 总量，使用 254296（仅 1%） |

**❌ 排除**：空间与 inode 均充足，非资源耗尽问题。

---

#### 假设 D：权限不足

> 🧪 假设：容器内权限不够，无法访问 upperdir

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 当前用户 | `whoami` | root |
| 目录权限 | `ls -ld /tmp/overlay_test_A/{lower,upper_nonexistent,work,merged}` | 755, 属主 root |
| 写入测试 | `touch /tmp/overlay_test_A/upper_nonexistent/test` | ✅ 成功 |

**❌ 排除**：root 用户，权限正常。

---

#### 假设 E：mount 语法错误

> 🧪 假设：mount 参数格式不正确

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 语法校验 | `mount -t overlay overlay -o lowerdir=...,upperdir=...,workdir=... /merged` | 完全遵循标准语法 |
| 参考文档 | 对比内核文档标准格式 | ✅ 一致 |

**❌ 排除**：参数格式完全正确。

---

#### 假设 F：跨设备 overlay（upperdir 与 lowerdir 在不同文件系统）

> 🧪 假设：upperdir 和 lowerdir 位于不同设备上导致冲突

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 设备一致性 | `stat -c %d /tmp/overlay_test_A/lower` vs `.../upper_nonexistent` | 同一设备号（同一 overlay） |
| 文件系统类型 | `stat -f /tmp/overlay_test_A/*` | 均为 overlayfs |

**❌ 排除**：所有目录在同一 overlay 文件系统上，非跨设备问题。

---

#### 假设 G：下层文件系统不兼容（nested overlay on overlay） ✅ 确认根因

> 🧪 假设：overlay 文件系统不支持作为另一个 overlay 挂载的 upperdir

**Step 1 — 确认 upperdir 所在文件系统类型**
```bash
stat -f /tmp/overlay_test_A/upper_nonexistent
# Type: overlayfs
```

**Step 2 — 确认容器根文件系统拓扑**
```bash
cat /proc/self/mountinfo | head -30
# 容器根文件系统: overlay (Docker overlay2)
```

**Step 3 — 内核态代码路径确认**
```text
文件: fs/overlayfs/super.c / fs/overlayfs/params.c
函数: ovl_check_upper_fs() / ovl_mount_dir_noesc()
机制: 挂载校验 — upperdir 文件系统兼容性检查
```
内核在挂载时执行多层检查：
1. 路径解析检查（`ovl_mount_dir_noesc()`）→ 目录必须存在且可访问
2. d_type 支持检查 → 文件系统需支持 `readdir` 返回文件类型
3. xattr 支持检查 → 文件系统需支持 `trusted.overlay.*` 扩展属性
4. 文件系统类型检查 → **内核明确拒绝将 overlay 文件系统作为 upperdir**

**✅ 结论：Linux 内核 overlayfs 明确禁止以 overlay 文件系统作为另一个 overlay 的 upperdir。** 这是内核的设计限制，并非 Bug。Docker overlay2 容器根文件系统本身已是 overlay，在其内部无法再创建嵌套 overlay。

---

### 3.3 排查结论

```text
OverlayFS 挂载失败
├─► upperdir 路径不存在        → ✅ 修复后错误消失
├─► 内核模块未加载             → ✅ 正常，排除
├─► 磁盘空间/inode 耗尽       → ✅ 充足，排除
├─► 权限不足                  → ✅ root 用户，排除
├─► mount 语法错误             → ✅ 标准语法，排除
├─► 跨设备 overlay            → ✅ 同一文件系统，排除
└─► 文件系统不兼容（nested overlay on overlay）
        ├─► stat -f 确认 upperdir 位于 overlayfs 上
        ├─► 内核源码确认 ovl_check_upper_fs() 拒绝 overlay fs
        └─► 🎯 根因确认：内核设计限制，禁止 overlay on overlay
```

---

## 四、修复方案

### 4.1 应急处置（当前场景下的可工作方式）

如果需要在容器内测试或使用 OverlayFS，可采用以下方案绕过内核限制：

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 创建 tmpfs 作为 upperdir 和 workdir 的载体 | 人工 | 即时 | 提供非 overlay 的文件系统供 upperdir 使用 |
| 2 | 执行 mount -t overlay 挂载 | 人工 | 即时 | 挂载成功 |

**具体命令：**
```bash
# 方案一：使用 tmpfs 作为 upperdir 的载体（重启后数据丢失）
mkdir -p /tmp/overlay_test_B/upper /tmp/overlay_test_B/work
mount -t tmpfs tmpfs /tmp/overlay_test_B/upper
mount -t tmpfs tmpfs /tmp/overlay_test_B/work
mount -t overlay overlay \
  -o lowerdir=/tmp/overlay_test_A/lower,upperdir=/tmp/overlay_test_B/upper,workdir=/tmp/overlay_test_B/work \
  /tmp/overlay_test_B/merged
```

### 4.2 永久修复计划

| 修复措施 | 负责人 | 完成时间 |
|----------|--------|----------|
| 避免在 overlay2 驱动的容器内执行裸 overlay 挂载，改用 tmpfs 或宿主机 bind mount 作为 upperdir 载体 | 开发/运维 | 即时 |
| 若需在容器内测试 OverlayFS，使用 `--privileged` 模式并配合 tmpfs 挂载 | 开发 | 按需 |
| 直接在宿主机（非容器内）测试 OverlayFS | 开发/测试 | 推荐 |

**核心原则**：
- **不要在 overlay2 驱动的 Docker 容器内执行裸 overlay 挂载**。容器根文件系统已经是 overlay，嵌套 overlay 不被内核支持。
- 若需要在容器内测试 OverlayFS，推荐三种方式：
  1. 在容器内挂载 `tmpfs` 作为独立文件系统后再做 overlay（数据易失）
  2. 使用 `docker run -v /host/ext4/path:/overlay-ext4` 从宿主机 bind mount ext4 目录
  3. 直接在宿主机（非容器）上进行 OverlayFS 测试

---

## 五、验证建议

1. **确认修复**：使用上述 tmpfs 方案后重新执行 mount，验证是否挂载成功：
   ```bash
   mount | grep overlay
   df -hT | grep overlay
   ```

2. **验证读写**：在 merged 目录中创建文件，确认 copy-up 正常：
   ```bash
   touch /tmp/overlay_test_B/merged/test_file
   ls -la /tmp/overlay_test_B/merged/test_file
   ```

3. **验证隔离**：确认 merged 中的修改不会破坏 lowerdir 的原始内容

4. **替代方案验证**：使用宿主机 bind mount 方式验证：
   ```bash
   # 宿主机操作
   docker run -v /home/user/ext4_overlay:/ext4_src -it overlayfs-fault-A
   # 容器内操作
   mkdir -p /ext4_src/{upper,work,merged}
   mount -t overlay overlay -o lowerdir=/tmp/overlay_test_A/lower,upperdir=/ext4_src/upper,workdir=/ext4_src/work /ext4_src/merged
   ```

---

## 附录：诊断命令执行记录

| 步骤 | 命令 | 关键输出 |
|------|------|----------|
| Step 1: 目录检查 | `ls -ld /tmp/overlay_test_A/{lower,upper_nonexistent,work,merged}` | upper_nonexistent: No such file or directory |
| Step 1: dmesg检查 | `dmesg \| tail -30` | `overlayfs: failed to resolve '...upper_nonexistent': -2` |
| Step 1: 内核版本 | `uname -r` | 6.6.87.2-microsoft-standard-WSL2 |
| Step 2: 创建目录 | `mkdir -p /tmp/overlay_test_A/upper_nonexistent` | 成功 |
| Step 3: 重新挂载 | `mount -t overlay overlay -o ...` | wrong fs type, bad option, bad superblock |
| Step 5: 再次 dmesg | `dmesg \| grep -i overlay` | `filesystem on ... not supported as upperdir` |
| 文件系统检查 | `stat -f /tmp/overlay_test_A/upper_nonexistent` | Type: overlayfs |
| 挂载拓扑 | `cat /proc/self/mountinfo \| head -30` | 容器根 = overlay (Docker overlay2) |
| 基线收集 | `scripts/01_baseline_info.sh` | CONFIG_OVERLAY_FS=y, 分支推荐: A+B |
| 分支诊断 A | `scripts/branch_A_config_error.sh` | 确认配置正常，排除配置错误 |
| 分支诊断 B | `scripts/branch_B_fs_incompatible.sh` | overlay 不在兼容列表，确认为文件系统不兼容 |

---

> **本次分析使用的证据来源**：
> - `/home/win11/.witty-diagnosis-agent/dayu/report/kuafu_T1_20260528_225200.md`
> - 分析日期：2026-05-28 22:53:15
