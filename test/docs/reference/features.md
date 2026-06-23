# 功能列表 (Features)

本项目按 OS 全栈（硬件层 → 内核层 → 系统服务层）梳理故障模式并分层构建诊断能力，目前已支持 38 个故障诊断 Skill（用户态 14、内核 15、硬件 9），并将随场景丰富与方案迭代持续演进。

> 故障层说明：**用户态** — 进程/服务/应用层故障；**内核** — 内核子系统/驱动/系统调用层故障；**硬件** — 物理设备/固件/链路层故障

---

## 一、用户态故障诊断技能

| 序号  | skill 名称                   | 能力                                                                                                                                                                                                                              | 故障层 |
|:---:|:-------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:---:|
| 1   | coredump_diagnose          | 面向 Linux 用户态进程 coredump 的结构化诊断。覆盖 SIGSEGV/SIGBUS/SIGABRT/SIGFPE 等异常信号，针对空指针解引用、栈溢出、堆内存破坏、总线错误、除零异常、Python+C 混合栈等场景。按场景下钻输出崩溃链与根因假设，依赖 GNU gdb 进行反汇编与调用栈分析。                                                                      | 用户态 |
| 2   | docker-fault-analysis      | Docker 容器全生命周期故障诊断。覆盖内核/系统调用、资源限制（OOM/CPU）、文件系统/存储、网络、权限/安全以及日志/监控六大故障类别。采用"宿主机系统层 → Docker 引擎层 → 容器运行时层"逐层收敛思维模型，涵盖容器启动失败（Exited/CrashLoopBackOff）、频繁重启、网络不通、I/O 卡顿、OOM、磁盘写满、端口冲突、Docker daemon 挂死等场景。                         | 用户态 |
| 3   | fd-leak-diagnosis          | 文件描述符泄漏全路径诊断。覆盖进程 FD 逼近 ulimit 上限、Socket CLOSE_WAIT 堆积、epoll 实例泄漏、系统级 FD 耗尽（file-nr 告警）、inotify watch 泄漏、已删除文件仍被进程占用等场景。采用"系统级 → 进程级 → FD 类型级 → 代码级"四层下钻模型，集成 strace 系统调用级追踪确认 open/close 不匹配。                                  | 用户态 |
| 4   | linux-security-diagnosis   | Linux 操作系统安全故障定位与分析。覆盖用户无法登录/SSH 连接失败/PAM 认证异常、文件权限或 SELinux 策略问题、防火墙规则异常/端口访问被拒、审计日志缺失或 rsyslog/auditd 异常、账户被锁定或疑似暴力破解、异常登录行为、内核安全模块异常、sudo 权限异常、SSSD/LDAP 认证服务故障等场景。强调"认证 → 权限 → 网络 → 审计 → 防护 → 账户 → 内核模块"层级化分析和证据驱动的脚本化信息采集。 | 用户态 |
| 5   | python-memory-leak-analyzer | Python 进程内存泄漏根因分析。覆盖 Python 托管对象泄漏、全局容器/无界缓存、闭包/回调/线程局部保留、引用循环、分配点与保留点分离、RSS 与 Python 堆背离、碎片化或缓存预热伪泄漏。支持从目录、PID、服务名或日志包自动发现证据，默认采用只读和可复现路径。                                                                                                                   | 用户态 |
| 6   | strace-syscall-diagnosis   | 基于 strace/ltrace 的系统调用级故障深度诊断。采用"调用轨迹 + 内核语义"双轨分析模型，覆盖 syscall 错误码模式识别（EACCES/ENOENT/EAGAIN/ENOMEM）、慢 syscall 定位（futex/epoll_wait/read 阻塞）、库函数调用链异常追踪、进程 hang/blocked 在 syscall、文件描述符泄漏、资源泄漏模式等场景。支持可选的内核源码级根因交叉验证。             | 用户态 |
| 7   | system-resource-diagnosis  | 系统资源限制与耗尽故障在线诊断。覆盖进程数超 ulimit 限制、进程栈溢出、IPC 资源耗尽（消息队列/共享内存/信号量）、inotify 句柄耗尽、内核模块加载失败、fork 失败无法创建新进程、SIGSEGV core dump、文件监控失效、insmod/modprobe 失败等场景。通过系统级和进程级两层指标采集定位资源瓶颈。                                                       | 用户态 |
| 8   | time-sync-diagnosis        | Linux 时间同步故障结构化诊断。覆盖 NTP/chronyd 时间漂移、同步失败、ntpq 查询异常、UDP 123 连通性异常、计时源不稳定、False Ticker、Panic 阈值触发、时钟源或 Stratum 异常等场景。按"全量信息采集 → 场景下钻 → 交叉验证 → 输出结论"四阶段流程输出时间链与根因链。                                                              | 用户态 |
| 9   | unix-socket-pipe-diagnosis | Unix Domain Socket（UDS）与匿名管道（Pipe）故障诊断。覆盖 UDS 连接拒绝（ECONNREFUSED）、地址冲突（EADDRINUSE）、socket 文件权限错误、管道阻塞写、SIGPIPE 进程退出、socketpair 泄漏、SO_PASSCRED 凭证传递失败、listen backlog 满等场景。采用"系统层 → 类型层 → 代码根因层"三层下钻模型。                            | 用户态 |
| 10  | dns-resolution-diagnosis   | DNS 解析故障诊断。覆盖解析超时/查询失败、NXDOMAIN 误报、/etc/resolv.conf 配置异常、nsswitch.conf 顺序错误、systemd-resolved 缓存污染、DNS 劫持检测、TCP fallback 失败、EDNS0 兼容性问题、间歇性解析失败、特定域名解析异常等场景。采用"系统层 → 类型层 → 代码根因层"三层下钻模型。                                                           | 用户态 |
| 11  | flamegraph-analysis        | 火焰图性能分析。支持 folded/perf script/Chrome cpuprofile/Go pprof/AsyncProfiler/SVG 等十余种格式输入适配与 SVG 反向解析。通过自然语言意图识别与性能模式检测，识别锁竞争、GC 压力、I/O 等待等性能反模式。支持 On-CPU + Off-CPU 联合分析与差分对比，输出结构化根因分析报告与交互式 HTML 火焰图。                                      | 用户态 |
| 12  | memory-leak-diagnosis      | 用户态/内核态内存泄漏检测与诊断。用户态覆盖 RSS 持续增长趋势分析、/proc/[pid]/smaps 匿名页增长、valgrind/AddressSanitizer 报告解析；内核态覆盖 slab 增长（slabinfo/slabtop）、vmalloc 泄漏、kmalloc 未释放追踪、memcg 内存泄漏等场景。采用"用户态 → 内核态"双轨分析模型，按场景下钻定位泄漏根因。                                               | 用户态 |
| 13  | process-hang-diagnosis     | 用户态进程挂起/无响应深度诊断。覆盖死锁检测（wchan + gdb bt）、futex 锁等待、文件锁竞争（/proc/locks）、管道/socket 阻塞读写、信号屏蔽导致无法终止、SIGSTOP 误发送、内核 D 状态（TASK_UNINTERRUPTIBLE）阻塞等场景。采用"OS 状态 + 进程内省"双轨并行分析，支持有符号/源码级交叉验证。                                               | 用户态 |
| 14  | tls-certificate-diagnosis  | TLS/SSL 证书与握手故障诊断。覆盖证书过期/即将过期检测、证书链不完整、CA 信任库缺失/过期、TLS 版本/密码套件不兼容、SNI 配置错误、OCSP stapling 失败、客户端证书认证失败、mTLS 双向认证等场景。按故障场景分支下钻输出根因链与修复建议。                                                                 | 用户态 |

---

## 二、内核故障诊断技能

| 序号  | skill 名称                            | 能力                                                                                                                                                                                                                                                | 故障层 |
|:---:|:----------------------------------- |:------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:---:|
| 15  | linux-oom-analyzer                  | Linux 内存 OOM 故障系统化分析。覆盖系统级 OOM（整机内存耗尽触发 OOM killer）、进程级 OOM（特定进程内存异常被 kill）、cgroup OOM（容器/cgroup 内存限制触发）、内核态 OOM（slab/shmem/内核模块异常）四大场景。支持用户提供故障时间点精准定位，可选内核源码级根因分析。                                                                              | 内核  |
| 16  | network-diagnosis                   | 通用网络故障诊断。覆盖 IP 不通、丢包、延迟、抖动、端口/服务偶发不可用、部分网段访问异常、MTU 问题、路由表错误、ARP 异常等场景。采用分层诊断方法论（物理层 → 链路层 → 网络层 → 传输层 → 应用层），强调"只诊断不修复"原则，所有修复建议标注风险等级并提供回滚方案。                                                                                                    | 内核  |
| 17  | offline-file-system-fault-diagnosis | 基于离线日志（iBMC/OS Messages/InfoCollect）的 Linux 文件系统故障诊断。重点诊断 EXT4/XFS 文件系统逻辑损坏、挂载异常、元数据损毁、空间/Inode 耗尽、I/O 错误引发的逻辑一致性等问题。通过自动化脚本从海量日志中蒸馏故障线索，定位文件系统与底层存储关联性根因。                                                                                        | 内核  |
| 18  | online-cpu-scheduling-diagnosis     | CPU 调度在线诊断。覆盖系统 load 飙升、进程 D 状态/不可中断睡眠、僵尸进程/Z 状态、软中断过载、硬中断过载、RT 进程死循环、R 状态死锁、CPU 使用率异常、cgroup CPU 限流、系统响应卡顿、业务时延抖动、进程无法 kill、PID 资源耗尽等场景。通过收集系统运行状态数据进行分层下钻分析。                                                                                    | 内核  |
| 19  | online-file-system-fault-diagnosis  | 文件系统在线故障诊断。覆盖磁盘空间满、inode 耗尽、IO 时延高、关键文件损坏、权限错误、无法写入文件、进程 D 状态等待 IO、动态库加载失败等场景。通过采集文件系统挂载信息、容量指标、IO 统计等实时数据逐层定位根因。                                                                                                                                 | 内核  |
| 20  | os-restart-diagnosis                | Linux 操作系统异常重启分阶段诊断。覆盖外部供电中断、人为/计划重启、内核自保复位（OOM/Softlockup）、内核崩溃/Panic、硬件底层异常（MCE/ECC/PCIe）等场景。按"全量信息采集与指纹归类 → 场景深度下钻 → 交叉验证 → 输出结论"四阶段流程，输出完整故障时间链与根因链。                                                                                          | 内核  |
| 21  | overlayfs-diagnosis                 | OverlayFS 叠加文件系统故障诊断。覆盖 upper/lower/work 目录配置错误、cross-device overlay 限制、opaque whiteout 导致文件"消失"、copy-up 性能退化、overlay 上 inotify 不工作、Docker overlay2 存储驱动特有问题（inode 耗尽、diff 目录膨胀）、redirect_dir 配置冲突、metacopy 异常等场景。支持系统态诊断 + 内核态机理双轨并行分析。          | 内核  |
| 22  | swap-thrashing-diagnosis            | Swap 与虚拟内存异常深度诊断。覆盖 swap 空间耗尽、swap 频繁换入换出（thrashing 检测）、swappiness 配置不当、swap 文件/分区损坏、swap on SSD 磨损、kswapd CPU 占用过高、zswap/zram 配置异常、内存不足触发 OOM 等场景。采用"现场指标 + 内核语义"双轨分析，可选内核源码级根因验证。                                                               | 内核  |
| 23  | vmcore-analysis                     | Linux 内核 VMcore 崩溃转储深度分析。覆盖空指针解引用、内核栈溢出、内存越界（OOB）、Use-After-Free（UAF）、硬件 MCE 异常、Bit Flip、内存 UE、死锁、Soft/Hard Lockup、BUG() 触发、OOM panic、驱动异常、文件系统崩溃、网络子系统崩溃、存储 IO 崩溃、RCU Stall、SMEP/SMAP 触发、KVM/vCPU 异常、ACPI 固件异常等场景。采用"vmcore 逆向 + 源码正向"双轨并行并交叉验证。 | 内核  |
| 24  | X-diagnosis-io                      | 基于 X-diagnosis 工具栈的在线存储与文件系统 IO 诊断。严格限定使用 xd_iolatency、xd_scsiiocount、xd_scsiiotrace、xd_ext4fsstat 四种核心 IO 工具，采用"时延切片、指令追踪、文件级审计"手段定位块设备与文件系统的内核级性能瓶颈与异常。                                                                                         | 内核  |
| 25  | X-diagnosis-network-analysis        | 基于 X-diagnosis 工具栈的在线网络系统故障诊断。严格限定使用 xd_ntrace、xd_tcpresetstack、xd_tcpskinfo、xd_arpstormcheck、xd_netvringcheck、xd_skblen_check 六种核心网络工具，采用"实时探测、微观交互、多维证伪"手段定位网络协议栈内核级故障。                                                                         | 内核  |
| 26  | kernel-io-uring-diagnosis           | Linux io_uring 异步 I/O 子系统故障诊断。覆盖 io_uring_setup/io_uring_enter/io_uring_register 系统调用异常、提交队列/完成队列异常、CQE 丢失、completion 延迟、io-wq worker 繁忙、SQPOLL 异常、fixed buffer 注册失败、O_DIRECT EINVAL 等场景。采用"运行证据 + 内核语义"双轨并行模型，交叉验证定位 io_uring 根因。                   | 内核  |
| 27  | kernel-fuse-diagnosis               | FUSE（用户态文件系统）内核端故障诊断。覆盖 FUSE daemon 崩溃后 EIO、请求队列阻塞与 D 状态、max_read/max_write 配置不当导致性能退化、writeback cache 一致性问题、多线程 daemon 死锁、/dev/fuse 设备权限问题、内核 FUSE 模块 Bug、混合复杂 FUSE 故障等场景。采用"系统层 → 类型层 → 代码根因层"三层下钻模型，支持 FUSE 全链路诊断。                   | 内核  |
| 28  | netfilter-conntrack-diagnosis       | Netfilter / iptables / conntrack 防火墙与连接跟踪深度诊断。覆盖 nf_conntrack 表满、iptables/nftables 规则误命中导致 DROP/REJECT、NAT 映射异常、conntrack 状态丢包（INVALID/UNREPLIED）、TCP window tracking 异常、ct timeout 超时、helper/ALG 协议辅助模块异常、ipset 匹配失效等场景。采用"规则链分析 + conntrack 分析"并行双轨模型并交叉验证。   | 内核  |
| 29  | nfs-client-diagnosis                | NFS 客户端故障诊断。覆盖 mount 挂载失败/hung、stale file handle、NFSv4 lease 过期/state 恢复失败、rpc.statd/lockd 异常、性能退化（rtt 飙升）、soft/hard mount 超时行为差异等场景。采用"系统状态逆向 + NFS 协议正向"并行双轨模型，交叉验证定位客户端或服务端问题。                                                                              | 内核  |

---

## 三、硬件故障诊断技能

| 序号  | skill 名称                                 | 能力                                                                                                                                                                                                              | 故障层 |
|:---:|:---------------------------------------- |:--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |:---:|
| 30  | disk-health-diagnosis                    | 服务器磁盘健康全栈诊断与故障预测。基于"现状、趋势、背景"三视角，覆盖 L1~L6 六层检测体系（盘本体 SMART → 控制器/链路 → 文件系统/OS → 业务服务层）。支持 iBMC 带外日志（华为/浪潮/H3C）、OS infocollect 包、系统日志三类日志来源。输出风险评分与 P0~P3 风险等级及分级处置建议。                                           | 硬件  |
| 31  | grub-ibmc-diagnosis                      | 基于 iBMC 带外管理日志的服务器 GRUB 启动故障深度诊断。覆盖华为、浪潮、新华三三大厂商服务器，针对服务器上电后无法进入 OS、卡在 GRUB rescue、Kernel Panic、initramfs 失败、磁盘不识别、BIOS/UEFI 启动异常、RAID 故障无法启动等启动链故障。通过厂商识别与自动化脚本从海量 iBMC 日志中提取关键故障线索。                           | 硬件  |
| 32  | offline-CPU-fault-diagnosis              | 基于离线日志（iBMC/OS Messages/InfoCollect）的 CPU 硬件故障诊断。重点诊断 CPU 过热（Overheating）、降频（Throttling）、MCE 硬件错误、缓存错误（Cache Error）、UPI/QPI 链路不稳定等物理级故障，以及内核 Panic 或 Soft Lockup 的底层 CPU 根因溯源。                                  | 硬件  |
| 33  | offline-disk-fault-diagnosis             | 基于离线日志（iBMC/OS Messages/InfoCollect）的磁盘硬件故障诊断。重点诊断磁盘坏道（Bad Sector）、RAID 掉盘/降级（Offline/Degraded）、I/O 超时（Timeout/Blocked）、磁盘巡检错误（Predictive Failure/SMART Error）、SAS/SATA/NVMe 链路不稳定、物理槽位异常等场景，以及文件系统只读的底层存储根因溯源。 | 硬件  |
| 34  | offline-GPU-fault-diagnosis              | 基于离线日志（iBMC/OS Messages/InfoCollect）的 GPU 硬件故障诊断。重点诊断 GPU 掉卡（Fallen off the bus）、XID 错误、显存不可纠正错误（Uncorrectable ECC）、GPU 维度过温、PCIe 链路问题、驱动异常等物理及软件驱动层面的故障。                                                       | 硬件  |
| 35  | offline-memory-fault-diagnosis           | 基于离线日志（iBMC/OS Messages/InfoCollect）的内存硬件故障诊断。重点诊断内存 ECC 错误（CE/UCE）、MCE 报错、内存巡检告警、内存在位异常、内存热插拔、内存主板插槽故障等物理级故障，以及内存泄漏/耗竭引发的系统挂起或业务异常的多维根因溯源。                                                                     | 硬件  |
| 36  | offline-network-hardware-fault-diagnosis | 基于离线日志（iBMC/OS Messages/InfoCollect）的网络硬件故障诊断。重点诊断网卡硬件错误、PCIe 致命错误、网口 Link Down、丢包/错包/延时大、Bond 切换、网卡驱动 Panic 或固件加载失败等网络硬件及物理链路层故障，提供底层物理坐标定位。                                                                   | 硬件  |
| 37  | offline-NPU-fault-diagnosis              | 基于离线日志（iBMC/OS Messages/InfoCollect）的 NPU 硬件故障诊断。重点诊断 NPU（如华为昇腾 Ascend 系列）掉卡、HBM（高带宽内存）故障、AER 链路错误、驱动加载失败、Acl Error、温度过高保护等 NPU 及关联 PCIe 链路/固件/存储子系统的故障。                                                        | 硬件  |
| 38  | offline-power-fault-diagnosis            | 基于离线日志（iBMC/OS Messages/InfoCollect）的电源硬件故障诊断。重点诊断电源掉电（Power Loss/Off）、电源模块故障（PSU Fault）、电压异常（Voltage Over-range）、冗余丢失（Redundancy Lost）、电源过载（Overload）以及服务器无法上电等电源供电链路及冗余异常的物理级故障。                              | 硬件  |

**诊断方式**：

- **在线**：智能诊断Agent将自动登录至故障服务器采集遥测数据并进行根因分析，需用户提供服务器的登录凭证。
- **离线**：智能诊断Agent基于用户提供的遥测数据归档路径，在本地进行根因分析。