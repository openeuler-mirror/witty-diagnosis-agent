# overlay2 / 文件系统故障诊断经验

## 目录
1. overlay2 常见故障
2. 卷挂载失败
3. I/O 性能瓶颈
4. 文件系统完整性
5. 典型故障链案例

---

## 1. overlay2 常见故障

### overlay2 工作原理快速回顾
```
lowerdir (只读镜像层) + upperdir (读写层) + workdir → merged (容器视图)
```
- **lowerdir**：镜像只读层，多层叠加
- **upperdir**：容器写操作发生在此
- **merged**：容器挂载点

### overlay2 健康检查
```bash
# 检查挂载状态
mount | grep overlay | wc -l
# 挂载数 = 运行中容器数，多则正常

# 检查是否有损坏的 merged 目录
for dir in /var/lib/docker/overlay2/*/merged; do
  if [ -d "$dir" ] && ! mountpoint -q "$dir"; then
    echo "损坏的 merged: $dir"
  fi
done

# 检查 link 文件完整性
for dir in /var/lib/docker/overlay2/*/; do
  link_file="$dir/link"
  if [ ! -f "$link_file" ]; then
    echo "缺失 link 文件: $dir"
  fi
done
```

### devicemapper 到 overlay2 迁移
```bash
# 修改 daemon.json
{"storage-driver": "overlay2"}
# 停止 docker，备份并清空旧数据目录
systemctl stop docker
mv /var/lib/docker /var/lib/docker.backup
systemctl start docker
```

---

## 2. 卷挂载失败

### 诊断矩阵
| 错误 | 排查方向 |
|------|---------|
| `no such file or directory` | 宿主机路径不存在，docker 不会自动创建 named volume 以外的目录 |
| `permission denied` | 文件权限或 SELinux 标签问题 |
| `read-only file system` | 宿主机文件系统 ro 挂载，或 docker run --read-only |
| `invalid mount config` | 路径语法错误 |

### 权限问题排查
```bash
# 检查宿主机目录权限
ls -laZ /path/to/volume

# 容器进程 UID
docker inspect <id> | grep '"User"'

# 若容器以 UID 1000 运行，宿主机需要：
chown 1000:1000 /path/to/volume
# 或 SELinux 标签
chcon -Rt svirt_sandbox_file_t /path/to/volume
```

---

## 3. I/O 性能瓶颈

### I/O 瓶颈判断指标
| 指标 | 瓶颈阈值 |
|------|---------|
| `%util`（iostat） | > 80% 持续 |
| `await`（ms） | > 20ms (HDD), > 5ms (SSD) |
| `r/s + w/s` | 接近设备 IOPS 上限 |

### overlay2 I/O 放大问题
- 小文件写入会触发 **copy-on-write（CoW）**，在 upperdir 复制整个文件
- 大文件频繁修改（如数据库文件）**不适合**放在容器层，应挂载 volume
- 建议：数据库、日志等 I/O 密集型数据**必须使用 bind mount 或 named volume**

### 容器 I/O 限速配置
```bash
# 限制容器块设备 I/O
docker run --device-write-bps /dev/sda:10mb \
           --device-read-bps /dev/sda:50mb \
           --device-write-iops /dev/sda:100 image
```

---

## 4. 文件系统完整性

### 检查文件系统错误
```bash
# 不能对挂载的文件系统 fsck，需先 umount
# 检查时机：系统异常重启后
# 在系统启动时 fsck 自动修复
touch /forcefsck && reboot

# XFS 检查（不需要 umount，只读检查）
xfs_check /dev/sda1
xfs_repair -n /dev/sda1  # -n 只检查不修复

# ext4 检查
e2fsck -fn /dev/sda1
```

### dmesg 文件系统错误关键词
- `EXT4-fs error` / `XFS internal error`：文件系统元数据损坏
- `Buffer I/O error on device`：磁盘物理错误
- `SCSI error`：磁盘/控制器硬件问题
- `journal commit I/O error`：journal 写入失败，数据可能不一致

---

## 5. 典型故障链案例

### 案例 A：高频日志写入导致 I/O 卡顿
```
T1: Java 应用 DEBUG 日志级别未关闭
T2: 日志写入容器 overlay2 upperdir（CoW 放大）
T3: iostat %util 达到 95%，await > 100ms
T4: 所有容器 I/O 操作等待，表现为容器卡顿、API 超时
T5: docker stats 显示 BlockIO 飙升

根因: 容器内大量小文件写入触发 overlay2 CoW，I/O 竞争
修复: 
  1. 关闭 DEBUG 日志
  2. 应用日志挂载到 bind mount 绕过 overlay2
  3. 长期: 迁移到 SSD
```

### 案例 B：volume 路径权限错误容器启动失败
```
T1: 新部署容器，-v /data/config:/app/config
T2: /data/config 由 root 创建，权限 700
T3: 容器内应用以 UID 1001 运行（非 root）
T4: 容器启动但应用立即退出，ExitCode=1
T5: docker logs 显示 "open /app/config/app.yaml: permission denied"

根因: 宿主机目录权限与容器内用户 UID 不匹配
排除项: SELinux（getenforce 返回 Disabled）
修复: chown -R 1001:1001 /data/config 或 chmod o+r /data/config
```
