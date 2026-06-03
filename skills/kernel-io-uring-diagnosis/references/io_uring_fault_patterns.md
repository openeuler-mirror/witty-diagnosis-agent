# io_uring 故障模式参考

本文用于把常见 io_uring 现象映射到证据、候选根因和验证步骤。诊断时不要只凭单个
errno 下结论，应同时检查调用阶段、参数、资源状态和运行上下文。

## 资源限制

| 现象 | 关键证据 | 候选根因 | 验证方式 |
| --- | --- | --- | --- |
| `io_uring_setup` 返回 `ENOMEM` | 内存压力、cgroup 限制、entries 较大 | ring 分配失败或内存资源不足 | 检查 `/proc/meminfo`、cgroup memory、entries |
| `io_uring_register` 返回 `ENOMEM` | fixed buffer 注册、`Max locked memory` 较低 | `RLIMIT_MEMLOCK` 不足 | 对比注册字节数和 `/proc/<pid>/limits` |
| `io_uring_setup` 返回 `EPERM` | 使用 SQPOLL 或受限 flag | 权限不足或 flag 组合受限 | 检查 setup flags 和进程 capabilities |
| submit 返回 `EAGAIN` | in-flight I/O 多、瞬时队列压力 | 资源暂不可用或队列压力 | 关联 queue depth、worker 状态和重试行为 |

不能把所有 `ENOMEM` 都归为系统 OOM。fixed buffer 场景更常见的是 memlock、
pinned page accounting 或 cgroup 限制。

## Ring 容量与完成路径

| 现象 | 关键证据 | 候选根因 | 验证方式 |
| --- | --- | --- | --- |
| submission queue full | 应用日志、高 in-flight 请求 | SQ depth 过小或 submitter 过快 | 对比队列深度、提交速率和完成速率 |
| CQ overflow 或 CQE missing | 日志出现 overflow、完成事件延迟 | CQ 未及时消费 | 检查消费线程状态和事件循环 |
| 请求超时 | 应用 timeout、worker D 状态、存储延迟 | 后端 I/O 慢或 worker 阻塞 | 关联 `iou-wrk`、块设备、文件系统日志 |
| 短 I/O 反复出现 | 应用日志和文件系统行为 | EOF、Direct I/O 对齐、后端错误 | 检查返回值、offset、length 和文件状态 |

Ring 压力通常只是现象。根因可能是消费线程阻塞、后端设备慢、worker 受限或应用重试策略错误。

## Worker 与 SQPOLL

| 现象 | 关键证据 | 候选根因 | 验证方式 |
| --- | --- | --- | --- |
| `iou-wrk-*` 线程很多 | `ps -eLf`、线程状态 | worker 阻塞或并发过高 | 检查线程 state、wchan、cgroup CPU/io 限制 |
| `iou-sqp-*` CPU 高 | SQPOLL 开启、CPU 占用高 | busy polling、CPU 亲和性或调度问题 | 检查 CPU affinity、调度策略、cgroup CPU quota |
| 提交继续但完成停止 | worker D 状态或 CQ 消费线程阻塞 | 后端 I/O hang 或 CQ drain 失败 | 关联 worker 栈/wchan 和应用事件循环 |
| SQPOLL setup 失败 | `EPERM` 或 `EINVAL` | 权限不足或 flag 组合不支持 | 检查 flags、内核版本和 capabilities |

不能只根据 worker 数量判断耗尽。必须同时关联 worker 状态、应用症状、后端延迟和完成行为。

## Fixed Buffer 与 Fixed File

| 现象 | 关键证据 | 候选根因 | 验证方式 |
| --- | --- | --- | --- |
| buffer 注册失败 | `io_uring_register` errno | memlock、地址无效、生命周期错误 | 对比地址/长度、maps 和 limits |
| fixed file 操作失败 | `IOSQE_FIXED_FILE`、注册文件表 | stale index 或 unregister 时序错误 | 检查 register/unregister 顺序 |
| 偶发 `EFAULT` | userspace 指针无效 | buffer 被过早 unmap/free | 检查应用生命周期和 maps |
| unregister 返回 `EBUSY` | 仍有 in-flight 请求引用资源 | 注销与活跃 SQE 竞争 | 确认注销前 CQE 已 drain |

需要区分“注册失败”和“注册后生命周期错误”。两类问题的修复路径不同。

## O_DIRECT 对齐

| 现象 | 关键证据 | 候选根因 | 验证方式 |
| --- | --- | --- | --- |
| `read`/`write` 返回 `EINVAL` | `O_DIRECT` fd、buffer/len/offset 未对齐 | Direct I/O 对齐违规 | 检查地址、长度、offset、逻辑块大小 |
| 去掉 `O_DIRECT` 后成功 | 同 workload buffered I/O 成功 | Direct I/O 约束 | 验证文件系统和块设备约束 |
| 只有部分路径失败 | 文件系统或挂载选项不同 | 路径相关 Direct I/O 支持差异 | 对比 mount、文件系统和 block size |

Direct I/O 对齐可能同时涉及用户态 buffer 地址、I/O 长度、文件 offset、文件系统块大小和设备逻辑块大小。

## 内核兼容性

| 现象 | 关键证据 | 候选根因 | 验证方式 |
| --- | --- | --- | --- |
| `ENOSYS` | syscall 不存在 | 当前内核缺少 io_uring | 检查内核版本和 syscall 可用性 |
| setup/register 返回 `EINVAL` | 新 flag/opcode 或参数组合 | feature 不支持或参数非法 | 对比运行内核和实际参数 |
| 不同发行版行为不同 | 同应用、不同内核 | backport 差异 | 检查发行版内核 changelog 和 runtime probe |

优先使用 runtime probe 证据，而不是只看 header。应用可能用新 header 编译，却运行在不支持对应 feature 的内核上。
