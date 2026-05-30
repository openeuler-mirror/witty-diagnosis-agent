# OverlayFS 故障诊断模式与命令速查

> 本文件配合 SKILL.md 第三节统一诊断流程使用，提供各故障场景的诊断命令速查与模式识别指南。

---

## 一、基础诊断命令速查

### 1.1 Overlay 挂载信息

| 命令 | 用途 | 示例 |
|------|------|------|
| `mount \| grep overlay` | 列出所有 overlay 挂载 | `mount \| grep overlay` |
| `cat /proc/self/mountinfo \| grep overlay` | 详细挂载信息（含选项） | `cat /proc/self/mountinfo \| grep overlay` |
| `cat /proc/mounts \| grep overlay` | mount 表（精简版） | `cat /proc/mounts \| grep overlay` |
| `findmnt -t overlay` | 树状挂载视图 | `findmnt -t overlay` |
| `df -hT \| grep -E "overlay\|Filesystem"` | overlay 文件系统磁盘使用 | `df -hT \| grep -E "overlay\|Filesystem"` |

### 1.2 内核与模块信息

| 命令 | 用途 | 示例 |
|------|------|------|
| `uname -r` | 内核版本 | `uname -r` |
| `modinfo overlay` | overlay 模块信息/参数 | `modinfo overlay` |
| `cat /sys/module/overlay/parameters/*` | overlay 运行时参数 | `cat /sys/module/overlay/parameters/*` |
| `lsmod \| grep overlay` | 模块加载状态 | `lsmod \| grep overlay` |
| `dmesg \| grep -i overlay` | overlay 相关内核日志 | `dmesg \| grep -i overlay` |

### 1.3 文件系统状态

| 命令 | 用途 | 示例 |
|------|------|------|
| `df -hT <dir>` | 目录所在文件系统与使用量 | `df -hT /merged` |
| `df -i <dir>` | inode 使用量 | `df -i /var/lib/docker/overlay2` |
| `stat <file>` | 文件元数据（含设备号、inode 号） | `stat /merged/somefile` |
| `stat -f <dir>` | 文件系统信息（类型、块大小等） | `stat -f /merged` |

### 1.4 Extended Attributes (xattr)

| 命令 | 用途 | 示例 |
|------|------|------|
| `getfattr -d -m - <dir>` | 列出目录所有 xattr | `getfattr -d -m - /upper/dir` |
| `getfattr -n trusted.overlay.opaque <dir>` | 检查 opaque 标记 | `getfattr -n trusted.overlay.opaque /upper/dir` |
| `getfattr -n trusted.overlay.whiteout <file>` | 检查 whiteout 标记 | `getfattr -n trusted.overlay.whiteout /upper/file` |
| `getfattr -n trusted.overlay.redirect <dir>` | 检查 redirect 标记 | `getfattr -n trusted.overlay.redirect /upper/dir` |
| `getfattr -n trusted.overlay.metacopy <file>` | 检查 metacopy 标记 | `getfattr -n trusted.overlay.metacopy /upper/file` |
| `setfattr -n trusted.overlay.opaque -v "y" <dir>` | 设置 opaque（手动） | `setfattr -n trusted.overlay.opaque -v "y" /upper/dir` |

### 1.5 Whiteout 检查

| 命令 | 用途 |
|------|------|
| `find <upperdir> -name ".wh.*"` | 查找传统命名格式的 whiteout |
| `find <upperdir> -type c 2>/dev/null` | 查找字符设备（可能为 whiteout） |
| `getfattr -d -m trusted.overlay.whiteout <upperdir> 2>/dev/null` | 通过 xattr 查找 whiteout |
| `ls -la <upperdir>/` | 直接查看目录内容（whiteout是特殊的字符设备 0,0） |

### 1.6 Docker overlay2 特定命令

| 命令 | 用途 |
|------|------|
| `docker info \| grep -i "storage\|overlay"` | Docker 存储驱动信息 |
| `docker system df` | Docker 磁盘使用统计 |
| `docker ps -a --size` | 容器大小（含层大小） |
| `docker inspect <container> \| jq '.[0].GraphDriver'` | 容器存储驱动详情 |
| `docker inspect <container> \| jq '.[0].GraphDriver.Data'` | 容器各层路径 |
| `cat /var/lib/docker/overlay2/<hash>/lower` | 容器的 lowerdir 配置 |

---

## 二、故障模式与诊断指引

### 模式A：Upper/Lower/Work 目录配置错误

**典型 dmesg**：
```
overlayfs: failed to get directory (upperdir)
overlayfs: workdir is not on the same filesystem as upperdir
overlayfs: failed to create workdir
```

**核心检查**：
```bash
# 1. 确认目录存在
ls -ld /upper /work /lower

# 2. 确认 upper/work 同设备
stat -c "%d" /upper
stat -c "%d" /work  # 必须相同

# 3. 确认文件系统类型
df -hT /upper

# 4. 确认 xattr 支持
touch /upper/.test_xattr && setfattr -n user.test -v "1" /upper/.test_xattr && getfattr -n user.test /upper/.test_xattr

# 5. 确认权限
ls -ld /upper /work
```

---

### 模式B：跨设备 overlay（XDev）

**典型 dmesg**：
```
overlayfs: upperdir is not on same filesystem as workdir
```

**核心检查**：
```bash
# 检查各目录的设备号
stat -c "%d %i %n" /upper /work /lower

# 检查挂载点
df -h /upper /work /lower
```

**解决**：将 upperdir 和 workdir 放在同一文件系统。

---

### 模式C：Opaque Whiteout 导致文件"消失"

**现象**：
- 挂载成功，merged 目录中某些文件/目录看不到
- `ls -la /merged/` 看不到文件，但 `ls -la /upper/` 有 whiteout 节点
- 在 upper 中有 `.wh.<filename>` 或 xattr whiteout

**核心检查**：
```bash
# 1. 检查 opaque 目录
getfattr -d -m - /merged/dir/ | grep -E "opaque"

# 2. 检查 whiteout
find /var/lib/docker/overlay2/*/diff/ -name ".wh.*" 2>/dev/null | head -20

# 3. 检查 xattr whiteout
find /var/lib/docker/overlay2/*/diff/ -exec \
  getfattr -d -m trusted.overlay.whiteout {} \; 2>/dev/null | head -20

# 4. 对比 upper 和 lower 的目录内容
ls -la /upper/dir/
ls -la /lower/dir/  # 对比差异
```

---

### 模式D：Copy-up 性能退化

**现象**：
- 首次写入 overlay 中"已有"文件时非常慢
- `iotop` 显示大量磁盘读写而非预期
- 容器首次写入日志/数据文件时延迟高

**核心检查**：
```bash
# 1. 确认 copy-up 发生
strace -e trace=write cp /merged/largefile /merged/newfile 2>&1

# 2. 检查文件是否在 lower 还是 upper
stat /merged/somefile | grep "Device"   # 与 lower 设备一致则未 copy-up

# 3. 启用 copy-up 跟踪
echo 1 > /sys/kernel/debug/tracing/events/overlayfs/overlayfs_copy_up/enable
cat /sys/kernel/debug/tracing/trace_pipe

# 4. 分析文件分布
find /var/lib/docker/overlay2/<hash>/diff/ -type f | wc -l
```

---

### 模式E：inotify 在 overlay 上不工作

**现象**：
- `inotifywait -m /merged/dir/` 在 merged 上没有事件
- 在 upper 层可以看到事件，但 merged 层不转发
- 使用 inotify 的应用程序在 overlay 上行为异常

**核心检查**：
```bash
# 1. 确认问题范围
inotifywait -m /merged/testfile &
touch /merged/testfile     # 有事件吗？
echo "data" > /merged/testfile  # 有事件吗？
rm /merged/testfile        # 有事件吗？

# 2. 对比：上层是否有事件
inotifywait -m /upper/testfile &
# 在容器内操作？有事件吗？

# 3. 确认内核版本
uname -r
# < 5.12 有已知的 inotify 问题

# 4. 检查 inotify 限制
cat /proc/sys/fs/inotify/max_user_watches
cat /proc/sys/fs/inotify/max_user_instances
```

---

### 模式F：Docker overlay2 inode 耗尽

**现象**：
- 新容器无法启动
- 已有容器内操作报 `No space left on device`
- `df -i /var/lib/docker` 显示 100%

**核心检查**：
```bash
# 1. 确认 inode 使用率
df -i /var/lib/docker

# 2. 找出 inode 消耗来源
find /var/lib/docker/overlay2 -xdev -type f | wc -l
find /var/lib/docker/overlay2 -xdev -type d | wc -l

# 3. 检查大量 whiteout
find /var/lib/docker -xdev -name ".wh.*" | wc -l

# 4. 检查退出容器的层
docker ps -a --size | grep "Exited"

# 5. Docker 系统清理评估
docker system df
```

---

### 模式G：Docker overlay2 diff 目录膨胀

**现象**：
```
/var/lib/docker/overlay2 越来越大，超出预期
```

**核心检查**：
```bash
# 1. 找出大目录
du -sh /var/lib/docker/overlay2/*/diff/ | sort -rh | head -20

# 2. 检查 diff 中最大的子目录
du -sh /var/lib/docker/overlay2/<hash>/diff/*/ | sort -rh | head -10

# 3. 检查容器日志
du -sh /var/lib/docker/containers/*/*-json.log 2>/dev/null | sort -rh | head -10

# 4. 分析 diff 中的文件类型
find /var/lib/docker/overlay2/<hash>/diff/ -type f | \
  awk -F. '{print $NF}' | sort | uniq -c | sort -rn | head -20

# 5. 检查 BuildKit 缓存
du -sh /var/lib/docker/buildkit/
```

---

### 模式H：redirect_dir / metacopy 行为异常

**现象**：
- 文件符号链接指向 lower 层（应指向 merged 或 upper）
- 目录重命名后文件丢失
- `readlink` 返回异常路径

**核心检查**：
```bash
# 1. 查看当前的 redirect_dir 设置
cat /sys/module/overlay/parameters/redirect_dir

# 2. 检查 metacopy 状态
cat /sys/module/overlay/parameters/metacopy

# 3. 检查 redirect xattr
getfattr -n trusted.overlay.redirect /upper/some/dir/ 2>/dev/null

# 4. 检查 metacopy xattr
getfattr -n trusted.overlay.metacopy /upper/some/file 2>/dev/null

# 5. 比较不同挂载方式的差异
mount -t overlay overlay -o lowerdir=/lower,upperdir=/upper,workdir=/work,redirect_dir=on /merged_on
mount -t overlay overlay -o lowerdir=/lower,upperdir=/upper,workdir=/work,redirect_dir=off /merged_off
```

---

### 模式I：overlayfs 日志解读

```text
# dmesg 中的常见 overlay 错误：
overlayfs: filesystem on '/upper' not supported as upperdir
  → upperdir 所在文件系统不支持 trusted xattr
  → 解决：换用 ext4/xfs 等本地文件系统

overlayfs: workdir is not on the same filesystem as upperdir
  → upperdir 和 workdir 跨设备
  → 解决：将两者放在同一文件系统

overlayfs: failed to get directory (upperdir)
  → upperdir 路径错误、权限不足、或不存在
  → 解决：检查目录存在性和访问权限

overlayfs: failed to get kernel config
  → CONFIG_OVERLAY_FS 未启用
  → 解决：重新编译内核或使用支持 overlay 的发行版

overlayfs: maximum fs stacking depth exceeded
  → overlay 层数超过限制（默认 2 层 stacking）
  → 解决：减少嵌套 overlay 使用

overlayfs: redirect_dir functionality disabled (unavailable)
  → 内核版本不支持 redirect_dir 或模块未启用
  → 解决：升级内核或确认 CONFIG_OVERLAY_FS_REDIRECT_DIR
```

---

## 三、OverlayFS 诊断工具链

### 3.1 必要的用户空间工具

```bash
# xattr 操作
apt-get install attr                            # getfattr/setfattr

# 性能分析
apt-get install sysstat iotop perf-tools-unstable  # iostat, iotop, perf

# 文件系统调试
apt-get install strace lsof                      # syscall 跟踪与打开文件检查

# Docker 分析
apt-get install jq                              # Docker inspect 输出解析
```

### 3.2 跟踪点（Tracepoints）使用

```bash
# 启用 overlayfs 跟踪事件
echo 1 > /sys/kernel/debug/tracing/events/overlayfs/enable

# 查看实时跟踪
cat /sys/kernel/debug/tracing/trace_pipe

# 单独跟踪 copy-up 事件
echo 1 > /sys/kernel/debug/tracing/events/overlayfs/overlayfs_copy_up/enable

# 内核函数跟踪（需 kprobe）
echo 'p ovl_copy_up' > /sys/kernel/debug/tracing/kprobe_events
echo 1 > /sys/kernel/debug/tracing/events/kprobes/enable

# 清理
echo 0 > /sys/kernel/debug/tracing/events/overlayfs/enable
```

### 3.3 控制变量实验方法

当症状不明确时，用最小化复现来隔离问题：

```bash
# Step 1: 准备隔离环境
TMPDIR=$(mktemp -d)
mkdir -p $TMPDIR/{lower,upper,work,merged}
echo "test data" > $TMPDIR/lower/testfile

# Step 2: 最小化挂载
mount -t overlay overlay \
  -o lowerdir=$TMPDIR/lower,upperdir=$TMPDIR/upper,workdir=$TMPDIR/work \
  $TMPDIR/merged

# Step 3: 验证基本功能
cat $TMPDIR/merged/testfile          # 应能读取
echo "write test" > $TMPDIR/merged/testfile  # 写入触发 copy-up
ls -la $TMPDIR/upper/                # 应有 testfile（copy-up 后的副本）

# Step 4: 逐步引入复杂配置（多层 lower/redirect_dir/metacopy 等）
# 逐项验证直到复现原问题

# Step 5: 清理
umount $TMPDIR/merged
rm -rf $TMPDIR
```

---

## 四、OverlayFS 内核源码分析入口

| 功能场景 | 内核源码路径 | 入口函数 |
|---------|------------|---------|
| 挂载参数解析 | `fs/overlayfs/params.c` | `ovl_parse_param()` |
| 超级块初始化 | `fs/overlayfs/super.c` | `ovl_fill_super()` |
| Copy-up | `fs/overlayfs/copy_up.c` | `ovl_copy_up()` |
| 读目录（合并） | `fs/overlayfs/readdir.c` | `ovl_iterate()` |
| Inode 操作 | `fs/overlayfs/inode.c` | `ovl_create/ovl_mkdir/ovl_unlink` |
| 文件操作 | `fs/overlayfs/file.c` | `ovl_open/ovl_release` |
| 元数据处理 | `fs/overlayfs/util.c` | `ovl_check_metacopy_xattr()` |
| 跨设备检查 | `fs/overlayfs/util.c` | `ovl_same_fs()` |
| Whiteout | `fs/overlayfs/whiteout.c` | `ovl_whiteout() / ovl_check_whiteout()` |
