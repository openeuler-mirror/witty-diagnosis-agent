# OOM / 资源限制故障诊断经验

## 目录
1. OOM Killer 触发分析
2. 磁盘空间不足
3. 文件描述符限制
4. cgroup 资源配额
5. 典型故障链案例

---

## 1. OOM Killer 触发分析

### 关键日志特征
```
# dmesg 标准 OOM 输出
[时间] oom-kill:constraint=CONSTRAINT_MEMCG,nodemask=(null),
       cpuset=/docker/xxx,mems_allowed=0,
       task_memcg=/docker/xxx,task=java,pid=1234,uid=0
[时间] Memory cgroup out of memory: Killed process 1234 (java) total-vm:2048000kB, 
       anon-rss:1536000kB, file-rss:51200kB, shmem-rss:0kB,
       UID:0 policyname:auto_kill
```

### OOM 分析要点
- `constraint=CONSTRAINT_MEMCG`：cgroup 内存限制触发（非系统 OOM）
- `constraint=CONSTRAINT_NONE`：系统级内存不足
- 对比 `total-vm` 和 `anon-rss`：rss >> limit 说明内存泄漏
- 查看 oom_score：`cat /proc/<PID>/oom_score`（值越高越先被杀）

### cgroup OOM 触发条件
```bash
# 容器内存限制
docker inspect <id> | grep -E '"Memory"'
# 0 = 无限制；>0 = 字节数

# 当前内存使用 vs 限制
cat /sys/fs/cgroup/memory/docker/<id>/memory.usage_in_bytes
cat /sys/fs/cgroup/memory/docker/<id>/memory.limit_in_bytes

# OOM 触发次数（非0即发生过OOM）
cat /sys/fs/cgroup/memory/docker/<id>/memory.oom_control
```

### 容器频繁重启的 ExitCode 含义
| ExitCode | 含义 |
|----------|------|
| 137 | SIGKILL（通常是 OOM Killer 或 docker stop -t 0） |
| 139 | SIGSEGV（段错误，应用 bug） |
| 1 | 应用退出码1，查应用日志 |
| 143 | SIGTERM（优雅停止） |
| 159 | SIGSYS（seccomp 阻断） |

---

## 2. 磁盘空间不足

### 清理优先级（从安全到激进）
```bash
# 1. 清理悬空镜像（安全）
docker image prune -f

# 2. 清理停止的容器（安全）
docker container prune -f

# 3. 清理悬空卷（确认无用再操作）
docker volume prune -f

# 4. 清理构建缓存
docker builder prune -f

# 5. 全量清理（危险：会删所有未使用镜像）
docker system prune -af --volumes

# 6. 清理容器日志
truncate -s 0 /var/lib/docker/containers/<id>/<id>-json.log
```

### 日志限制最佳实践
```json
// /etc/docker/daemon.json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
```

---

## 3. 文件描述符限制

### 诊断路径
```
应用报 "too many open files"
  → ulimit -n （当前 shell 限制）
  → cat /proc/<dockerd_pid>/limits（dockerd 实际限制）
  → cat /proc/<container_pid>/limits（容器进程限制）
  → /etc/security/limits.conf & limits.d/
  → /etc/systemd/system/docker.service.d/ 中 LimitNOFILE
```

### 永久修复
```bash
# systemd 方式（推荐 CentOS 7+）
mkdir -p /etc/systemd/system/docker.service.d/
cat > /etc/systemd/system/docker.service.d/limits.conf << EOF
[Service]
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
EOF
systemctl daemon-reload
systemctl restart docker
```

---

## 4. 典型故障链案例

### 案例 A：Java 容器 OOM 导致频繁重启
```
T1: 容器 memory limit=512m（docker run -m 512m）
T2: JVM 默认 Xmx 未设置，JVM 按宿主机内存 25% = 8GB 分配 heap
T3: 应用负载升高，JVM heap 扩张至 512m
T4: cgroup OOM Killer 触发，容器 ExitCode=137
T5: restart policy=always → 容器重启 → 循环

根因: JVM -Xmx 未适配容器内存限制
修复: -e JAVA_OPTS="-Xmx400m -Xms256m" 或使用 JVM 容器感知（JDK11+）
```

### 案例 B：磁盘写满导致镜像拉取失败
```
T1: 生产环境多次构建镜像，overlay2 层累积
T2: du -sh /var/lib/docker/overlay2/ = 450GB（磁盘 500GB）
T3: docker pull → 写入新层 → ENOSPC
T4: docker logs 报 "no space left on device"
T5: docker build 失败，CI/CD 停止

根因: 长期未清理 dangling images 和 build cache
修复: docker system prune -af；设置 cron 定期清理
预防: daemon.json 配置日志大小限制；分离 /var/lib/docker 到独立分区
```
