# 源码分析常见缺陷模式速查

> 本文件配合 SKILL.md 第二节"源码主导分析路径"使用。
> 按故障类型索引，每种模式给出：源码特征、vmcore 对应现象、搜索策略。

---

## 一、空指针解引用类

### 模式1：函数返回值未校验

**源码特征**：
```c
struct obj *p = get_something(args);  // 可能返回 NULL
p->field = value;                      // ← 未检查 p 是否为 NULL，直接解引用
```

**vmcore 对应**：RIP 在赋值/访问指令，RAX/RBX/RDI 等寄存器值为 0x0

**源码搜索策略**：
1. 找到崩溃函数，定位到崩溃行
2. 向上找最近的指针赋值语句（`= get_xxx()` / `= kmalloc()` / `= container_of()` 等）
3. 检查该赋值与崩溃行之间是否有 `if (!p)` 或 `if (IS_ERR(p))` 分支
4. 检查 `get_something()` 的返回值规范（注释/文档/其他调用点是否都做了检查）

---

### 模式2：错误路径的早返回遗漏初始化

**源码特征**：
```c
int init(struct ctx *ctx) {
    ctx->dev = alloc_dev();
    if (some_other_fail)
        return -EINVAL;          // ← 早返回，ctx->dev 未初始化完成
    ctx->dev->ops = &my_ops;    // 正常路径
    return 0;
}
// 调用者在 init() 失败后仍访问 ctx->dev->ops
```

**vmcore 对应**：调用栈显示是在 init() 失败后的清理/使用路径崩溃

**源码搜索策略**：
1. 找到崩溃对象（如 `ctx->dev`）的初始化函数
2. 列出该函数**所有的返回路径**（正常返回 + 所有 goto/early return）
3. 对每条返回路径，检查对象的哪些字段被初始化了，哪些没有
4. 重点检查：goto err 路径是否与正常路径的初始化状态一致

---

### 模式3：并发 NULL 化（Race Condition）

**源码特征**：
```c
// 线程A：
spin_lock(&lock);
dev->buf = NULL;       // 并发释放，将指针置 NULL
spin_unlock(&lock);

// 线程B（无锁保护）：
if (dev->buf)          // 检查时非 NULL
    use(dev->buf);     // ← 到这里可能已被置 NULL（TOCTOU）
```

**vmcore 对应**：随机性崩溃，崩溃时对应指针确实为 NULL，但软件逻辑上"不应该"为 NULL

**源码搜索策略**：
1. 找到崩溃指针被置为 NULL 的所有位置（全局 grep `= NULL` / `->ptr = NULL`）
2. 检查这些置 NULL 操作和读取操作是否在同一把锁的保护下
3. 检查 `if (ptr)` 检查与 `use(ptr)` 之间是否有锁覆盖（TOCTOU 窗口）

---

## 二、Use-After-Free 类

### 模式4：引用计数不对称

**源码特征**：
```c
// 某路径多做了一次 put（或漏做了一次 get）
kobject_put(kobj);     // 第N次 put，引用计数降为0，触发释放
kobject_put(kobj);     // ← 重复 put！对象已释放，触发 UAF 或 double free
```

**vmcore 对应**：KASAN 报告 use-after-free，对象含 0x6b poison 值

**源码搜索策略**：
1. 确定对象类型（从 slab cache 名称推断）
2. 全局搜索该对象类型的 `get()`/`put()`/`hold()`/`drop()`/`ref()`/`unref()` 调用点
3. 对每条代码路径（正常路径 + 错误路径），手动配对 get 和 put 的次数
4. 重点检查：错误处理路径是否有额外的 put，中断处理路径是否有不对称操作

---

### 模式5：对象释放后指针未清零，被复用

**源码特征**：
```c
struct obj *cached_ptr;    // 全局或父结构体中的缓存指针

void cleanup(void) {
    kfree(cached_ptr);
    // ← 漏了 cached_ptr = NULL
}

void later_use(void) {
    if (cached_ptr)           // cached_ptr 非 NULL（指向已释放内存）
        cached_ptr->field++;  // ← UAF
}
```

**源码搜索策略**：
1. 找到释放操作（kfree/kmem_cache_free 等）
2. 检查释放后是否立即将指针置 NULL（`ptr = NULL`）
3. 在所有可能访问该指针的代码路径中，检查是否依赖 NULL 检查来判断有效性

---

### 模式6：RCU 保护对象在读临界区外被访问

**源码特征**：
```c
struct obj *p;
rcu_read_lock();
p = rcu_dereference(global_ptr);
rcu_read_unlock();

// ← 已退出 RCU 读临界区，p 可能已被释放
p->field++;   // UAF！
```

**源码搜索策略**：
1. 查找通过 `rcu_dereference()` 获取的指针
2. 检查这些指针的使用是否全部在 `rcu_read_lock()` / `rcu_read_unlock()` 范围内
3. 检查是否有在 rcu_read_unlock 后仍保留并使用的指针

---

## 三、越界访问（OOB）类

### 模式7：长度参数使用错误（最常见）

**源码特征**：
```c
char buf[64];
// 错误：使用指针大小而非缓冲区大小
memcpy(buf, src, sizeof(buf *));    // sizeof(指针) = 8，但本意是 sizeof(buf) = 64
// 或者：
memcpy(buf, src, user_len);         // user_len 来自用户输入，未做上界检查
```

**vmcore 对应**：KASAN 报告 slab-out-of-bounds，越界偏移量与对象大小的差值

**源码搜索策略**：
1. 从 KASAN 报告获取越界偏移量（如：`object size 64, access at offset 72`）
2. 找到崩溃帧对应的写操作（memcpy/strcpy/sprintf 等）
3. 检查长度参数的来源：是常量？来自用户输入？来自其他对象的字段？
4. 验证：长度参数是否有上界检查（`if (len > sizeof(buf)) return -EINVAL`）

---

### 模式8：数组下标未做边界检查

**源码特征**：
```c
#define MAX_ENTRIES 16
struct entry entries[MAX_ENTRIES];

int idx = get_index_from_hw();    // 来自硬件，可能超出范围
entries[idx].value = data;        // ← 若 idx >= MAX_ENTRIES，越界写
```

**源码搜索策略**：
1. 找到崩溃的数组访问语句
2. 追踪下标变量的来源（用户输入/硬件寄存器/函数参数）
3. 检查下标变量在使用前是否有 `if (idx >= MAX_ENTRIES)` 类的检查

---

## 四、死锁/Lockup 类

### 模式9：锁获取顺序不一致（ABBA 死锁）

**vmcore 对应**：LOCKDEP 报告 `possible circular locking dependency`

**源码搜索策略**：
1. 从 LOCKDEP 报告获取两把锁的地址/名称（`lock_classA` 和 `lock_classB`）
2. 全局搜索同时获取这两把锁的所有代码路径
3. 对每条路径，记录加锁顺序（A→B 还是 B→A）
4. 找到加锁顺序与其他路径相反的那条路径——那就是引入死锁的代码
5. 解法：统一加锁顺序，或使用 `mutex_trylock` + 重试

---

### 模式10：spinlock 持有期间调用可睡眠函数

**源码特征**：
```c
spin_lock(&lock);
ptr = kmalloc(size, GFP_KERNEL);  // ← GFP_KERNEL 可能睡眠！应用 GFP_ATOMIC
spin_unlock(&lock);
```

**源码搜索策略**：
1. 找到崩溃的调用栈，定位 spinlock 获取点（`spin_lock` / `spin_lock_irq` 等）
2. 从获取点到释放点之间，检查所有函数调用
3. 重点检查：`kmalloc/vmalloc`（GFP 标志）、`mutex_lock`、`msleep`、`schedule`、`copy_from_user`

---

## 五、栈溢出类

### 模式11：超大局部变量

**源码特征**：
```c
void process_packet(void) {
    char buf[8192];              // ← 内核栈默认 8KB/16KB，单个 8KB 局部变量极危险
    struct huge_ctx ctx;         // ← 巨型结构体作为局部变量
    memcpy(buf, input, len);
}
```

**源码搜索策略**：
1. 从崩溃调用栈提取所有函数名
2. 对每个函数，检查局部变量声明，计算总栈使用量
3. 特别关注：大数组、大结构体（> 1KB 即需警惕）
4. 工具辅助：编译时可用 `-Wframe-larger-than=1024` 静态检测

---

### 模式12：无限/过深递归

**源码特征**：
```c
void recursive_func(struct node *n) {
    // 递归终止条件有缺陷，在某些特殊输入下无法终止
    if (n->type == LEAF) return;
    recursive_func(n->child);   // ← 某些 n->type 下未正确终止
}
```

**源码搜索策略**：
1. 在调用栈中识别重复出现的函数名（递归特征）
2. 找到该函数的递归终止条件
3. 分析：在崩溃场景下，什么样的数据/状态导致终止条件永不满足
4. 检查：是否有最大递归深度的防护（计数器/深度限制）

---

## 六、BUG() 触发类

### 模式13：状态机状态不一致

**源码特征**：
```c
void handle_event(struct dev *dev, int event) {
    BUG_ON(dev->state != STATE_ACTIVE);   // ← 断言：此时应该是 ACTIVE 状态
    // ...
}
// 但在某个并发路径或错误路径中，dev->state 已被设为其他值
```

**源码搜索策略**：
1. 从 `kernel BUG at file:line` 定位到 BUG_ON/BUG 语句
2. 读取 BUG_ON 的条件表达式，确认崩溃时条件为什么为真
3. 全局搜索条件中涉及的变量（如 `dev->state`）的所有赋值点
4. 分析：在什么情况下，变量会到达 BUG_ON 期望之外的状态

---

## 七、源码搜索通用工具命令

```bash
# 在源码中搜索函数的所有调用点
grep -rn "function_name(" src/

# 搜索特定变量的赋值
grep -rn "->ptr\s*=" src/
grep -rn "ptr\s*=\s*NULL" src/

# 搜索某类内存操作
grep -rn "kfree\|kmem_cache_free\|vfree" src/ | grep -v "\.h:"

# 搜索引用计数操作
grep -rn "_get\|_put\|atomic_inc\|atomic_dec\|refcount_inc\|refcount_dec" src/

# 搜索加锁/解锁配对
grep -rn "spin_lock\|spin_unlock\|mutex_lock\|mutex_unlock" src/path/to/file.c

# 查看函数的所有返回路径（用于找错误处理遗漏）
grep -n "return\|goto" src/path/to/file.c

# git 历史中找类似修复
git log --oneline --grep="use-after-free\|null pointer\|fix.*leak" -- path/to/file.c

# 找最近的修改（回归 Bug 排查）
git log --oneline -20 -- path/to/file.c
git show <commit> -- path/to/file.c
```

---

## 八、版本匹配验证速查

```bash
# 方法1：反汇编对比（最可靠）
# vmcore 侧：
crash> dis -l suspicious_function | head -30
# 源码侧：
addr2line -e vmlinux -f 0x<RIP_addr>
# 两者源码行号应吻合

# 方法2：结构体偏移验证
crash> struct task_struct | grep -A2 "comm"
# 偏移量应与源码中 offsetof(struct task_struct, comm) 一致

# 方法3：内核配置验证
crash> rd $(sym kernel_config_data) 50
# 或：strings vmlinux | grep "CONFIG_" | head -20
```
