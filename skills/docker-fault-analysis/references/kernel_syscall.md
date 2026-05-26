# 内核/系统调用故障诊断经验

## 目录
1. overlay mount 失败
2. cgroup 相关问题
3. SELinux/AppArmor/seccomp 阻断
4. 内核参数不合理
5. 典型故障链案例

---

## 1. overlay mount 失败

### 常见错误信息
- `driver failed programming external connectivity: failed to create endpoint`
- `error creating overlay mount to /var/lib/docker/overlay2/xxx/merged: device or resource busy`
- `mkdir /var/lib/docker/overlay2/xxx/merged: permission denied`
- `storage driver overlay not supported`

### 根因分类
| 错误 | 根因 | 验证命令 |
|------|------|---------|
| overlay not supported | 内核 < 3.18 或未加载模块 | `uname -r`, `lsmod | grep overlay` |
| device or resource busy | 旧挂载点残留 | `mount | grep overlay`, `fuser /var/lib/docker` |
| permission denied | SELinux 或宿主机权限 | `ausearch -m AVC -c dockerd` |
| ext4: no d_type support | XFS 以 ftype=0 格式化 | `xfs_info /dev/xxx | grep ftype` |

### XFS ftype 问题（CentOS 7 高发）
```bash
# 验证
xfs_info $(df -P /var/lib/docker | tail -1 | awk '{print $1}') | grep ftype
# ftype=0 是问题根因，必须重新格式化（数据破坏性操作）
mkfs.xfs -n ftype=1 /dev/xxx
# 或迁移到 ext4
```

### overlay2 残留挂载清理
```bash
# 查看残留挂载
grep overlay /proc/mounts
# 卸载残留
umount -l /var/lib/docker/overlay2/*/merged 2>/dev/null
# 重启 docker
systemctl restart docker
```

---

## 2. cgroup 相关问题

### cgroup v1 vs v2 冲突
- CentOS 8+ / RHEL 8+ 默认启用 cgroup v2
- 某些旧版 Docker（<20.10）不支持 cgroup v2
- 验证：`docker info | grep "Cgroup Version"`

### 解决方案（降级为 cgroup v1）
```bash
# /etc/default/grub 添加
GRUB_CMDLINE_LINUX="systemd.unified_cgroup_hierarchy=0"
grub2-mkconfig -o /boot/grub2/grub.cfg
reboot
```

### cgroup memory 子系统未启用
```bash
# 检查
cat /proc/cgroups | grep memory
# 内核启动参数添加 cgroup_memory=1 cgroup_enable=memory
```

---

## 3. SELinux/AppArmor/seccomp 阻断

### SELinux 排查流程
```
1. getenforce → Enforcing/Permissive/Disabled
2. ausearch -m AVC -c dockerd -ts today
3. 分析 scontext/tcontext/tclass/{ } 权限
4. 临时测试：setenforce 0
5. 生成永久策略：audit2allow -a -M docker_local
   semodule -i docker_local.pp
```

### 常见 Docker SELinux 场景
| 场景 | AVC 特征 | 修复 |
|------|----------|------|
| 卷挂载 | `tclass=file { read write }` | `chcon -Rt svirt_sandbox_file_t /path` |
| 容器访问宿主机 | `scontext=system_u:system_r:container_t` | 使用 `:z` 或 `:Z` 挂载选项 |
| Docker socket | `tclass=sock_file` | 检查 docker 组和 socket SELinux 标签 |

### seccomp profile 阻断
```bash
# 检查是否因 seccomp 失败（Exit Code 159 = 128+31 = SIGSYS）
docker inspect container_name | grep ExitCode
# 临时禁用 seccomp 测试
docker run --security-opt seccomp=unconfined image_name
```

---

## 4. 内核参数不合理

### 关键参数速查

| 参数 | 推荐值 | 影响 |
|------|--------|------|
| `vm.max_map_count` | ≥ 262144 | Elasticsearch 等需要大量内存映射 |
| `fs.file-max` | ≥ 1000000 | 系统级 fd 上限 |
| `fs.inotify.max_user_watches` | ≥ 524288 | 文件监控（IDE、监控工具） |
| `net.ipv4.ip_forward` | 1 | 容器网络必需 |
| `net.bridge.bridge-nf-call-iptables` | 1 | Docker 网络规则生效 |
| `kernel.pid_max` | ≥ 32768 | 高并发容器 |

### 永久修改方式
```bash
cat >> /etc/sysctl.d/99-docker.conf << EOF
vm.max_map_count = 262144
fs.file-max = 1000000
fs.inotify.max_user_watches = 524288
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system
```

---

## 5. 典型故障链案例

### 案例 A：CentOS 7 + XFS + overlay2 启动失败
```
T1: yum 升级 docker-ce → 19.03 → overlay2 成为默认驱动
T2: 原有 XFS 分区 ftype=0 创建时未指定 ftype=1
T3: docker pull image → 写入 overlay2 层 → ENOTSUP
T4: docker start 报 "backing file system doesn't support d_type"
根因: XFS ftype=0 不支持 overlay2 需要的 d_type 目录特性
```

### 案例 B：SELinux 阻断卷挂载
```
T1: 容器启动，volume 挂载宿主机 /data/app
T2: SELinux context: /data/app = admin_home_t, 容器需要 svirt_sandbox_file_t
T3: AVC denied { read } for scontext=container_t tcontext=admin_home_t
T4: 容器内应用无法读取配置文件，报 FileNotFoundError 或 Permission Denied
根因: 宿主机目录 SELinux 标签与容器期望标签不匹配
修复: chcon -Rt svirt_sandbox_file_t /data/app 或挂载时加 :z
```
