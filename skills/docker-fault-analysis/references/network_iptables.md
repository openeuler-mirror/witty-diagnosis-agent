# 网络 / iptables 故障诊断经验

## 目录
1. iptables 与 Docker 冲突
2. 容器间通信失败
3. 端口映射失败
4. veth/network namespace 异常
5. 典型故障链案例

---

## 1. iptables 与 Docker 冲突

### Docker 的 iptables 规则结构
```
filter 表：
  FORWARD → DOCKER-USER → DOCKER-ISOLATION-STAGE-1 → DOCKER-ISOLATION-STAGE-2 → DOCKER

nat 表：
  PREROUTING → DOCKER（端口映射 DNAT）
  POSTROUTING → MASQUERADE（出口 SNAT）
```

### 常见冲突场景
1. **手动 iptables -F 清空规则**：Docker 规则被删除，网络立即失效
   - 修复：`systemctl restart docker`（重建所有规则）
   
2. **firewalld 与 iptables 冲突**（CentOS 7）
   ```bash
   # firewalld 重载会覆盖 Docker iptables 规则
   # 解决方案 A：停止 firewalld
   systemctl stop firewalld
   systemctl restart docker
   # 解决方案 B：配置 firewalld 放行 Docker 流量
   firewall-cmd --permanent --zone=trusted --add-interface=docker0
   firewall-cmd --reload
   ```

3. **FORWARD 链默认 DROP**
   ```bash
   iptables -P FORWARD ACCEPT  # 临时修复
   # 永久：在 /etc/sysconfig/iptables 中设置
   ```

### 关键检查点
```bash
# 1. ip_forward 必须为 1
cat /proc/sys/net/ipv4/ip_forward  # 期望: 1

# 2. bridge-nf-call-iptables
cat /proc/sys/net/bridge/bridge-nf-call-iptables  # 期望: 1

# 3. DOCKER 链是否存在
iptables -L DOCKER -n 2>/dev/null | head -5

# 4. MASQUERADE 规则是否存在
iptables -t nat -L POSTROUTING -n | grep MASQUERADE
```

---

## 2. 容器间通信失败

### 同网络容器 ping 不通
```bash
# 检查 DOCKER-ISOLATION 链是否拦截
iptables -L DOCKER-ISOLATION-STAGE-1 -n -v
iptables -L DOCKER-ISOLATION-STAGE-2 -n -v

# 检查容器是否在同一 network
docker inspect c1 | grep NetworkID
docker inspect c2 | grep NetworkID

# 手动测试
docker exec c1 ping <c2_ip>
```

### 自定义 bridge 网络 vs 默认 bridge
- **默认 bridge（docker0）**：容器间只能通过 IP 通信，不支持 DNS 解析
- **自定义 bridge**：支持容器名 DNS 解析，推荐生产使用
```bash
docker network create mynet
docker run --network mynet --name app1 ...
docker run --network mynet --name app2 ...
# app2 内可以直接 ping app1
```

---

## 3. 端口映射失败

### 端口占用检测
```bash
# 完整端口占用检测
ss -ltnp | awk 'NR>1{print $4,$6}' | grep ":8080"
# 或
fuser 8080/tcp
```

### Docker 端口映射原理
```
宿主机:8080 → nat PREROUTING DNAT → 容器IP:80
```
- 若宿主机 `0.0.0.0:8080` 已被占用，Docker 启动时报 `bind: address already in use`
- 即使端口可用，若 `net.ipv4.ip_forward=0`，流量无法转发

### `userland-proxy` 与性能
```json
// daemon.json 禁用 userland-proxy（减少转发开销）
{"userland-proxy": false}
```
禁用后端口映射完全由 iptables DNAT 处理，性能更好但需确保 iptables 正常。

---

## 4. veth/network namespace 异常

### veth 接口残留
```bash
# 容器停止但 veth 残留（Docker 异常退出场景）
ip link show | grep "veth"
# 若容器已不存在但 veth 仍在，清理：
ip link delete veth_name
```

### network namespace 泄漏
```bash
# 检查 netns 数量
ls /var/run/docker/netns/ | wc -l
# 对比运行容器数
docker ps | wc -l
# 若前者远多于后者，说明 netns 泄漏
```

---

## 5. 典型故障链案例

### 案例 A：firewalld reload 导致容器网络中断
```
T1: 运维执行 firewall-cmd --reload（更新防火墙规则）
T2: firewalld 重建 iptables 规则，清除 Docker 注入的 DOCKER/DOCKER-USER 链
T3: FORWARD 链不再转发 Docker 流量
T4: 所有容器间通信失败，外部访问 published 端口失败
T5: docker ps 显示容器运行中，但网络完全不可用

时间线特征: 故障时间点与 firewall-cmd 执行时间一致
排除项: 容器本身未重启，应用进程正常
根因: firewalld reload 覆盖 Docker iptables 规则
修复: systemctl restart docker（重建所有 iptables 规则）
预防: 配置 firewalld trusted zone 包含 docker0，或禁用 firewalld 使用 iptables-services
```

### 案例 B：宿主机端口冲突导致容器启动失败
```
T1: 部署脚本 docker run -p 8080:8080 app_image
T2: 宿主机上 Nginx 占用 0.0.0.0:8080
T3: docker 报错: "bind: address already in use"
T4: 容器启动失败，ExitCode=128

排除项: 镜像问题（手动 docker run -p 8081:8080 正常）
根因: 宿主机端口冲突
修复: ss -ltnp | grep 8080 找到 Nginx，修改 Nginx 端口或容器映射端口
```
