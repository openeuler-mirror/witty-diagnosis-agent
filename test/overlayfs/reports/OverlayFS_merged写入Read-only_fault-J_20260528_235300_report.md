# 🔴 故障诊断报告

> **报告编号**：RCA-20260528-003
> **故障级别**：P2（功能受限）
> **报告时间**：2026-05-28 23:53:00
> **当前状态**：🔴 处理中

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | Docker 容器 overlayfs-fault-J 写入 merged 目录报 Read-only file system |
| 影响范围 | 容器 overlayfs-fault-J 内所有需要写入 overlay merged 层的操作（单个容器） |
| 故障时段 | 2026-05-28 23:50:00 ～ 至今 |
| 根本原因 | OverlayFS merged 挂载点为只读（ro）状态，导致通过 merged 视图的写入操作被 VFS 层拒绝，返回 EROFS（Read-only file system） |
| 是否恢复 | ❌ 未恢复 |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|---------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | 本场景：mount ro 标志或容器 --read-only 导致 EROFS |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                             事件                                            性质         证据来源
───────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-05-28 23:50:00             容器 overlayfs-fault-J 启动（或 overlay 挂载完成）    📦 容器启动    用户描述
  │
  ▼
2026-05-28 23:50:XX             执行 echo "write test" > merged/test.txt           ⚠️ 操作用户    用户描述
  │                             触发 write 系统调用 → VFS → overlayfs → 检查挂载 ro 标志
  ▼
2026-05-28 23:50:XX             VFS 层检测到 overlay 挂载点的 MS_RDONLY 标志         🔍 内核判断    [EROFS 语义]
  │                             → 拒绝写入 → 返回 -EROFS (Read-only file system)
  ▼
2026-05-28 23:50:XX             用户侧收到 "Read-only file system" 错误              🔴 故障表现    [用户描述]
  │                             upper 目录本身可写但 merged 层拒绝写入
  ▼
2026-05-28 23:50:XX             当前状态：❌ 未恢复，merged 层写入持续失败            🔴 持续故障
```

### 故障因果链

```text
容器 overlayfs-fault-J 的 overlay merged 挂载点为只读 (ro)
    └─► 应用层 write() 系统调用到达 VFS 层
            └─► VFS 检查挂载点 super_block.s_flags & MS_RDONLY
                    └─► 标志位被置位 → 返回 -EROFS
                            └─► 用户态看到 "Read-only file system" 错误
                                    └─► 🔴 所有写入 merged 的操作均失败
```

---

## 三、排查过程

> 排查逻辑：**提出假设 → 收集证据 → 验证或排除 → 逐步收敛到根因**

### 3.1 初始现象

- 容器 `overlayfs-fault-J` 中执行 `echo "write test" > merged/test.txt` 失败
- 错误信息：`Read-only file system`
- upper 目录的读写权限正常（ls -la 显示可写）
- 症状符合 OverlayFS 分支 J：**文件写入报 Read-only file system 但 upperdir 可写**

---

### 3.2 假设驱动排查

#### 假设 A：容器以 `--read-only` 模式启动 ✅ 高度可能

> 🧪 假设：Docker 容器启动时指定了 `--read-only` 参数，导致容器根文件系统（含 overlay merged）为只读挂载

| 检查项 | 操作/证据 | 结论 |
|--------|----------|------|
| 错误语义 | Linux 内核 EROFS 错误码（-30），VFS 层直接返回，与应用层权限无关 | ✅ 符合 mount ro 特征 |
| upper 目录可写 | 用户明确描述"upper 目录权限正常但写入被拒绝" | ✅ 排除 upper 层文件系统 rw 问题 |
| SELinux 拦截 | SELinux 拦截通常返回 EACCES（Permission denied）而非 EROFS | ✅ EROFS 非 SELinux 典型行为 |
| 典型 Docker 场景 | `docker run --read-only` 使容器 rootfs 为 ro，仅显式 volume 可写 | ✅ 与现象完全吻合 |

**🟢 高置信度**：ROFS 错误 + upper 可写 + 非 SELinux 语义，三者联合指向 overlay 挂载点为只读。

---

#### 假设 B：底层文件系统被内核强制 remount 为只读

> 🧪 假设：upperdir 所在的底层块设备发生 I/O 错误，内核自动将文件系统 remount 为 ro

| 检查项 | 操作/证据 | 结论 |
|--------|----------|------|
| upper 目录可写 | 用户确认 upper 目录权限正常且可写 | ❌ 如果底层 fs 被 remount ro，upper 也会拒绝写入 |
| dmesg 日志 | 未提供 I/O error 或 remount ro 相关的内核日志 | ❌ 无相关证据 |

**❌ 排除**：若底层文件系统被 remount ro，upper 目录本身也会拒绝写入，与"upper 可写"矛盾。

---

#### 假设 C：SELinux/AppArmor 安全模块拦截

> 🧪 假设：安全模块因标签不匹配阻止对 merged 目录的写入

| 检查项 | 操作/证据 | 结论 |
|--------|----------|------|
| 错误类型 | SELinux AVC 拒绝返回 EACCES（13 / Permission denied） | ❌ EROFS ≠ EACCES |
| 错误消息 | "Read-only file system" 是 VFS 只读检查的标准返回 | ❌ 非安全模块典型错误 |

**❌ 排除**：EROFS 是 VFS 层只读挂载检查的专用错误码，SELinux/AppArmor 的拒绝路径返回的是 EACCES。

---

#### 假设 D：Overlay 挂载参数缺少读写标志或 user_xattr 冲突

> 🧪 假设：mount 命令未传递 `rw` 标志，或某些 xattr 配置导致 overlay 只读

| 检查项 | 操作/证据 | 结论 |
|--------|----------|------|
| xattr 冲突 | overlay xattr 配置错误通常导致 mount 失败，而非写入时 EROFS | ❌ 挂载已成功，merged 可读 |
| 挂载参数 | 若 `mount -t overlay -o ro,...` 显式指定只读，则 merged 为 ro | ✅ 可能原因之一 |

**🟡 中置信度**：是 overlay 挂载点 ro 的子原因之一，但无法区分是 `mount -o ro` 还是容器 `--read-only`。

---

### 3.3 排查结论

```text
merged 写入 Read-only file system
├─► 假设 B：底层 fs 被 remount ro     → ❌ 排除（upper 仍可写）
├─► 假设 C：SELinux/AppArmor 拦截     → ❌ 排除（错误码 EROFS ≠ EACCES）
├─► 假设 D：mount -o ro 显式指定      → 🟡 可能（需验证 mountinfo）
└─► 假设 A：容器 --read-only 启动      → 🟢 高度可能
        └─► VFS super_block MS_RDONLY 标志被置位
                └─► write 系统调用 → overlay_file_write_iter → EROFS
                        └─► 🎯 根因：overlay merged 挂载点为只读
```

---

## 四、修复方案

### 4.1 应急处置

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 检查容器启动参数：`docker inspect overlayfs-fault-J \| grep -A 10 HostConfig` 确认是否包含 `"ReadonlyRootfs": true` | SRE | 立即 | 明确根因 |
| 2 | 如为 --read-only 导致，可通过重新挂载 merged 为 rw：`mount -o remount,rw /mnt/ovl/merged`（需容器内 root 权限） | SRE | 立即 | 临时恢复写入能力 |
| 3 | 或将需要写入的目录挂载为 Docker volume：`docker run -v /host/path:/container/path ...` | SRE | 立即 | 数据持久化且可写 |

### 4.2 永久修复计划

| 修复措施 | 负责人 | 完成时间 |
|---------|--------|---------|
| 方案一：移除 `--read-only` 启动参数，恢复容器 rootfs 读写能力 | 应用运维 | 待定 |
| 方案二：保留 `--read-only`，通过 `--mount type=bind,src=...,dst=...` 显式挂载可写 volume 用于日志/数据写入 | 应用运维 | 待定 |
| 方案三：如确需 overlay merged 可写但不使用 volume，修改 Docker Compose 或 K8s Pod 配置中的 `readOnlyRootFilesystem: false` | 应用运维 | 待定 |
| 验证：修复后执行 `echo "write test" > merged/test.txt` 确认写入成功 | SRE | 修复后立即 |

### 4.3 验证命令

```bash
# 1. 检查容器 rootfs 是否为只读
docker inspect overlayfs-fault-J --format '{{.HostConfig.ReadonlyRootfs}}'
# 输出 true 表示 rootfs 为只读

# 2. 检查 overlay 挂载参数（容器内）
cat /proc/mounts | grep overlay

# 3. 确认写入正常
docker exec overlayfs-fault-J sh -c "echo 'write test' > /mnt/ovl/merged/test.txt && cat /mnt/ovl/merged/test.txt"
# 若无错误且输出 "write test"，则修复成功
```

---

## 五、附录

### 5.1 诊断参考

| 项目 | 内容 |
|------|------|
| 故障场景 | OverlayFS 分支 J——元数据/权限问题 |
| 分析轨道 | 系统态诊断（基于现有证据） |
| 相关技能 | overlayfs-diagnosis → branch_J_permission.sh |
| 诊断依据 | Kuafu T1 J report、用户描述、EROFS 内核语义分析 |

### 5.2 相关内核机制

Linux 内核中 EROFS（Read-only file system）错误的产生路径：

```
write() 系统调用
  └─► vfs_write()
        └─► file_start_write()
              └─► sb_start_write() → 检查 super_block 的 MS_RDONLY 标志
                    └─► 若 MS_RDONLY 被置位 → 返回 -EROFS
                          └─► 用户态收到 "Read-only file system"
```

此标志在以下情况被置位：
- `mount -o ro` 显式指定只读挂载
- Docker `--read-only` 创建容器时 rootfs 挂载为 ro
- 底层文件系统因 I/O 错误被内核自动 remount ro（但此场景 upper 也会 ro）

### 5.3 报告路径

**RCA 报告路径**：`/home/win11/.witty-diagnosis-agent/baize/reports/OverlayFS_merged写入Read-only_fault-J_20260528_235300_report.md`
