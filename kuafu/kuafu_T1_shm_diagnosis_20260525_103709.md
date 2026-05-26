# 共享内存故障诊断报告 - T1

## 基本信息
- **任务ID**: T1
- **故障模式**: 共享内存故障
- **目标**: 容器 mmap-f4（Docker Desktop）
- **诊断时间**: 2026-05-25T10:37:09 UTC
- **分析时间**: 2026-05-25T11:01 UTC

## 诊断结果

### 1. 共享内存段状态确认

| 属性 | 值 |
|------|-----|
| key | 0x12345678 |
| shmid | 6（动态分配） |
| perms | 0666（rw-rw-rw-） |
| size | 4096 bytes |
| owner/creator | root:root (uid=0, gid=0) |
| nattch | 0（已分离） |

> **说明**: shmid 由内核动态分配，首次运行时为 shmid=1，清理后重建为 shmid=6。key=0x12345678 固定不变。

### 2. 共享内存创建与访问测试

| 操作 | 结果 |
|------|------|
| shmget(key=0x12345678, 4096, IPC_CREAT\|0666) | ✅ 成功，shmid=6 |
| shmat(shmid=6, NULL, 0) | ✅ 成功，地址 0x7050b075b000 |
| 写入数据 "HELLO_FROM_DIAG" | ✅ 成功 |
| 读取验证 | ✅ 数据一致 |
| shmdt() | ✅ 成功分离 |

### 3. 内核共享内存参数

| 参数 | 当前值 | 说明 |
|------|--------|------|
| kernel.shmall | 18446744073692774399 | 几乎无上限（约 16EB） |
| kernel.shmmax | 18446744073692774399 | 几乎无上限（约 16EB） |
| kernel.shmmni | 4096 | 最大共享内存段数量 |
| kernel.shm_rmid_forced | 0 | 需手动 IPC_RMID 清理 |

### 4. 系统级共享内存使用

```
segments allocated: 0（诊断测试清理后）
pages allocated: 0
```

### 5. /proc/sysvipc/shm 确认

共享内存段在 /proc/sysvipc/shm 中有完整记录，包含 key、shmid、perms、size、cpid、lpid、nattch、时间戳等完整信息。

### 6. Root 权限特殊行为测试

测试 perms=0000 时 root 仍可 attach 成功——这是 Linux 内核 CAP_IPC_OWNER 特权豁免的正常行为。非 root 用户将受 perms 限制。

## 诊断结论

**状态: ✅ 共享内存功能正常**

容器 mmap-f4 的 System V 共享内存功能完全正常：
- 共享内存创建（shmget）：正常
- 共享内存挂接（shmat）：正常
- 共享内存读写：正常
- 共享内存分离（shmdt）：正常
- 共享内存删除（IPC_RMID）：正常
- 内核参数配置：宽松无限制

**无故障**：当前环境下共享内存创建、权限检查、数据读写均无异常。

📁 **输出文件路径**: `G:\witty-diagnosis-agent\kuafu\kuafu_T1_shm_diagnosis_20260525_103709.md`
