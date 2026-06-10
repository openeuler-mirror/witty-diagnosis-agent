# 线上不可重启进程边界

线上 PID 默认只读。允许执行：

- `live_process_snapshot.py --pid <PID>` 读取 `/proc/<pid>/status`、`smaps_rollup`、`maps`、`cgroup`、子进程、线程数和 fd 数。
- `monitor_rss.py --pid <PID>` 外部 RSS/VMS/Private_Dirty/cgroup/children 采样。
- `correlate_evidence.py` 对既有 snapshot、monitor、heap、tracemalloc、semantic 和 retention JSON 做只读对账。
- 读取用户已提供的 tracemalloc 快照、memray capture、日志、监控曲线。
- 分析 `/proc/<pid>/status`、`smaps_rollup`、`maps`、cgroup memory 文件。

默认不允许执行：

- ptrace/attach 或进程注入类线上观察。
- 安装 pip 包或系统包。
- 清缓存、置空全局、注销回调、重启服务。
- 对生产进程运行 `reachability_probe.py --allow-mutation`。

若确需线上注入，报告或执行计划必须写清影响：可能暂停进程、改变时序、暴露敏感对象、需要 root/ptrace 权限，并等待用户批准。

## 结论边界

- Live PID 只读证据只能确认目标范围、增长形态和可疑内存表面，不能确认 Python 对象根因。
- 只读 PID 场景没有 `object_growth.json`、`tracemalloc.json`、`semantic.json`、`retention.json` 时，最终结论必须封顶为 scope/trend/direction。
- 父进程稳定但 child/cgroup 增长时，应先切换到增长 worker 或扩大到 cgroup 口径，不得只看 master PID 下结论。
- RssFile/RssShmem 净增长或 file/shmem mapping 主导时，应优先输出 mmap/file/shmem 方向，除非 Python heap/retention 对账能解释主要 Private_Dirty 增长。最终报告先引用 `correlation.json.summary.memory_surface`，再讨论 Python heap 或 native allocator。
- 报告前读取 `correlation.json`；若缺失，先运行 `correlate_evidence.py`，缺少某类证据时让它进入 `missing_evidence[]`，不要绕过总闸门。
