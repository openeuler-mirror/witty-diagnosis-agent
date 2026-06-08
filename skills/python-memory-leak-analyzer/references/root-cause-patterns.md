# 根因模式卡片

本文件只做模式映射。证据冲突、竞争假设和置信度判定按 `evidence-analysis.md` 与 `validation-gates.md`。

## 全局容器无界增长

- 触发信号：`global_container_growth`、`module_global:<name>`、`big_containers_after` 中 dict/list/set 长度持续上升。
- 必要证据：容器规模增长能解释主要对象增长；retention 指向 module global。
- 常见误判：小 global 很显眼但 coverage 低，只能写次要问题。
- 修复方向：设置容量上限、TTL、淘汰策略，或在请求/任务结束时清理。
- 置信度边界：未做 G3/G4 时最多 strong。

## 无界 cache 或方法 cache 保留 self

- 触发信号：`unbounded_cache_growth`、`cache_info.currsize` 增长、`maxsize=None`。
- 必要证据：cache size 增长解释 retained 对象；实例方法 cache 需说明 key 或 wrapper 间接保留 `self`。
- 常见误判：只写“cache 增长”，但没有解释为什么对象不能释放。
- 修复方向：设置 `maxsize`、按生命周期 `cache_clear()`、避免实例方法直接承载长期无界 cache。
- 置信度边界：只有 cache_info 无保留链时写主导假设，不写 confirmed。

## 回调或监听器未注销

- 触发信号：`global_registry_retains_bound_methods`，全局 registry/list 保存 bound method。
- 必要证据：registry 长度增长，bound method 的 `__self__` 指向业务实例或 payload。
- 常见误判：把实例初始化或 payload 分配点当根因。
- 修复方向：生命周期结束时 unregister，使用 weakref listener，避免全局强引用。
- 置信度边界：若 G1 显示 registry 不是主增长源，写次要泄漏。

## 闭包捕获大对象

- 触发信号：`global_table_retains_closures`，closure cell 中有 payload、dict、list 或请求上下文。
- 必要证据：全局 task/table 保留 function，function closure 保留大对象。
- 常见误判：只定位 payload 分配点，不说明 closure cell 保留路径。
- 修复方向：闭包只捕获 ID 或轻量字段，任务完成后删除表项。
- 置信度边界：无 retention 时最多 weak/strong，视 semantic 与 G1 对账而定。

## 线程局部状态累积

- 触发信号：长期 worker、`threading.local`、每 worker local 容器增长。
- 必要证据：线程生命周期长于请求，local 中请求态或 payload 数量增长。
- 常见误判：把线程池本身当根因，忽略无界 local 数据。
- 修复方向：任务结束清理 local，避免在线程常驻对象中保存请求级大对象。
- 置信度边界：线上不杀线程、不清理 local 时通常为 strong 或 weak。

## generator/coroutine frame 未释放

- 触发信号：`unclosed_generators_retain_frames`、`pending_asyncio_tasks_retain_frames`、`frame_or_generator`。
- 必要证据：OPEN_GENERATORS/PENDING_TASKS 增长，frame locals 中有 payload。
- 常见误判：只看到 generator/task 数量增长，未说明 frame locals。
- 修复方向：显式 close/await/cancel，修复异常路径和 finally 清理。
- 置信度边界：未执行 close/cancel 反事实时不写 confirmed。

## 引用循环与 finalizer

- 触发信号：`gc.garbage` 增长、cycle root_kind、finalizer 或 `__del__`。
- 必要证据：cycle/finalizer 对象增长大于干扰项，G2 排除普通全局容器。
- 常见误判：把小的 debug/global 容器当主因。
- 修复方向：拆环、使用 weakref/context manager，避免 finalizer 环。
- 置信度边界：依赖 gc debug flag 的场景要说明运行条件。

## weakref.finalize 回调误用

- 触发信号：`weakref_finalize_callbacks_retained`，finalizer 列表增长。
- 必要证据：finalizer callback 是 bound method 或闭包，反向持有目标对象。
- 常见误判：看到 weakref 就认为不会强引用。
- 修复方向：finalizer callback 使用静态函数和轻量参数，不传 bound method。
- 置信度边界：没有回调对象细节时只写可能模式。

## native、allocator 或 mmap/file/shmem

- 触发信号：`native_or_allocator_suspect`、`mmap_or_file_backed_growth`、`allocator_reuse_or_fragmentation_possible`。
- 必要证据：Python heap/tracked object ratio 低，或 RssFile/RssShmem/mapping/cgroup 指向非 Python heap。
- 常见误判：仅凭 RSS 增长确认 Python 对象泄漏。
- 修复方向：补 native allocation stack、allocator stats、mmap/shmem owner 或 C 扩展释放路径证据；采集方式需单独授权。
- 置信度边界：无 native allocator 栈时只能 direction-only。
