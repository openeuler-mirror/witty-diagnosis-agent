# 日志 / 时间漂移故障诊断经验

## 目录
1. 容器日志故障
2. 时间漂移与 NTP
3. 证书校验失败
4. 典型故障链案例

---

## 1. 容器日志故障

### 日志写入失败原因
| 原因 | 诊断 | 修复 |
|------|------|------|
| 磁盘满 | `df -h /var/lib/docker` | 清理日志/dangling镜像 |
| 日志文件权限 | `ls -la /var/lib/docker/containers/<id>/` | 修复权限 |
| journald 故障 | `systemctl status systemd-journald` | 重启 journald |
| log driver 配置错误 | `docker info | grep "Logging Driver"` | 修改 daemon.json |

### 日志大小管理
```bash
# 查看所有容器日志大小（汇总）
find /var/lib/docker/containers/ -name "*.log" -exec du -sh {} + | sort -rh | head -20

# 单个容器日志大小限制（运行时指定）
docker run --log-opt max-size=100m --log-opt max-file=3 image

# 全局限制（daemon.json，对新容器生效）
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "50m",
    "max-file": "5"
  }
}

# 清空已有日志（不影响运行中容器）
truncate -s 0 /var/lib/docker/containers/<id>/<id>-json.log
# 注意：Docker 24.0+ 可用 docker logs --since 查询，清空后历史丢失
```

### 使用 syslog/journald 集中收集
```json
// daemon.json 切换日志驱动
{"log-driver": "journald"}
// 或
{"log-driver": "syslog", "log-opts": {"syslog-address": "tcp://logserver:514"}}
```

---

## 2. 时间漂移与 NTP

### 时间漂移影响
- JWT/OAuth token 校验失败（时钟偏差 > 5 分钟）
- TLS 证书校验失败（notBefore/notAfter）
- 分布式系统时序混乱（Kafka、etcd 等）
- 定时任务错误触发（cron）

### NTP 同步状态诊断
```bash
# chrony（CentOS 7+ 默认）
chronyc tracking
# 关键指标：
# System time: X.XXX seconds slow/fast of NTP time
# RMS offset: 历史偏移均方根
# Frequency: 时钟频率偏差

# 强制立即同步
chronyc makestep

# 检查 NTP 服务
systemctl status chronyd
```

### 容器时间同步机制
- 容器默认**共享宿主机时钟**（同一内核）
- 容器内无法修改系统时钟（除非 `--privileged`）
- 容器时间 = 宿主机时间（时区可以不同，通过 `/etc/localtime` 挂载）

```bash
# 统一容器时区
docker run -v /etc/localtime:/etc/localtime:ro image
# 或
docker run -e TZ=Asia/Shanghai image
```

### 时钟跳变排查
```bash
# 查看 chrony 日志中的跳变事件
journalctl -u chronyd | grep -iE "(offset|step|jump|slew)" | tail -30

# 检查是否有多个 NTP 客户端冲突
systemctl list-units | grep -iE "(ntp|chrony|timesyncd)"
# 只应有一个 NTP 服务运行
```

---

## 3. 证书校验失败

### 常见证书错误
| 错误信息 | 原因 |
|---------|------|
| `certificate has expired or is not yet valid` | 时间偏差或证书过期 |
| `x509: certificate signed by unknown authority` | 自签名证书未加入信任 |
| `x509: certificate is valid for X, not Y` | 证书域名不匹配 |
| `tls: failed to verify certificate` | 中间人或证书链不完整 |

### 证书检查命令
```bash
# 检查证书有效期
openssl x509 -noout -dates -in /path/to/cert.crt
# 检查远端证书
echo | openssl s_client -connect registry.example.com:443 -servername registry.example.com 2>/dev/null | openssl x509 -noout -dates

# Docker registry 自签名证书信任
mkdir -p /etc/docker/certs.d/registry.example.com:5000/
cp ca.crt /etc/docker/certs.d/registry.example.com:5000/ca.crt
systemctl restart docker
```

### 时间差对证书校验的影响
```
场景: 容器内时间比实际时间慢 >5分钟
现象: JWT token 被认为已过期（iat + 5分钟 < 当前时间）
根因: 宿主机 NTP 未同步，或虚拟机挂起恢复后时钟未更新
修复: chronyc makestep 强制同步时钟
```

---

## 4. 典型故障链案例

### 案例 A：VM 挂起恢复导致容器任务全失败
```
T1: 虚拟机挂起（VM suspend）8小时
T2: VM 恢复运行，内核时钟仍在旧时间点
T3: 宿主机时钟落后实际时间 8 小时
T4: 容器内应用发送 JWT 请求，token 签发时间"早于"当前时间
T5: 上游服务拒绝所有请求（iat + max_skew < now）
T6: 5分钟后 chrony 逐渐纠正时钟，但期间所有请求失败

根因: VM 挂起后时钟不连续，chrony 采用 slew 模式缓慢修正（默认不做 step 跳变）
修复: chronyc makestep（强制立即跳变到正确时间）
预防: /etc/chrony.conf 添加 makestep 1.0 -1 允许任意次数跳变
```

### 案例 B：容器日志磁盘写满触发连锁故障
```
T1: 容器日志驱动 json-file，无 max-size 限制
T2: 高并发应用持续写入 ERROR 日志（BUG 导致）
T3: /var/lib/docker/containers/<id>/<id>-json.log 增长至 200GB
T4: 宿主机 /var/lib/docker 所在分区写满（100%）
T5: 其他容器写入临时文件失败，数据库容器无法写 WAL → crash
T6: Docker daemon 无法创建新容器（无法写元数据）
T7: 监控系统告警无法记录（也写不了磁盘）

故障扩散: 单个容器日志 → 磁盘满 → 级联影响所有容器
根因: 未配置日志大小限制 + 应用 BUG 导致日志爆炸
修复: truncate -s 0 大日志文件; 添加 log-opts max-size
预防: daemon.json 全局配置日志限制；应用日志级别监控告警
```
