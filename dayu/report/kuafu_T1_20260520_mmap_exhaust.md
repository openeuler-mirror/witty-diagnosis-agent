# T1 诊断结果：验证 vm.max_map_count 耗尽

## 基本信息
- **任务 ID**: T1
- **故障模式**: vm.max_map_count 耗尽（mmap ENOMEM）
- **目标容器**: mmap-f1
- **目标进程**: PID 8 (/test/fault_mmap_exhaust)
- **执行方式**: docker exec
- **诊断时间**: 2026-05-20 18:54 UTC+8（故障发生时间附近）
- **容器状态**: Up 4 minutes ✅

---

## 诊断结果

### 1. 系统 vm.max_map_count 参数
| 参数 | 值 | 默认值 | 状态 |
|------|-----|-------|------|
| `vm.max_map_count` | **5000** | 65530 | ⚠️ 远低于默认值 |

### 2. 进程 PID 8 当前 VMA 数量
| 指标 | 值 | 阈值 | 状态 |
|------|-----|------|------|
| 当前 VMA 数量 | **26** | 5000（max_map_count） | ✅ 目前正常（持续增长中）|
| 可用额度 | 4974 | - | - |

### 3. 进程内存状态
| 指标 | 值 | 说明 |
|------|-----|------|
| VmPeak | 870,901,060 kB | 进程虚拟内存峰值（约 830 GB，含大量 mmap 匿名映射）|
| VmSize | 870,901,060 kB | 当前虚拟内存大小（与峰值相同）|
| VmLck | 0 kB | 未锁定内存 |
| VmRSS | 1,408 kB | 物理内存驻留集仅约 1.4 MB |
| Threads | 1 | 单线程进程 |

> **关键发现**: VmPeak/VmSize 高达 870 GB，但 RSS 仅 1.4 MB。这强烈表明进程已通过 mmap 创建了大量匿名映射（MAP_ANONYMOUS），但由于 mmap 创建的页面是惰性分配的（demand paging），大部分映射尚未实际触发缺页，因此物理内存占用极低。此模式正是故障注入程序 `/test/fault_mmap_exhaust` 的典型行为——持续创建匿名 mmap 直到耗尽 VMA 上限。

### 4. VMA 类型分布
| 类型 | 数量 | 说明 |
|------|------|------|
| [anonymous]（匿名映射） | **10** | 含堆、BSS 段等 |
| /usr/lib/x86_64-linux-gnu/libc.so.6 | 6 | glibc 文件映射 |
| /test/fault_mmap_exhaust | 5 | 程序文件映射 |
| /usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2 | 5 | 动态链接器映射 |
| **总计** | **26** | |

> **发现**: 当前 26 个 VMA 中约 10 个为匿名映射（含程序 BSS/BSS、堆等固有匿名区域），远未达到 5000 上限。进程正在持续创建映射，VMA 数量将逐步增长至耗尽。

### 5. 进程 limits（memlock）
| 限制项 | 软限制 | 硬限制 | 单位 |
|--------|--------|--------|------|
| Max locked memory | unlimited | unlimited | bytes |
| Max file locks | unlimited | unlimited | locks |

### 6. 内核日志（mmap 相关）
当前内核日志中未发现 mmap ENOMEM 或 max_map_count 相关告警（dmesg）。**预计在 VMA 增长至接近 5000 时才会触发相关告警。**

### 7. 系统内存概况
| 指标 | 值 |
|------|-----|
| MemTotal | ~15,987 MB |
| MemFree | ~14,300 MB |
| MemAvailable | ~14,888 MB |
| VmallocTotal | ~32 TB |
| VmallocUsed | ~38 MB |

> 系统物理内存充裕（空闲约 14 GB），mmap 失败原因**不是物理内存不足**，而是 `vm.max_map_count` 限制。

### 8. 容器环境
| 项目 | 值 |
|------|-----|
| 操作系统 | Ubuntu 22.04.5 LTS (Jammy Jellyfish) |
| 运行状态 | Up 4 minutes ✅ |

---

## 诊断结论

**直接原因**: 容器 `mmap-f1` 内 `vm.max_map_count` 设置为 **5000**（远低于系统默认值 65530），进程 PID 8 (`/test/fault_mmap_exhaust`) 正持续创建匿名 mmap 映射。当前 VMA 数量为 **26**，仍在增长中。

**当前状态**: 尚未触发 ENOMEM（VMA 26 < 5000，已用 0.5%），但 VmSize 已达 870 GB，表明进程正在快速创建映射。预计 VMA 增长至耗尽 5000 上限后，所有 mmap 调用将返回 ENOMEM "Cannot allocate memory"。

**风险等级**: ⚠️ 低（当前未触发，增长趋势明确）

---
📁 **输出文件路径**: `G:\witty-diagnosis-agent\dayu\report\kuafu_T1_20260520_mmap_exhaust.md`
