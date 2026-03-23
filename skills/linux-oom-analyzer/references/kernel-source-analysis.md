# Linux 内核 OOM 源码分析参考手册

## 使用前提
用户明确要求"源码分析"，且已有初步根因假设，需要代码层面印证。

## 核心原则
1. **深度优先**：不能只到函数入口就停止，必须追踪完整执行路径
2. **因果链接**：展示代码中的"为什么"，不只是"是什么"
3. **数据结构联动**：关键数据结构的状态变化必须体现在分析中
4. **版本对齐**：源码分析必须基于用户系统的实际内核版本

---

## 准备工作

```bash
# 1. 确认内核版本
uname -r
# 示例输出：5.15.0-76-generic

# 2. 在线源码查看工具
# https://elixir.bootlin.com/linux/v5.15/source  （替换版本号）
# https://github.com/torvalds/linux/tree/v5.15

# 3. 如果本地有内核源码
find /usr/src -name "*.c" -path "*/mm/*" 2>/dev/null | head
```

---

## 关键代码路径分析

### 路径1：OOM killer 完整触发流程

**场景**：用户态进程申请内存失败，触发 OOM killer

```
触发路径（以 malloc 为例）：
用户态 malloc()
  → glibc brk() / mmap() 系统调用
    → 内核 sys_brk() / sys_mmap()
      → 仅建立 VMA，不分配物理页（延迟分配）
        → 进程访问内存时触发缺页异常
          → do_page_fault() [arch/x86/mm/fault.c]
            → handle_mm_fault() [mm/memory.c]
              → __handle_mm_fault()
                → handle_pte_fault()
                  → do_anonymous_page()  ← 匿名页分配
                    → alloc_zeroed_user_highpage_movable()
                      → alloc_pages_vma()
                        → __alloc_pages() [mm/page_alloc.c]  ← 核心分配
```

**关键函数 `__alloc_pages_slowpath()`** [mm/page_alloc.c]：

```c
// 慢速路径：当快速路径无法分配时调用
static inline struct page *
__alloc_pages_slowpath(gfp_t gfp_mask, unsigned int order,
                       struct alloc_context *ac)
{
    // 第一轮：唤醒 kswapd 进行异步内存回收
    wake_all_kswapds(order, gfp_mask, ac);
    
    // 第二轮：降低水位线重试分配
    page = get_page_from_freelist(gfp_mask, order, 
                                   ALLOC_NO_WATERMARKS, ac);
    if (page) goto got_pg;
    
    // 第三轮：直接内存回收（同步）
    page = __alloc_pages_direct_reclaim(gfp_mask, order, 
                                         alloc_flags, ac, &did_some_progress);
    
    // 第四轮：内存规整（碎片整理）
    page = __alloc_pages_direct_compact(gfp_mask, order, 
                                         alloc_flags, ac, ...);
    
    // 所有回收手段失败 → 触发 OOM
    if (should_reclaim_retry(gfp_mask, order, ac, ...))
        goto retry;
    
    // 最终：调用 OOM killer
    out_of_memory(&oc);    // ← OOM killer 入口
    ...
}
```

**`out_of_memory()`** [mm/oom_kill.c]：

```c
bool out_of_memory(struct oom_control *oc)
{
    // 1. 检查是否可以杀任务
    if (!is_memcg_oom(oc)) {
        blocking_notifier_call_chain(&oom_notify_list, 0, &freed);
        if (freed > 0)
            return true;  // 通知处理器释放了内存
    }
    
    // 2. 选择要杀死的进程
    select_bad_process(oc);   // ← 选择 oom_score 最高的进程
    
    if (!oc->chosen) {
        // 没有可杀的进程 → panic（如果配置了 panic_on_oom）
        if (sysctl_panic_on_oom)
            panic("Out of memory and no killable processes\n");
        return false;
    }
    
    // 3. 杀死选定进程
    oom_kill_process(oc, "Out of memory");
    return true;
}
```

**`select_bad_process()`** [mm/oom_kill.c]：

```c
// OOM score 计算：决定谁被杀
static unsigned long oom_badness(struct task_struct *p,
                                  unsigned long totalpages)
{
    // 基础分 = 进程占用物理页数 / 系统总页数 * 1000
    points = get_mm_rss(p->mm) + get_mm_counter(p->mm, MM_SWAPENTS);
    points += mm_pgtables_bytes(p->mm) >> PAGE_SHIFT;
    
    // 调整分 = oom_score_adj（-1000 ~ 1000）
    adj = (long)p->signal->oom_score_adj;
    
    // 最终分
    points = points * 1000 / totalpages;
    points += adj;
    
    return points;  // 返回值最大的进程被杀死
}
```

**根因联系**：
- 如果一个进程 `oom_score_adj = 0` 且占用内存最多 → 它会被优先杀死
- 如果关键进程没有设置 `oom_score_adj = -1000` → 存在被意外杀死的风险

---

### 路径2：Slab 内存泄漏根因（dentry 为例）

**场景**：大量 `find /` 操作导致 dentry cache 暴涨

```
触发路径：
find 命令调用 getdents() 系统调用
  → iterate_dir() [fs/readdir.c]
    → filldir64()
      → vfs_getattr()
        → 对每个目录项调用 lookup_one_len()
          → __lookup_hash()
            → d_lookup()  → 缓存中查找
            → d_alloc()   → 缓存中没有，分配新 dentry  ← 关键点
              → kmem_cache_alloc(dentry_cache, ...)  [mm/slub.c]
                → 从 dentry_cache slab 分配内存
```

**关键数据结构** `struct dentry` [include/linux/dcache.h]：
```c
struct dentry {
    unsigned int d_flags;       // 4 bytes
    struct hlist_bl_node d_hash; // LRU 链表节点
    struct dentry *d_parent;    // 父目录
    struct qstr d_name;         // 目录名
    struct inode *d_inode;      // 对应 inode
    // ...
    // 总大小约 192-256 bytes（视内核版本）
};
```

**为什么 dentry 不被回收？**

```c
// dentry 引用计数管理 [fs/dcache.c]
static void retain_dentry(struct dentry *dentry)
{
    // 引用计数 > 0 时不会被回收
    // d_count > 0 的 dentry 加入 active list
    // d_count = 0 的 dentry 加入 LRU list（等待回收）
}

// 回收触发点
static void shrink_dentry_list(struct list_head *list)
{
    // 从 LRU 末尾开始回收
    // 但是：在内存压力不够大时，不会主动回收
    // sysctl vm.vfs_cache_pressure 控制回收积极性
    // 默认值 100，值越大回收越积极
}
```

**根因代码链**：
```
find / 遍历 N 个文件
  → 为每个路径分配一个 dentry（d_alloc）
  → 每个 dentry 约 200 bytes
  → 1000万个文件 = 2GB dentry cache
  → 内存耗尽触发 OOM
  → vm.vfs_cache_pressure 默认值 100，回收不够激进
  → 建议：echo 200 > /proc/sys/vm/vfs_cache_pressure
```

---

### 路径3：cgroup OOM 触发流程

```
进程在 cgroup 内申请内存
  → mem_cgroup_try_charge() [mm/memcontrol.c]
    → try_charge()
      → 检查 cgroup memory.limit_in_bytes
      → 如果 usage + new_charge > limit：
        → try_to_free_mem_cgroup_pages() 尝试回收
        → 如果回收后仍不足：
          → mem_cgroup_oom() ← cgroup OOM 入口
            → mem_cgroup_out_of_memory()
              → 在 cgroup 范围内选择要杀的进程
              → 调用 oom_kill_process()
```

**关键差异**：cgroup OOM 只在该 cgroup 内选择进程，不影响其他 cgroup

---

## 源码分析输出模板

```markdown
## 源码级根因分析

### 内核版本
`uname -r` 输出：X.XX.X

### 触发路径（调用链）
[入口] → [中间层] → [关键决策点] → [最终效果]

### 关键代码逻辑
**文件**：mm/xxx.c（行号: XXX-XXX）
**函数**：function_name()
**逻辑**：
- 条件 A 时 → 执行 B → 导致 C
- 条件 D 时 → 跳过 E → 无法 F

### 数据结构状态变化
- struct xxx.field 从 [正常值] 变为 [异常值]
- 原因：[代码路径] 中的 [具体操作]

### 代码因果链
[第1步代码行为] 
  → 导致 [数据结构变化]
    → 触发 [第2步代码行为]
      → 最终 [OOM 发生]

### 修复方向（代码级）
- 方案A（内核参数调整）：修改 [sysctl 参数]，影响 [代码分支 XXX]
- 方案B（业务侧修复）：避免 [触发行为]，防止 [第1步]
```
