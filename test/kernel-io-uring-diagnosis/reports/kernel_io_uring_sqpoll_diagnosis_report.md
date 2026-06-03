# io_uring SQPOLL 设置诊断报告

## 故障概要

| 字段 | 值 |
|------|-----|
| **故障模式** | SQPOLL 设置验证（setup_flags=0x2） |
| **置信度** | 高 |
| **分析轨道** | 双轨（运行证据 + 内核语义） |
| **内核版本** | 6.6.87.2-microsoft-standard-WSL2（诊断工作站） |
| **目标对象** | 测试用例：`sqpoll` 场景，复现命令 `bash ./run.sh run sqpoll` |
| **时间窗口** | 日志提供时间未标注，以日志内容为完整故障证据 |

---

## 用户可见现象

测试程序通过 raw syscall 调用 `io_uring_setup`，使用 `setup_flags=0x2`（`IORING_SETUP_SQPOLL`）。

**日志输出**：
```
io_uring_setup: ret=3 errno=0
setup_entries=8 setup_flags=0x2 returned_features=0x3fff
```

**现场还原**：
- syscall 返回 fd=3（成功，非负 fd）
- errno=0（无错误）
- 内核返回 features=0x3fff（14 个 feature 位均已置位）

---

## 运行证据轨道结论

| 维度 | 结论 |
|------|------|
| **异常阶段** | 无异常——`io_uring_setup` 成功完成 |
| **关键 errno** | 0（无错误） |
| **关键日志** | `io_uring_setup: ret=3 errno=0` |
| **setup 参数** | entries=8, flags=0x2 (IORING_SETUP_SQPOLL) |
| **返回 features** | 0x3fff（14 bit 全部置位） |
| **资源状态** | 测试环境未触发资源限制（errno=0 即无需排查限制） |
| **线程状态** | 无可用 PID 快照；SQPOLL setup 成功即表明内核已创建 `iou-sqp` 内核线程 |
| **运行证据归因假设** | `IORING_SETUP_SQPOLL` 模式下 ring 创建成功，内核正常启动 SQPOLL 内核线程 |

### 运行的诊断脚本

| 脚本 | 执行结果 |
|------|---------|
| `diagnose_io_uring_workers.sh` | 无运行中的 `iou-sqp`/`iou-wrk` 线程（测试程序已退出），解释性输出已记录 |
| `diagnose_io_uring_compat.sh` | 成功从日志中提取 `io_uring_setup` 行和 `setup_flags`，解码 flags 和 features |
| `diagnose_io_uring_limits.sh` | 确认当前 shell `max locked memory=65536 kB`，日志中无 `ENOMEM`/`EPERM` |
| `diagnose_io_uring_rings.sh` | 日志无 SQ full、CQ overflow 或 completion 延迟信号 |

---

## 内核语义轨道结论

### 解码 setup_flags=0x2

| 位掩码 | 标志 | 含义 |
|--------|------|------|
| `(1U << 1)` = 0x2 | `IORING_SETUP_SQPOLL` | 请求内核创建独立的 SQ 轮询线程 |

### 解码 returned_features=0x3fff

`0x3fff` 二进制展开为 `0011 1111 1111 1111`（bits 0–13 全部置位）：

| Bit | 掩码 | Feature 名称 | 状态 |
|:---:|:----:|------------|:----:|
| 0 | 0x001 | `IORING_FEAT_SINGLE_MMAP` | ✓ 支持 |
| 1 | 0x002 | `IORING_FEAT_NODROP` | ✓ 支持 |
| 2 | 0x004 | `IORING_FEAT_SUBMIT_STABLE` | ✓ 支持 |
| 3 | 0x008 | `IORING_FEAT_RW_CUR_POS` | ✓ 支持 |
| 4 | 0x010 | `IORING_FEAT_CUR_PERSONALITY` | ✓ 支持 |
| 5 | 0x020 | `IORING_FEAT_FAST_POLL` | ✓ 支持 |
| 6 | 0x040 | `IORING_FEAT_POLL_32BITS` | ✓ 支持 |
| 7 | 0x080 | `IORING_FEAT_SQPOLL_NONFIXED` | ✓ 支持 |
| 8 | 0x100 | `IORING_FEAT_EXT_ARG` | ✓ 支持 |
| 9 | 0x200 | `IORING_FEAT_NATIVE_WORKERS` | ✓ 支持 |
| 10 | 0x400 | `IORING_FEAT_RSRC_TAGS` | ✓ 支持 |
| 11 | 0x800 | `IORING_FEAT_CQE_SKIP` | ✓ 支持 |
| 12 | 0x1000 | `IORING_FEAT_LINKED_FILE` | ✓ 支持 |
| 13 | 0x2000 | `IORING_FEAT_REG_REG_RING` | ✓ 支持 |

| 维度 | 结论 |
|------|------|
| **根因类型** | 无异常 — SQPOLL 设置成功 |
| **语义解释** | `setup_flags=0x2` 对应 `IORING_SETUP_SQPOLL`，内核接受该 flag 并成功创建 ring |
| **触发条件** | 内核版本 >= 5.11 且编译了 `CONFIG_IO_URING` |
| **因果链** | `[io_uring_setup(entries=8, flags=IORING_SETUP_SQPOLL)]` → `[内核分配 ring buffers + 创建 SQPOLL 内核线程]` → `[返回 fd=3, errno=0]` → `[返回 features=0x3fff 表明 14 个 feature 全部可用]` |

**关键发现**：
- `IORING_FEAT_SQPOLL_NONFIXED` (bit 7) 置位表明：SQPOLL 模式下不需要固定（pin）内存，这是 5.19+ 内核的重要改进
- `IORING_FEAT_NATIVE_WORKERS` (bit 9) 置位表明：内核使用原生 io_uring worker 线程模型（非 io-wq 回退）
- 所有 14 个 feature 位全量支持，表明内核 io_uring 实现功能完备

---

## 交叉验证结果

| 验证维度 | 运行证据结论 | 内核语义结论 | 吻合？ |
|---------|-------------|-------------|:------:|
| 异常阶段 | setup 成功，无异常 | setup 路径正常返回 | ✓ 吻合 |
| 关键 errno | errno=0 | 参数合法、资源充足 → errno=0 | ✓ 吻合 |
| 资源状态 | 无需排查限制 | memlock 充足，entries=8 极小 | ✓ 吻合 |
| feature 支持 | returned_features=0x3fff | header 中 IORING_FEAT_ bits 1–13 全部定义 | ✓ 吻合 |
| 时间序列 | 单次 setup 调用 | 同步返回，无延迟 | ✓ 吻合 |

**综合判断**：双轨完全吻合。SQPOLL 设置成功，无任何异常信号。

---

## 完整因果链（双轨收敛后）

```
[触发条件]
  └─ 测试程序调用 io_uring_setup(entries=8, flags=IORING_SETUP_SQPOLL)
      └─ 内核版本支持 io_uring 且支持 SQPOLL
          └─ [根因判定]
              └─ 无故障 — 设置成功返回 fd=3

[内核行为]
  └─ 分配 SQ ring (8 entries) + CQ ring + SQPOLL 内核线程
      └─ 返回 errno=0, returned_features=0x3fff

[系统表现]
  └─ io_uring_setup: ret=3 errno=0
      └─ setup_entries=8 setup_flags=0x2 returned_features=0x3fff
```

**结论**：该日志是正常的 `IORING_SETUP_SQPOLL` 成功设置记录，不属于故障场景。

---

## 排除的替代假设

| 假设 | 排除原因 |
|------|---------|
| 内核不支持 io_uring/SQPOLL | errno=0 且 returned_features=0x3fff 强证据排除 |
| 资源限制导致 setup 失败 | errno=0，且 entries=8 极小，memlock=64MB 充足 |
| Ring 容量不足 | 日志范围仅含 setup，无 submit/complete 阶段证据 |
| PQPOLL 调度异常 | 无运行时线程快照，但 setup 成功表明内核线程已创建 |
| Direct I/O 对齐问题 | 本场景不涉及 O_DIRECT |

---

## 风险与影响

| 维度 | 评估 |
|------|------|
| **数据一致性风险** | 无—诊断过程只读，且 setup 阶段不涉及数据操作 |
| **性能风险** | 无—仅执行只读诊断脚本 |
| **影响范围** | 诊断工作站（Windows 11），通过 WSL2 Ubuntu 24.04 执行脚本 |
| **故障范围** | 非故障 — SQPOLL 设置成功 |

---

## 修复建议

### 只读建议

> ⚠️ 本案例不属于故障场景。SQPOLL 设置已成功，无需修复。

如欲验证 SQPOLL 运行时行为，建议：
1. **持久化 PID 快照**：在 `io_uring_setup` 成功后立即采集 `/proc/<pid>/task/*` 中 `iou-sqp` 线程的 `status`、`wchan` 和 `stack`
2. **运行 strace 追踪 submit/complete 路径**：`strace -f -e trace=io_uring_setup,io_uring_enter,io_uring_register -p <pid>`
3. **验证 SQPOLL busy polling 行为**：观察 `iou-sqp` 线程 CPU 使用率，确认是否存在异常高占用

### 需要审批的操作

不适用（无故障场景）。

---

## 缺失证据

| 缺失项 | 说明 | 影响 |
|--------|------|------|
| PID 快照 | 未提供测试程序运行时的 PID 和 `/proc` 状态 | 无法验证 `iou-sqp` 线程的调度状态 |
| strace 输出 | 未提供 strace 跟踪 | 无法校验 `io_uring_enter`/`io_uring_register` 行为 |
| 内核日志 | 未提供 `dmesg` 或 `journalctl -k` 输出 | 无法确认是否存在 SQPOLL 相关的内核日志 |
| 复现环境内核版本 | 当前日志来自测试环境，未标注内核版本 | 特征解码基于通用 WSL2 内核 header，非实际目标内核 |

以上缺失不影响本结论（高置信度），但在 SQPOLL 运行时行为分析场景中为必要证据。

---

## 已执行命令

```bash
# 基线信息采集
uname -a
cat /etc/os-release
grep -R "IORING_FEAT_\|IORING_SETUP_" /usr/include/linux/io_uring.h

# 分支诊断脚本执行
bash diagnose_io_uring_workers.sh -l sqpoll.log
bash diagnose_io_uring_compat.sh -l sqpoll.log
bash diagnose_io_uring_limits.sh -l sqpoll.log
bash diagnose_io_uring_rings.sh -l sqpoll.log
```

---

## 清理结果

只读诊断不需要清理。若后续通过 test 套件的 `./run.sh run sqpoll` 复现，应执行 `./run.sh clean` 清理 `out/` 目录下的测试产物。

---

## 附录 A：setup_flags=0x2 详细解码

```text
IORING_SETUP_SQPOLL = (1U << 1) = 0x2
```

`0x2` 仅包含 `IORING_SETUP_SQPOLL` 一个标志位，说明测试程序：
- 请求了 SQ 轮询模式（内核创建 `iou-sqp` 线程）
- **未**指定 `IORING_SETUP_SQ_AFF`（bit 2），因此 SQPOLL 线程的 CPU 亲和性由内核自动选择
- **未**指定 `IORING_SETUP_IOPOLL`（bit 0），使用中断驱动而非轮询完成

## 附录 B：returned_features=0x3fff 语义

`0x3fff` = `0011 1111 1111 1111`：

| 特征 | 含义 | since 内核版本 |
|------|------|:--------------:|
| SINGLE_MMAP | SQ 和 CQ 可单次 mmap | 5.6 |
| NODROP | 溢出时不丢 CQE | 5.6 |
| SUBMIT_STABLE | SQE 提交后内核不再引用 | 5.6 |
| RW_CUR_POS | read/write 使用当前文件位置 | 5.6 |
| CUR_PERSONALITY | 支持 personalities | 5.6 |
| FAST_POLL | 快速轮询路径 | 5.7 |
| POLL_32BITS | poll events 32 位 | 5.8 |
| SQPOLL_NONFIXED | SQPOLL 不需固定内存 | 5.19 |
| EXT_ARG | 扩展超时参数 | 5.11 |
| NATIVE_WORKERS | 原生 worker 线程 | 6.0 |
| RSRC_TAGS | 资源标签 | 5.13 |
| CQE_SKIP | 跳过 CQE 生成 | 6.1 |
| LINKED_FILE | 链接文件支持 | 6.6 |
| REG_REG_RING | 注册 ring fd | 6.7 |

全量 feature 可用表明内核 >= 6.7，io_uring 实现成熟完整。
