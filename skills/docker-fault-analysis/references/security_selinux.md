# SELinux / AppArmor / 权限故障诊断经验

## 目录
1. SELinux 深度分析
2. AppArmor 分析
3. Docker 用户权限
4. Capability 与 Privileged
5. 典型故障链案例

---

## 1. SELinux 深度分析

### AVC 日志解读
```
type=AVC msg=audit(1234567890.123:456): avc:  denied  { read write } 
  for  pid=1234 comm="java" name="data.db" dev="sda1" ino=67890 
  scontext=system_u:system_r:container_t:s0:c1,c2 
  tcontext=unconfined_u:object_r:admin_home_t:s0 
  tclass=file permissive=0
```

| 字段 | 含义 |
|------|------|
| `{ read write }` | 被拒绝的权限 |
| `comm="java"` | 发起操作的进程 |
| `scontext=container_t` | 主体（进程）的 SELinux 标签 |
| `tcontext=admin_home_t` | 目标（文件）的 SELinux 标签 |
| `tclass=file` | 目标类型（file/dir/sock_file/chr_file） |
| `permissive=0` | 强制模式（0=阻断，1=仅记录） |

### Docker 常见 SELinux 类型
| 上下文类型 | 用途 |
|-----------|------|
| `container_t` | 容器进程默认类型 |
| `container_file_t` | 容器可读写的文件 |
| `svirt_sandbox_file_t` | 挂载卷（容器可访问） |
| `container_ro_file_t` | 容器只读文件 |

### 挂载卷 SELinux 修复
```bash
# 单次修复（重启后 SELinux 可能重置）
chcon -Rt svirt_sandbox_file_t /path/to/volume

# 永久修复（推荐）
semanage fcontext -a -t container_file_t "/path/to/volume(/.*)?"
restorecon -Rv /path/to/volume

# Docker 挂载时自动打标签
docker run -v /path:/container:z   # 所有容器共享标签
docker run -v /path:/container:Z   # 仅当前容器独占标签（更安全）
```

### 生成自定义 SELinux 策略
```bash
# 将 audit 日志中的 AVC 转为策略模块
ausearch -m AVC -ts today | audit2allow -M myapp_docker
semodule -i myapp_docker.pp
# 查看生成的规则
cat myapp_docker.te
```

---

## 2. AppArmor 分析（Ubuntu/Debian 系）

### 检查 Docker AppArmor profile
```bash
# Docker 默认 profile
cat /etc/apparmor.d/docker-default 2>/dev/null

# 容器使用的 profile
docker inspect <id> | grep AppArmorProfile

# AppArmor 拒绝日志
dmesg | grep apparmor | grep DENIED | tail -20
journalctl | grep apparmor | grep DENIED | tail -20
```

### 临时禁用 AppArmor（测试用）
```bash
docker run --security-opt apparmor=unconfined image
```

---

## 3. Docker 用户权限

### 权限检查清单
```bash
# 1. 用户是否在 docker 组
groups $USER | grep docker

# 2. docker socket 权限
ls -la /var/run/docker.sock
# 期望: srw-rw---- root docker 或 srw-rw-rw-

# 3. 添加用户到 docker 组（需重新登录生效）
usermod -aG docker $USER
newgrp docker  # 临时生效

# 4. rootless docker 检查
docker context ls
```

### sudo 与 docker 组的区别
- `sudo docker`：以 root 身份运行 docker 客户端
- `docker 组`：允许非 root 用户访问 docker socket，**等同于 root 权限**
- 安全考虑：生产环境应使用 rootless Docker 或严格控制 docker 组成员

---

## 4. Capability 与 Privileged

### 容器 capability 与 SELinux
```bash
# 查看容器有效 capability
docker inspect <id> | python3 -c "
import sys, json
d = json.load(sys.stdin)[0]
hc = d['HostConfig']
print('CapAdd:', hc.get('CapAdd'))
print('CapDrop:', hc.get('CapDrop'))
print('Privileged:', hc.get('Privileged'))
"

# privileged 容器绕过 SELinux/AppArmor
# 仅在必要时使用，如 docker-in-docker 场景
```

### 最小权限原则
```bash
# 仅添加必要的 capability
docker run --cap-drop ALL --cap-add NET_BIND_SERVICE nginx
```

---

## 5. 典型故障链案例

### 案例 A：SELinux 阻断 Redis 持久化写入
```
T1: Redis 容器 -v /data/redis:/data
T2: /data/redis 在安装系统时由 root 创建，SELinux 标签为 default_t
T3: 容器启动，Redis 尝试写 /data/rdb.dump
T4: AVC denied { write } scontext=container_t tcontext=default_t tclass=file
T5: Redis 报 "MISCONF Redis is configured to save RDB snapshots, but is currently not able to persist on disk"

时间线: 容器第一次写磁盘时触发（非启动时）
排除项: 权限检查 ls -la 显示 777（Linux 权限层面正常，问题在 SELinux）
根因: SELinux 标签 default_t 不允许 container_t 写入
诊断依据: /var/log/audit/audit.log 中 AVC denied 记录时间与 Redis 报错时间吻合
修复: chcon -Rt container_file_t /data/redis
```

### 案例 B：非 root 用户 docker 命令 permission denied
```
T1: 新员工 dev01 尝试执行 docker ps
T2: Got permission denied while trying to connect to the Docker daemon socket
T3: ls -la /var/run/docker.sock → srw-rw---- root docker
T4: groups dev01 → dev01 : dev01（不含 docker 组）

根因: dev01 未加入 docker 组
排除项: socket 权限正常（docker 组可读写）；SELinux 正常（getenforce=Permissive）
修复: usermod -aG docker dev01; 重新登录
```
