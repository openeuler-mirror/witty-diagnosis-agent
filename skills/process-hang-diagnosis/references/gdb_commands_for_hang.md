# GDB 进程挂起诊断命令速查

> 配合 SKILL.md "进程内省轨道"使用。所有命令默认 `--batch -nx` 模式。

---

## 一、安全须知

```bash
# 权限检查
cat /proc/sys/kernel/yama/ptrace_scope
# 0 = 所有进程可 ptrace
# 1 = 只能 ptrace 子进程（默认）
# 2 = 仅 root 可用
# 3 = 不允许（需重启禁用以修改）

# PID 存在性检查（attach 前必做）
kill -0 <pid> 2>/dev/null || echo "PID does not exist"
```

> **生产环境警告**：`gdb -p <pid>` 会通过 ptrace 暂停进程。对延时敏感的服务，
> 应先在预发/灰度环境验证。如果 ptrace_scope=1，需要以与目标进程相同用户运行。

---

## 二、核心采集命令（单次执行, 每次一项）

### 2.1 全线程调用栈（最重要的命令）

```bash
# 完整版：bt full（带局部变量和参数）
gdb --batch -nx \
  -ex "thread apply all bt full" \
  -p <pid> 2>&1

# 轻量版：bt 不带局部变量（更快，适合生产快速采集）
gdb --batch -nx \
  -ex "thread apply all bt" \
  -p <pid> 2>&1

# 限定栈深度（栈特别深时控制输出量）
gdb --batch -nx \
  -ex "set backtrace limit 30" \
  -ex "thread apply all bt" \
  -p <pid> 2>&1
```

### 2.2 线程信息

```bash
# 线程列表
gdb --batch -nx \
  -ex "info threads" \
  -p <pid> 2>&1

# 指定线程 bt（线程号从 info threads 输出获取）
gdb --batch -nx \
  -ex "thread 3" \
  -ex "bt full" \
  -p <pid> 2>&1
```

### 2.3 帧信息

```bash
# 当前帧的详细信息（源码+参数+局部变量）
gdb --batch -nx \
  -ex "bt full" \
  -ex "frame" \
  -ex "info args" \
  -ex "info locals" \
  -p <pid> 2>&1
```

### 2.4 信号分析

```bash
# 进程信号处理配置（GDB 视角）
gdb --batch -nx \
  -ex "info signals" \
  -ex "info handle" \
  -p <pid> 2>&1

# 等价于 /proc/<pid>/status 中的 SigBlk/SigCgt/SigIgn
cat /proc/<pid>/status | grep -E "^Sig"
```

### 2.5 锁信息

```bash
# 打印互斥锁状态（需要知道锁变量地址/符号名）
# 假设锁变量是全局变量 my_lock
gdb --batch -nx \
  -ex "print my_lock" \
  -ex "print &my_lock" \
  -p <pid> 2>&1

# 条件变量等待者查询
gdb --batch -nx \
  -ex "print my_cond" \
  -p <pid> 2>&1
```

### 2.6 共享库与符号

```bash
# 共享库列表
gdb --batch -nx \
  -ex "info sharedlibrary" \
  -p <pid> 2>&1

# 确认调试符号是否加载
gdb --batch -nx \
  -ex "info functions my_function" \
  -p <pid> 2>&1
```

---

## 三、采样模式（确认是否在死循环/重复执行同路径）

```bash
# 方法1：gdb 连续采样（推荐，portable）
for i in {1..5}; do
  echo "=== Sample $i ==="
  gdb --batch -nx -ex "bt" -p <pid> 2>&1
  sleep 0.5
done

# 方法2：perf 采样（如果有权限，更轻量）
perf top -p <pid> -s symbol -d 1 -n 20 2>/dev/null
```

**采样结果解读：**
- 5 次采样 bt 完全一致 → 进程卡在某调用点不动
- 5 次采样 bt 有微小变化（如不同 malloc 内部）→ 进程在运行但可能效率低
- 5 次采样 bt 完全不同 → 进程正常运行，非 hang

---

## 四、ABBA 死锁识别

### 4.1 死锁判别流程

1. 采集每个线程的 `bt full`（含局部变量中的锁地址）
2. 对每把锁，从 bt 帧中提取：
   - 锁变量地址（`pthread_mutex_t*` 值）
   - 线程状态：持有锁 / 等待锁
3. 构建等待图：
   ```
   Thread A ──持有──> Lock L1
   Thread A ──等待──> Lock L2
   Thread B ──持有──> Lock L2
   Thread B ──等待──> Lock L1
   ──> ABBA 死锁确认
   ```

### 4.2 典型死锁 bt 帧模式

**线程 A（持有 L1, 等待 L2）：**
```
#0  __lll_lock_wait ()
#1  __pthread_mutex_lock (mutex=0x7f...1234)  ← L2 地址
#2  func_B()  ← 期望获取 L2 后才释放 L1
#3  ...
```

**线程 B（持有 L2, 等待 L1）：**
```
#0  __lll_lock_wait ()
#1  __pthread_mutex_lock (mutex=0x7f...5678)  ← L1 地址
#2  func_A()  ← 期望获取 L1 后才释放 L2
#3  ...
```

将两个线程的 `mutex=` 地址对调即可确认 ABBA。

---

## 五、futex 底层锁诊断

### 5.1 pthread_mutex_t 结构解读

```gdb
# 在 gdb 中打印互斥锁的内部状态
(gdb) print (pthread_mutex_t) my_lock
$1 = {
  __data = {
    __lock = 2,           # 0=未锁定, 1=锁定无竞争, 2=锁定有竞争者
    __count = 1,          # 递归锁计数
    __owner = 12345,      # 持有者线程 ID
    __kind = 0,           # 0=普通, 1=检错, 2=递归, 32=自适应, 256=robust
    ...
  }
}
```

**`__lock` 字段解读（核心）：**
| 值 | 含义 |
|----|------|
| 0 | 未锁定，可用 |
| 1 | 已锁定，无竞争者 |
| 2 | 已锁定，有线程在 futex 上等待（竞争标志置位） |

### 5.2 条件变量诊断

```gdb
(gdb) print my_cond
$2 = {
  __data = {
    __wseq = 123,                # 总 signal 序列号
    __g1_start = 0,              # group1 起始序列
    __wakeups = 3,               # 唤醒次数
    __broadcasts_seq = 0,        # broadcast 序列号
    __mutex = 0x7f...1234,       # 关联的 mutex 地址
  }
}
```

**诊断价值：** `__wseq` 和 `__wakeups` 不增长 → 条件变量没有 signal/broadcast → 等待线程永远等不到。

---

## 六、管道 / Socket 诊断

```bash
# gdb 查看文件描述符状态
gdb --batch -nx \
  -ex "print fd" \
  -ex "call (int) fcntl(fd, F_GETFL)" \
  -p <pid> 2>&1

# 查看调用链上的 fd 号（从 bt frame 参数中提取）
gdb --batch -nx \
  -ex "thread apply all bt" \
  -ex "print (int) $rdi" \
  -p <pid> 2>&1
```

---

## 七、执行流确认

### 7.1 正在执行的系统调用

```bash
# 查看进程当前系统调用（Linux 5.x+ 内核）
cat /proc/<pid>/syscall
# 输出: 0 0x7f... 0x0 0x0 0x0 0x0 0x0
# 第1列 = 系统调用号（0=read, 1=write, 202=futex, 35=nanosleep）
```

### 7.2 gdb 检查当前系统调用上下文

```bash
gdb --batch -nx \
  -ex "info registers" \
  -ex "x/10i \$pc" \
  -p <pid> 2>&1
```

`$pc` 处的指令可以判断进程正在执行哪个函数（结合符号表）。

---

## 八、快速诊断命令集（一键复制）

```bash
# 完整采集（推荐用于复杂场景）
gdb --batch -nx \
  -ex "set print thread-events off" \
  -ex "info threads" \
  -ex "thread apply all bt full" \
  -ex "info signals" \
  -p <pid> 2>&1 | tee gdb_hang_<pid>.log

# 轻量采集（生产环境友好，速度快）
gdb --batch -nx \
  -ex "thread apply all bt" \
  -p <pid> 2>&1 | tee gdb_hang_light_<pid>.log
```
