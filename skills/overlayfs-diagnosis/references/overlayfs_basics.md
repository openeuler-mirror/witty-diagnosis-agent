# OverlayFS 内核基础概念与机制

> 本文件配合 SKILL.md 第三节统一诊断流程使用，提供 overlayfs 内核机制的基础知识储备。
> 覆盖从 v4.x 到 v6.x 的主要行为。

---

## 一、OverlayFS 核心架构

### 1.1 三层结构

```
┌──────────────────────────────────────────────────────┐
│                    merged （合并视图）                  │
│       用户看到的是这一层的合并结果                       │
├──────────────────────────────────────────────────────┤
│                    upper （读写层）                    │
│  所有对 merged 的修改（增/删/改）都反映在这里           │
│  文件系统必须支持 xattr（trusted.overlay.* 命名空间）   │
├──────────────────────────────────────────────────────┤
│                    lower （只读层，可多个）              │
│  原始数据层，可叠加多个 lowerdir（":" 分隔），只读      │
│  不支持 xattr 中的 overlay 命名空间也可工作             │
└──────────────────────────────────────────────────────┘
```

### 1.2 关键目录角色

| 目录 | 必须性 | 文件系统要求 | 说明 |
|------|--------|------------|------|
| `lowerdir` | 必须要 | 可只读 | 一个或多个，":"分隔。多层时顺序：最左为最高优先 lower |
| `upperdir` | 选配（RW 必需） | 可读写，支持 overlay xattr | 所有变更写入此层 |
| `workdir` | 选配（RW 必需） | 与 upperdir 同一文件系统 | 存放临时文件（copy-up 过程中的中间文件） |
| `merged` | 挂载点 | - | 呈现层的最终视图 |

> **核心约束**：`upperdir` 和 `workdir` **必须在同一文件系统**（同一设备）。`lowerdir` 可以跨设备。

### 1.3 多层 lowerdir 的查找顺序

```text
查找优先级：upper > lower[0] > lower[1] > ... > lower[n]
                   最高优先                    最低优先
```

---

## 二、关键内核机制

### 2.1 Copy-up（写时复制）

OverlayFS 的核心机制：对 lower 层文件的修改不需要复制整个文件内容。

**触发条件**：
- 对 lower 文件的**修改**（写/截断/chmod/chown/utimens）
- 对 lower 文件的**删除**（在 upper 创建 whiteout）
- 对 lower 文件的**重命名**（涉及目录时较复杂）

**流程**：
```
1. open("/merged/file", O_WRONLY)   # 打开 lower 文件写入
2. 内核识别到该文件在 lower，不在 upper
3. ovl_copy_up() 调用：
   a. workdir 中创建临时文件
   b. lower → 临时文件 数据拷贝
   c. 元数据（权限/owner/xattr）同步
   d. 临时文件重命名为 upperdir 中的目标文件
   e. 删除 workdir 中的临时文件
4. open 操作重定向到 upper 中新拷贝的文件
5. 写入实际发生在上层文件
```

**性能影响**：
- 首次写入大文件的时间 = 文件大小 / IO 吞吐量（额外一次完整的读+写）
- 小文件/元数据修改通常可接受
- 大量小文件的写触发大量 copy-up → 性能急剧下降

**内核代码路径**：`fs/overlayfs/copy_up.c`

### 2.2 Opaque 目录

**含义**：opaque 标记用于阻止从 lower 层读取目录内容。

**场景**：当 upper 层需要"遮盖"某个目录，使其在 merged 视图中只显示 upper 中的内容，不显示 lower 中的任何内容时，upper 目录会被标记为 opaque。

**检查方式**：
```bash
# 检查目录是否有 opaque xattr
getfattr -d -m - /upper/some/dir/ | grep "trusted.overlay.opaque"
# 返回值 "y" 表示 opaque
```

**内核代码路径**：`fs/overlayfs/readdir.c` — `ovl_check_whiteouts()` / `ovl_opaquedir()`

### 2.3 Whiteout 节点

**含义**：Whiteout 是 upper 层中的特殊文件，表示"此文件在 merged 中不可见"。

**实质**：whiteout 是一个特殊的**字符设备节点**（`0,0` 设备号），通常带有 `trusted.overlay.whiteout` xattr。

**作用场景**：
- 删除 lower 层的文件时，upper 层不会真正删除（因为 lower 是只读的），而是在 upper 创建一个 whiteout 来"遮盖"它
- readdir 时遇到 whiteout 会跳过对应的 lower 条目

**检查方式**：
```bash
# 方法1：检查字符设备节点
ls -la /upper/dir/
crw------- 1 root root 0, 0 ... .wh.filename  # 传统 whiteout 命名
# 注意：重命名后的 whiteout 可以没有 .wh. 前缀，通过 xattr 识别

# 方法2：检查 xattr（更可靠）
getfattr -d -m - /upper/path/file | grep "trusted.overlay.whiteout"
```

**命名约定**：
- 传统模式：`.wh.<filename>`（在 merged 中隐藏对应的 filename）
- 新内核（v5.10+）：普通文件/目录名 + `trusted.overlay.whiteout` xattr

**内核代码路径**：`fs/overlayfs/whiteout.c` — `ovl_whiteout()` / `ovl_check_whiteout()`

### 2.4 Redirect 目录

**含义**：Redirect 是 overlayfs 为支持跨层目录重命名而引入的机制（v4.18+）。

**实现方式**：目录在 upper 层被重命名后，原位置会留下一个 xattr（`trusted.overlay.redirect`），指向新的路径。

**配置控制**：
```bash
# 挂载时控制 redirect_dir 行为
mount -t overlay overlay -o lowerdir=/lower,upperdir=/upper,workdir=/work,redirect_dir=on /merged

# redirect_dir 模式：
#   on            - 启用（默认，v4.18+）
#   off           - 关闭
#   follow        - 跟随 redirect（兼容旧行为）
#   nofollow      - 不跟随（忽略 redirect）
```

**涉及的内核代码**：`fs/overlayfs/readdir.c` — `ovl_redirect_directory()`

### 2.5 Metacopy

**含义**：Metacopy（v5.10+）是一种优化机制，允许仅 copy-up 文件的元数据（inode 属性）而**不复制数据内容**到 upper 层。

**适用场景**：
- chmod/chown 等只改属性的操作
- 大文件的属性修改——避免完整的数据拷贝

**检查方式**：
```bash
# 查看 metacopy 状态
cat /sys/module/overlay/parameters/metacopy
# 0 = 禁用，1 = 启用（默认启用）

# 检查文件是否使用 metacopy
getfattr -d -m - /upper/path/file | grep "trusted.overlay.metacopy"
# 存在此 xattr 表示文件是 metacopy 状态
```

### 2.6 Index（索引目录）

**含义**：Index（v4.13+）是 overlayfs 的一致性保护机制，通过在 upperdir 内创建 `.overlay.upperidx` 和 `.overlay.loweridx` 目录来追踪文件。

**作用**：
- 防止 hardlink 的 copy-up 不一致
- 检测 lower 层的变更
- 防止文件"别名"问题

**启用方式**：
```bash
mount -t overlay overlay -o lowerdir=/lower,upperdir=/upper,workdir=/work,index=on /merged
```

### 2.7 NFS Export

**含义**：OverlayFS（v5.11+）支持通过 `nfs_export=on` 导出合并视图，但会有额外的编码要求。

**限制**：
- 需要 `index=on`
- 文件句柄在重启后可能不稳定
- 某些操作（如 unlink 后立刻通过文件句柄访问）可能返回 EACCES

---

## 三、OverlayFS 关键内核参数（/sys/module/overlay/parameters/）

| 参数 | 默认 | 说明 | 修改方式 |
|------|------|------|---------|
| `metacopy` | Y (v5.10+) | 启用 metacopy 优化 | 模块参数/挂载选项 |
| `redirect_dir` | on (v4.18+) | 目录重定向行为 | 挂载时 redirect_dir= |
| `ovl_redirect_dir_always_follow` | N | 是否始终跟随 redirect | 模块参数 |
| `xino` | auto (v5.4+) | 伪 inode 号生成策略 | 挂载时 xino= |
| `user_xattr` | N | 是否支持 user. xattr 命名空间 | 模块参数/挂载选项 |
| `check_copy_up` | N (v5.8+) | copy-up 时检查数据一致性 | 模块参数 |

---

## 四、OverlayFS 内核版本特性速查

| 特性 | 引入版本 | 说明 |
|------|---------|------|
| 基础 overlay | v2.6.22 (experimental) | 首次合入 |
| overlay 稳定化 | v3.18 | 标记为稳定 |
| 多层 lowerdir | v3.18 | 支持多个 lower 层（":"分隔）|
| Index 目录 | v4.13 | index=on 支持硬链接一致性 |
| Redirect 目录 | v4.18 | 支持跨层目录重命名 |
| xino (伪 inode) | v5.4 | 降低 inode 号冲突概率 |
| metacopy | v5.10 | 仅复制元数据不复制数据 |
| NFS export | v5.11 | 支持 overlay 的 NFS 导出 |
| 复合 whiteout | v5.10+ | 使用 xattr 替代 .wh. 前缀命名 |

---

## 五、OverlayFS 常见内核态检查场景

### 5.1 挂载参数解析过程

```text
fs/overlayfs/params.c 中的核心流程：
1. ovl_parse_layer()  — 解析 lowerdir/upperdir/workdir
2. ovl_opt2string()   — 将选项转为内核字符串
3. ovl_parse_param()  — 逐一解析各选项
4. ovl_mount_dir()    — 验证目录是否存在/可访问
5. ovl_mount_dir_noesc() — 验证文件系统兼容性
```

### 5.2 跨设备检查逻辑

```text
fs/overlayfs/util.c 中的 ovl_same_fs() 和 ovl_mount_dir_noesc()
核心逻辑：检查 upperdir 和 workdir 是否在同一超级块（super_block）
方法：比较两个路径的 st_dev
若跨设备，返回 -EXDEV（"cross-device link"）
```

### 5.3 下层文件系统兼容性检查

```text
fs/overlayfs/super.c 中的 ovl_check_origin_fs()
检查下层 fs 是否支持 d_type（readdir 需要）
不支持的文件系统（如某些 FUSE）会报错或降速
特殊处理：tmpfs、ext4/xfs/btrfs 等主流 fs 均支持
```

### 5.4 Opaque 标记处理

```text
fs/overlayfs/readdir.c
ovl_iterate() 遍历 merged 目录时：
1. 先读 upper 条目（如有 opaque，直接返回 upper 结果）
2. 若没有 opaque，继续合并 lower 条目
3. 遇到 whiteout 时跳过 lower 对应条目
4. 遇到 redirect 时到新位置继续收集条目
```

---

## 六、典型内核 Bug 与 Fix 模式

| 问题 | 影响版本 | 内核修复 |
|------|---------|---------|
| metacopy + 硬链接导致数据损坏 | v5.10~v5.16 | commit a62f3e3e |
| redirect_dir 在多层 lower 中丢失 | v4.18~v5.8 | commit 0e5d2a1e |
| inotify 事件传递异常 | v3.18~v5.12 | commit 3e2b0e33 |
| opaque 目录在 rename 后失效 | v4.13~v5.4 | commit 6b7826e3 |
| copy-up 后文件属主不一致 | v4.18~v5.10 | commit 4ed7e16e |
| NFS export + overlay 死锁 | v5.11~v5.15 | commit 87e2a5d3 |
| whiteout 与 hardlink 冲突 | v4.13~v5.6 | commit 2b88f7a6 |
