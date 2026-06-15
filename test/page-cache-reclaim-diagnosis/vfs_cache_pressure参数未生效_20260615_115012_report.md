# 故障诊断报告

> **报告编号**：RCA-20260615-001
> **故障级别**：P3（配置理解偏差 / 测试方法不当）
> **报告时间**：2026-06-15 11:50:12
> **当前状态**：🟢 已分析完成（非系统故障，为测试设计偏差）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | WSL2 Ubuntu 22.04 `vfs_cache_pressure` 参数调节后 slab 增长无差异 |
| 影响范围 | 单一 WSL2 测试环境，无业务影响 |
| 故障时段 | 2026-06-15 11:34:00（诊断时间）~ 分析完成 |
| 根本原因 | **测试设计偏差**：`vfs_cache_pressure` 是"回收压力调节器"而非"缓存增长节流阀"。系统内存充裕（MemFree 占 87%）时 kswapd/slab shrinker 未被唤醒，参数无论设何值均不会影响 dentry 缓存增长率。 |
| 是否恢复 | ✅ 不适用（系统本身无故障） |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 本报告适用情况 |
|------|------|------|--------------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | ✅ 通过 kallsyms 符号验证、drop_caches 回收验证、slabs_scanned 计数器监控、内存状态等多维度证据，完整解释参数未生效的原因 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                            事件                                                    性质          证据来源
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-06-15 11:34:00            用户测试在不同 vfs_cache_pressure 下创建 100K 文件          📋 测试执行   [用户测试脚本]
                                  │
                                  ▼
                                各配置下 slab 增长量无差异（139~150MB）                    ❓ 异常表现   [kuafu_T1: L15-L21]
                                  │
                                  ▼
2026-06-15 11:34:00            系统状态确认：MemFree=14GB/15.4GB (87%)                   📊 关键背景   [/proc/meminfo]
                                  │                   MemFree 充裕 → kswapd 不唤醒
                                  │                   → slab shrinker 不执行
                                  │
                                  ▼
                                验证：参数可写性确认                                       ✅ 系统正常   [/proc/sys/vm/vfs_cache_pressure]
                                  │                   echo 1000 → 读取确认 1000
                                  │
                                  ▼
                                验证：drop_caches 手动回收确认                             ✅ 回收机制正常 [sync; echo 3 > drop_caches]
                                  │                   Slab 从 400MB+ 降至 ~113MB
                                  │
                                  ▼
                                验证：内存压力下 slab shrinker 扫描确认                     ✅ shrinker 正常 [/proc/vmstat:slabs_scanned]
                                  │                   slabs_scanned = 12,354,742
                                  │
                                  ▼
                                验证：内核符号与参数实现确认                                 ✅ 实现完整   [/proc/kallsyms]
                                  │                   sysctl_vfs_cache_pressure_denom 存在
                                  │                   公式：effective = vfs_cache_pressure / denom
                                  │
                                  ▼
                                🎯 结论：参数实现正确，测试方法衡量的      是"增长"而非"回收"
```

### 故障因果链

```text
用户创建 100K 文件
    │
    ├─► 内核分配 dentry + inode 对象 → Slab 缓存增长（正常行为）
    │
    ├─► 系统 MemFree = 14GB / 总量 15.4GB（空闲 87%）
    │       │
    │       └─► 无内存压力 → kswapd 不唤醒 → slab shrinker 不执行
    │               │
    │               └─► vfs_cache_pressure 参数不参与缓存增长过程
    │                       │
    │                       └─► 无论设 0、100、1000 还是 10000
    │                               增长阶段表现完全相同 ← 🔴 用户观察到的现象
    │
    └─► 🔍 正确理解：vfs_cache_pressure 仅在回收阶段生效
            │
            └─► effective_pressure = vfs_cache_pressure / vfs_cache_pressure_denom
                    │
                    ├─► vfs_cache_pressure=0    → 0%  回收（完全不回收）
                    ├─► vfs_cache_pressure=100  → 1.0x 标准行为（denom=100）
                    ├─► vfs_cache_pressure=1000 → 10.0x 激进回收
                    └─► vfs_cache_pressure=10000→ 100.0x 极端激进
```

---

## 三、排查过程

> 排查逻辑：**确认参数实现完整性 → 验证参数可写性 → 验证回收机制 → 分析测试方法缺陷 → 得出结论**

### 3.1 初始现象

- 在 WSL2 Ubuntu-22.04 环境中，对 `vfs_cache_pressure` 设置不同值（0, 100, 1000, 10000）后执行 100K 文件创建测试
- 各配置下 **Slab 增长量无明显差异**（139MB ~ 150MB），用户认为"参数未生效"
- 测试环境：内核 `6.18.33.1-microsoft-standard-WSL2`，内存总量 `~15.4GB`

---

### 3.2 假设驱动排查

#### 假设 A：WSL2 内核未编译 vfs_cache_pressure 支持

> 🧪 假设：WSL2 定制内核可能移除了 vfs_cache_pressure 功能

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 内核符号验证 | `sudo cat /proc/kallsyms \| grep vfs_cache` | ✅ `sysctl_vfs_cache_pressure` 与 `sysctl_vfs_cache_pressure_denom` 均存在 |
| 参数读取 | `cat /proc/sys/vm/vfs_cache_pressure` | ✅ 返回 `100`（默认值正常） |
| WSL2 源码验证 | 查阅 WSL2-Linux-Kernel 6.18.y `fs/dcache.c` | ✅ `vfs_pressure_ratio()` 完整实现，含 `vfs_cache_pressure_denom` |
| Kconfig 检查 | `zcat /proc/config.gz \| grep -i VFS_CACHE` | ✅ 该功能无 Kconfig 开关，是 VFS 层内置功能，始终编译 |

**❌ 排除**：WSL2 内核实现完整，参数存在且可读。

---

#### 假设 B：参数不可写，写入后未生效

> 🧪 假设：`/proc/sys/vm/vfs_cache_pressure` 权限限制导致写入失败

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 权限检查 | `ls -la /proc/sys/vm/vfs_cache_pressure` | ✅ `rw-r--r--`，root 可写 |
| 写入验证 | `echo 1000 \| sudo tee ...` → `cat` 验证 | ✅ 写入成功，读取确认值为 `1000` |

**❌ 排除**：参数可写，写入后读取值正确。

---

#### 假设 C：内核 slab 回收机制故障

> 🧪 假设：内核 slab shrinker 存在缺陷，无法回收 dentry/inode 缓存

| 检查项 | 操作 | 结论 |
|--------|------|------|
| drop_caches 回收 | `sync; echo 3 \| sudo tee /proc/sys/vm/drop_caches` | ✅ Slab 从 400MB+ 降至 ~113MB（SReclaimable 从 281MB 降至 ~28MB） |
| 内存压力下 shrinker 激活 | 设置 `vfs_cache_pressure=10000`，`stress-ng` 制造压力 | ✅ `slabs_scanned` 从 0 增至 12,354,742，shrinker 正常扫描 |
| cgroup 验证 | `mount \| grep cgroup` → cgroup2 | ℹ️ WSL2 仅用 cgroup v2，cgroup 内存限制不回收 dentry/inode slab（计入根 cgroup） |

**❌ 排除**：slab 回收机制正常，shrinker 在内存压力下正确激活。

---

#### 假设 D：vfs_cache_pressure_denom 导致有效值被缩小（核心发现 ✅）

> 🧪 假设：WSL2 特有参数 `vfs_cache_pressure_denom=100` 导致有效回收压力被缩小，使参数调节效果被掩盖

| 检查项 | 操作 | 结论 |
|--------|------|------|
| denom 值确认 | `cat /proc/sys/vm/vfs_cache_pressure_denom` | ✅ 值为 `100`（最小值） |
| 有效压力计算 | `effective = vfs_cache_pressure / denom` | ✅ vfs_cache_pressure=1000 → 有效值=10.0x（激进）；10000 → 100.0x（极端） |
| 参数公式影响分析 | 查阅内核源码 `vfs_pressure_ratio()` | ✅ 公式正确，`denom=100` 未缩小参数效果，反而使设置值等比例生效 |

**❌ 排除（补充发现）**：`vfs_cache_pressure_denom=100` 不影响参数功能。该参数仅为内核提供更细粒度的中间值控制能力，默认值 100 等价于标准行为；即便设 10000（有效 100.0x），在无内存压力时依然不生效。

---

### 3.3 排查结论

```text
参数 "未生效" 现象
├─► 假设 A：内核未编译支持       → ❌ 排除（符号存在，实现完整）
├─► 假设 B：参数不可写           → ❌ 排除（rw 权限，写入确认成功）
├─► 假设 C：slab 回收机制故障    → ❌ 排除（drop_caches 正常，shrinker 正常激活）
├─► 假设 D：denom 缩小效果       → ❌ 排除（公式正确，denom=100 为最小值）
│
└─► 🎯 真正根因：测试方法偏差
        │
        ├─► 测量的对象：dentry/inode 缓存**增长**速率
        ├─► 系统状态：MemFree=14GB（总量 15.4GB，空闲 87%）
        ├─► kswapd 状态：未唤醒（无内存压力）
        ├─► slab shrinker：未执行
        │
        └─► vfs_cache_pressure 的作用域：仅在 slab shrinker 回收阶段生效
                └─► 增长阶段不受此参数影响 → 所有配置值表现相同 ← 与观测一致
```

---

## 四、修复方案

### 4.1 正确测试方法建议

由于此案例是 **测试设计偏差** 而非系统故障，以下为验证 `vfs_cache_pressure` 效果的正确方案：

#### 方案一：制造全局内存压力后再观察回收差异（推荐）

```bash
# 1. 先创建大量文件构建 dentry 缓存
# 2. 同步并记录 slab 基线
sync
grep Slab /proc/meminfo

# 3. 设置目标 vfs_cache_pressure 值（如 10000）
echo 10000 | sudo tee /proc/sys/vm/vfs_cache_pressure

# 4. 制造全局内存压力触发 kswapd 回收
stress-ng --vm 2 --vm-bytes 12G --timeout 30s

# 5. 观察 slab 回收量差异
grep Slab /proc/meminfo
```

#### 方案二：对比不同压力值下的回收效率

```bash
# 设置保守值（压力=100）
echo 100 | sudo tee /proc/sys/vm/vfs_cache_pressure
stress-ng --vm 2 --vm-bytes 12G --timeout 30s
grep Slab /proc/meminfo
# 记录残留 slab 量

# 恢复后设置激进值（压力=10000）
echo 10000 | sudo tee /proc/sys/vm/vfs_cache_pressure
stress-ng --vm 2 --vm-bytes 12G --timeout 30s
grep Slab /proc/meminfo
# 对比：激进值应回收更多 slab，残留量显著更低
```

#### 方案三：直接监控 slabs_scanned 计数器

```bash
# 设置不同压力值后观察 shrinker 扫描深度
echo 100 | sudo tee /proc/sys/vm/vfs_cache_pressure
stress-ng --vm 2 --vm-bytes 12G --timeout 30s
grep slabs_scanned /proc/vmstat
# 压力值越高，slabs_scanned 应越大（shrinker 扫描更积极）
```

### 4.2 关键知识点总结

| 知识点 | 说明 |
|--------|------|
| `vfs_cache_pressure` 的作用域 | **仅控制 slab 回收阶段**，不参与缓存增长过程 |
| 生效前提 | 必须存在全局内存压力（kswapd 被唤醒） |
| WSL2 `vfs_cache_pressure_denom` | 上游主线补丁（commit `e7b9cea718ee`），非 WSL2 独有，用于提供更细粒度的中间压力值控制 |
| 有效压力公式 | `effective = vfs_cache_pressure / vfs_cache_pressure_denom` |
| `denom` 默认值 | 100（最小值），不影响标准行为 |
| `min_slab_ratio=5` | 确保 slab 至少占用 5% 内存，是下限而非上限，不影响本次分析 |

### 4.3 补充建议

| 建议项 | 说明 |
|--------|------|
| 理解参数语义 | `vfs_cache_pressure` 是"回收倾向"参数，类似内存回收的"油门"，不是"缓存限速阀" |
| 测试验证方法 | 验证回收类参数的正确方法是**制造对应压力条件**后观察回收行为差异，而非观察增长行为 |
| 内核版本兼容 | 如需在非 WSL2 环境复现，`vfs_cache_pressure_denom` 需要 Linux 主线内核 ≥ 2025年5月合入版本 |

---

## 五、证据清单

| # | 命令/操作 | 关键输出 | 支撑结论 |
|---|-----------|----------|----------|
| 1 | `cat /proc/sys/vm/vfs_cache_pressure` | `100` | 参数存在，默认值正常 |
| 2 | `cat /proc/sys/vm/vfs_cache_pressure_denom` | `100` | WSL2 特有参数，默认值 100（最小值） |
| 3 | `uname -a` | `6.18.33.1-microsoft-standard-WSL2` | 内核版本确认 |
| 4 | `zcat /proc/config.gz \| grep -iE "VFS_CACHE\|SLAB\|MEMCG"` | 无 `CONFIG_VFS_CACHE_PRESSURE` | 该功能无 Kconfig 开关，VFS 层内置 |
| 5 | `sudo cat /proc/kallsyms \| grep vfs_cache` | `sysctl_vfs_cache_pressure_denom` | 内核符号存在，实现已编译 |
| 6 | `ls -la /proc/sys/vm/vfs_cache_pressure` | `rw-r--r-- root root` | 参数可写 |
| 7 | `sync; echo 3 \| sudo tee /proc/sys/vm/drop_caches` | Slab 从 400MB+ 降至 ~113MB | 回收机制正常 |
| 8 | `cat /proc/vmstat \| grep slabs_scanned` | `slabs_scanned 12354742` | slab shrinker 在压力下正常扫描 |
| 9 | `grep Slab /proc/meminfo` | `Slab: 123884 kB`; `SReclaimable: 33316 kB` | 当前 slab 使用量较小 |
| 10 | `grep MemFree /proc/meminfo` | `MemFree: 14084204 kB` | 系统内存充裕（87% 空闲），无回收压力 |

---

## 六、参考链接

- [WSL2-Linux-Kernel 源码 fs/dcache.c](https://github.com/microsoft/WSL2-Linux-Kernel/blob/linux-msft-wsl-6.18.y/fs/dcache.c) — `vfs_pressure_ratio()` 与 `vfs_cache_pressure_denom` 实现
- [上游主线补丁](https://lore.kernel.org/20250511083624.9305-1-laoar.shao@gmail.com) — commit `e7b9cea718ee`，作者 Yafang Shao，2025年5月合入
- 诊断原始报告：`C:\Users\86135\.witty-diagnosis-agent\dayu\report\kuafu_T1_20260615_113412.md`

---

*报告由 Baize (分析与报告 Agent v1.4) 自动生成*
*生成时间：2026-06-15 11:50:12 (UTC+8)*
