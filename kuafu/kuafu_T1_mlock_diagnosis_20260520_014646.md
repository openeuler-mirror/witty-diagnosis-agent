# 诊断任务 T1：mlock 超限故障诊断报告

## 基本信息
- **Plan 文件**: `G:\witty-diagnosis-agent\dayu\plans\20260520_014646_mlock_overlimit.md`
- **任务 ID**: T1
- **获取时间**: 2026-05-20 01:46:46
- **目标容器**: mmap-f3 (Container ID: ec5b4fcb511f)
- **目标用户**: tu (uid=1000)

---

## 1. 系统环境

| 项目 | 值 |
|------|------|
| 容器 OS | Ubuntu 22.04.5 LTS (Jammy) |
| 内核版本 | 6.6.87.2-microsoft-standard-WSL2 (x86_64) |
| 容器运行时间 | ~32 分钟 (Up 32 minutes) |
| 总内存 | 15986876 kB (~15.2 GB) |
| 可用内存 | 14877552 kB (~14.2 GB) |

---

## 2. RLIMIT_MEMLOCK 限制检查

### tu 用户限制（通过 `ulimit -l`）
| 限制类型 | 值 | 转换 |
|---------|-----|------|
| 软限制 (soft) | **8 KB** | 8192 bytes |
| 硬限制 (hard) | **8 KB** | 8192 bytes |

### 容器 root 用户限制
| 限制类型 | 值 |
|---------|-----|
| Max locked memory | **unlimited** |

### 配置来源
发现 `/etc/security/limits.conf` 中明确配置了 tu 用户的 memlock 限制：
```
tu soft memlock 8
tu hard memlock 8
```

### Docker 容器 ulimit 配置
`docker inspect` 显示容器未设置额外的 ulimit（`HostConfig.Ulimits: []`），限制完全来自 `/etc/security/limits.conf`。

---

## 3. mlock 调用测试结果

### 测试代码
C 程序调用 `mlock(addr, 9216)`（9 KB），并在 tu 用户上下文中执行。

### 执行结果
```
mlock(9216 bytes) returned: -1, errno=12 (Cannot allocate memory)
RLIMIT_MEMLOCK: soft=8192 hard=8192
```

### 结论
- **请求锁定**: 9 KB (9216 bytes)
- **软限制**: 8 KB (8192 bytes)
- **结果**: mlock 返回 **-1**，errno=**12 (ENOMEM)**
- **状态**: ✅ **成功复现故障** — 请求锁定量 (9KB) 超出 RLIMIT_MEMLOCK 软限制 (8KB)

---

## 4. 系统 Mlocked 统计

| 指标 | 值 |
|------|-----|
| Mlocked | 0 kB |
| Unevictable | 0 kB |

系统当前未被锁定的任何内存页面，说明所有 mlock 尝试均已失败（均被限制拦截）。

---

## 5. 内核日志检查

执行 `dmesg -T | grep -i "mlock\|RLIMIT_MEMLOCK\|locked memory"`：

**结果**: 未找到相关记录。

说明 mlock 被 `RLIMIT_MEMLOCK` 拒绝时，内核不会主动在 dmesg 中产生日志记录（这是一个常见的"静默拒绝"行为）。

---

## 6. tu 用户完整资源限制

| 限制 | 软限制 | 硬限制 |
|------|--------|--------|
| locked memory | **8 KB** | **8 KB** |
| time | unlimited | unlimited |
| file | unlimited | unlimited |
| data | unlimited | unlimited |
| stack | 8192 KB | 8192 KB |
| memory | unlimited | unlimited |
| process | unlimited | unlimited |
| nofiles | 1024 | 1024 |
| vmemory | unlimited | unlimited |

---

## 7. 诊断结论

### 故障根因
```
[配置状态] RLIMIT_MEMLOCK = 8KB（通过 /etc/security/limits.conf 配置）
    ↓
[触发动作] tu 用户进程调用 mlock(9KB)
    ↓
[限制碰撞] 请求锁定量 9KB > RLIMIT_MEMLOCK 8KB
    ↓
[系统响应] mlock 返回 -1，errno=12 (ENOMEM / Cannot allocate memory)
```

### 直接原因
tu 用户 RLIMIT_MEMLOCK 软限制为 **8KB**，而进程请求锁定 **9KB**，超出限制导致 `mlock()` 返回 `ENOMEM`。

### 根本原因
`/etc/security/limits.conf` 中 tu 用户的 memlock 配置值（8KB）过小，小于业务所需的内存锁定量（9KB）。

### 修复建议

**临时措施**：
1. 增大 tu 用户的 memlock 限制：
   ```
   # 在 /etc/security/limits.conf 中修改
   tu soft memlock 64
   tu hard memlock 64
   ```
   或通过 `prlimit` 动态调整（需 root 权限）：
   ```
   docker exec -u root mmap-f3 prlimit --pid <PID> --memlock=65536:65536
   ```

**永久措施**：
1. 在容器镜像构建或 Docker Compose 中提前配置合适的 memlock 值
2. 若使用 `docker run`，可通过 `--ulimit memlock=<soft>:<hard>` 参数设置：
   ```
   docker run --ulimit memlock=65536:65536 ...
   ```

**预防措施**：
1. 监控 `/proc/meminfo` 中的 `Mlocked` 值，确保未接近限制
2. 在 CI/CD 中增加 mlock 容量测试
