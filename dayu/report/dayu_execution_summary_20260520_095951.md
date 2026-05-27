# Dayu 诊断执行汇总报告

## 基本信息
- **分析时间**: 2026-05-20 09:59 UTC
- **执行依据**: G:\witty-diagnosis-agent\dayu\plans\20260520_014646_es_mmap_exhaust.md
- **模式**: Plan Execution
- **目标容器**: mmap-fault1 (docker exec)
- **故障进程 PID**: 8

## 任务执行清单

### T1: 验证 vm.max_map_count 耗尽 / mmap 映射数超限
- **任务描述**: mmap 返回 ENOMEM，Cannot allocate memory for mmap
- **状态**: ✅ 已完成
- **诊断步骤**:
  1. ✅ Step 1 — 系统 VMA 综合信息收集 (collect_vma_info.sh)
  2. ✅ Step 2 — vm.max_map_count 专项诊断 (diagnose_mapcount.sh)
  3. ✅ Step 3 — VMA 类型分布精细化分析
  4. ✅ Step 4 — 进程内存状态和限制检查
- **关键发现**:
  - m.max_map_count = 5000（模拟环境调低）
  - 进程 PID 8 当前 VMA 数量 = 26（使用率 0%）
  - 故障进程 /test/fault_mmap_exhaust 已创建 5 个文件映射
  - VmPeak = 618586236 kB, VmRSS = 1408 kB
  - 内核日志中未发现 max_map_count 相关告警（模拟环境限制）
- **结果文件路径**: G:\witty-diagnosis-agent\kuafu\kuafu_T1_20260520_095936_vma_diag\

## 结果文件清单
| 文件 | 完整路径 |
|------|---------|
| VMA 综合收集日志 | G:\witty-diagnosis-agent\kuafu\kuafu_T1_20260520_095936_vma_diag\collect.log |
| max_map_count 诊断日志 | G:\witty-diagnosis-agent\kuafu\kuafu_T1_20260520_095936_vma_diag\diagnose_mapcount.log |
| 进程 maps | G:\witty-diagnosis-agent\kuafu\kuafu_T1_20260520_095936_vma_diag\pid_8_maps.txt |
| 进程 smaps_rollup | G:\witty-diagnosis-agent\kuafu\kuafu_T1_20260520_095936_vma_diag\pid_8_smaps_rollup.txt |
| 进程 status | G:\witty-diagnosis-agent\kuafu\kuafu_T1_20260520_095936_vma_diag\pid_8_status.txt |
| 进程 limits | G:\witty-diagnosis-agent\kuafu\kuafu_T1_20260520_095936_vma_diag\pid_8_limits.txt |
| 进程 fd 信息 | G:\witty-diagnosis-agent\kuafu\kuafu_T1_20260520_095936_vma_diag\pid_8_fd.txt |

---
*本报告仅为任务级诊断执行汇总，不包含根因分析。请转交 Baize 进行根因分析。*
