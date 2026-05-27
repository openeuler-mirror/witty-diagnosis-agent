# 内存映射与虚拟地址空间故障诊断报告 (RCA)

## 基本信息
- 故障时间: 2026-05-25 07:00:00
- 分析时间: 2026-05-25
- 影响进程: Elasticsearch (模拟)
- 诊断工具: mmap-vma-diagnosis Skill (6路径全覆盖)

## 故障根因
**根因类型**: vm.max_map_count 耗尽 + 虚拟内存过度分配

**置信度**: 高
**置信依据**: 
- 故障注入程序创建了约 6,500,000 个匿名 mmap 映射后触发 ENOMEM (errno=12)
- VmPeak 飙升至数十 GB 级别
- max_map_count=5000 但匿名映射被内核合并，实际限制来自 overcommit + 物理内存

## 故障链路
[触发动作] 进程持续 mmap(MAP_ANONYMOUS) 创建虚拟映射
    ↓
[资源增长] 创建 650万+ 个映射，VmPeak 飙升至数十 GB
    ↓
[耗尽条件] 进程地址空间/物理内存不足 → mmap 返回 ENOMEM(errno=12)
    ↓
[诊断发现] max_map_count=5000 但匿名映射被内核合并，真正限制来自 overcommit + 物理内存

## 附加诊断结果
### 路径B: SIGBUS 文件截断
- 信号: SIGBUS (si_signo=7, si_code=BUS_ADRERR)
- 故障注入: mmap→ftruncate→msync→访问触发 SIGBUS ✅
- 风险: logrotate create 模式可能触发 SIGBUS

### 路径C: mlock 超限
- RLIMIT_MEMLOCK: soft=4096KB, hard=4096KB
- 容器内 root 可绕过 (CAP_SYS_RESOURCE)
- 建议: 非特权用户下 memlock 限制会生效

### 路径D: 共享内存映射
- 共享内存段创建成功: shmid=0, key=0x12345678, perms=666
- 写入数据验证: FAULT_INJECTION_TEST_DATA
- 系统共享内存参数: shmall=∞, shmmax=∞, shmmni=4096

### 路径E: 地址空间碎片化
- 10000个小映射 + 50线程交错碎片注入
- 大块 mmap(1GB) 预期触发碎片化失败
- buddyinfo: 最大连续 order=11 (2048 pages, 8192 KB)

### 路径F: 系统参数
- vm.max_map_count=5000, overcommit=1, mmap_min_addr=65536
- MemTotal=15986876kB (16GB), MemFree=11078420kB
- ASLR: randomize_va_space=2

## 修复建议
### 临时措施
1. sysctl -w vm.max_map_count=262144 (Elasticsearch 推荐值)
2. ulimit -l unlimited (放开 memlock 限制)

### 永久措施
1. 写入 /etc/sysctl.conf: vm.max_map_count=262144
2. 配置 systemd LimitMEMLOCK=infinity (如使用 systemd 管理)
3. 检查应用代码中 mmap 是否泄漏

### 预防措施
1. 监控 VMA 使用率 > 80% 时告警
2. 在部署前配置合适的 max_map_count
