---
name: docker-fault-analysis
description: >
  提供专业的 Docker 容器运维故障分析能力，覆盖内核/系统调用、资源限制（OOM/CPU）、文件系统/存储、网络、权限/安全以及日志/监控等六大故障类别。
  当用户提到任何与 Docker 相关的异常时务必使用此 skill，例如：容器启动失败（Exited/CrashLoopBackOff）、容器频繁重启、服务连不上/网络不通、I/O 卡顿、权限被拒绝（Permission denied）、资源耗尽（OOM）、磁盘写满或挂载失败、端口冲突、Docker daemon 挂死或无响应等。
  即使没有明确提及 "Docker" 而是说到 "容器挂了"、"Pod 异常"、"应用起不来" 且怀疑是底层环境问题时，也应当积极触发本技能进行环境诊断。
---

# Docker 故障分析 Skill

---

## 一、分析方法论（必读，每次诊断前内化）

### 1.1 分层思维模型

故障永远从**宿主机视角**切入，逐层向内收敛，禁止跳层分析：

```
┌─────────────────────────────────────────┐
│  Layer 0：宿主机系统层                   │  ← 优先排查
│  内核版本 / cgroup / namespace / sysctl  │
│  磁盘 / 内存 / CPU / fd 限制             │
├─────────────────────────────────────────┤
│  Layer 1：Docker 引擎层                  │
│  dockerd / containerd / runc             │
│  存储驱动 / 网络驱动 / 日志驱动           │
├─────────────────────────────────────────┤
│  Layer 2：容器运行时层                   │
│  cgroup 配额 / namespace 隔离            │
│  卷挂载 / 端口映射 / 网络接口             │
├─────────────────────────────────────────┤
│  Layer 3：容器应用层                     │  ← 最后排查
│  进程状态 / 应用日志 / 配置文件           │
└─────────────────────────────────────────┘
```

**核心原则**：如果 Layer 0 存在异常，不要急于分析 Layer 3 的应用日志——底层异常会以各种伪装形式传播到上层，误导分析方向。

### 1.2 时间线优先原则

**故障分析的本质是还原事件因果链**。在拿到诊断数据后，第一步是提取所有带时间戳的事件，建立统一时间线：

- `dmesg --time-format iso` 的内核事件
- `journalctl` 的 systemd/docker daemon 事件
- `docker events` 的容器生命周期事件
- 应用日志中的异常时间

将以上事件按时间排列后，**第一个出现的异常通常最接近根因**，后续事件往往是前者的级联反应。

### 1.3 交叉印证原则

单一数据点不足以定论。每个结论至少需要 **3 个独立数据源**印证：

| 结论 | 弱证据（不够） | 强证据（需要） |
|------|------------|-------------|
| OOM 导致重启 | `docker ps` 显示 Exited | dmesg OOM 事件 + ExitCode=137 + cgroup memory.failcnt > 0 |
| SELinux 拦截 | `permission denied` 日志 | audit.log AVC 记录 + scontext/tcontext 匹配 + getenforce=Enforcing |
| 磁盘写满 | `no space left on device` | df -h 100% + docker system df 占用 + inode 使用率 |

### 1.4 排除法的使用

分析过程中，**明确排除**的项与确认的根因同等重要，能显著提升结论可信度：

- 排除时需给出**数据依据**，而非主观判断
- 典型排除逻辑：若 `getenforce` 返回 `Disabled`，则可排除 SELinux 干扰
- 排除项列入最终报告，防止运维人员走弯路

---

## 二、快速分类入口

根据用户描述的症状，**先定位故障类别**，再执行对应诊断脚本：

| 症状关键词 | 故障类别 | 执行脚本 | 优先参考 |
|---|---|---|---|
| overlay mount failed / cgroup not found / 启动失败 | 内核/系统调用 | `scripts/kernel.sh` | `references/kernel_syscall.md` |
| OOM / 频繁重启 / Exited / too many open files | 资源限制 | `scripts/resource.sh` | `references/resource_oom.md` |
| 卷挂载失败 / 写入失败 / I/O 卡顿 / fsck | 文件系统/存储 | `scripts/storage.sh` | `references/storage_overlay.md` |
| ping 不通 / 端口映射失败 / 端口冲突 / veth 异常 | 网络 | `scripts/network.sh` | `references/network_iptables.md` |
| permission denied / SELinux / AppArmor | 权限/安全 | `scripts/security.sh` | `references/security_selinux.md` |
| 日志写失败 / 时间漂移 / NTP / 证书校验 | 日志/监控 | `scripts/logtime.sh` | `references/log_time.md` |
| 症状不明确 / 多类别混合 | 全量采集 | `scripts/full.sh` | 视输出结果决定 |

> **执行方式**：
> 诊断脚本支持多种参数以精准过滤日志和定位问题：
> `bash scripts/xxx.sh -c [container_name_or_id] -k [关键字] -s [开始时间] -e [结束时间]`
> 
> **参数说明**：
> - `-c, --container`  : 指定要分析的容器名称或 ID。
> - `-k, --keyword`    : 过滤日志的关键字（例如 "error", "timeout"）。
> - `-s, --start-time` : 日志查询的开始时间（例如 "2023-10-01 12:00:00" 或 "1 hour ago"）。
> - `-e, --end-time`   : 日志查询的结束时间（例如 "2023-10-01 13:00:00"）。若都不填默认查询过去24小时。
> - `-h, --help`       : 显示脚本的帮助和使用说明。
> 
> *注意：脚本需以 `root` 或 `sudo` 身份运行，输出结构化文本供模型直接分析。*

---

## 三、分析流程（步骤化）

1. **收集症状描述与基础环境信息（必做）**
   - 用户提供容器故障现象、容器名称/ID。
   - 提取关键字：提取关键报错（如 OOM、permission denied）和大概的故障时间点。
   - **第一步必须执行环境采集脚本**，获取 OS/内核、Docker 配置及系统级错误日志的全局快照：
     ```bash
     sudo bash scripts/env_collect.sh -s "2023-10-01 12:00:00" -e "2023-10-01 13:00:00"
     ```
     *(请务必根据用户描述的故障时间，替换为具体的起始和结束时间戳)*

2. **“假设-验证”推导与专项排查**
   - 结合用户输入（是特定容器报错，还是整个 Docker 服务异常）与第一步 `env_collect.sh` 收集到的全局线索。
   - **提出假设**：判断最有可能的故障方向（例如：内核限制、网络冲突、存储耗尽等）。
   - **验证假设**：根据你的假设，跳转到 [第四节：各故障类别](#四各故障类别关键诊断要点) 进行专项排查。
   - 优先使用第四节中对应的专项脚本（如 `resource.sh`, `network.sh` 等）进行验证，确保通过一次脚本调用收集全面信息，避免零散地反复执行单条命令。

3. **读取并解析脚本输出**
   - 脚本会将结果输出到终端或临时文件中，仔细阅读各区块的检查结果。
   - 提取关键报错信息和时间戳。

4. **查阅专家经验库（按需）**
   - 根据脚本抛出的异常点，如果需要更深度的知识（如不理解 overlay2 挂载失败原因），请查阅对应的 `references/*.md`（见第八节）。

5. **根因推导与报告生成**
   - 遵循分层思维，建立时间线，进行多源交叉印证。
   - 输出标准化的诊断报告（参见[第五节：输出报告规范](#五标准输出格式必须遵守)）。

---

## 四、各故障类别：关键诊断要点

> 以下是执行脚本前的**认知框架**，帮助模型在拿到脚本输出后快速聚焦，避免泛读数据。
> 
> **核心原则：** 
> 1. **脚本优先**：在进行分类排查时，**优先执行本目录下对应的预置诊断脚本（如 `scripts/diag_kernel.sh`）**，这些脚本已经封装了该类别下所有关键的收集命令。
> 2. **合并命令**：如果预置脚本未覆盖你需要的特定信息，必须使用 `bash -c "cmd1 && cmd2 && cmd3"` 或 `eval` 的方式一次性执行多条命令，**严禁**一条一条地反复调用命令行工具。

### 4.1 内核/系统调用类

> **推荐使用脚本**：`sudo bash scripts/diag_kernel.sh -c [容器名] -s [开始时间]`

**最高优先看**：
- **内核版本**：确认 overlay2 要求（≥ 4.0）与 cgroup v2 完整支持要求（≥ 4.15）。
- **存储驱动**：确认 Docker 当前使用的存储驱动是否与内核版本匹配。
- **内核日志**：检查是否存在 `call trace` / `BUG:` / `kernel panic` 等关键报错。

**关键判断逻辑**：
- 若报 `overlay: filesystem not supported`，需确认 overlay 模块是否已被内核加载。
- 对于 CentOS 7 + XFS 的环境，必须确认 XFS 的 `ftype` 特性是否开启（`ftype=0` 是 overlay2 的致命缺陷）。
- SELinux 在 `Enforcing` 模式下导致的权限问题，需第一时间查看系统的 AVC（审计拒绝）日志。
- `seccomp` 阻断通常表现为容器退出码（ExitCode）为 159（128+31，SIGSYS）。

**常见误判**：将 SELinux 阻断当成普通文件权限问题。此时即便普通权限看似正常，安全上下文标签的不匹配也会导致挂载或读写失败。

### 4.2 资源限制类

> **推荐使用脚本**：`sudo bash scripts/diag_resource.sh -c [容器名] -s [开始时间]`

**最高优先看**：
- **OOM 事件**：检查内核日志确认是否存在 OOM。若包含 `constraint=CONSTRAINT_MEMCG`，说明是容器内存限制触发而非宿主机全局 OOM。
- **容器退出状态**：检查容器 Inspect 信息，ExitCode=137 且 OOMKilled=true 是容器被 OOM 强杀的铁证。
- **磁盘与 Inode**：磁盘空间和 inode 必须双重检查。inode 耗尽时即便磁盘容量充足也会导致写入失败。

**关键判断逻辑**：
- 频繁重启容器：**先看 ExitCode**。137=SIGKILL(OOM/强杀)，1=应用内部错误退出，143=SIGTERM(正常停止)，139=SIGSEGV(段错误)。
- Java 容器 OOM 高发原因：老版本 JVM 未感知容器内存限制，默认按宿主机物理内存计算 Xmx（JDK < 8u191 无容器感知）。
- 报 `too many open files`：不仅要检查系统的句柄限制，还要检查 `dockerd` 进程自身的 fd 限制。
- 磁盘满时优先清理顺序：无用资源清理（`docker system prune`） → 容器超大日志截断 → 悬空卷清理。

**常见误判**：磁盘写满但容量使用率未到 100%。此时应检查是否 inode 耗尽，或检查是否有进程仍持有已删除文件的句柄（处于 deleted 状态的僵尸文件）。

### 4.3 文件系统/存储类

> **推荐使用脚本**：`sudo bash scripts/diag_storage.sh -c [容器名] -s [开始时间]`

**最高优先看**：
- **挂载状态**：检查系统 overlay 挂载数是否等于运行中容器数，数量不一致通常意味着存在僵尸挂载或挂载失败。
- **文件系统错误**：检查内核日志是否存在磁盘硬件故障、I/O error 或文件系统损坏报错。
- **I/O 性能**：分析磁盘 I/O 负载状况（如利用率和延迟），确认是否存在读写瓶颈。

**关键判断逻辑**：
- 容器内写入卷失败但路径存在 → 需按三步排查：① 基础 Linux 读写权限；② SELinux 安全上下文标签；③ 容器内运行进程的 UID 与宿主机目录 owner 的 UID 是否匹配。
- overlay2 I/O 卡顿：通常由于大量小文件写入触发 CoW (写时复制) 放大导致。数据库或高频日志文件**禁止**存放在容器层，必须使用 Volume 或 bind mount。
- 读日志或执行命令卡住报错 → 优先检查该容器对应的 overlay2 `merged` 目录是否处于正常挂载状态。

**常见误判**：容器内报 `read-only file system` 时，不一定是数据卷配置错误，很可能是 overlay2 所在的基础文件系统（宿主机分区）已经写满，或因底层故障被内核强制以 ro（只读）模式重新挂载。

### 4.4 网络类

> **推荐使用脚本**：`sudo bash scripts/diag_network.sh -c [容器名] -s [开始时间]`

**最高优先看**：
- **内核转发开关**：检查系统的 `ip_forward` 是否开启（必须为 1），若关闭会导致所有容器的路由转发功能失效。
- **防火墙规则**：检查防火墙的 `DOCKER` 链及 `nat` 表是否存在，规则是否完整。
- **端口占用**：检查宿主机的网络监听状态，确认需映射的端口是否已被其他进程绑定。

**关键判断逻辑**：
- 容器网络突然全局中断 → 优先怀疑系统防火墙重载（如 `firewalld reload`）清空了 Docker 自动注入的 iptables 规则。
- 容器间无法互通 → 检查它们是否位于**同一个 network** 内（注意：Docker 默认的 `bridge` 网络不支持基于容器名的 DNS 解析）。
- 端口映射失败但未发现端口冲突 → 重点检查内核参数 `net.ipv4.ip_forward` 以及网桥相关拦截配置。
- 报 `cannot allocate network interface` → 检查宿主机的 netns（网络命名空间）文件描述符数量，排查是否存在 netns 泄漏。

**常见误判**：容器能 ping 通宿主机，但无法 ping 通外网。此时不要盲目排查外部网络，应首先检查主机的 NAT `MASQUERADE`（源地址伪装）规则是否丢失。

### 4.5 权限/安全类

> **推荐使用脚本**：`sudo bash scripts/diag_security.sh -c [容器名] -s [开始时间]`

**最高优先看**：
- **SELinux 状态与日志**：确认 SELinux 是否处于强制拦截模式（Enforcing）。若开启，必须优先检查审计日志（AVC）中是否有明确的拒绝记录，重点关注安全上下文匹配情况。
- **Socket 权限**：检查 Docker 守护进程 Unix Socket 的属主和读写权限，确认调用用户是否属于合法用户组。

**关键判断逻辑**：
- 出现 `permission denied` 但常规 Linux 读写权限（rwx）完全正常 → **高度怀疑是 SELinux 拦截**，需比对宿主机目录与容器的 SELinux 标签。
- 数据卷挂载时报权限拒绝 → 若由 SELinux 导致，可通过在挂载参数追加 `:z`（共享标签）或 `:Z`（私有标签）解决，或手动修复宿主机目录标签。
- 容器内进程 UID 与宿主机映射目录 owner 发生错位 → 并非底层权限故障，而是 Docker 用户映射（User Namespace / runAsUser）配置问题。

**常见误判**：普通用户执行 docker 命令报权限不足时，图省事直接修改 `/var/run/docker.sock` 为 777 权限（极高安全风险）。正确做法是将该用户加入系统 `docker` 组。

### 4.6 日志/监控类

> **推荐使用脚本**：`sudo bash scripts/diag_logtime.sh -c [容器名] -s [开始时间]`

**最高优先看**：
- `timedatectl` + `chronyc tracking`：时间同步状态，`System time` 偏移 > 1s 需警惕，> 60s 会导致 TLS/JWT 失效
- `find /var/lib/docker/containers/ -name "*.log" -size +500M`：超大日志文件定位
- `openssl x509 -noout -dates -in <cert>`：证书有效期

**关键判断逻辑**：
- 任务调度失效/证书校验失败突然出现 → **第一时间检查时间漂移**，VM 挂起恢复是高发场景
- 日志磁盘写满级联故障：单容器日志爆增 → 分区写满 → 其他容器写入失败 → docker daemon 元数据写失败 → 大规模故障
- `docker logs` 输出正常但监控系统无数据 → 检查日志驱动（`docker info | grep "Logging Driver"`），若改为 `syslog`/`journald`，`docker logs` 命令将不可用

**常见误判**：时区配置错误被误判为时间漂移 → `date` 命令输出时区与业务预期对齐，`timedatectl` 显示 UTC 时间正常，问题是容器 `TZ` 环境变量未设置。

---

## 五、诊断结论格式（强制输出）

**每次诊断必须严格按此格式输出，任何字段不得省略**：

```
## 故障诊断报告

**故障根因**：[一句话，明确到具体原因，例如："XFS 分区 ftype=0 不支持 overlay2 d_type 特性"]
**故障组件**：[具体到组件层级，例如："宿主机 /dev/sdb1 XFS 文件系统 → overlay2 存储驱动 → 所有容器"]
**故障时间**：[从日志中提取的最早异常时间戳，注明数据来源]

**故障链时间线**：
  T1 [精确时间] → [触发事件/变更，标注数据来源]
  T2 [精确时间] → [因T1导致的中间事件]
  T3 [精确时间] → [最终故障表现]
  （时间线必须有因果关系，不能只是事件列表）

**已排除项**：
  - [候选原因A]：排除依据：[具体数据，如 "getenforce 返回 Disabled，排除 SELinux"]
  - [候选原因B]：排除依据：[具体数据]
  （至少列出 2 个排除项，体现分析严谨性）

**为什么确定是此问题**：
  1. [数据点1]：[具体数值/日志片段，说明指向根因]
  2. [数据点2]：[具体数值/日志片段，说明指向根因]
  3. [数据点3]：[具体数值/日志片段，说明指向根因]
  （三点独立数据交叉印证，禁止使用推测性语言）

**修复建议**：
  1. 【立即】[当前可执行的临时恢复操作]
  2. 【根治】[消除根因的永久性修复方案]
  3. 【预防】[防止同类问题复发的加固措施]
```

---

## 六、高危场景速查（经验积累）

以下是运维现场最容易误判、耗时最长的场景，遇到时优先对照排查：

| 高危场景 | 表面现象 | 真实根因 | 快速验证 |
|---------|---------|---------|---------|
| CentOS 7 + XFS + Docker 升级 | 所有容器启动失败 | XFS ftype=0 不支持 overlay2 | `xfs_info \| grep ftype` |
| firewalld reload 后网络中断 | 容器网络全断，但 `docker ps` 正常 | Docker iptables 规则被清空 | `iptables -L DOCKER -n` |
| VM 挂起恢复后服务异常 | JWT/TLS 校验失败、cron 乱序 | 时钟跳变未及时修正 | `chronyc tracking` 看偏移量 |
| Java 容器 OOM 循环重启 | 容器反复 Exited(137) | JVM Xmx 未感知 cgroup 限制 | `docker inspect \| grep Memory` vs JVM 参数 |
| SELinux 拦截卷写入 | `ls -la` 权限正常，写入 denied | SELinux 标签不匹配 | `ls -laZ` + `ausearch -m AVC` |
| 磁盘 inode 耗尽 | `df -h` 空间充足但无法创建文件 | inode 耗尽（小文件过多） | `df -i` |
| 日志文件占满磁盘级联 | 多容器同时故障 | 单容器日志无限增长 | `find /var/lib/docker/containers -name "*.log" -size +1G` |
| 容器 pid 1 非前台进程 | 容器立即退出 ExitCode=0 | 启动脚本后台化，pid 1 退出 | `docker inspect \| grep -A5 "Cmd\|Entrypoint"` |

---

## 七、脚本说明

所有脚本位于 `scripts/` 目录，使用 bash + Python 原生库，**不依赖第三方包**，兼容 CentOS 7/8/9、EulerOS/OpenEuler。

| 脚本 | 采集内容 |
|------|---------|
| `kernel.sh` | 内核版本、cgroup/namespace、sysctl 参数、SELinux/audit 日志 |
| `resource.sh` | CPU/内存/OOM 事件、磁盘空间+inode、fd 限制、cgroup 配额 |
| `storage.sh` | 卷挂载权限、overlay2 层状态、iostat、磁盘错误 |
| `network.sh` | iptables 规则、bridge/veth 接口、端口占用、网络命名空间 |
| `security.sh` | docker 用户组、SELinux AVC 日志、AppArmor、audit 事件 |
| `logtime.sh` | 容器日志大小、NTP/时间同步偏移、证书时效 |
| `full.sh` | 调用以上所有模块，输出保存至 `/tmp/docker_diag_<timestamp>.txt` |

---

## 八、参考资料（按需加载）

> 拿到脚本输出后，若需要更深入的专家经验，按需读取以下文件：

- `references/kernel_syscall.md` — overlay 挂载、cgroup、SELinux 策略、内核参数调优
- `references/resource_oom.md` — OOM 日志解读、ExitCode 含义、fd 限制修复、磁盘清理顺序
- `references/storage_overlay.md` — overlay2 原理、CoW 性能问题、设备映射、fsck 操作
- `references/network_iptables.md` — Docker iptables 规则结构、firewalld 冲突、NAT 调试
- `references/security_selinux.md` — AVC 日志解读、标签修复命令、策略生成、capability 管理
- `references/log_time.md` — 日志驱动对比、NTP 跳变处理、证书校验、时区问题