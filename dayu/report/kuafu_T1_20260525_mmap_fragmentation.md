# 诊断任务 T1 执行报告: mmap 地址空间碎片化/高 VMA 计数诊断

## 基本信息
- **执行依据**: `C:\Users\86188\.witty-diagnosis-agent\dayu\plans\20260525_194707_mmap_fragmentation.md`
- **任务 ID**: T1
- **任务描述**: 验证 mmap 地址空间碎片化 / 高 VMA 计数导致大块分配失败
- **目标容器**: mmap-E (Docker)
- **目标进程**: Python3 (PID 1)
- **执行时间**: 2026-05-25 10:37 UTC

---

## 1. 系统 VMA 参数

| 参数 | 值 | 说明 |
|------|------|------|
| vm.max_map_count | **5000** | 默认值 65530，容器环境下被大幅压低 |
| vm.overcommit_memory | 1 | 允许超额分配 |
| vm.overcommit_ratio | 50 | - |
| ASLR | 2 (完全随机化) | 完全 ASLR |

## 2. 进程内存统计 (PID 1)

| 指标 | 值 |
|------|------|
| 进程名 | python3 |
| PID | 1 |
| VmPeak | 25720 kB (~25.1 MB) |
| VmSize | 25720 kB |
| VmLck | 0 kB |
| VmRSS | 8064 kB |
| VmData | 4008 kB |
| VmStk | 132 kB |

## 3. VMA 分布分析

| 指标 | 值 |
|------|------|
| **VMA 总数** | **3049** |
| 匿名映射 (anon) | 9 |
| 文件映射 (file) | 3040 |
| **/dev/zero (deleted) 映射** | **~3000** (共享内存映射) |

**VMA 类型分布 (Top 10):**

| VMA 数量 | 设备号/文件 |
|----------|------------|
| 2996 | /dev/zero (deleted) |
| 6 | /usr/lib/x86_64-linux-gnu/libexpat.so.1.8.7 |
| 6 | /usr/lib/x86_64-linux-gnu/libz.so.1.2.11 |
| 6 | /usr/lib/x86_64-linux-gnu/libc.so.6 |
| 5 | /usr/lib/x86_64-linux-gnu/libm.so.6 |
| 5 | /usr/lib/python3.10/lib-dynload/mmap.cpython-310-x86_64-linux-gnu.so |
| 5 | /usr/bin/python3.10 |

## 4. 地址空间碎片化评估

| 指标 | 值 | 判定 |
|------|------|------|
| 已映射内存总量 | 25.1 MB | 进程本身内存占用很小 |
| 最大连续空闲区域 | ~14.4 GB | **充裕** |
| 总地址空间范围 | ~128 TB | 64 位地址空间 |
| 空闲空间占比 | ~22.3% | 正常 |
| 小空洞 (<4KB) 数量 | 0 | 无微空洞问题 |

**评估结论**: 当前地址空间**未出现严重碎片化**。由于进程运行在 64 位地址空间上，地址空间范围极大(~128TB)，即使有 3000 个 VMA 散布在其中，仍然保留了大块连续空闲区域。

## 5. 内核日志

dmesg 中未发现 mmap 失败或 ENOMEM 相关日志。仅有的 HugeTLB 相关消息属于系统启动的正常信息。

## 6. 容器环境

- **cgroup**: 根 cgroup (0::/) — 没有受限于容器的 memory cgroup
- **HugePage**: 未启用
- **ASLR**: 完全随机化 (值=2)

## 7. 核心发现

### 关键问题 1: vm.max_map_count 异常偏低 (5000)
- 系统默认应为 65530，但**容器环境将此值压低至 5000**
- 当前 VMA 计数 3049，**已占上限的 61%**
- 只要 VMA 再增长约 60% (到 5000)，mmap 就会直接返回 ENOMEM

### 关键问题 2: 3000 个 /dev/zero 共享映射是 VMA 激增的主因
- Python 进程通过 `mmap(MAP_SHARED)` 创建了约 3000 个 `/dev/zero` 映射
- 每个映射仅 4KB (单页大小)，属于典型的"大量小映射"模式
- 这是导致 VMA 计数高达 3049 的直接原因

### 关键问题 3: 当前地址空间碎片化风险较低，但 max_map_count 耗尽风险高
- 由于 64 位地址空间巨大，即使 3000 个 VMA 也未造成严重碎片化
- 主要风险在于 **vm.max_map_count=5000 的限制**，而非地址空间不足

---

## 8. 风险等级评估

| 风险维度 | 等级 | 说明 |
|---------|------|------|
| 地址空间碎片化 | **低** | 64 位空间充裕，最大连续空闲 ~14.4 GB |
| max_map_count 耗尽 | **高** | 当前已用 3049/5000 (61%)，再增长 64% 即耗尽 |
| /dev/zero 映射泄漏 | **中** | 3000 个 /dev/zero 映射需确认是否为正常业务行为 |

---

## 9. 修复建议 (仅建议，不执行)

### 临时措施
1. **调高 vm.max_map_count**: 容器内执行 `sysctl -w vm.max_map_count=262144` 或 Docker run 时添加 `--sysctl vm.max_map_count=262144`

### 永久措施
2. **应用层优化**: 审查 Python 代码中创建 `/dev/zero` mmap 的逻辑，考虑复用已有映射而非为每次调用新建 4KB 映射
3. **Docker 配置**: 在 docker-compose 或 Docker run 参数中设置 `--sysctl vm.max_map_count=262144`

### 预防措施
4. **监控告警**: 监控进程 VMA 数量 (`/proc/<pid>/maps | wc -l`)，当超过 `max_map_count * 80%` 时告警

---

## 10. 排除项

- [已排除] 物理内存不足: 进程 VmRSS 仅 8 MB
- [已排除] 内核 mmap 失败日志: dmesg 无 ENOMEM 记录
- [已排除] cgroup 内存限制: 容器无独立 memory cgroup 限制

---

*本报告由 Dayu (Orchestrator) 编排, Kuafu 执行生成*
*报告时间: 2026-05-25T10:37:09Z*
