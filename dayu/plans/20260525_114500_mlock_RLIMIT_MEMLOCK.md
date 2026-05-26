# 诊断排查方案: mlock 超限 (RLIMIT_MEMLOCK)

## 1. 故障场景 (Fault Scenario)

- **场景类型 (Mode)**: 在线诊断 (Online)
- **连接信息 (Connection)**:
  - **Target**: Docker 容器 `mmap-C` (ID: 9cabf3afbded)
  - **Access**: 本地 `docker exec`

## 2. 故障澄清 (Issue Clarification)

- **用户原始描述**:
  > Diagnose container mmap-C. Non-root user (tu) has RLIMIT_MEMLOCK set to 8KB (soft and hard). Process called mlock(9KB) which returns ENOMEM errno=12 (Cannot allocate memory). The fault is that 9KB > 8KB limit, kernel rejects.

- **时间窗口 (Time Window)**:
  > 故障时间：2026-05-25 11:45 UTC
  > (满足：历史明确时间段)

- **经过交互确认的关键故障现象 (Key Verified Symptoms)**:
  - 用户 `tu`，RLIMIT_MEMLOCK soft/hard 均为 8KB
  - 进程调用 `mlock(9KB)` 返回 ENOMEM (errno=12)
  - 直接根因：9KB 申请超过 8KB 限制，内核拒绝

- **影响范围 (Impact)**:
  - 容器 `mmap-C` 内用户 `tu` 的进程无法锁定 9KB 内存

## 3. 前期检测结果 (Pre-check Results)

- **环境可达性 (Reachability)**: Pass (`docker ps` 确认容器 `mmap-C` 运行中，Up 45 seconds)
- **基础环境信息 (Basic Info)**:
  - **环境**: Docker 容器 (本地)
  - **容器名**: mmap-C
  - **访问方式**: `docker exec -it mmap-C bash`

## 4. 诊断模型 (Diagnostic Model - Failure Modes)

⛔️ **【确定性路径触发】**：用户提供了唯一性指向的诊断信息，直接使用确定根因。

| 故障模式 (Failure Mode) |
| :--- |
| mlock 超限 (RLIMIT_MEMLOCK) |

## 5. 任务元数据 (JSON Metadata)

```json
{
  "plan_path": "G:\\witty-diagnosis-agent\\dayu\\plans\\20260525_114500_mlock_RLIMIT_MEMLOCK.md",
  "created_at": "2026-05-25T11:45:00Z",
  "mode": "online",
  "target": "docker:mmap-C",
  "tasks": [
    {
      "id": "T1",
      "symptom": "mlock(9KB) 返回 ENOMEM，RLIMIT_MEMLOCK 限制为 8KB",
      "failure_mode": "mlock 超限 (RLIMIT_MEMLOCK)"
    }
  ]
}
```
