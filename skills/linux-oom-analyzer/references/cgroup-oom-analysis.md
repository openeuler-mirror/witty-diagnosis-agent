# cgroup OOM 分析参考手册

## 适用场景
- 容器（Docker/K8s）内进程被 OOM kill
- cgroup 内存限制触发 OOM
- memory.failcnt 持续增加

---

## C1. 确认 cgroup OOM 事件

```bash
# 方法1：内核日志中的 cgroup OOM 特征
dmesg -T | grep -E "memory cgroup.*oom\|Task in.*killed as a result of limit"

# 方法2：查看 memory.oom_control（cgroup v1）
# oom_kill_disable=0 表示允许 OOM kill
# under_oom=1 表示当前正在 OOM 状态
find /sys/fs/cgroup/memory -name "memory.oom_control" 2>/dev/null | \
    xargs -I{} sh -c 'echo "{}:"; cat {}'

# 方法3：检查 failcnt（失败次数）
find /sys/fs/cgroup/memory -name "memory.failcnt" 2>/dev/null | \
    while read f; do
        cnt=$(cat $f 2>/dev/null)
        [ "$cnt" -gt 0 ] 2>/dev/null && echo "$f: $cnt"
    done
```

---

## C2. 分析 cgroup 内存使用

```bash
# cgroup v1：找出内存使用最高的 cgroup
find /sys/fs/cgroup/memory -name "memory.usage_in_bytes" | \
    while read f; do
        usage=$(cat $f 2>/dev/null)
        limit=$(cat $(dirname $f)/memory.limit_in_bytes 2>/dev/null)
        name=$(dirname $f | sed 's|/sys/fs/cgroup/memory||')
        [ -n "$usage" ] && echo "$usage $limit $name"
    done | sort -rn | head -20 | \
    awk '{printf "usage=%8.1fMB  limit=%8.1fMB  name=%s\n", $1/1024/1024, $2/1024/1024, $3}'

# cgroup v2
find /sys/fs/cgroup -name "memory.current" 2>/dev/null | \
    while read f; do
        usage=$(cat $f 2>/dev/null)
        max=$(cat $(dirname $f)/memory.max 2>/dev/null)
        echo "$usage $max $(dirname $f)"
    done | sort -rn | head -20
```

---

## C3. Docker/Kubernetes 容器 OOM 分析

```bash
# Docker：检查被 OOM kill 的容器
docker stats --no-stream 2>/dev/null | head -20

docker inspect <container_id> 2>/dev/null | \
    python3 -c "import sys,json; d=json.load(sys.stdin); \
    s=d[0]['State']; print('OOMKilled:', s.get('OOMKilled'), '\nExitCode:', s.get('ExitCode'))"

# 查看容器内存限制
docker inspect <container_id> | \
    python3 -c "import sys,json; d=json.load(sys.stdin); \
    h=d[0]['HostConfig']; print('MemoryLimit:', h.get('Memory', 0)//1024//1024, 'MB')"

# Kubernetes：检查 OOM
kubectl describe pod <pod_name> | grep -E "OOM|Killed|Exit Code|Reason"
kubectl get events --field-selector reason=OOMKilling 2>/dev/null

# K8s Pod 内存使用
kubectl top pod <pod_name> --containers 2>/dev/null
```

---

## C4. cgroup OOM 根因分析

```bash
# 分析 cgroup 内进程内存分布
CGROUP_PATH="/sys/fs/cgroup/memory/docker/<container_id>"

# 找出 cgroup 内内存占用最高的进程
cat ${CGROUP_PATH}/memory.stat  # 内存统计详情

# cgroup v2 内存统计
cat /sys/fs/cgroup/<cgroup_path>/memory.stat

# 关键指标解读
# cache: page cache（可回收）
# rss: 匿名内存（不可回收）
# mapped_file: 文件映射
# pgfault/pgmajfault: 缺页次数
# active_anon/inactive_anon: 活跃/不活跃匿名页
```

---

## C5. 修复和预防

```bash
# 临时：增加 cgroup 内存限制
echo $((2*1024*1024*1024)) > /sys/fs/cgroup/memory/<path>/memory.limit_in_bytes

# Docker：增加容器内存限制
docker update --memory 2g --memory-swap 2g <container_id>

# K8s：调整 resources.limits.memory

# 预防：启用内存软限制（触发时优先回收，不直接 kill）
echo $((1024*1024*1024)) > /sys/fs/cgroup/memory/<path>/memory.soft_limit_in_bytes

# 监控：定期检查 failcnt
watch -n 5 'find /sys/fs/cgroup/memory -name "memory.failcnt" | xargs grep -l "^[1-9]" 2>/dev/null'
```
