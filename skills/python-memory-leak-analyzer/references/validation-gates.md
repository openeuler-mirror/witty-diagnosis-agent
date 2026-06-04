# 验证门

## G0 目标范围和口径确认

真实 PID 或线上只读场景必须先确认：

- PID、PPID、cmdline、exe、cwd 是否匹配用户目标。
- 是否存在 pre-fork master/worker、子进程或 sibling 进程增长。
- cgroup memory 读取是否基于目标 PID 的 `/proc/<pid>/cgroup`，而不是诊断进程自己的 cgroup。
- RssAnon、RssFile、RssShmem、Private_Dirty 和 mapping 组成是否支持当前口径。
- `live_process_snapshot.py` 与 `monitor_rss.py` 是否指向同一个 PID/worker/cgroup。

G0 不通过时，只能输出范围定界、scope mismatch 或下一步采集建议，不能确认 Python heap 根因。

## G1 量化对账

主候选应解释主要对象增长或分配增长。报告前必须读取 `correlation.json`：

- `python_heap_to_private_dirty_ratio` 或 `tracked_object_to_private_dirty_ratio` 足够高，并且有 semantic/retention 证据，才能写 Python retained leak likely。
- ratio 很低但 Private_Dirty/RSS 增长明显时，输出 native/allocator 方向疑似。
- candidate coverage 很低时，报告必须写“候选不足以解释 RSS 增长”，并回到对象/分配扫描。

## G2 竞争假设

至少排除：

- 缓存预热后 plateau。
- pymalloc/glibc arena 不归还 OS。
- native/C 扩展、mmap/file/shmem 或已有外部 profiler 指向的非 Python 堆增长。
- 采样窗口太短。
- workload 与真实故障不一致。
- 看错 PID、worker、sibling 进程或 cgroup 口径。

## G3 可达性反事实

沙箱中可清空全局容器、cache 或 registry，然后 `gc.collect()` 并比较对象计数或 weakref 存活。生产环境不执行副作用，只做静态保留链论证，置信度封顶。

## G4 隔离复测

禁用候选逻辑、设置缓存上限或修复注销逻辑后复跑相同 workload。增长停止才能作为高置信度确认。

## G5 置信度

- 高：G1/G2/G3 或 G4 均通过，证据链自洽。
- 中：G0/G1/G2 通过，但 G3/G4 只能静态论证。
- 低：只有 RSS 或单条分配线，缺保留证据。
- 方向级：`correlation.json` 输出 native/mmap/readonly verdict，但没有 native allocator 栈或 Python retention 证据。
