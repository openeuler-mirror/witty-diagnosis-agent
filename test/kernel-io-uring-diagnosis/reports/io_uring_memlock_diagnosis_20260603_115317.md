# io_uring Fixed Buffer 注册失败诊断报告 (memlock 场景)

## 故障概要
- 故障模式：资源限制 (RLIMIT_MEMLOCK)
- 置信度：高
- 分析轨道：双轨（运行证据 + 内核语义）
- 内核版本：由 `returned_features=0x3fff` 确认内核支持全部主流 feature（单轨无 `uname` 时可从日志推断兼容性）
- 目标对象：PID=测试进程 (io_uring_fault_probe)  服务=memlock 场景  时间窗口=测试执行窗口

## 运行证据轨道结论
- 异常阶段：register (io_uring_register_buffers)
- 关键 errno：12 (ENOMEM - Cannot allocate memory)
- 关键日志：
  - `ulimit -l=64`
  - `io_uring_setup: ret=3 errno=0`（setup 成功）
  - `setup_entries=8 setup_flags=0x0 returned_features=0x3fff`
  - `io_uring_register_buffers: ret=-1 errno=12 (Cannot allocate memory)`
  - `registered_buffer_bytes=4194304`
- 资源状态：memlock=64 KB (ulimit -l=64)
- 线程状态：不涉及（未提交 SQE，无 worker 线程参与）
- 运行证据归因假设：fixed buffer 注册 4MB 超过 locked-memory limit 64KB，触发 ENOMEM

## 内核语义轨道结论
- 根因类型：资源限制 (RLIMIT_MEMLOCK)
- 语义解释：io_uring 注册 fixed buffer 时，内核通过 `io_account_mem()` 检查当前进程是否能锁定足够物理内存。该检查受 `RLIMIT_MEMLOCK`（由 `ulimit -l` 控制）约束。测试中 `ulimit -l=64`（64 KB），而注册 buffer 大小为 4,194,304 字节（4 MB），远超限制，因此内核返回 ENOMEM。
- 触发条件：`ulimit -l` 值 < 注册 buffer 总字节数
- 因果链：[ulimit -l=64 KB] → [io_uring_register(IORING_REGISTER_BUFFERS) 调用 io_account_mem] → [RLIMIT_MEMLOCK 校验失败] → [errno=12 (ENOMEM)] → [fixed buffer 注册失败]

## 交叉验证结果
| 验证维度 | 运行证据结论 | 内核语义结论 | 是否吻合？ |
|---------|-------------|-------------|-----------|
| 异常阶段 | register (io_uring_register_buffers) | IORING_REGISTER_BUFFERS opcode 路径 | ✅ 吻合 |
| 关键 errno | errno=12 (ENOMEM) | RLIMIT_MEMLOCK 受限返回 ENOMEM | ✅ 吻合 |
| 资源状态 | ulimit -l=64 (64 KB) | RLIMIT_MEMLOCK 硬限制 | ✅ 吻合 |
| 时间序列 | setup 成功 → register 失败 | 生命周期早期：ring 创建后立即注册 | ✅ 吻合 |
| 修正方向 | 提高 ulimit -l 或减小 buffer | 调整 RLIMIT_MEMLOCK 或 buffer 大小 | ✅ 吻合 |

- 综合判断：两轨完全吻合，无矛盾。

## 完整因果链（双轨收敛后）
[ulimit -l=64 KB 限制 locked memory] → [RLIMIT_MEMLOCK 不足以容纳 4MB fixed buffer 的 pinned pages] → [io_uring_register_buffers 调用 io_account_mem 返回 ENOMEM] → [errno=12 (Cannot allocate memory)] → [应用层 fixed buffer 注册失败]

## 排除的替代假设
- **系统 OOM（全局内存不足）**：排除。`io_uring_setup` 成功，说明系统有足够内存分配 SQ/CQ rings。ENOMEM 仅出现在 register 阶段，是 memlock 检查而非全局内存耗竭。
- **参数错误（EINVAL 类）**：排除。errno=12 为 ENOMEM，不是 EINVAL。setup 的参数 (entries=8, flags=0x0) 合法且成功。
- **feature 兼容性（ENOSYS / EINVAL）**：排除。`returned_features=0x3fff` 表明内核支持全部主流 feature，且 `IORING_REGISTER_BUFFERS` 是基础 opcode，从 5.1 内核就已支持。
- **CQ overflow / 完成路径问题**：排除。本场景未提交任何 SQE，不涉及完成路径。
- **O_DIRECT 对齐问题**：排除。本场景不使用 O_DIRECT 文件操作。
- **worker / SQPOLL 异常**：排除。setup flags=0x0，未启用 SQPOLL，未提交 SQE 故无 worker 参与。

## 风险与影响
- 数据一致性风险：无（诊断阶段只读，未修改系统状态）
- 性能风险：无（仅读取日志文件，未执行侵入式探测）
- 影响范围：所有使用 io_uring fixed buffer 且 locked-memory (`ulimit -l`) 配置不足的应用进程

## 修复建议
### 只读建议（进一步确认）
1. 确认目标进程运行时的 `/proc/<pid>/limits` 中 `Max locked memory` 字段值
2. 确认系统 `/proc/meminfo` 中 `Mlocked`、`MemAvailable` 是否正常
3. 对比实际注册 buffer 总字节数与当前 locked-memory limit
4. 若 memlock 不是限制项（unlimited），则继续检查 cgroup memory.max 和系统内存压力

### 需要审批的操作
1. **提高 locked-memory limit**：在启动进程的 shell 中执行 `ulimit -l <new_limit>`（new_limit 需大于注册 buffer 总字节数，如 `ulimit -l 8192` 表示 8MB），或以 systemd service 方式部署时在 unit 文件中配置 `LimitMEMLOCK=<new_limit>`
2. **永久配置**：编辑 `/etc/security/limits.conf`，添加 `<user> soft memlock <new_limit>` 和 `<user> hard memlock <new_limit>`
3. **降低注册 buffer 大小**：如果实际业务场景可接受更小 buffer，修改应用层代码减小 `io_uring_register` 传入的 iov_len
4. **使用 `mlockall()` 提前锁定**：先通过 `mlockall(MCL_CURRENT | MCL_FUTURE)` 预锁定内存（需确保 RLIMIT_MEMLOCK 充足）

## 验证建议
1. **根因确认**：使用 `ulimit -l 8192`（或足够大值）在同一测试环境复跑 `./run.sh run memlock`，应看到 `io_uring_register_buffers: ret=0 errno=0`
2. **修复验证**：确认进程 `/proc/<pid>/limits` 中 `Max locked memory` 值已更新，且 fixed buffer 注册成功
3. **边界测试**：逐步降低 `ulimit -l`，找到恰好使 register 成功的临界值，验证与注册 buffer 字节数一致（4MB）
