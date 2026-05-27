# mmap-vma 故障诊断计划

## 故障描述
Elasticsearch 进程频繁报 "mmap of 16777216 bytes failed: Cannot allocate memory"
系统日志显示大量 mmap 失败错误

## 诊断任务
T1: 收集系统VMA参数和进程VMA统计
    脚本: test/mmap-vma-diagnosis/scripts/collect_vma_info.sh
    参数: -S "2026-05-25 07:00:00" -n elasticsearch

T2: 诊断vm.max_map_count耗尽场景
    脚本: test/mmap-vma-diagnosis/scripts/diagnose_mapcount.sh
    参数: -S "2026-05-25 07:00:00" -n elasticsearch

T3: 检查SIGBUS文件截断风险
    脚本: test/mmap-vma-diagnosis/scripts/diagnose_sigbus.sh
    参数: -S "2026-05-25 07:00:00"

T4: 检查mlock超限
    脚本: test/mmap-vma-diagnosis/scripts/diagnose_mlock.sh
    参数: -S "2026-05-25 07:00:00" -n elasticsearch

T5: 检查共享内存状态
    脚本: test/mmap-vma-diagnosis/scripts/diagnose_shm.sh
    参数: -S "2026-05-25 07:00:00"

T6: 检查地址空间碎片化
    脚本: test/mmap-vma-diagnosis/scripts/diagnose_fragmentation.sh
    参数: -S "2026-05-25 07:00:00" -n elasticsearch
