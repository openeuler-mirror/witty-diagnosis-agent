---
name: overlayfs-diagnosis
description: >
  OverlayFS 叠加文件系统故障诊断技能。当用户提到 OverlayFS 报错、文件"消失"、
  overlay 挂载失败、docker overlay2 存储驱动异常、容器层损坏、copy-up 报错、
  inotify 在 overlay 上不工作、whiteout/opaque 行为异常等关键词时，必须使用本技能。
  覆盖场景：upper/lower/work 目录配置错误、跨设备 overlay 限制、opaque whiteout 导致文件"消失"、
  copy-up 性能退化、overlay 上 inotify 不工作、Docker storage driver overlay2 特有问题
  （inode 耗尽、diff 目录膨胀）、redirect_dir 配置冲突、metacopy 异常等。
  支持系统态诊断 + 内核态机理双轨并行分析。
---

# OverlayFS 叠加文件系统故障诊断（双轨：系统态 + 内核态）

## 第一节：故障目录结构

```text
overlay_panic/             # 故障排查文件夹
├── mountinfo/             # 【可选，优先】容器/主机的挂载信息
│   ├── /proc/mounts       # mount 表
│   ├── /proc/self/mountinfo # 详细挂载信息
│   └── /sys/fs/overlay/   # overlayfs 内核接口（若有）
├── lower/                 # lowerdir 快照（在只读层之一）
├── upper/                 # upperdir 快照（在读写层）
├── work/                  # workdir 快照
└── merged/               # merged 目录快照（最终视图）
```

**典型挂载示例：**
```bash
# 常规 overlay 挂载
mount -t overlay overlay -o lowerdir=/lower,upperdir=/upper,workdir=/work /merged

# Docker overlay2 自动管理（不可手动模拟）
# /var/lib/docker/overlay2/<layer-hash>/ 下的结构：
#   diff/     ← upperdir（实际文件变更）
#   link      ← 指向短链接名
#   lower     ← lowerdir 配置（仅merged层有）
#   merged/   ← 最终视图
```

---

## 第二节：分析策略（并行双轨，交叉验证）

**系统态诊断和内核态机理分析应同时进行，而非二选一。** 两条轨道相互独立推进，最终交叉比对以确认根因。

```
┌─────────────────────────────────────────────────────────────────┐
│                    并行双轨分析模型                               │
│                                                                 │
│  轨道一：系统态诊断（逆向）         轨道二：内核态分析（正向）      │
│  ─────────────────────────         ───────────────────────     │
│  从当前系统现象出发，逆向推理            从 overlayfs 内核机制出发，正向追踪    │
│                                                                 │
│  回答：当前状态是什么？哪里                    回答：为什么出现此现象？内核         │
│        配置异常？                                代码逻辑上哪里有缺陷或限制？       │
│                                                                 │
│            ↓                                   ↓                │
│            └────────────── 交叉验证 ────────────┘                │
│                                                                 │
│  见：第三节（统一诊断流程：分支决策→双轨并行→交叉验证→输出）       │
└─────────────────────────────────────────────────────────────────┘
```

**两条轨道的分工与互补**：

| | 系统态诊断轨道 | 内核态分析轨道 |
|--|------------|---------|
| **优势** | 真实系统状态、挂载参数、dmesg 日志、Docker 状态 | 完整因果模型、限制条件的源码依据、预期行为可见 |
| **局限** | 只有静态快照，内核内部决策过程不可见 | 需要内核版本精确匹配；自定义内核可能有差异 |
| **典型盲区** | 内核版本间的行为差异、特定配置的副作用 | 实际系统中其他因素的干扰（磁盘空间、并发） |

**何时两条轨道都必须做**：涉及 overlayfs 内核行为导致的异常时，两条轨道**必须同时进行**，最终通过交叉验证收敛到高置信度结论。

**何时只能走系统态诊断轨道**：无内核源码/调试环境时，仅走系统态诊断，但应明确标注分析局限性。

---

## 第三节：统一诊断流程（分支决策 → 双轨并行 → 交叉验证 → 输出）

> 执行约束：所有诊断脚本的默认超时时间为 **3 分钟（180s）**。

### Step 1：启动（基线信息收集 + 分支推荐）

运行：

```bash
bash scripts/01_baseline_info.sh [target_mount_point] [container_id]
```

记录输出中的五类关键信息（后续所有步骤都围绕它们推进）：

- 内核版本 + overlayfs 模块版本（用于 S0 版本验证）
- Overlay 挂载拓扑（upperdir/lowerdir/workdir 路径与挂载点）
- 文件系统类型与设备信息（是否跨设备 overlay）
- dmesg 异常关键字（overlayfs 错误/警告）
- Docker overlay2 存储状态（若涉及容器）

### Step 2：故障类型定界（选择分支脚本一键跑）

按 Step 1 输出推荐，执行对应分支脚本：

```bash
bash scripts/branch_X_xxx.sh [target_mount_point] [container_id]
```

说明：每个 `branch_*.sh` 已内置系统态诊断的检查序列（覆盖 E1–E4），并在检测到内核源码路径时给出内核态追踪指引（覆盖 K0–K5）。

若 Step 1 输出推荐多个分支脚本，必须按输出顺序全部执行，不可只选其一。

脚本对应执行参考如下：

```
故障现象
  ├─ mount 失败，dmesg 含 "failed to get directory"
  │  / "not supported as upperdir" / "failed to create workdir"
  │  / "failed to get kernel config"                           → 分支A: 配置错误
  │                                                               → scripts/branch_A_config_error.sh
  ├─ mount 失败，dmesg 含 "filesystem on ... not supported"
  │  或含 "upper fs not supported"                              → 分支B: 下层 fs 不兼容
  │                                                               → scripts/branch_B_fs_incompatible.sh
  ├─ mount 失败，dmesg 含 "upperdir is not on same filesystem"
  │  或含 "cross-device" / "XDev" / "not on same filesystem"   → 分支C: 跨设备 overlay
  │                                                               → scripts/branch_C_cross_device.sh
  ├─ 挂载成功但文件"消失"/"不显示"，ls 无输出                  → 分支D: Opaque Whiteout
  │                                                               → scripts/branch_D_opaque_whiteout.sh
  ├─ 文件读取/写入变慢，ioprofile 显示 copy-up 耗时            → 分支E: Copy-up 性能退化
  │                                                               → scripts/branch_E_copyup_perf.sh
  ├─ inotify/inotifywait 在 merged 目录无事件                   → 分支F: 文件事件监听失效
  │                                                               → scripts/branch_F_inotify.sh
  ├─ Docker 容器报 "no space left on device" 但 df 有余量      → 分支G: overlay2 inode 耗尽
  │                                                               → scripts/branch_G_docker_inode_exhaust.sh
  ├─ Docker /var/lib/docker/overlay2 目录持续膨胀               → 分支H: diff 目录膨胀
  │                                                               → scripts/branch_H_docker_diff_bloat.sh
  ├─ 挂载成功但 redirect_dir 行为异常（符号链接指向 lower）    → 分支I: redirect_dir / metacopy 冲突
  │                                                               → scripts/branch_I_redirect_metacopy.sh
  ├─ 文件写入报 "Read-only file system" 但 upperdir 可写       → 分支J: 元数据/权限问题
  │                                                               → scripts/branch_J_permission.sh
  ├─ overlay + 容器场景下磁盘 I/O 异常高（readdir 慢）         → 分支K: 目录深度/合并读性能问题
  │                                                               → scripts/branch_K_readdir_perf.sh
  └─ 其他异常或无明确匹配                                       → 分支Z: 通用诊断
                                                                   → scripts/branch_Z_general.sh
```

### Step 3：系统态逆向诊断（回答"当前状态是什么 + 哪里异常"）

在分支脚本输出基础上，完成并固化四步证据链：

- **E1 现场还原**：确认 overlay 挂载拓扑（`mount | grep overlay`、`cat /proc/self/mountinfo`），记录所有 upperdir/lowerdir/workdir 路径
- **E2 权限与空间验证**：确认 upperdir/workdir 目录权限、磁盘空间（`df -hT`、`df -i`）、写权限
- **E3 关键元数据检查**：用 `getfattr` 读取 trusted.overlay.overlay.* xattr、检查 opaque/redirect 标记、whiteout 节点
- **E4 独立归因**：仅基于系统态客观数据，给出"异常值的类型与来源"

输出（供后续交叉验证使用）：

```
挂载点：<path>
Overlay 拓扑：lowerdir=<path> upperdir=<path> workdir=<path>
各层文件系统：lower=<fstype> upper=<fstype>
磁盘/空间状态：<used/free/inodes>
异常值：<配置错误/权限问题/xattr异常/whiteout/...>
系统态归因假设：<一句话>
```

### Step 4：内核态正向分析（有内核源码时必做；回答"为什么出现此现象"）

#### K0：版本验证（防止版本不匹配导致误判）

```bash
# 获取内核版本
uname -r

# 查看 overlayfs 模块版本
modinfo overlay | grep version

# 确认 overlayfs 模块参数
cat /sys/module/overlay/parameters/*
```

版本不匹配的典型信号：
- 某特性（如 metacopy/redirect_dir）在内核版本中不存在
- 内核模块参数行为在不同版本间有差异
- overlayfs 代码中大版本重构（如 v22 之后的 redirect_dir 重构）

版本不匹配时不停止：标注"版本存在差异"，后续推断以系统态事实校正。

#### K1–K2：以现象为入口，完成"内核机制 - 系统表现对齐"

- **K1 锚定入口**：取 Step 3 的异常现象类型，定位到内核源码中对应的处理逻辑
- **K2 对齐确认**：以内核源码逻辑为准理解系统表现，避免把预期行为误当作 Bug

关键内核源码区域（参考 `fs/overlayfs/`）：

| 功能 | 内核文件 | 说明 |
|------|---------|------|
| 挂载参数解析 | `fs/overlayfs/params.c` | upperdir/lowerdir/workdir 的参数处理 |
| 目录合并 | `fs/overlayfs/readdir.c` | opaque/whiteout/redirect 的处理逻辑 |
| Copy-up | `fs/overlayfs/copy_up.c` | 写时复制机制 |
| Inode 操作 | `fs/overlayfs/inode.c` | 权限、ACL、xattr 处理 |
| 文件操作 | `fs/overlayfs/file.c` | read/write/llseek 等 |
| 超级块 | `fs/overlayfs/super.c` | 挂载校验与初始化 |
| 元数据 | `fs/overlayfs/util.c` | 辅助函数与元数据定义 |

#### K3：逐层机制追踪（不允许省略链路）

原则：从最底层现象向上追溯至内核决策点，逐层完成三件事：

```
① 找到对应的内核处理路径
② 用系统态的配置/参数验证该路径的输入条件
③ 判断：该路径上哪个检查/决策是"异常引入点"？
```

#### K4：配置流溯源（异常配置的生命周期追踪）

围绕 Step 3 的"异常值"，在源码和配置中追踪：

```
挂载参数解析 → 内核检查 → 限制条件判断 → 异常返回/警告
```

重点审查的高发区：跨设备检查（`ovl_mount_dir_noesc`）、下层 fs 兼容性检查（`ovl_check_origin_fs`）、redirect_dir 策略检查（`ovl_parse_redirect_mode`）、metacopy 特性门控。

#### K5：反事实验证（强制；不能止步于"找到可疑配置"）

用系统态根因假设正向推演，并与系统态现象逐条对齐：

```
✓ 推演的异常路径  == 系统态的 dmesg/行为？
✓ 推演的配置条件  == 系统态的实际配置？
✓ 推演的触发条件  == 系统态的触发场景？
```

三条全 ✓ 才能判定"根因确认"。

内核态轨道输出格式：

```
文件：fs/overlayfs/<file>.c
函数：<func>()
机制：[挂载校验 | copy-up决策 | readdir处理 | inode操作]
缺陷类型：[兼容性检查遗漏 | 配置解析错误 | 限制条件不完整 | 预期行为误解]
机制解释：<精确描述，含相关源码行为>
触发条件：<前置状态与配置>
因果链：[配置/条件] → [内核检查] → [异常状态] → [用户可见现象]
```

### Step 5：交叉验证（双轨汇合，冲突仲裁，置信度收敛）

对每条证据做对齐检查：

| 验证维度 | 系统态结论 | 内核态结论 | 是否吻合？ |
|---------|------------|---------|-----------|
| 异常现象 | dmesg/log 中的 <message> | 源码中 <condition> 产生此消息 | □ 吻合 □ 不符 |
| 配置条件 | upperdir/lowerdir 的 <特征> | 源码 <检查> 决定此特征 | □ 吻合 □ 不符 |
| 触发路径 | 系统态操作序列 | 源码中对应调用路径 | □ 吻合 □ 不符 |
| 根因位置 | 配置/参数中 <问题特征> | 对应内核检查点存在限制 | □ 吻合 □ 不符 |
| 触发条件 | 场景特征 | 缺陷在此条件下触发 | □ 吻合 □ 不符 |

不一致时的仲裁原则：

```
异常现象：优先信任系统态事实（客观现象）
配置条件不符：优先检查内核版本差异（不同版本行为可能不同）
根因不符：保留多假设并补证据（必要时做控制变量实验验证）
```

置信度收敛：

- **高**：两轨完全吻合 + 反事实验证通过 + 控制变量实验可复现
- **中**：两轨基本吻合，但有 1 个维度依赖推断；或仅完成系统态轨道
- **低**：两轨存在矛盾且无法解释；或证据链缺失超过两环节
- **疑似预期行为**：两轨证据均指向"内核按设计行为运行"，实际是用户预期偏差

常见误判陷阱（用于复核结论质量）：

- **挂载成功 ≠ 配置正确**：某些配置项（如 redirect_dir=off）只在特定操作时才触发异常
- **docker overlay2 ≠ 裸 overlay**：Docker 的 layer 管理逻辑增加了元数据跟踪、link 文件等额外复杂性
- **upperdir 有空间但不代表可写**：需要检查 inode 余量、selinux 标签、ACL、挂载时是否显式 readonly
- **内核版本差异**：overlayfs 在 4.x~6.x 之间有多次行为变更（redirect_dir 重构、metacopy 引入等）
- **容器内嵌套 overlay 限制**：Docker overlay2 容器根文件系统本身就是 overlay，在此类容器内部无法再次执行 `mount -t overlay`（内核报告 'not supported as upperdir'）。如需要在容器内测试 overlay，应使用 ext4 loop 设备或 tmpfs 作为底层文件系统

应**优先考虑用户预期/配置错误**而非内核 Bug：
```
用户配置/预期偏差优先，但以下情况提升内核 Bug 怀疑优先级：
  ① 配置完全符合内核文档要求但报错
  ② 历史内核版本正常运行，升级后异常
  ③ 多个独立用户报告相同现象
  ④ 内核邮件列表/commit log 有相关修复
```

### Step 6：最终输出（按第九节模板落盘）

将 Step 3/4/5 的输出填入第九节报告结构，并显式写清：结论、证据链、排除项、修复建议、验证建议。

---

## 第四节：轨道一 —— 系统态诊断（逆向推理）

本节已合并进第三节的统一流程（Step 3）。

---

## 第五节：轨道二 —— 内核态分析（正向追踪）

本节已合并进第三节的统一流程（Step 4）。

---

## 第六节：交叉验证与结论收敛（双轨汇合）

本节已合并进第三节的统一流程（Step 5）。

---

## 第七节：故障类型决策树（两条轨道共用）

本节内容已合并进第三节的统一流程（Step 2）。

---

## 第八节：注意事项与置信度评级

本节内容已合并进第三节的统一流程（Step 5）。

---

## 第九节：最终报告结构

```
## 故障概要
  故障模式：<类型>
  置信度：<高/中/低/疑似预期行为>
  分析轨道：[双轨（系统态 + 内核态）| 单轨（仅系统态，无内核源码）]
  内核版本：<uname -r>
  测试环境：<发行版 + Docker版本（若适用）>

## 系统态诊断结论
  挂载拓扑：upper=<path> lower=<path> work=<path>
  各层文件系统状态：<文件系统类型/空间/inode>
  异常现象：<dmesg/日志/用户可见行为>
  系统态侧根因假设：<基于系统信息的推断>

## 内核态分析结论（有源码时填写）
  相关内核代码路径：fs/overlayfs/<file>.c:<line>  函数：<func>()
  机制类型：[挂载校验 | copy-up | readdir | inode操作 | 元数据处理]
  机制解释：<精确描述，含内核预期行为与实际行为对比>
  触发条件：<需要什么前置配置/状态>
  因果链：[配置触发] → [内核检查] → [异常状态] → [用户可见现象]

## 交叉验证结果（有源码时填写）
  异常现象吻合：  □ 是  □ 否（差异说明：<...>）
  配置条件吻合：  □ 是  □ 否（差异说明：<...>）
  触发路径吻合：  □ 是  □ 否（差异说明：<...>）
  根因位置吻合：  □ 是  □ 否（差异说明：<...>）
  触发条件吻合：  □ 是  □ 否（差异说明：<...>）
  综合判断：<两轨结论是否一致，若有矛盾如何解释>

## 完整因果链（双轨收敛后）
  [触发条件/配置] → [内核路径] → [异常状态]
  → [用户可见现象]

## 排除的替代假设
  - <假设X>：排除原因 <...>

## 修复建议
  最小修复（立即可做）：
    <具体配置修改或操作命令>
  根本修复（设计层面）：
    <更深层的系统设计改进方向>

## 验证建议
  <如何确认根因 + 如何验证修复有效>
```

---

## 第十节：参考文件

- `references/overlayfs_basics.md`：OverlayFS 内核基础概念与机制
- `references/docker_overlay2.md`：Docker overlay2 存储驱动特有问题
- `references/diagnosis_patterns.md`：OverlayFS 故障诊断模式与命令速查
