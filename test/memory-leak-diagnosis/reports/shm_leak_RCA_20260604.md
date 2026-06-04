# 🔴 共享内存泄漏诊断报告 (Branch A5)

> **报告编号**: BAIZE-RCA-20260604-SHM002
> **故障级别**: P1 (严重)
> **报告时间**: 2026-06-04 02:05 UTC
> **诊断来源**: Kuafu 全分支诊断报告 (`kuafu_full_test_report_20260604.md`)
> **当前状态**: 🔴 处理中

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | 进程 PID 50 (fault_shm_leak) 共享内存泄漏 |
| 影响范围 | 容器 memleak-test 内 PID 50 进程，已消耗 120MB 共享内存，系统 Shmem=127MB |
| 故障时段 | 2026-06-04 01:55 ~ 至今 (持续中) |
| 根本原因 | C 程序循环调用 `shmget()` 创建 SysV 共享内存段，但未执行 `shmdt()` 和 `shmctl(IPC_RMID)` 清理 |
| 是否恢复 | ❌ 未恢复 |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 |
|------|------|------|
| 高置信 | 🟢 | 根因已明确，反事实验证全通过，排除所有替代假设 |
| 中置信 | 🟡 | 根因基本确认，但有 1-2 个维度依赖推断 |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 |

---

## 二、根因速览

**根本原因**：`fault_shm_leak` 进程循环调用 `shmget(IPC_PRIVATE, 1MB, IPC_CREAT|0666)` 创建 SysV 共享内存段，每次创建后既不调用 `shmdt()` 分离，也不调用 `shmctl(IPC_RMID)` 标记删除，导致 120 个 1MB 共享内存段持续驻留，累计消耗 120MB 内存。

### 故障因果链

```
fault_shm_leak 启动（PID 50）
    └─► for (i=0; i<120; i++)
        └─► shmget(IPC_PRIVATE, 1MB, IPC_CREAT|0666)  // 创建 1MB 共享内存段
            └─► shmat(shmid, NULL, 0)                   // 附加到进程地址空间
                └─► ❌ 未调用 shmdt()                    // 未分离
                └─► ❌ 未调用 shmctl(IPC_RMID)           // 未标记删除
                    └─► 120 个共享内存段持续存在
                        └─► RSS = 124,672 kB (122MB)
                        └─► 系统 Shmem = 127,728 kB (约 120MB 来自此进程)
                            └─► 共享内存资源耗尽风险
```

### 事故时间线

| 时间点 (UTC) | 事件 | 证据来源 |
|-------------|------|---------|
| 2026-06-04 01:55 | 容器启动，PID 50 (fault_shm_leak) 运行 | `process_baseline.csv` |
| 2026-06-04 01:57 | 基线采集：VmRSS=124,672 kB，RssShmem=122,880 kB | `pmap_50.txt`, `shm_trend_50.csv` |
| 2026-06-04 01:57 | `ipcs -m` 确认 120 个共享内存段 | 容器内诊断输出 |
| 2026-06-04 01:58 | Kuafu 完成 SHM 泄漏分支诊断并确认 | `kuafu_full_test_report_20260604.md` |
| 至今 | 120 段共享内存持续驻留，系统 Shmem=127 MB | 持续监控中 |

---

## 三、排查过程

### 3.1 初始现象

- **进程信息**: PID 50, `fault_shm_leak`, 单线程
- **RSS 异常高**: 124,672 kB (~122 MB)，但 VmData 仅 224 kB
- **RssShmem 占比 98.6%**: 122,880 kB
- **系统级影响**: `/proc/meminfo` 中 Shmem=127,728 kB，几乎全部为此进程贡献
- **IPC 段数**: 120 个 SysV 共享内存段

### 3.2 假设驱动排查

#### 假设 A5: 共享内存泄漏 ✅ 确认根因

> 🧪 假设：进程反复创建 SysV 共享内存段但未清理

| 检查项 | 操作 | 结论 |
|--------|------|------|
| IPC 段计数 | `ipcs -m \| wc -l` | 120 个共享内存段 |
| 每段大小 | `ipcs -m \| awk '{print $5}'` | 每段 1024 kB (1MB)，总共 120 MB |
| RssShmem | `grep RssShmem /proc/50/status` | 122,880 kB，占 RSS 98.6% |
| VmData vs RSS | 对比 VmData(224 kB) 与 RSS(124,672 kB) | VmData 极小，表明非 heap 增长 |
| 进程内存映射 | `pmap -x 50` | 大量 1024 kB 匿名共享映射 |

**✅ 结论**：PID 50 创建了 120 个 SysV 共享内存段，每段 1MB，未执行 shmdt() 分离或 IPC_RMID 删除。

#### 假设 A1: Heap 段内存泄漏

| 检查项 | 操作 | 结论 |
|--------|------|------|
| VmData | `grep VmData /proc/50/status` | 224 kB，非常小 |

**❌ 排除**：VmData 仅 224 kB，无堆内存泄漏。

#### 假设 A2: 匿名映射泄漏 (mmap)

| 检查项 | 操作 | 结论 |
|--------|------|------|
| AnonPages | `grep Anonymous /proc/50/smaps \| awk '{sum+=$2} END{print sum}'` | 132 kB，极小 |
| 匿名 mmap 数 | `pmap -x 50 \| grep anon` | 无显著匿名 mmap 区域 |

**❌ 排除**：匿名页仅 132 kB，RSS 增长完全由共享内存驱动。

#### 假设 A3: 线程栈泄漏

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 线程数 | `ls /proc/50/task/ \| wc -l` | 1，无线程增长 |

**❌ 排除**：单线程进程。

### 3.3 排查结论与逻辑树

```
PID 50 RSS=122MB 但 VmData=224kB（高度异常）
├─► 计算方式：RSS - VmData - VmStk ≈ RssShmem
├─► 确认 RSS 几乎全部来自共享内存
│
├─► 假设 A1: Heap 泄漏      → ❌ VmData=224 kB，排除
├─► 假设 A2: 匿名 mmap 泄漏  → ❌ AnonPages=132 kB，排除
├─► 假设 A3: 线程栈泄漏      → ❌ 线程数=1，排除
└─► 假设 A5: 共享内存泄漏    → 🎯 确认根因
        └─► ipcs -m 显示 120 段 x 1MB
        └─► RssShmem=122,880 kB ≈ RSS
        └─► 无 shmdt() / IPC_RMID 调用
```

---

## 四、关键证据

1. **证据1 — IPC 段计数**：`ipcs -m` 输出显示 **120 个共享内存段**，每段 1024 kB，总计 122,880 kB。容器中无其他进程使用共享内存。
2. **证据2 — RssShmem 确认**：`/proc/50/status` 中 `RssShmem: 122880 kB`，占 RSS (124,672 kB) 的 **98.6%**，明确指向共享内存。
3. **证据3 — VmData 与 RSS 背离**：VmData 仅 224 kB 而 RSS 高达 122 MB，强有力地排除了 heap 泄漏可能性。
4. **证据4 — 系统级 Shmem 污染**：`/proc/meminfo` 中 `Shmem: 127728 kB`，其中 120 MB 来自此单一进程，已对系统共享内存池造成显著占用。

---

## 五、反事实验证

| 维度 | 推演结果 | 实际现象 | 是否吻合 |
|------|---------|---------|---------|
| SHM 泄漏 → RSS ≈ Shmem | RSS 几乎全部为 RssShmem | RssShmem=122,880 kB, RSS=124,672 kB, 占比 98.6% | ✅ 是 |
| SHM 泄漏 → ipcs 段数多 | 大量 SysV 共享内存段 | 120 段 x 1MB | ✅ 是 |
| SHM 泄漏 → VmData 低 | VmData 不增长 | VmData=224 kB | ✅ 是 |
| SHM 泄漏 → 系统 Shmem 升高 | 系统 Shmem 随进程增长 | Shmem=127 MB | ✅ 是 |

---

## 六、排除的替代假设

- **假设 A1 (Heap 泄漏)**：排除。VmData=224 kB，无 [heap] 段增长迹象。
- **假设 A2 (匿名映射泄漏)**：排除。AnonPages=132 kB，匿名页占比 RSS 约 0.1%。
- **假设 A3 (线程栈泄漏)**：排除。单线程进程，`/proc/50/task/` 仅 1 个条目。

---

## 七、修复建议

### 7.1 应急处置

| 步骤 | 操作 | 执行人 | 预期效果 |
|------|------|--------|---------|
| 1 | `kill -9 50` | 系统管理员 | 终止进程，进程附加的 SHM 自动分离 |
| 2 | `ipcs -m \| grep ^0x \| awk '{print $2}' \| xargs -I{} ipcrm -m {}` | 系统管理员 | 清理所有残留共享内存段 |
| 3 | 确认清理: `ipcs -m \| wc -l` 应降至 1 (仅标题行) | 系统管理员 | 共享内存完全释放 |

### 7.2 永久修复

```c
// 修复前（故障代码模式）
for (int i = 0; i < 120; i++) {
    int shmid = shmget(IPC_PRIVATE, 1024 * 1024, IPC_CREAT | 0666);
    void *addr = shmat(shmid, NULL, 0);
    // ❌ 缺少 shmdt(addr);
    // ❌ 缺少 shmctl(shmid, IPC_RMID, NULL);
}

// 修复后（正确模式）
for (int i = 0; i < 120; i++) {
    int shmid = shmget(IPC_PRIVATE, 1024 * 1024, IPC_CREAT | 0666);
    void *addr = shmat(shmid, NULL, 0);
    // 使用共享内存...
    shmdt(addr);                       // ✅ 分离地址空间
    shmctl(shmid, IPC_RMID, NULL);     // ✅ 标记删除（引用归零后立即释放）
}
```

### 7.3 预防措施

1. **SysV IPC 资源监控**：监控 `ipcs -m` 段数和 `Shmem` 指标，设置告警阈值（段数 > 50 或 Shmem > 总内存 5%）。
2. **代码规范**：所有 `shmget()` + `shmat()` 必须配对 `shmdt()` + `shmctl(IPC_RMID)`。
3. **定期巡检**：将 `ipcs -m -p` 纳入每日巡检脚本，识别长时间驻留的共享内存段。
4. **内核参数保护**：设置 `kernel.shmmax` 和 `kernel.shmall` 上限，防止单进程耗尽系统共享内存。

---

## 八、附件

- 进程基线表: `process_baseline.csv` (PID 50 行: VmRSS=124,672 kB, RssShmem=122,880 kB)
- 共享内存趋势: `shm_trend_50.csv`
- 进程内存映射: `pmap_50.txt`
- 系统内存快照: `meminfo_final.txt` (Shmem=127,728 kB)
- 容器环境: memleak-test, Linux 6.6.87.2-microsoft-standard-WSL2
- Kuafu 全分支报告: `kuafu_full_test_report_20260604.md` (行 107-117)
