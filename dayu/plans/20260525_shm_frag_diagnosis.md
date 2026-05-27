# 共享内存与地址空间碎片化故障诊断计划

## 故障描述
1. 共享内存权限拒绝：跨进程 shmget/shmat 返回 EACCES
2. 地址空间碎片化：大块 mmap 返回 ENOMEM

## 诊断任务
T1: 诊断共享内存映射状态（路径D）
    脚本: test/mmap-vma-diagnosis/scripts/diagnose_shm.sh
    参数: -S "2026-05-25 07:00:00"

T2: 诊断地址空间碎片化（路径E）
    脚本: test/mmap-vma-diagnosis/scripts/diagnose_fragmentation.sh
    参数: -S "2026-05-25 07:00:00"

T3: 收集系统VMA综合信息
    脚本: test/mmap-vma-diagnosis/scripts/collect_vma_info.sh
    参数: -S "2026-05-25 07:00:00"
