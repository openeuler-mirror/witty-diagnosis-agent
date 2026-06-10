# 内核 FUSE 相关参数说明

## FUSE 内核模块参数

### /sys/module/fuse/parameters/

| 参数 | 路径 | 默认值 | 说明 |
|------|------|--------|------|
| `max_read` | `/sys/module/fuse/parameters/max_read` | 131072 (128K) | 单个 FUSE 读请求最大字节数，通过 sysfs 设置的上限 |
| `max_write` | `/sys/module/fuse/parameters/max_write` | 131072 (128K) | 单个 FUSE 写请求最大字节数 |
| `use_writeback_cache` | `/sys/module/fuse/parameters/use_writeback_cache` | 0 (off) | 是否启用 writeback cache 模式 |

**注意**：这些是内核模块级别的全局上限，实际 FUSE 连接中的 max_read/max_write 在挂载协商时确定，不能超过模块参数值。

```bash
# 查看当前值
cat /sys/module/fuse/parameters/max_read
cat /sys/module/fuse/parameters/max_write
cat /sys/module/fuse/parameters/use_writeback_cache

# 修改模块参数（需要 root，重启后失效）
echo 262144 > /sys/module/fuse/parameters/max_read
```

## FUSE sysfs 连接参数

### /sys/fs/fuse/connections/<ID>/

每个活跃的 FUSE 连接在 `/sys/fs/fuse/connections/` 下有一个以连接 ID 命名的目录。

| 文件 | 类型 | 说明 |
|------|------|------|
| `waiting` | RO | 当前等待 FUSE daemon 处理的请求数 |
| `abort` | WO | 写入 1 中止该连接（所有等待请求返回 EIO） |
| `max_background` | RW | 最大后台请求数（排队上限） |
| `congested_threshold_ms` | RW | 拥塞阈值（毫秒），超过后标记连接为拥塞 |
| `max_read` | RO | 该连接协商后的最大读取大小 |

```bash
# 监控 waiting 值（请求队列深度）
watch -n 1 "cat /sys/fs/fuse/connections/*/waiting"

# 修改 max_background
echo 64 > /sys/fs/fuse/connections/<ID>/max_background
```

## 挂载选项

```bash
# FUSE 文件系统挂载
<daemon_binary> <mount_point> -o <options>

# 或通过 mount 命令
mount -t fuse.<fs_type> [-o <options>] <device> <mount_point>
```

### 关键挂载选项

| 选项 | 默认值 | 说明 |
|------|--------|------|
| `max_read=<N>` | 1MB (内核协商) | 最大读请求大小（字节） |
| `max_write=<N>` | 128KB (内核协商) | 最大写请求大小（字节） |
| `writeback_cache` | 未启用 | 启用 writeback cache（需内核 3.14+） |
| `allow_other` | 不允许 | 允许其他用户访问（需配置 user_allow_other） |
| `default_permissions` | 不启用 | 使用内核权限检查 |
| `auto_unmount` | 不启用 | daemon 退出时自动卸载 |
| `direct_io` | 不启用 | 禁用 page cache，绕过 VFS 缓存 |
| `kernel_cache` | 不启用 | 使用内核 page cache（不失效） |
| `async_read` | 启用 | 异步读请求 |
| `sync_read` | 不启用 | 同步读请求 |
| `atomic_o_trunc` | 不启用 | open(O_TRUNC) 作为原子操作 |
| `no_rofd` | 不启用 | 不重用只读 FD |
| `blksize=<N>` | 4096 | 文件系统块大小 |
| `subtype=<type>` | - | FUSE 文件系统子类型 |

### 调试选项

```bash
-d         # 调试模式（打印所有请求到 stderr）
-f         # 前台模式（不 daemon 化）
-s         # 单线程模式
```

## FUSE daemon 资源限制

### /dev/fuse 设备

```bash
crw-rw-rw- 1 root fuse 10, 229 /dev/fuse
```

- 主设备号：10（misc device）
- 次设备号：229
- 默认权限：0666（所有用户可读写）
- 某些发行版限制为 0660 root:root

### 用户级配置

```bash
# /etc/fuse.conf
user_allow_other    # 允许非 root 用户使用 allow_other 选项
mount_max=<N>       # 最大挂载数（默认 1000）
```

### 容器环境

容器中访问 /dev/fuse 需要：
1. `--device /dev/fuse` 或 `--privileged`
2. `CAP_SYS_ADMIN` 或特定 capabilities
3. `/dev/fuse` 设备节点必须存在

## 内核相关参数

### 影响 FUSE 性能的内核参数

```bash
# VM 参数（影响 FUSE page cache）
sysctl vm.dirty_ratio                    # 脏页占内存百分比（默认 20%）
sysctl vm.dirty_background_ratio         # 后台脏页阈值（默认 10%）
sysctl vm.dirty_writeback_centisecs     # 回写间隔（默认 500 = 5秒）
sysctl vm.dirty_expire_centisecs        # 脏页过期时间（默认 3000 = 30秒）

# 文件系统参数
sysctl fs.file-max                       # 系统最大 FD 数
sysctl fs.inotify.max_user_watches       # inotify 最大 watch 数

# 内存参数
sysctl vm.min_free_kbytes                # 最小剩余内存
sysctl vm.vfs_cache_pressure             # VFS 缓存回收压力
```

### FUSE 与 OOM

FUSE daemon 被 OOM Killer 杀死时：
- 内核自动中止连接（abort）
- 所有等待的 I/O 请求返回 EIO
- 仍然挂载（dentry 保留）但操作返回错误

```bash
# 检查 OOM Killer 日志
dmesg | grep -i "oom-killer"
journalctl -k | grep -i "oom-kill"
```

## 已知 FUSE 内核 Bug 版本

| 内核版本 | 问题 | 状态 |
|----------|------|------|
| < 3.10 | FUSE writeback cache 不稳定 | 建议升级 |
| 3.15 - 3.18 | FUSE 并发写竞态条件 (deadlock) | 已修复 (3.19) |
| 4.4 - 4.6 | FUSE 大文件 truncate 问题 | 已修复 (4.7) |
| 4.18 - 5.0 | FUSE 在 memory cgroup 下 OOM 行为异常 | 已修复 (5.1) |
| 5.10 - 5.15 | FUSE 多层挂载竞争条件 | 已修复 (5.16) |
| 6.0 - 6.2 | FUSE writeback + mmap 一致性 Bug | 已修复 (6.3) |

## FUSE 模块挂载参数（modprobe）

```bash
# /etc/modprobe.d/fuse.conf
options fuse max_read=262144
options fuse max_write=262144
options fuse use_writeback_cache=1
```

```bash
# 手动加载模块
modprobe fuse [max_read=262144] [max_write=262144]
```

## 性能参考

| 场景 | max_read | max_write | writeback_cache | 预期吞吐 |
|------|----------|-----------|-----------------|---------|
| 小文件读写 | 128K | 128K | 启用 | 中 |
| 大文件顺序读 | 1M+ | 128K | - | 高 |
| 大文件顺序写 | 128K | 1M+ | 启用 | 高 |
| 数据库随机读写 | 4K-64K | 4K-64K | 禁用 | 中 |
| SSD 后端存储 | 1M | 1M | 启用 | 最高 |
| 网络后端存储 | 512K | 512K | 启用 | 依赖网络延迟 |
