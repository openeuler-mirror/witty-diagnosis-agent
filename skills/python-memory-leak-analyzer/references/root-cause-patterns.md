# 常见 Python 内存泄漏模式

| 模式 | 典型保留者 | 证据 | 修复方向 |
| --- | --- | --- | --- |
| 全局容器无界增长 | module global dict/list/set | `root_kind=module_global:<name>`，容器 len 持续增长，或 `semantic_probe` 标记 `global_container_growth` | 设置上限、淘汰策略、按请求结束清理 |
| `lru_cache` 无 `maxsize` | wrapper cache | `cache_info().currsize` 持续增长，或 `semantic_probe` 标记 `unbounded_cache_growth` | 设置 `maxsize` 或定期 `cache_clear()` |
| 回调/监听器未注销 | registry/list | 对象被全局 registry 持有，或 `semantic_probe` 标记 `global_registry_retains_bound_methods` | 生命周期结束时 unregister |
| 闭包捕获大对象 | closure cell | `semantic_probe` 标记 `global_table_retains_closures`，closure cell 中出现 payload | 避免闭包持有请求级大对象 |
| 线程局部状态 | `threading.local` 或线程帧 | 线程长期存活，局部值不释放 | 在线程任务结束清理 |
| generator/coroutine 未关闭 | frame/generator | `root_kind=frame_or_generator`，或 `semantic_probe` 标记 `unclosed_generators_retain_frames` / `pending_asyncio_tasks_retain_frames` | 显式 close/await，修复异常路径 |
| 引用循环带 finalizer | cycle + `__del__` | `gc.garbage` 或多条 referrer | 使用 weakref/context manager，避免 finalizer 环 |
| native/C 扩展泄漏 | Python 堆无明显增长 | RSS 与 tracemalloc 背离 | memray/gdb/debug symbols，升级或修复扩展 |
