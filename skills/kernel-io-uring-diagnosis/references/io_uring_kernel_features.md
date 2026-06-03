# io_uring 内核 Feature 参考

io_uring 能力与内核版本、发行版 backport 和运行时 probe 强相关。本文件只作为分诊辅助，
不能替代运行证据。

## 版本与运行时检查

始终采集：

```bash
uname -r
uname -m
cat /etc/os-release
grep -R "IORING_FEAT_" /usr/include/linux/io_uring.h 2>/dev/null
```

优先使用运行时证据：

- `io_uring_setup` 返回值和可用时的 `features` 字段。
- `io_uring_register` opcode 和 errno。
- 应用 feature probe 输出。
- setup/register 失败附近的 strace 记录。

## 常见兼容性信号

| 信号 | 含义 | 下一步检查 |
| --- | --- | --- |
| `io_uring_setup` 返回 `ENOSYS` | syscall 不可用 | 确认内核配置和版本 |
| setup 返回 `EINVAL` | entries、flags 或 flag 组合非法/不支持 | 解码 setup flags 和 entries |
| register 返回 `EINVAL` | register opcode 不支持或参数非法 | 确认 opcode 和参数大小 |
| 应用使用新 header 编译 | 编译期符号可能超出运行内核能力 | 在目标主机运行 feature probe |
| 新发行版成功、旧 openEuler 内核失败 | feature 或 backport 差异 | 对比运行内核和应用依赖 feature |

## 需要识别的 feature 类型

- Setup flags：`IORING_SETUP_SQPOLL`、`IORING_SETUP_IOPOLL`、
  `IORING_SETUP_CLAMP`、`IORING_SETUP_ATTACH_WQ`、`IORING_SETUP_COOP_TASKRUN`、
  `IORING_SETUP_SINGLE_ISSUER`。
- Register 操作：buffers、files、eventfd、restrictions、personality、ring fd、
  provided buffers。
- Operation codes：read/write、timeout、poll、fsync、accept/connect、send/recv、
  splice、openat/statx、cancel、cmd passthrough。
- Setup 返回 feature bits：single mmap、nodrop、submit stable、rw cur pos、fast poll、
  poll 32bits、sqpoll nonfixed、ext arg、native workers、rsrc tags。

## 诊断规则

- 不要因为 header 定义了某个 feature 就判定运行内核支持。
- 不要在未检查参数和资源限制前，把 `EINVAL` 直接归因到兼容性。
- 只有泛化 `EINVAL` 证据时，先分类为“兼容性或参数错误”，等待 setup/register 参数补齐。
- 社区 PR 报告中应写精确内核版本和已采集的运行证据，不写“旧内核不支持”这类泛化结论。
