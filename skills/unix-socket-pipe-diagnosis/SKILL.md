---
name: unix-socket-pipe-diagnosis
description: >
  Unix Domain Socket（UDS）与匿名管道（Pipe）故障诊断技能。当用户提到
  UDS 连接拒绝、ECONNREFUSED、EADDRINUSE、socket 文件权限错误、管道阻塞、
  SIGPIPE 进程退出、socketpair 泄漏、SO_PASSCRED 凭证传递失败、
  EACCES、connect 失败、pipe write 卡住 D 状态等关键词时，
  必须使用本技能。覆盖场景：UDS listen backlog 满、abstract socket 冲突、
  socket 文件权限拒绝、管道缓冲区满写阻塞、SIGPIPE 未处理进程退出、
  socketpair FD 泄漏、SCM_RIGHTS 凭证传递异常。
  即使只收到"连接不上"、"进程卡住"、"消息发不出"但怀疑 UDS/pipe 相关时
  也应触发本技能。
---

# Unix Domain Socket 与管道故障诊断（三层下钻：系统层 → 类型层 → 代码根因层）

## 第一节：故障目录结构

```text
uds_pipe_case/             # 故障案例目录
├── scripts/               # 【内置】本技能的诊断脚本
│   ├── 01_baseline_info.sh
│   ├── branch_A_uds_backlog.sh
│   ├── branch_B_abstract_conflict.sh
│   ├── branch_C_credential_fail.sh
│   ├── branch_D_socket_perm.sh
│   ├── branch_E_pipe_block.sh
│   ├── branch_F_sigpipe.sh
│   └── branch_G_socketpair_leak.sh
├── logs/                  # 【可选】应用日志
│   ├── app.log
│   └── dmesg_output.txt
├── procfs_snapshot/       # 【可选】故障时刻的 /proc 快照
│   ├── net_unix.txt       # cat /proc/net/unix
│   ├── pipe_max_size.txt  # cat /proc/sys/fs/pipe-max-size
│   └── pid_status.txt     # cat /proc/<PID>/status
└── report/                # 【输出】诊断报告目录
```

```bash
# 检查 UDS listen socket 列表
ss -xl
```

---

## 第二节：分析策略（三层下钻，逐层收敛）

UDS 与管道故障诊断采用**三层下钻模型**，从最外层逐层深入，层间存在依赖关系：

```
┌─────────────────────────────────────────────────────────────────┐
│                   三层下钻分析模型                                 │
│                                                                 │
│   L1: 系统层              ss -xl / /proc/net/unix / dmesg       │
│       └─ 判断：系统 UDS/pipe 整体状态是否异常？                  │
│                                                                 │
│   L2: 类型层              ss -xp / lsof -U / ls -la socket       │
│       └─ 判断：是 UDS backlog 满？abstract 冲突？权限问题？       │
│             pipe 阻塞？SIGPIPE？socketpair 泄漏？                 │
│                                                                 │
│   L3: 代码根因层          strace / fcntl / signal 分析 / 源码审查│
│       └─ 判断：哪段代码 backlog 设太小？哪段没关 pipe 写端？       │
│                                                                 │
│            ↓                                     ↓              │
│      基线脚本(01) → 分支决策 → 分支脚本(A~G) → 交叉验证 → 报告   │
└─────────────────────────────────────────────────────────────────┘
```

| 层级 | 分析内容 | 核心命令 | 典型发现 |
|------|---------|---------|---------|
| **L1** | 系统 UDS/pipe 水位 | `ss -xl \| wc -l`、`cat /proc/net/unix` | listen socket Recv-Q 堆积 > 0 |
| **L2** | 类型定位 | `ss -xp`、`lsof -U`、`ls -la` socket 文件 | UDS backlog 满 / abstract 冲突 / pipe D 状态 |
| **L3** | 代码根因 | `strace -e trace=bind,listen,accept,connect`、`fcntl F_GETPIPE_SZ` | backlog 设 1、pipe buffer 4K 太小、缺 SIGPIPE handler |

**何时逐层完整执行**：出现 UDS/pipe 相关拒绝/阻塞/退出错误时，三层必须全部检查。

**何时跳到 L2/L3**：已明确目标进程且故障类型已知时，可从 L2 直接切入。

---

## 第三节：统一分析流程（基线采集 → 分支决策 → 逐层下钻 → 根因定位 → 交叉验证 → 输出）

### Step 1：启动（基线信息采集 + 分支推荐）

运行：

```bash
bash scripts/01_baseline_info.sh [target_pid] [socket_path_or_pipe_id]
```

记录输出中的四类关键信息（后续所有步骤围绕它们推进）：

- 系统 UDS/pipe 状态：`ss -xl` listen socket 列表、Recv-Q/Send-Q 水位
- 目标进程信息：PID、进程名、FD 中 UDS/pipe 数量、socket 文件路径
- UDS/pipe 类型分布：listen socket / established / abstract / pipe / socketpair 各占多少
- 异常线索：Recv-Q 堆积、权限错误、D 状态进程、SIGPIPE 相关退出

### Step 2：故障类型定界（选择分支脚本一键跑）

按 Step 1 输出推荐，执行对应分支脚本：

```bash
bash scripts/branch_X_xxx.sh [target_pid] [socket_path]
```

脚本对应执行参考：

```
基线信息
  ├─ Recv-Q > 0 且 listen backlog 小               → 分支A: UDS listen backlog 满
  ├─ EADDRINUSE 错误 / ss 显示双绑定 @address       → 分支B: Abstract socket 冲突
  ├─ recvmsg 收不到 cmsg / ss -xp 无凭证            → 分支C: 凭证传递失败
  ├─ EACCES 错误 / socket 文件权限 000              → 分支D: 文件权限拒绝
  ├─ 进程 D 状态 / wchan=pipe_wait / write 卡住     → 分支E: 管道缓冲区满
  ├─ 进程意外退出无 core / dmesg 无异常              → 分支F: SIGPIPE 未处理退出
  └─ anon_unix FD 持续增长 / lsof 计数增加           → 分支G: socketpair 泄漏
```

若 Step 1 输出推荐多个分支脚本，必须按输出顺序全部执行，不可只选其一。

### Step 3：L1 系统层分析（回答"系统 UDS/pipe 整体状态是否异常"）

在分支脚本输出基础上，完成并固化证据链：

- V1 UDS 全局概况：`ss -x` 显示所有 UDS socket 数量，listen / established / closed 分布
- V2 内核 UDS 表检查：`cat /proc/net/unix` 各 socket 的 Flags、State、Recv-Q
- V3 系统 pipe 参数检查：`cat /proc/sys/fs/pipe-max-size`、`pipe-user-pages-soft`
- V4 dmesg 检查：`dmesg | grep -E "unix|pipe|socket"` 是否有相关告警

输出（供后续交叉验证使用）：

```
UDS socket 总数：<N>
listen socket 数：<N_listen>  Established：<N_est>
Recv-Q 异常 socket：<N>  Send-Q 异常：<N>
pipe-max-size：<N> bytes
dmesg 告警：[有/无]
趋势判断：[正常/异常/恶化中]
```

### Step 4：L2 类型层分析（回答"具体是哪类 UDS/pipe 故障"）

原则：逐类型排查，定位故障分类。

#### 4.1 UDS listen socket 检查

```bash
ss -xl | head -30
ss -x state listening
```

#### 4.2 UDS 进程凭证检查

```bash
ss -xp | head -30
```

#### 4.3 Abstract socket 检查

```bash
ss -xl | grep @
lsof -U | grep ABSTRACT
```

#### 4.4 Socket 文件权限检查

```bash
ls -la /path/to/socket.sock
stat /path/to/socket.sock
getfacl /path/to/socket.sock
```

#### 4.5 进程 FD 中 socket/pipe 分布

```bash
ls -la /proc/<PID>/fd/ | grep -E "socket|pipe"
lsof -p <PID> | grep -E "unix|pipe"
```

#### 4.6 D 状态进程检查

```bash
ps aux | awk '$8 ~ /D/ {print $2, $11, $8}'
cat /proc/<PID>/wchan
```

#### 4.7 SIGPIPE 信号处理检查

```bash
cat /proc/<PID>/status | grep -E "SigIgn|SigCgt"
```

### Step 5：L3 代码根因层（分支脚本自动执行）

各分支脚本内置了 L3（代码根因回溯）的命令序列。按 Step 2 推荐的脚本逐分支执行，每个分支脚本输出：

```
## 分支 <X> 诊断结论

### L2 类型层（故障分类定位）
  故障类型：<UDS backlog / abstract 冲突 / 凭证失败 / 权限拒绝 / pipe 阻塞 / SIGPIPE / socketpair 泄漏>
  关键指标：<Recv-Q=N / EADDRINUSE / EACCES / D 状态 / SIGPIPE 退出>
  异常范围：<进程/全局>
  判定：[正常/可疑/确认]

### L3 根因层（代码级回溯）
  strace 追踪结果：
    bind(backlog=<N>)：<N>
    listen() 结果：<success/fail>
    pipe() 调用次数：<N>
    write() 阻塞：<count>
    socketpair()/close() 对比：<N/M>
  调用栈线索（如果可用）：
    <从 strace / /proc/PID/stack 获取的调用栈>
  根因假设：<一句话根因推断>
```

### Step 6：交叉验证与最终输出

对每条证据做对齐检查：

| 验证维度 | L1 系统层 | L2 类型层 | L3 根因层 | 是否吻合？ |
|---------|-----------|-----------|-----------|-----------|
| 故障范围 | 全局异常 | 确认类型 | 代码路径确认 | □ 吻合 □ 不符 |
| 异常指标 | Recv-Q 堆积 | 对应类型异常 | 系统调用验证 | □ 吻合 □ 不符 |
| 根因定位 | - | 分类定位 | 缺陷代码确认 | □ 吻合 □ 不符 |

置信度收敛：

- **高**：三层完全吻合 + 反事实验证通过（如 strace 确认 backlog 设 1）
- **中**：两层吻合，一层依赖推断
- **低**：两层及以上依赖推断，或各层结论存在矛盾
- **疑似内核/平台Bug**：用户态证据链完整但无法在应用层定位到缺陷代码

将 Step 3/4/5 的输出填入第九节报告结构，并显式写清：结论、证据链、修复建议、验证建议。

执行约束：所有分析脚本的默认超时时间为 **3 分钟（180s）**。

---

## 第四节：L1 系统层分析（已合并进第三节 Step 3）

本节内容已合并进第三节的统一流程（Step 3）。

---

## 第五节：L2 类型层分析（已合并进第三节 Step 4）

本节内容已合并进第三节的统一流程（Step 4）。

---

## 第六节：L3 代码根因层（已合并进第三节 Step 5）

本节内容已合并进第三节的统一流程（Step 5）。

---

## 第七节：交叉验证与结论收敛（已合并进第三节 Step 6）

本节内容已合并进第三节的统一流程（Step 6）。

---

## 第八节：故障类型决策树（已合并进第三节 Step 2）

本节内容已合并进第三节的统一流程（Step 2）。

---

## 第九节：最终报告结构

```
## UDS / Pipe 故障诊断报告

### 会话信息
  会话 ID：<session_id>
  分析时间：<timestamp>
  目标 PID：<pid>（<process_name>）
  目标 socket/pipe：<socket_path / pipe_id>
  分析层级：[L1+L2+L3 | L2+L3 | ...]

### 故障概要与置信度
  故障模式：<UDS backlog满 / Abstract冲突 / 凭证失败 / 权限拒绝 / pipe阻塞 / SIGPIPE / socketpair泄漏>
  置信度：<高/中/低>
  分析轨道：[三层下钻 | 两层]

### L1 系统层结论
  UDS socket 总数：<N>
  listen / established：<L> / <E>
  Recv-Q 异常数：<N>
  dmesg 告警：[有/无]
  pipe 系统参数：<pipe-max-size=N>
  趋势判断：[正常/异常/恶化中]

### L2 类型层结论
  故障类型：<已确认的故障分类>
  关键证据：
    - Recv-Q 最大值：<N>
    - Socket 文件权限：<permission>
    - D 状态进程数：<N>
    - SIGPIGN 掩码：<SigIgn=SigCgt=>
  异常进程 FD 分布：
    - UDS socket：<N>
    - pipe：<N>
    - socketpair：<N>
  判定：[正常/可疑/已确认]

### L3 根因层结论
  strace 系统调用分析：
    bind()：<call_count>
    listen(backlog=<N>)：<call_count>
    accept()：<call_count>
    connect()：<call_count>
    pipe()：<call_count>
    write() 阻塞：<count>
    socketpair()：<N>  close()：<M>  差值：<N-M>
  根因代码路径（如有）：<文件:行号 / 函数名 / 调用链>
  根因假设：<一句话描述>

### 交叉验证结果
  L1↔L2 吻合：□ 是  □ 否（差异说明：<...>）
  L2↔L3 吻合：□ 是  □ 否（差异说明：<...>）
  综合判断：<各层结论是否一致>

### 完整因果链
  [根因代码缺陷] → [UDS/pipe 操作异常] → [连接拒绝/阻塞/退出]
  → [业务影响] → [用户/监控告警]

### 排除的替代假设
  - <假设X>：排除原因 <...>

### 修复建议
  立即处置：
    <增大 backlog / 修复权限 / kill D 状态进程 / 调整 pipe buffer / 添加 SIGPIPE handler 等>
  根本修复：
    <修改代码 backlog 参数 / 加锁防止 abstract 冲突 / 添加 SO_PASSCRED 设置 / 
     保证 socketpair 两端 close / 注册 SIGPIPE handler>
  验证方法：
    <修复后 strace 确认 / ss 确认 Recv-Q 下降 / 测试无 D 状态 / 确认无意外退出>
```

---

## 第十节：参考文件

- `references/unix_socket_pipe_commands.md`：UDS / Pipe 诊断命令速查（ss/lsof/strace/procfs）
- `references/unix_socket_pipe_patterns.md`：UDS / Pipe 故障模式目录（9 种已知模式）
- `references/unix_socket_pipe_params.md`：UDS / Pipe 内核参数调优参考
