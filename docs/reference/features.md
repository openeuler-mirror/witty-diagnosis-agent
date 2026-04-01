# 功能列表 (Features)

## 故障诊断能力

本项目基于**OS 全栈（硬件层→内核层→系统服务层）** 全维度故障模式梳理，系统构建故障诊断能力（通过表格 “Skill” 字段承载）。诊断能力将随故障场景丰富与技术方案迭代持续演进，具体故障模式及对应诊断能力如下表所示：

| 故障域                       | 故障模式             | 故障描述                                     | 诊断方式 | Skill                                                                                | 状态  |
|:------------------------- |:---------------- |:---------------------------------------- |:---- |:------------------------------------------------------------------------------------ |:--- |
| OS内核                      | 系统Crash          | 内核异常、硬件故障或驱动冲突导致系统宕机、重启或无响应。             | 离线   | [vmcore-analysis](skills/vmcore-analysis.md)                                         | 已支持 |
| CPU调度                     | 用户态/内核态CPU 过载    | 系统CPU利用率持续高位，调度队列过长，导致响应能力急剧下降。          | 离线   | [cpu-scheduling-diagnosis](skills/cpu-scheduling-diagnosis.md)                       | 已支持 |
| CPU调度                     | cgroup组CPU 过载    | Cgroup CPU使用超限或争抢，内核节流导致任务执行延迟、排队。       | 离线   | [cpu-scheduling-diagnosis](skills/cpu-scheduling-diagnosis.md)                       | 已支持 |
| 内存                        | OOM              | 物理内存耗尽，内核触发OOM killer杀进程或导致系统Hang/Panic。 | 离线   | [linux-oom-analyzer](skills/linux-oom-analyzer.md)                                   | 已支持 |
| 网络                        | 网络不通             | 路由、防火墙或链路异常导致连接超时、丢包，业务交互中断。             | 在线   | [network-diagnosis](skills/network-diagnosis.md)                                     | 已支持 |
| 硬盘                        | UNC/UF 坏道        | 扇区出现不可纠正错误，读写校验失败，导致数据丢失或文件系统崩溃。         | 离线   | [disk-diagnosis-by-log](skills/disk-diagnosis-by-log.md)                             | 已支持 |
| 文件系统                      | 文件系统损坏           | 元数据损坏致挂载失败或变只读，导致目录乱码、文件丢失。              | 离线   | [offline-file-system-fault-diagnosis](skills/offline-file-system-fault-diagnosis.md) | 已支持 |
| Docker                    | 容器异常退出           | 因崩溃、OOM或配置错误导致容器非正常退出并产生非0退出码。           | 离线   | [docker-fault-analysis](skills/docker-fault-analysis.md)                             | 已支持 |
| Docker                    | 容器cgroup pid资源耗尽 | 容器PID达上限，内核拒绝创建新进程，导致无法Fork或Clone。       | 离线   | [docker-fault-analysis](skills/docker-fault-analysis.md)                             | 已支持 |
| 系统安全                      | SELinux 策略拒绝     | SELinux Enforcing模式下拦截无权访问，导致操作被拒。       | 离线   | [linux-security-diagnosis](skills/linux-security-diagnosis.md)                       | 已支持 |
| 启动引导                      | GRUB引导失败         | 读取配置或加载内核/Initrd失败，导致开机卡住无法进入系统。         | 离线   | [grub-ibmc-diagnosis](skills/grub-ibmc-diagnosis.md)                                 | 已支持 |
| 硬盘                        | 预失效              | SMART上报重映射扇区增加等预警，介质可靠性下降，存在高危风险。        | 在线   | 开发中                                                                                  | 开发中 |
| 内存条                       | GPIO中断上报FATAL级故障 | 内存控制器上报不可恢复故障，BIOS隔离异常内存致可用内存骤减。         | 离线   | 开发中                                                                                  | 开发中 |
| 内存条                       | GPIO 中断上报CE故障    | ECC检测可纠正错误超阈值，触发CE风暴，内存页被标记降级。           | 离线   | 开发中                                                                                  | 开发中 |
| 内存条                       | 空闲页 UCE 故障       | 空闲页发生不可纠正ECC错误，内核标记Poison并移除该页。          | 离线   | 开发中                                                                                  | 开发中 |
| 电源                        | 电压异常             | PSU输出电压偏离范围，触发保护机制致CPU降频，性能下降。           | 离线   | 开发中                                                                                  | 开发中 |
| 电源                        | 电源掉电             | PSU断电致系统立即停机，未持久化数据丢失，需重启恢复。             | 离线   | 开发中                                                                                  | 开发中 |
| 💡**更多故障模式和诊断能力持续演进中...** |                  |                                          |      |                                                                                      |     |

**诊断方式**：

- **在线**：智能诊断Agent将自动登录至故障服务器采集遥测数据并进行根因分析，需用户提供服务器的登录凭证。
- **离线**：智能诊断Agent基于用户提供的遥测数据归档路径，在本地进行根因分析。
