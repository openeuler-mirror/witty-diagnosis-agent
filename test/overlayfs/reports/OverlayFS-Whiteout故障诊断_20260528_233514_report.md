# OverlayFS Whiteout/Opaque 故障诊断报告

> **报告编号**：RCA-20260528-001
> **故障级别**：P3（测试/验证环境故障注入分析）
> **报告时间**：2026-05-28 23:35:14
> **当前状态**：🟢 根因已确认（通过独立测试验证）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | OverlayFS `.wh.` 前缀常规文件 whiteout 失效导致 merged 层文件仍可见 |
| 影响范围 | Docker 容器 `overlayfs-fault-D`（containerd overlay2 存储驱动），容器根文件系统为 overlay 挂载 |
| 故障时段 | 2026-05-28 15:33:58 ～ 持续中（诊断确认阶段） |
| 根本原因 | Linux 内核 6.6.87.2-microsoft-standard-WSL2 未启用 `CONFIG_OVERLAY_FS_METACOPY`，仅支持传统字符设备 (0,0) whiteout 机制。注入的 `.wh.` 前缀零长度常规文件不被内核识别为 whiteout，导致 lower 层对应文件在 merged 中仍然可见 |
| 是否恢复 | ❌ 未恢复（故障注入场景，需手动修复 whiteout 注入方式） |
| 根因置信度 | 🟢 高置信（通过 ext4 loop 设备独立 overlay 测试验证，因果链完整） |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|--------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | 本场景：内核缺失 METACOPY → char 0/0 唯一生效 → `.wh.` 前缀无效 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                          事件                                                         性质          溯源路径
──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-05-28 15:33:58          诊断开始：检查容器 overlayfs-fault-D 的 overlay 挂载拓扑              🔍 诊断启动   [kuafu_T1_20260528_153358.md:13-19]
  │
  ▼
2026-05-28 15:33:58          发现 upper 目录中存在 3 个 .wh. 前缀零长度常规文件                   ⚠️ 异常发现   [kuafu_T1_20260528_153358.md:49]
  │                          .wh.secret.key, .wh.data.db, .wh.backup.tar（均为常规文件）
  ▼
2026-05-28 15:33:58          尝试设置 trusted.overlay.whiteout xattr → "Operation not supported"   ❌ 阻塞点     [kuafu_T1_20260528_153358.md:50]
  │
  ▼
2026-05-28 15:33:58          尝试容器内嵌套 overlay 挂载 → upperdir 不被接受                     ❌ 阻塞点     [kuafu_T1_20260528_153358.md:51]
  │                          (容器根已是 overlay，不支持作为另一个 overlay 的 upperdir)
  ▼
2026-05-28 15:33:58          检查内核配置 → CONFIG_OVERLAY_FS_METACOPY 未设置                    🔴 根因发现   [kuafu_T1_20260528_153358.md:72-79]
  │
  ▼
2026-05-28 15:33:58          转向 ext4 loop 设备独立 overlay 验证测试                            🧪 验证测试   [kuafu_T1_20260528_153358.md:56-69]
  │                          ├─ char(0,0) whiteout → ✅ 生效（merged 中文件消失）
  │                          ├─ xattr whiteout → ❌ 不生效（需 METACOPY）
  │                          └─ .wh. 前缀常规文件 → ❌ 不生效（纯 tar 约定）
  ▼
2026-05-28 15:33:58          根因确认：内核不支持 METACOPY → 仅 char(0,0) whiteout 有效        🟢 结论锁定
```

### 故障因果链

```text
故障注入：上层创建 .wh. 前缀零长度常规文件 (预期：隐藏 lower 同名文件)
    │
    ├─► 内核 readdir 检查 upper 中的 .wh.secret.key
    │       ├─► 是否为 char(0,0) 设备？ → ❌ 是常规文件
    │       ├─► 是否有 trusted.overlay.whiteout xattr？ → ❌ xattr 不可用（无 METACOPY）
    │       └─► 结论：不是 whiteout → 作为常规文件显示
    │
    ├─► lower 中的 secret.key 未被遮盖
    │       └─► 同时显示在 merged 中（来自 lower）
    │
    └─► 🔴 merged 目录中文件全部可见（与注入预期相反）
            ├─► lower/ 中的 secret.key, data.db, backup.tar → 可见
            └─► upper/ 中的 .wh.secret.key, .wh.data.db, .wh.backup.tar → 作为独立文件可见

根本原因层：
    ┌─► Linux 内核 6.6.87.2 WSL2 内核配置
    │       ├─► CONFIG_OVERLAY_FS=y
    │       ├─► # CONFIG_OVERLAY_FS_METACOPY is not set ← 关键缺失
    │       ├─► # CONFIG_OVERLAY_FS_INDEX is not set
    │       └─► # CONFIG_OVERLAY_FS_XINO_AUTO is not set
    │
    └─► 内核 whiteout 支持矩阵
            ├─► char(0,0) 设备 whiteout → ✅ 基础支持（始终可用）
            ├─► .wh. 前缀文件 → ❌ 纯 tar/导出格式约定，内核不识别
            ├─► xattr trusted.overlay.whiteout → ❌ 需 CONFIG_OVERLAY_FS_METACOPY=y
            └─► opaque xattr trusted.overlay.opaque → ⚠️ 可设置但不立即生效（目录缓存）
```

---

## 三、排查过程

### 3.1 初始现象

- **故障注入**：在 Docker 容器 `overlayfs-fault-D` 的 upper 目录 `/tmp/overlay_test_D/upper/` 中创建了 3 个 `.wh.` 前缀的零长度常规文件（`.wh.secret.key`、`.wh.data.db`、`.wh.backup.tar`），预期通过命名约定使 lower 层对应文件在 merged 中隐藏。
- **预期行为**：`.wh.` 前缀文件应被 OverlayFS 内核识别为 whiteout，merged 目录中对应 lower 层文件（`secret.key`、`data.db`、`backup.tar`）不可见。
- **实际现象**：merged 目录中所有 lower 层文件依然可见，同时 `.wh.` 前缀文件本身也作为独立常规文件出现在 merged 中。
- **次级现象**：`subdir` 目录的 `trusted.overlay.opaque` xattr 无法在容器根 overlay 文件系统上设置（"Operation not supported"）。

### 3.2 假设驱动排查

#### 假设 A：`.wh.` 前缀文件本身即为内核 whiteout 机制

> 🧪 假设：OverlayFS 内核会将任何 `.wh.` 前缀的常规文件视为 whiteout，并隐藏对应 lower 层文件

| 检查项 | 操作 | 结论 |
|--------|------|------|
| Whiteout 文件特征 | `stat .wh.secret.key` 查看文件类型 | 常规文件（不是字符设备 0,0） |
| 内核配置检查 | `cat /proc/config.gz \| grep OVERLAY` | `CONFIG_OVERLAY_FS_METACOPY` 未设置 |
| 内核文档/源码对照 | OverlayFS whiteout 实现机制溯源 | `.wh.` 前缀仅为 tar 归档导出约定 |
| ext4 验证测试 | 在独立 ext4 overlay 上 touch `.wh.` 文件 | `.wh.backup.tar` 文件在 merged 中仍可见 |

**❌ 排除**：`.wh.` 前缀常规文件不被内核识别为 whiteout，该命名约定仅为 tar/export 工具的兼容性实现，非内核级机制。内核仅识别字符设备 (major=0, minor=0) 为 whiteout。

---

#### 假设 B：xattr-based whiteout 在所有内核版本均有效

> 🧪 假设：通过 `setfattr trusted.overlay.whiteout` 设置扩展属性即可实现 whiteout，无需依赖内核特性

| 检查项 | 操作 | 结论 |
|--------|------|------|
| xattr 可用性 | `setfattr -n trusted.overlay.whiteout upper/data.db` | ❌ "Operation not supported" |
| 内核配置关联 | 查阅 OverlayFS xattr whiteout 的实现要求 | 需要 `CONFIG_OVERLAY_FS_METACOPY=y` |
| ext4 验证测试 | 在独立 ext4 overlay 上设置 xattr whiteout | `data.db` 在 merged 中仍可见 |
| 交叉验证 | char(0,0) + xattr 同时设置 | char(0,0) 生效，xattr 无额外作用 |

**❌ 排除**：xattr-based whiteout 需要内核编译时启用 `CONFIG_OVERLAY_FS_METACOPY`。本内核未启用该选项，因此 `trusted.overlay.whiteout` xattr 被内核忽略。

---

#### 假设 C：Opaque 目录标记立即可见效果 ✅ 部分确认

> 🧪 假设：为 upper 中的 `subdir` 设置 `trusted.overlay.opaque` xattr 后，lower 层的同名目录内容会被立即隐藏

| 检查项 | 操作 | 结论 |
|--------|------|------|
| xattr 可用性 | `setfattr -n trusted.overlay.opaque upper/subdir` | ❌ 容器内无法设置（overlay 上不支持） |
| ext4 验证测试 | 在 ext4 上预置 opaque + 挂载 overlay | ⚠️ 需在挂载前设置，或挂载后清目录缓存 |

**⚠️ 部分确认**：
- 在容器根 overlay 上完全无法设置 opaque xattr（同因：文件系统类型限制）
- 在 ext4 底层文件系统上可以设置 opaque，但生效时机取决于内核目录缓存状态：若在挂载 **后** 设置 opaque，已缓存的 lower 条目不会自动消失，需要重新挂载或清缓存

---

#### 假设 D：嵌套 overlay 可直接挂载

> 🧪 假设：容器内部（根已是 overlay）可以再挂载一个新的 overlay，以容器内目录作为 upperdir

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 嵌套挂载尝试 | `mount -t overlay overlay -o ... /tmp/overlay_test_D/merged` | ❌ "filesystem on .../upper not supported as upperdir" |
| 原理分析 | overlay 文件系统本身不支持作为另一个 overlay 的 upperdir | upperdir 需要底层文件系统支持 xattr 和 d_type |

**❌ 排除**：OverlayFS 不支持嵌套（overlay on overlay），upperdir 必须建立在传统本地文件系统（ext4/xfs）上。这与 METACOPY 无关，是 OverlayFS 架构限制。

---

### 3.3 排查结论

```text
OverlayFS Whiteout 失效
│
├─► 假设 A：.wh. 前缀即为 whiteout                    → ❌ 排除
│       └─► 仅 tar 归档约定，内核不识别
│
├─► 假设 B：xattr whiteout 通用有效                   → ❌ 排除
│       └─► 需要 CONFIG_OVERLAY_FS_METACOPY=y
│           └─► 本内核 (WSL2 6.6.87.2) 未启用
│
├─► 假设 C：Opaque 标记立即可见                      → ⚠️ 部分确认
│       └─► 需预置或 remount，不生效于当前场景
│
├─► 假设 D：嵌套 overlay 可直接挂载                  → ❌ 排除
│       └─► overlay 不允许作为另一个 overlay 的 upperdir
│
└─► 🎯 根因确认：内核缺失 METACOPY + .wh. 文件不为 char(0,0)
        ├─► 决定性证据：独立 ext4 overlay 测试 100% 复现
        │   ├─ char(0,0) → ✅ 隐藏成功
        │   └─ .wh. 常规文件 → ❌ 隐藏失败
        └─► 内核配置决定性证据：/proc/config.gz 明确显示
            └─► # CONFIG_OVERLAY_FS_METACOPY is not set
```

---

## 四、修复方案

### 4.1 应急处置（当前故障注入场景下）

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 删除 upper 中的无效 `.wh.` 前缀常规文件 | 系统/人工 | 立即 | 清除非预期的文件显示 |
| 2 | 使用字符设备 whiteout 替代 `.wh.` 前缀文件 | 系统/人工 | 立即 | 正确隐藏 merged 中对应 lower 文件 |
| 3 | 若需隐藏而非 whiteout，可用 `cp /dev/null upper/file` 遮盖 | 系统/人工 | 立即 | 零长度文件遮盖 lower 同名内容 |

应急处置命令：

```bash
# Step 1: 清理无效的 .wh. 前缀常规文件
rm /tmp/overlay_test_D/upper/.wh.secret.key
rm /tmp/overlay_test_D/upper/.wh.data.db
rm /tmp/overlay_test_D/upper/.wh.backup.tar

# Step 2: 使用正确的 whiteout 方法（字符设备 0,0）
mknod /tmp/overlay_test_D/upper/secret.key c 0 0
mknod /tmp/overlay_test_D/upper/data.db c 0 0
mknod /tmp/overlay_test_D/upper/backup.tar c 0 0

# 验证 whiteout 效果
ls /tmp/overlay_test_D/merged/    # 预期：secret.key, data.db, backup.tar 消失
```

### 4.2 永久修复计划

| 修复措施 | 负责人 | 完成时间 |
|--------|------|--------|
| **容器内 OverlayFS 测试迁移**：使用 ext4 loop 设备或 tmpfs 作为底层文件系统构建独立 overlay，避免嵌套限制 | 测试团队 | 下一迭代 |
| **内核配置加固**：如生产环境需 xattr whiteout，重新编译内核启用 `CONFIG_OVERLAY_FS_METACOPY=y` 及 `CONFIG_OVERLAY_FS_INDEX=y` | 内核/基础设施团队 | 按需评估 |
| **Whiteout 注入规范制定**：明确指导团队在不同内核版本下的正确 whiteout 注入方法，区分 `char(0,0)` 与 `.wh.` 前缀的语义差异 | SRE 团队 | 1 周内 |
| **OverlayFS 白盒测试覆盖**：补充不同内核配置下的 whiteout/opaque 行为测试用例，纳入 CI | 测试团队 | 2 周内 |

### 4.3 不同内核配置下的 Whiteout 支持矩阵

| 内核特性 | char(0,0) whiteout | `.wh.` 前缀文件 | xattr whiteout | opaque xattr |
|---------|-------------------|-----------------|---------------|-------------|
| 基础 OverlayFS（本内核） | ✅ 支持 | ❌ 不支持 | ❌ 不支持 | ✅ 支持（需预置） |
| + METACOPY | ✅ 支持 | ❌ 不支持 | ✅ 支持 | ✅ 支持 |
| + METACOPY + INDEX | ✅ 支持 | ❌ 不支持 | ✅ 支持 | ✅ 支持（增强一致性） |

---

## 五、经验教训与建议

### 5.1 根因总结

**直接原因**：故障注入者使用了 `.wh.` 前缀的常规文件来模拟 whiteout。这种方式是 tar/export 工具导出 whiteout 时的 **存档格式约定**，而非 OverlayFS 内核识别 whiteout 的机制。内核仅将字符设备 (major=0, minor=0) 识别为 whiteout。

**深层原因**：Linux 内核 6.6.87.2-microsoft-standard-WSL2 的 OverlayFS 实现缺失 `CONFIG_OVERLAY_FS_METACOPY` 特性。即使通过 `setfattr trusted.overlay.whiteout` 设置 xattr，内核也会忽略，因为 xattr-based whiteout 需要 METACOPY 支持。

**限制因素**：
1. 容器根文件系统本身就是 overlay，无法在其上设置 whiteout xattr（"Operation not supported"）
2. 无法在容器内嵌套挂载新的 overlay（overlay 不能作为另一个 overlay 的 upperdir）
3. Opaque 标记在挂载后设置需要重新挂载才能生效

### 5.2 正确做法

在 WSL2 / 无 METACOPY 内核上实现 whiteout：

```bash
# ✅ 正确的 whiteout：字符设备 (0,0)
mknod /path/to/upper/secret.key c 0 0

# ✅ 或者通过删除 merged 中的文件让内核自动创建 whiteout
rm /path/to/merged/secret.key

# ❌ 错误的做法：创建 .wh. 前缀文件
touch /path/to/upper/.wh.secret.key    # 内核不识别

# ❌ 错误的做法：设置 xattr（需 METACOPY）
touch /path/to/upper/data.db
setfattr -n trusted.overlay.whiteout /path/to/upper/data.db  # 本内核忽略
```

---

## 六、验证建议

| 验证项 | 方法 | 预期结果 |
|--------|------|--------|
| char(0,0) whiteout 验证 | `mknod upper/secret.key c 0 0` → `ls merged/` | `secret.key` 消失 |
| `.wh.` 前缀无效验证 | `touch upper/.wh.backup.tar` → `ls merged/` | `backup.tar` 仍可见，`.wh.backup.tar` 也可见 |
| Opaque 预置验证 | `mkdir upper/dir && setfattr ... && mount overlay` | lower 同名目录内容被隐藏 |
| xattr 内核依赖验证 | 对比 METACOPY 启用/未启用内核 | 仅 METACOPY 启用时 xattr 生效 |
| 容器内 whiteout 验证 | 容器 overlay 根上 `mknod ... c 0 0` | ✅ 应成功（`mknod` 不依赖 METACOPY） |

---

## 诊断执行记录

| 步骤 | 操作 | 结果 |
|------|------|------|
| 1 | 读取 Kuafu 报告：`kuafu_T1_20260528_153358.md` | 获取证据：挂载拓扑、目录结构、异常现象、内核配置 |
| 2 | 加载 Skill：`fault-rca-report-generation` | 获取分析方法论与报告模板 |
| 3 | 场景判断：故障诊断 | OverlayFS whiteout/opaque 失效 |
| 4 | 证据分析：4 个假设的逐个验证 | 排除 3 个假设，确认 1 个根因 |
| 5 | 根因锁定：内核无 METACOPY → char(0,0) 唯一生效 | 🟢 高置信 |
| 6 | 报告生成与写入 | 写入 `.../OverlayFS-Whiteout故障诊断_20260528_233514_report.md` |
