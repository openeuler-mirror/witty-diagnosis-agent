# 故障诊断报告

> **报告编号**：RPT-20260528-OVERLAY-Z-001
> **故障级别**：N/A（验证通过，无故障）
> **报告时间**：2026-05-28 23:54:26
> **当前状态**：🟢 已恢复（验证通过，系统运行正常）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | Docker 容器 overlayfs-fault-Z 最小化 overlay 验证 |
| 影响范围 | 容器 overlayfs-fault-Z（单容器 overlay 文件系统功能验证） |
| 故障时段 | 2026-05-28 23:53:00 ～ 2026-05-28 23:54:00（验证执行窗口） |
| 根本原因 | 未发现异常——所有 overlay 操作均按预期正常工作 |
| 是否恢复 | ✅ 已恢复（始终正常） |
| 根因置信度 | 🟢 高置信（所有检查项均通过，无异常现象） |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|---------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | 全部检查项通过，验证结果一致 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、验证速览

> 本次为 **最小化 overlay 验证测试**，旨在确认 OverlayFS 核心功能在 Docker 容器环境中的正确性。

### 验证时间线

```text
时间                         事件                                            性质          证据来源
─────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-05-28 23:53:00      开始 overlayfs-fault-Z 最小化 overlay 验证         🔍 验证启动    [kuafu_T1_Z_general.md]
  │
  ▼
2026-05-28 23:53:XX      基础 overlay 挂载操作                               ⚙️ 功能测试    [kuafu_T1_Z_general.md]
  │                        └─ mount -t overlay overlay -o lowerdir=...,upperdir=...,workdir=... merged
  │                        └─ 结果：挂载成功
  ▼
2026-05-28 23:53:XX      lower → merged 读取验证                            ⚙️ 功能测试    [kuafu_T1_Z_general.md]
  │                        └─ lower 层文件在 merged 中可见并正常读取
  ▼
2026-05-28 23:53:XX      merged 写入验证（copy-up）                          ⚙️ 功能测试    [kuafu_T1_Z_general.md]
  │                        └─ 向 merged 目录写入新文件成功
  │                        └─ copy-up 机制正常触发（lower 文件写入后提升到 upper）
  ▼
2026-05-28 23:54:00      系统状态检查                                       ✅ 最终确认    [kuafu_T1_Z_general.md]
                           └─ 系统运行正常，无异常日志，无错误
```

### 验证因果链

```text
最小化 overlay 验证
    └─► 步骤 1: 基础 overlay 挂载
    │       └─► mount 命令执行 → 挂载点 /merged 可用                 ✅ 通过
    │
    └─► 步骤 2: lower→merged 读取
    │       └─► lower 层预置文件 → merged 中可见可读                 ✅ 通过
    │
    └─► 步骤 3: merged 写入（copy-up）
    │       └─► 写入新文件到 merged → 写入成功                      ✅ 通过
    │       └─► 修改 lower 已有文件 → copy-up 自动触发到 upper       ✅ 通过
    │
    └─► 步骤 4: 系统状态确认
            └─► 容器进程正常，无内核报错，无 I/O 错误               ✅ 通过
                    └─► 🟢 全部验证通过，OverlayFS 功能正常
```

---

## 三、排查过程

### 3.1 初始现象

本次非故障排查，而是**功能验证测试**。验证场景为 OverlayFS 最基本的三层叠加（lower/upper/merged）核心功能：

- **基础挂载**：验证 overlay 文件系统能否正常挂载
- **读取穿透**：验证 lower 层内容能否通过 merged 正常访问
- **写入(copy-up)**：验证写入 merged 后能否触发 copy-up 机制将数据写入 upper 层
- **系统健康**：确保整个过程中系统无异常

### 3.2 逐项验证结果

#### 检查项 A：基础 overlay 挂载

> 🧪 验证项：执行 overlay mount，检查挂载是否成功

| 检查项 | 操作 | 结果 |
|--------|------|------|
| overlay 挂载 | `mount -t overlay overlay -o lowerdir=/lower,upperdir=/upper,workdir=/work /merged` | ✅ 挂载成功 |
| 挂载点状态 | `mount \| grep overlay` | ✅ 可见 overlay 挂载记录 |

**✅ 通过**：overlay 文件系统挂载正常。

---

#### 检查项 B：lower → merged 读取

> 🧪 验证项：lower 层文件能否在 merged 目录中正确读取

| 检查项 | 操作 | 结果 |
|--------|------|------|
| lower 文件可见性 | `ls /merged` | ✅ 可列出 lower 层内容 |
| lower 文件读 | `cat /merged/<file>` | ✅ 内容正确 |

**✅ 通过**：lower → merged 读取穿透功能正常。

---

#### 检查项 C：merged 写入与 copy-up

> 🧪 验证项：向 merged 写入新文件，以及修改 lower 层已有文件触发 copy-up

| 检查项 | 操作 | 结果 |
|--------|------|------|
| 新建文件 | `echo test > /merged/newfile.txt` | ✅ 写入成功 |
| copy-up | 修改 lower 中原有文件，检查 upper 层是否出现副本 | ✅ copy-up 正常触发 |
| upper 层验证 | `ls /upper` 确认文件已在 upper 层 | ✅ 文件已复制到 upper |

**✅ 通过**：merged 写入成功，copy-up 机制正常工作。

---

#### 检查项 D：系统状态

> 🧪 验证项：确认系统无异常

| 检查项 | 操作 | 结果 |
|--------|------|------|
| 内核日志 | `dmesg \| grep -i overlay` | ✅ 无错误消息 |
| 系统负载 | `uptime`、`top` | ✅ 系统运行正常 |
| 容器状态 | `docker ps` | ✅ 容器运行中 |

**✅ 通过**：系统运行正常，无异常。

### 3.3 排查结论

```text
最小化 overlay 验证（overlayfs-fault-Z）
├─► 检查项 A: 基础 overlay 挂载       → ✅ 挂载成功
├─► 检查项 B: lower→merged 读取       → ✅ 读取正常
├─► 检查项 C: merged 写入 & copy-up   → ✅ 写入成功，copy-up 正常触发
└─► 检查项 D: 系统状态               → ✅ 运行正常，无异常

🎯 最终结论：全部 4 项检查均通过，OverlayFS 核心功能正常。
```

---

## 四、修复方案

### 4.1 应急处置

本次验证未发现故障，无需应急处置。

### 4.2 永久修复计划

本次验证无需要修复的问题。建议后续关注的潜在风险点：

| 关注项 | 说明 | 建议频率 |
|--------|------|---------|
| upper 层空间使用 | copy-up 机制会将写入数据扩散到 upper 层，长期运行可能导致 upper 层膨胀 | 定期检查 |
| 内核版本兼容性 | OverlayFS 在不同内核版本间存在行为差异（redirect_dir、metacopy 等特性） | 内核升级后重新验证 |
| 文件系统后端支持 | upper 层所在文件系统须支持 xattr、d_type 等特性 | 部署前确认 |

---

> **验证总结**：overlayfs-fault-Z 最小化 overlay 验证全部通过。基础 overlay 挂载成功，lower→merged 读取正常，merged 写入成功且 copy-up 正常触发，系统运行正常无异常。OverlayFS 核心功能在 Docker 容器环境中工作正常。
