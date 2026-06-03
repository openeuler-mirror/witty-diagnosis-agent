# I/O Wait - I/O 等待分析剧本

## 触发条件

用户问题包含以下关键词：
- "I/O 等待"
- "磁盘延迟"
- "网络延迟"
- "读写慢"
- "阻塞"
- "syscall"
- "epoll"

## 分析流程

### Step 1: 数据准备

1. 确认输入为 Off-CPU 采样
2. 转换为折叠栈格式

### Step 2: Off-CPU 分类

```bash
python scripts/analyzers/offcpu_classifier.py --input folded.folded --json
```

重点关注：
- 磁盘 I/O 占比
- 网络 I/O 占比

### Step 3: I/O 模式检测

```bash
python scripts/analyzers/pattern_match.py --input folded.folded --json
```

重点匹配：
- `read` / `write` / `pread` / `pwrite`
- `recv` / `send`
- `epoll_wait` / `select` / `poll`
- `vfs_read` / `vfs_write`
- `sk_wait_data` / `tcp_recvmsg`

### Step 4: I/O 热点栈

从折叠栈中筛选包含 I/O 操作的栈，识别：
- I/O 延迟最高的路径
- 同步 I/O vs 异步 I/O
- I/O 合并情况

## 输出结构

```
## I/O 等待分析

### I/O 类型分布
- 磁盘 I/O: XX%
- 网络 I/O: XX%
- 其他 I/O: XX%

### I/O 热点
| I/O 类型 | 帧 | 等待次数 | 占比 |
|----------|-----|----------|------|
| disk_read | read_file | 1234 | 45% |
| net_recv | handle_request | 567 | 20% |

### I/O 调用栈
[执行 I/O 操作的代码路径]

### 同步 vs 异步
[同步 I/O 和异步 I/O 的分布]
```

## I/O 类型识别

| I/O 类型 | 特征帧 | 优化建议 |
|----------|--------|----------|
| 磁盘顺序读 | `vfs_read`, `ext4_file_read` | 预读优化 |
| 磁盘随机读 | `filemap_fault` | 缓存优化 |
| 网络接收 | `tcp_recvmsg`, `sk_wait_data` | 批量处理 |
| 网络发送 | `tcp_sendmsg` | Nagle 算法调整 |
| epoll 等待 | `epoll_wait` | 事件密度优化 |

## 优化建议

### 磁盘 I/O

1. **顺序读优化**：
   - 增大预读缓冲区
   - 合并小读取

2. **随机读优化**：
   - 增加缓存
   - 使用 SSD

3. **同步 I/O 优化**：
   - 改为异步 I/O
   - 使用 DMA

### 网络 I/O

1. **减少网络往返**：
   - 批量操作
   - 管道化

2. **减少等待**：
   - 使用非阻塞 I/O
   - 多路复用

3. **协议优化**：
   - 调整缓冲区大小
   - 启用 TCP_NODELAY

### 系统调用

1. **减少 syscall**：
   - 批量操作
   - 用户态缓冲

2. **选择合适接口**：
   - sendfile vs read+write
   - io_uring
