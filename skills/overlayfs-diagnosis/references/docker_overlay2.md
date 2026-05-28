# Docker overlay2 存储驱动特有问题

> 本文件配合 SKILL.md 第三节统一诊断流程使用，提供 Docker 容器场景下 overlay2 驱动的特有诊断知识。
> Docker overlay2 驱动在裸 overlayfs 之上增加了 layer 管理、元数据跟踪等逻辑，故障表现与纯 overlay 有显著差异。

---

## 一、Docker overlay2 存储架构

### 1.1 目录结构

```
/var/lib/docker/overlay2/
├── <layer-hash>/              # 每一层（镜像层/容器层）
│   ├── diff/                  # ← 该层的实际文件变更（overlay upperdir 或 lowerdir）
│   ├── link                   # 简短符号连接名（如 "L<random>"）
│   ├── lower                  # 父层列表（仅 merged 层有，形如 l/<name1>:l/<name2>:...）
│   └── merged/                # ← 最终的 overlay 挂载点（容器可见）
├── l/                         # 短链接名目录
│   ├── <shortname> -> ../<layer-hash>/diff  # 指向实际的 diff 目录
│   └── ...
├── backingFsBlockDev          # 标识后备块设备
└── repositories.json          # 镜像仓库元数据
```

### 1.2 容器层 vs 镜像层

| 类型 | 读写？ | upperdir? | 生命周期 |
|------|--------|-----------|---------|
| 镜像层（image layers） | 只读 | 否（属于 lowerdir） | 镜像不被删除则永久 |
| 容器层（container layer） | 读写 | 是（容器的 upperdir） | 容器删除则删除 |
| init 层（init layer） | 只读 | 否 | 容器生命周期内存在，用于 /etc/hosts 等 |

### 1.3 Docker overlay2 挂载示例

```bash
# 内核中的实际挂载（Docker 自动管理）
mount -t overlay overlay \
  -o lowerdir=/var/lib/docker/overlay2/l/<base-short>:...:\
            /var/lib/docker/overlay2/l/<init-short>,\
     upperdir=/var/lib/docker/overlay2/<container-hash>/diff,\
     workdir=/var/lib/docker/overlay2/<container-hash>/work,\
     index=off,metacopy=on,xino=on \
  /var/lib/docker/overlay2/<container-hash>/merged
```

---

## 二、Docker overlay2 特有故障场景

### 2.1 Inode 耗尽（`no space left on device` 但 df 有余量）

**现象**：
```bash
# df 显示还有大量空间
df -h /var/lib/docker
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1       200G  100G  100G  50% /

# 但应用报 "no space left on device" 或 Docker 日志报 inode 耗尽
df -i /var/lib/docker
Filesystem     Inodes  IUsed  IFree IUse% Mounted on
/dev/sda1       13M    13M     0    100% /
```

**根因**：
- overlay2 upperdir 中的目录结构复杂，每个容器层在 diff/ 中创建大量目录和文件
- 频繁的容器创建/删除/重建导致大量遗留 whiteout 和空目录
- 下层文件系统的 inode 总数固定（尤其 ext4/xfs），一旦耗尽则所有文件操作失败

**检查命令**：
```bash
# 检查 inode 使用率
df -i /var/lib/docker

# 找出 inode 消耗大户（overlay2 目录下）
find /var/lib/docker/overlay2 -xdev -type d | wc -l
find /var/lib/docker/overlay2 -xdev -type f | wc -l

# 检查 whiteout 数量（可能有大量被删除文件的残留）
find /var/lib/docker/overlay2 -xdev -name ".wh.*" -o \
  -exec getfattr -d -m trusted.overlay.whiteout {} \; 2>/dev/null

# 查看特定容器的层大小
du -sh /var/lib/docker/overlay2/<container-hash>/diff/
```

---

### 2.2 Diff 目录膨胀

**现象**：
```
# overlay2 目录持续增长，远超镜像大小
du -sh /var/lib/docker/overlay2/
200G    /var/lib/docker/overlay2/

# 但所有容器的 diff 大小之和远小于此值
```

**根因**：
1. **停止的容器未清理**：`docker container prune` 未定期执行
2. **容器内产生大量日志/临时文件**：写入 upperdir diff/ 但不清除
3. **大量镜像 Tag**：每个镜像层都是独立目录
4. **容器内删除的文件留下 whiteout**：whiteout 在 upper 层占用 inode
5. **Docker 日志驱动产生大量文件**：json-file 驱动在 `/var/lib/docker/containers/` 写日志（非 overlay2）

**排查命令**：
```bash
# 最大的镜像层/容器层
du -sh /var/lib/docker/overlay2/*/diff/ | sort -rh | head -20

# 每个容器的层大小
docker ps -a --size

# 查看 diff 目录内容构成
du -sh /var/lib/docker/overlay2/<hash>/diff/*/ | sort -rh | head -10

# 检查未使用的镜像层
docker system df

# 检查容器日志大小
ls -lh /var/lib/docker/containers/*/*-json.log
```

---

### 2.3 容器层损坏（Docker overlay2 特有）

**现象**：
```
docker exec 报错或容器内文件访问异常
```

**根因**：
1. 容器所在宿主机异常断电/重启，导致 upperdir 中的 copy-up 操作未完成
2. workdir 中残留了临时文件，下次 overlay 合并时状态不一致
3. Docker 守护进程强制重启，某些层的写操作未 fsync

**检查方法**：
```bash
# 检查对应容器的 overlay 挂载
cat /proc/self/mountinfo | grep overlay | grep <container-id>

# 检查 workdir 是否有残留
ls -la /var/lib/docker/overlay2/<hash>/work/

# 检查 diff 目录的完整性
find /var/lib/docker/overlay2/<hash>/diff/ -type f -name "*.wh.*" | head

# 检查内核日志
dmesg | grep -i overlay | tail -20
```

---

### 2.4 容器启动/停止慢（大量 copy-up）

**现象**：
```
docker start 或 docker stop 耗时极长
```

**根因**：
- 容器层存在大量小文件的 copy-up 操作
- 容器启动时需要挂载 overlay，涉及大量 inode 操作
- 若下层文件系统是网络文件系统（NFS），copy-up 延迟极显著

**排查方法**：
```bash
# 查看 copy-up 相关的内核事件
perf trace -e 'fs:overlayfs:*' --duration 100

# 检查 diff 目录的文件数量
find /var/lib/docker/overlay2/<hash>/diff/ -type f | wc -l

# 检查容器 diff 中的文件分布
find /var/lib/docker/overlay2/<hash>/diff/ -type f -printf '%h\n' | \
  sort | uniq -c | sort -rn | head -20
```

---

### 2.5 overlay2 + 特殊文件系统

| 下层文件系统 | overlay2 兼容性 | 注意事项 |
|-------------|----------------|---------|
| ext4/xfs (本地) | ✅ 完全支持 | 推荐，xfs 建议开启 ftype=1 |
| btrfs | ⚠️ 部分支持 | overlay2 自身也支持 btrfs，但性能不如原生模式 |
| NFS (远程) | ❌ 不推荐 | 性能差，可能触发各种 timeout |
| tmpfs | ⚠️ 可挂载 | 内存限制，重启丢失 |
| FUSE (s3fs/glusterfs) | ❌ 不兼容 | d_type 不支持，overlay 报错 |

---

## 三、Docker overlay2 调优参数

### 3.1 Docker 守护进程配置

```json
// /etc/docker/daemon.json
{
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=1",   // 绕过内核版本检查
    "overlay2.size=10G"                    // 单容器层大小限制（需 xfs 配额）
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

### 3.2 清理策略

```bash
# 安全清理
docker system prune -a --volumes          # 清理所有未使用资源
docker container prune                    # 清理停止的容器
docker image prune -a                     # 清理未使用的镜像
docker builder prune                      # 清理 BuildKit 缓存

# 手动清理 overlay2 中的残留
# 注意：以下操作需要完全停止 Docker 守护进程
systemctl stop docker
find /var/lib/docker/overlay2 -name "*.wh.*" -delete  # 清理 whiteout 文件（谨慎！）
systemctl start docker
```

---

## 四、Docker overlay2 内核版本兼容性

| Docker 版本 | 最低内核版本 | 推荐内核版本 | 备注 |
|------------|------------|-------------|------|
| Docker CE 19.x | 3.18 (overlay) | 4.0+ | native overlay2 需 4.0+ |
| Docker CE 20.x | 4.0 | 4.9+ | 默认 overlay2 |
| Docker CE 23.x | 4.9 | 5.10+ | metacopy 支持提升性能 |
| Docker CE 24+ | 4.9 | 5.15+ | xino, metacopy, redirect_dir 均支持 |

---

## 五、Docker overlay2 常见 dmesg 错误模式

| dmesg 消息 | 典型原因 | 严重程度 |
|-----------|---------|---------|
| `overlayfs: filesystem on '...' not supported as upperdir` | upperdir 文件系统不支持 xattr | 致命 |
| `overlayfs: maximum fs stacking depth exceeded` | overlay 嵌套过多 | 致命 |
| `overlayfs: failed to get directory (upperdir)` | 目录权限/路径错误 | 致命 |
| `overlayfs: workdir is not on the same filesystem as upperdir` | 跨设备 overlay | 致命 |
| `overlayfs: failed to create workdir` | workdir 权限/磁盘满 | 致命 |
| `overlayfs: failed to create directory .overlay.upperidx` | index=on 时创建索引失败 | 警告 |
| `overlayfs: xino feature disabled because inode number collision` | xino 因冲突降级 | 警告 |
| `overlayfs: redirect_dir functionality disabled` | 内核不支持 redirect_dir | 警告 |
| `overlayfs: failed to get metacopy xattr` | metacopy 文件元数据损坏 | 警告 |
