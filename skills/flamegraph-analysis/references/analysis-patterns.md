# Performance Anti-Patterns Feature Library

性能反模式特征库，用于 `pattern_match.py` 分析器做正则/子串匹配。

## 模式分类

### 1. 锁与同步（Lock & Synchronization）

| 模式 | 特征函数/符号 | 权重 |
|------|-------------|------|
| Mutex 锁等待 | `pthread_mutex_lock`, `pthread_mutex_trylock`, `__pthread_mutex_lock` | 1.0 |
| Futex 等待 | `futex_wait`, `__lll_lock_wait`, `futex_wait_setup` | 1.0 |
| 条件变量 | `pthread_cond_wait`, `pthread_cond_timedwait`, `__pthread_cond_wait` | 0.8 |
| 读写锁 | `pthread_rwlock_rdlock`, `pthread_rwlock_wrlock` | 0.7 |
| 自旋锁 | `pthread_spin_lock`, `__spin_lock` | 0.9 |
| Java 同步 | `java.util.concurrent`, `sync.(*Mutex).Lock`, `sync.(*RWMutex).Lock` | 1.0 |
| C# 锁 | `Monitor.Enter`, `Monitor.Wait`, `lock()` | 1.0 |
| Go 通道 | `chanrecv`, `chansend`, `runtime.chansend` | 0.6 |
| .NET 锁 | `System.Threading.Monitor.Enter`, `System.Threading.Monitor.Wait` | 1.0 |

### 2. 垃圾回收（Garbage Collection）

| 模式 | 特征函数/符号 | 权重 |
|------|-------------|------|
| G1 GC | `G1Collect`, `G1Evacuate`, `G1GC`, `_ZN8G1Space4Free` | 1.0 |
| CMS/ParNew | `CMS`, `ParNew`, `GenCollectedHeap::do_collection` | 1.0 |
| 默认可达性 | `可达性`, `reachable`, `MarkSweep::mark` | 0.8 |
| GC 暂停 | `GC_locker`, `GCCause`, `VM_GC_Operation` | 1.0 |
| Go GC | `runtime.gcBgMarkWorker`, `runtime.mallocgc`, `runtime.gcAssistAlloc` | 1.0 |
| V8 GC | `v8::internal::Heap::CollectGarbage`, `MarkCompactCollector` | 1.0 |
| 分配压力 | `newinstance`, `alloc_array`, `ByteBuffer.allocate` | 0.7 |
| 对象分配 | `AllocObject`, `AllocateInOldGen`, `eden_alloc` | 0.6 |

### 3. I/O 与系统调用

| 模式 | 特征函数/符号 | 权重 |
|------|-------------|------|
| 读系统调用 | `read`, `pread`, `readv`, `__GI___libc_read` | 0.8 |
| 写系统调用 | `write`, `pwrite`, `writev`, `__GI___libc_write` | 0.8 |
| 网络读 | `recv`, `recvfrom`, `recvmsg`, `TCP/recv` | 0.9 |
| 网络写 | `send`, `sendto`, `sendmsg`, `TCP/send` | 0.9 |
| epoll 等待 | `epoll_wait`, `epoll_pwait`, `sys_epoll_wait` | 0.7 |
| select/poll | `select`, `poll`, `ppoll`, `do_select` | 0.6 |
| 异步 I/O | `io_submit`, `io_getevents`, `io_setup` | 0.7 |
| 磁盘 I/O | `vfs_read`, `vfs_write`, `blkdev_read`, `generic_file_read` | 0.9 |
| Direct I/O | `dio`, `dio_sync`, `ext4_file_operations` | 0.8 |
| 内存映射 I/O | `mmap`, `munmap`, `memfd` | 0.5 |

### 4. 调度与上下文切换

| 模式 | 特征函数/符号 | 权重 |
|------|-------------|------|
| 调度器 | `schedule`, `scheduler`, `pick_next_task` | 0.6 |
| 上下文切换 | `context_switch`, `switch_to`, `finish_task_switch` | 0.5 |
| 进程创建 | `fork`, `clone`, `do_fork`, `runtime.newproc` | 0.4 |
| 线程创建 | `pthread_create`, `CreateThread`, `java.lang.Thread.start` | 0.4 |

### 5. 反射与动态代码

| 模式 | 特征函数/符号 | 权重 |
|------|-------------|------|
| Java 反射 | `java.lang.reflect.Method.invoke`, `ReflectAccessor`, `NativeMethodAccessor` | 1.0 |
| 动态代理 | `Proxy.invoke`, `$Proxy`, `InvocationHandler.invoke` | 0.9 |
| Go 反射 | `reflect.Value.Call`, `reflect.TypeOf`, `runtime.reflect` | 0.8 |
| C# 反射 | `Type.GetType`, `Activator.CreateInstance`, `MethodInfo.Invoke` | 0.9 |
| JIT 编译 | `JIT_`, `CompileMethod`, `TieredCompilation` | 0.7 |

### 6. 序列化与反序列化

| 模式 | 特征函数/符号 | 权重 |
|------|-------------|------|
| JSON | `json.Unmarshal`, `json.Marshal`, `Jackson`, `Gson` | 0.8 |
| Protobuf | `protobuf.Unmarshal`, `ParseFrom`, `MarshalTo` | 0.8 |
| XML | `xml.Unmarshal`, `SAXParser`, `DOM` | 0.7 |
| Java 序列化 | `ObjectInputStream`, `ObjectOutputStream`, `readObject` | 0.9 |
| 压缩 | `deflate`, `inflate`, `compress`, `gzip` | 0.6 |

### 7. 加密与安全

| 模式 | 特征函数/符号 | 权重 |
|------|-------------|------|
| 对称加密 | `AES_`, `DES_`, `Cipher`, `EncryptBlock` | 0.9 |
| 非对称加密 | `RSA_`, `DSA_`, `ECDH`, `signer.sign` | 1.0 |
| 哈希 | `SHA1`, `SHA256`, `MD5`, `Hmac` | 0.7 |
| SSL/TLS | `SSL_read`, `SSL_write`, `SSL_do_handshake`, `crypto/tls` | 1.0 |

### 8. 内存管理

| 模式 | 特征函数/符号 | 权重 |
|------|-------------|------|
| 堆分配 | `malloc`, `free`, `realloc`, `jemalloc` | 0.5 |
| 对象分配 | `new`, `delete`, `alloc`, `heap_alloc` | 0.5 |
| 内存映射 | `mmap`, `madvise`, `brk` | 0.4 |
| 页错误 | `do_page_fault`, `handle_mm_fault`, `filemap_fault` | 0.6 |

### 9. 数据库相关

| 模式 | 特征函数/符号 | 权重 |
|------|-------------|------|
| SQL 执行 | `execQuery`, `Statement.execute`, `SQLException` | 0.8 |
| 事务 | `beginTransaction`, `commit`, `rollback` | 0.7 |
| 连接池 | `getConnection`, `DataSource.getConnection`, `HikariCP` | 0.6 |
| 缓存未命中 | `cache_miss`, `LookupAccountSid`, `DiskCache` | 0.8 |

### 10. HTTP 与网络

| 模式 | 特征函数/符号 | 权重 |
|------|-------------|------|
| HTTP 服务器 | `HttpServer`, `Netty`, `Undertow`, `http.Handler` | 0.5 |
| HTTP 客户端 | `HttpClient`, `okhttp`, `requests.get`, `curl` | 0.5 |
| 连接建立 | `connect`, `TCPConnect`, `socket()` | 0.6 |
| DNS 查询 | `getaddrinfo`, `lookupHost`, `DNS.lookup` | 0.7 |

## 使用方式

```python
# pattern_match.py 内部逻辑
import re

PATTERNS = {
    "lock": {
        "pthread_mutex_lock": 1.0,
        "futex_wait": 1.0,
        ...
    },
    "gc": {...},
    ...
}

def match_patterns(folded_content: str, min_weight: float = 0.5) -> dict:
    findings = []
    for category, patterns in PATTERNS.items():
        for pattern, weight in patterns.items():
            if weight >= min_weight and re.search(pattern, folded_content):
                # 收集匹配的栈和计数
                ...
    return findings
```

## 阈值建议

- 权重 >= 0.8：直接报告为疑似根因
- 权重 0.5-0.7：作为辅助线索
- 权重 < 0.5：仅在确认为主要耗时路径时报告
