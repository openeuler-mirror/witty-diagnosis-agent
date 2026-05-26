# 诊断排查方案: pcr-witty 容器内存回收故障

## 1. 故障场景 (Fault Scenario)

- **场景类型 (Mode)**: 在线诊断 (Online) - Docker 容器
- **连接信息 (Connection)**:
  - **Target**: 容器 `pcr-witty` (本地 Docker, ID: 9144947991c0)
  - **Access**: `docker exec pcr-witty` (本地访问, Ansible 不适用, 直接通过 Docker CLI)

## 2. 故障澄清 (Issue Clarification)

- **用户原始描述**:
  > 容器 pcr-witty 内存回收问题，严重内存压力: allocstall_normal=2400, allocstall_movable=4666, pgscan_direct=2,445,150, pgscan_kswapd=7,891,748。Python 进程 (PID 33) 通过 mmap 分配 4951MB 直至 ENOMEM。表明严重的 kswapd 和 direct reclaim 被触发。

- **时间窗口 (Time Window)**:
  > 故障发生时间: 2026-05-25 UTC (当前时间)，OOM killer 在 14:34:44 和 14:39:51 触发
  > (满足: 历史明确时间段 - dmesg 日志有精确时间戳)

- **经过交互确认的关键故障现象 (Key Verified Symptoms)**:
  - 严重内存回收压力: allocstall_normal=2400, allocstall_movable=4666（内存分配直接 stall）
  - 大量直接内存回收: pgscan_direct=2,445,150 (2.4M 页被直接回收扫描)
  - kswapd 回收扫描: pgscan_kswapd=7,891,748 (7.9M 页被 kswapd 扫描)
  - OOM killer 触发 2 次: 进程 `fault_reclaim_s` (PID 20893, 21383) 被 OOM 杀死
  - 异常进程特征: 虚拟内存高达 6.5TB (total-vm:~6.5TB), page tables 占用约 6.4GB, RSS 约 8.8GB
  - 容器 cgroup v2 内存限制: memory.max = "max" (无硬限制), 当前 usage 约 16MB
  - 系统总内存: 约 16GB (MemTotal=15.9GB), Swap 4GB, 当前空闲约 15GB
  - vm.max_map_count=5000 (极低，默认 65530，容器环境被覆写为更低值)
  - 内存不足时大量 swap 换出: pages paged out 高达 31.5M

- **影响范围 (Impact)**:
  - 容器中运行 `fault_reclaim_s` 进程反复被 OOM killer 终止
  - 容器级别内存回收无效（cgroup memory.max=unlimited）
  - 整个 WSL2 内核因全局 OOM 杀死进程，影响主机稳定性

## 3. 前期检测结果 (Pre-check Results)

- **环境可达性 (Reachability)**: Pass (容器运行中，docker exec 正常)
- **基础环境信息 (Basic Info)**:
  - **OS**: Ubuntu 22.04.5 LTS (容器内)
  - **Kernel**: 6.6.87.2-microsoft-standard-WSL2 (WSL2 内核)
- **数据完备性 (Data Availability)**:
  - [x] /proc/meminfo - 系统内存信息
  - [x] /proc/vmstat - 内存回收统计
  - [x] dmesg - OOM killer 日志
  - [x] /sys/fs/cgroup/ - cgroup v2 内存控制组信息
  - [x] /proc/sys/vm/ - 内核 VM 参数

## 4. 诊断模型 (Diagnostic Model - Failure Modes)

| 故障模式 (Failure Mode) |
| :--- |
| OOM (Out of Memory) |
| mmap ENOMEM |

**说明**:
- **OOM (Out of Memory)**: dmesg 明确显示 `invoked oom-killer` 两次，分别于 14:34:44 和 14:39:51 杀死 `fault_reclaim_s` 进程。进程中 total-vm 约 6.5TB，page tables 占用约 6.4GB，这是极不正常的现象。
- **mmap ENOMEM**: Python 进程 (PID 33) 分配 4951MB 时 mmap 返回 ENOMEM。容器内 vm.max_map_count=5000（远低于默认 65530）加剧了 VMA 限制问题，但更核心的原因是系统全局内存不足触发 reclaim 失败。

**排除项**:
- ~mlock 超限~: meminfo 中 Mlocked=0, Unevictable=0, 非 mlock 场景
- ~文件系统只读~: 无相关证据
- ~磁盘 IO 故障~: 无相关证据

---

## 5. 任务元数据 (JSON Metadata)

```json
{
  "plan_path": "G:\\witty-diagnosis-agent\\dayu\\plans\\20260525_224030_container_memory_reclaim.md",
  "created_at": "2026-05-25T22:40:30Z",
  "mode": "online",
  "target": "docker://pcr-witty",
  "tasks": [
    {
      "id": "T1",
      "symptom": "进程 `fault_reclaim_s` 占用 6.4GB page tables 后被 OOM 杀死",
      "failure_mode": "OOM (Out of Memory)"
    },
    {
      "id": "T2",
      "symptom": "Python 进程 mmap 分配 4951MB 返回 ENOMEM",
      "failure_mode": "mmap ENOMEM"
    }
  ]
}
```
