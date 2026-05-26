---
name: fd-leak-diagnosis
description: >
  文件描述符（FD）泄漏诊断技能。当用户提到 Too many open files、EMFILE、ENFILE、
  CLOSE_WAIT 堆积、epoll FD 泄漏、inotify watch 超限、文件句柄耗尽、file-nr 接近上限、
  VFS file-max limit reached、ENOSPC (file watchers)、ulimit 超限等关键词时，
  必须使用本技能。覆盖场景：进程 FD 逼近 ulimit 上限、Socket CLOSE_WAIT 堆积、
  epoll 实例泄漏、系统级 FD 耗尽（/proc/sys/fs/file-nr 告警）、inotify watch 泄漏、
  已删除文件仍被进程占用、strace 显示 open/close 严重不匹配的混合复杂泄漏。
  即使只收到 "连接不上"、"服务崩了"、"应用报错" 但怀疑 FD 相关时也应触发本技能。
  支持 FD 泄漏全路径分析（系统 → 进程 → FD 类型 → 代码级根因）。
---

# 文件描述符泄漏诊断（多层下钻：系统 → 进程 → FD 类型 → 代码根因）

## 第一节：故障目录结构

```text
fd_leak_case/             # 故障案例目录
├── scripts/              # 【内置】本技能的诊断脚本
│   ├── 01_baseline_info.sh
│   ├── branch_A_system_fd.sh
│   ├── branch_B_process_fd.sh
│   ├── branch_C_close_wait.sh
│   ├── branch_D_epoll.sh
│   ├── branch_E_inotify.sh
│   ├── branch_F_syscall.sh
│   ├── branch_G_deleted_file.sh
│   └── branch_H_mixed.sh
├── logs/                 # 【可选】应用日志
│   ├── app.log
│   └── dmesg_output.txt
├── procfs_snapshot/      # 【可选】故障时刻的 /proc 快照
│   ├── file-nr.txt       # cat /proc/sys/fs/file-nr
│   ├── file-max.txt      # cat /proc/sys/fs/file-max
│   └── pid_limits.txt    # cat /proc/<PID>/limits
└── report/               # 【输出】诊断报告目录
```

```bash
# 检查系统 FD 水位
cat /proc/sys/fs/file-nr
```

---

## 第二节：分析策略（四层下钻，逐层收敛）

FD 泄漏诊断采用**四层下钻模型**，从最外层逐层深入，层间存在依赖关系：

```
┌─────────────────────────────────────────────────────────────────┐
│                   四层下钻分析模型                                 │
│                                                                 │
│   L1: 系统层              /proc/sys/fs/file-nr                  │
│       └─ 判断：是否系统级 FD 耗尽？                              │
│                                                                 │
│   L2: 进程层              ps + /proc/PID/fd + ulimit            │
│       └─ 判断：哪个进程在泄漏？泄漏什么类型 FD？                  │
│                                                                 │
│   L3: FD 类型层           ss + lsof + 分支脚本                  │
│       └─ 判断：socket/pipe/epoll/inotify/regular file 哪个在漏？ │
│                                                                 │
│   L4: 代码根因层          strace + valgrind + 调用栈回溯         │
│       └─ 判断：哪段代码没调用 close() / 哪条路径漏了清理？        │
│                                                                 │
│            ↓                                     ↓              │
│      基线脚本(01) → 分支决策 → 分支脚本(A~H) → 交叉验证 → 报告   │
└─────────────────────────────────────────────────────────────────┘
```

| 层级 | 分析内容 | 核心命令 | 典型发现 |
|------|---------|---------|---------|
| **L1** | 系统 FD 水位 | `cat /proc/sys/fs/file-nr` | file-nr 第一列 / 第三列 > 80% |
| **L2** | 进程 FD 排行 | `ls -1 /proc/PID/fd \| wc -l` | 某进程 FD 数量与 ulimit 比例 > 80% |
| **L3** | FD 类型分布 | `lsof -p PID \| awk '{print \$5}' \| sort \| uniq -c \| sort -rn` | IPv4 socket 占 85%，或 eventpoll 占多数 |
| **L4** | 系统调用对比 | `strace -p PID -e trace=open,openat,close -c` | openat (10000) >> close (9500)，差 500 |

**何时逐层完整执行**：出现 FD 告警/错误时，四层必须全部检查。
**何时跳到 L3/L4**：已明确目标进程且 FD 类型已知时，可从 L3 直接切入。

---

## 第三节：统一分析流程（基线采集 → 分支决策 → 逐层下钻 → 根因定位 → 交叉验证 → 输出）

### Step 1：启动（基线信息采集 + 分支推荐）

运行：

```bash
bash scripts/01_baseline_info.sh [target_pid] [target_process_name]
```

记录输出中的四类关键信息（后续所有步骤围绕它们推进）：

- 系统 FD 水位：`/proc/sys/fs/file-nr` 三列值、`/proc/sys/fs/file-max`
- 目标进程信息：PID、进程名、FD 总数、ulimit 软/硬限制
- FD 类型分布：socket / regular file / eventpoll / inotify / pipe 各占多少
- 异常线索：CLOSE_WAIT 数量、inotify watch 用量、strace 中 open/close 比例

### Step 2：故障类型定界（选择分支脚本一键跑）

按 Step 1 输出推荐，执行对应分支脚本：

```bash
bash scripts/branch_X_xxx.sh [target_pid] [target_process_name]
```

脚本对应执行参考：

```
基线信息
  ├─ file-nr 使用率 > 80%                        → 分支A: 系统级 FD 耗尽
  ├─ 某进程 FD 数 > ulimit * 80% 且持续增长        → 分支B: 进程级 FD 泄漏
  ├─ CLOSE_WAIT 数量 > 1000 或持续增长            → 分支C: Socket FD 泄漏 (CLOSE_WAIT)
  ├─ eventpoll FD 数量 > 预期（通常 1-2 个）       → 分支D: epoll FD 泄漏
  ├─ inotify watch > max_user_watches * 80%       → 分支E: inotify watch 泄漏
  ├─ strace 显示 open > close                     → 分支F: 系统调用级 FD 泄漏
  ├─ lsof +L1 有已删除但未关闭的文件              → 分支G: 已删除文件 FD 泄漏
  └─ 混合现象或以上分支无法覆盖                    → 分支H: 混合/复杂 FD 泄漏
```

若 Step 1 输出推荐多个分支脚本，必须按输出顺序全部执行，不可只选其一。

### Step 3：L1 系统层分析（回答"系统 FD 水位是否危险"）

在分支脚本输出基础上，完成并固化证据链：

- V1 系统 FD 概况：`file-nr` 已分配 / 空闲 / 最大，`file-max` 系统上限
- V2 内核告警检查：`dmesg | grep "VFS: file-max limit"` 是否有耗尽记录
- V3 关键限制检查：`/proc/sys/fs/inotify/max_user_watches`、`max_user_instances`
- V4 趋势判断：`file-nr` 在时间窗口内是否持续上升

输出（供后续交叉验证使用）：

```
系统 FD 使用率：<allocated/max * 100>%
file-max 值：<max>
内核告警：[有/无] "VFS: file-max limit reached" 记录
inotify 限制：max_user_watches=<N>, max_user_instances=<M>
趋势判断：[稳定/上升/耗尽中]
```

### Step 4：L2 进程层分析（回答"哪个进程在泄漏"）

原则：找出 FD 使用异常的进程，确认泄漏嫌疑。

#### 4.1 进程 FD 排行
```bash
for x in $(ps -eF | awk '{ print $2 }'); do
  echo "$(ls /proc/$x/fd 2>/dev/null | wc -l) $x $(cat /proc/$x/cmdline 2>/dev/null | tr '\0' ' ')"
done | sort -n -r | head -10
```

#### 4.2 目标进程确认
```bash
cat /proc/<PID>/limits | grep "Max open files"
ls -1 /proc/<PID>/fd | wc -l
```

#### 4.3 FD 类型分布
```bash
lsof -p <PID> | awk '{print $5}' | sort | uniq -c | sort -rn
```

#### 4.4 趋势监控
```bash
watch -n 5 "ls -1 /proc/<PID>/fd | wc -l"
```

### Step 5：L3 类型层 + L4 根因层（分支脚本自动执行）

各分支脚本内置了 L3（类型定位）和 L4（根因回溯）的命令序列。按 Step 2 推荐的脚本逐分支执行，每个分支脚本输出：

```
## 分支 <X> 诊断结论

### L3 类型层（FD 分类定位）
  泄漏 FD 类型：<socket / eventpoll / inotify / pipe / regular file>
  该类 FD 数量：<N>  占比：<百分比>
  正常范围：<参考值>
  判定：[正常/可疑/泄漏]

### L4 根因层（代码级回溯）
  strace open/close 对比：
    open/creat/socket 调用数：<N>
    close 调用数：<M>
    差值：<N-M>
    判定：[匹配/不匹配/严重不匹配]
  调用栈线索（如果可用）：
    <从 strace/valgrind 获取的调用栈>
  根因假设：<一句话根因推断>
```

### Step 6：交叉验证与最终输出

对每条证据做对齐检查：

| 验证维度 | L1 系统层 | L2 进程层 | L3 类型层 | L4 根因层 | 是否吻合？ |
|---------|-----------|-----------|-----------|-----------|-----------|
| 泄漏范围 | 系统水位告警 | 确认特定进程 | FD 类型匹配 | 代码路径确认 | □ 吻合 □ 不符 |
| 泄漏趋势 | file-nr 上升 | 进程 FD 增长 | 该类 FD 增长 | open > close | □ 吻合 □ 不符 |
| 根因定位 | - | - | FD 类型定位 | 缺陷代码确认 | □ 吻合 □ 不符 |

置信度收敛：

- **高**：四层完全吻合 + 反事实验证通过（如 strace 确认 open > close）
- **中**：三层吻合，一层依赖推断
- **低**：两层及以上依赖推断，或各层结论存在矛盾
- **疑似硬件/内核Bug**：用户态证据链完整但无法在应用层定位到缺陷代码

将 Step 3/4/5 的输出填入第九节报告结构，并显式写清：结论、证据链、修复建议、验证建议。

执行约束：所有分析脚本的默认超时时间为 **3 分钟（180s）**。

---

## 第四节：L1 系统层分析（已合并进第三节 Step 3）

本节内容已合并进第三节的统一流程（Step 3）。

---

## 第五节：L2 进程层分析（已合并进第三节 Step 4）

本节内容已合并进第三节的统一流程（Step 4）。

---

## 第六节：L3 类型层 + L4 根因层（已合并进第三节 Step 5）

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
## FD 泄漏诊断报告

### 会话信息
  会话 ID：<session_id>
  分析时间：<timestamp>
  目标 PID：<pid>（<process_name>）
  分析层级：[L1+L2+L3+L4 | L3+L4 | ...]

### 故障概要与置信度
  故障模式：<系统FD耗尽 / 进程FD泄漏 / CLOSE_WAIT / epoll泄漏 / inotify泄漏 / 混合>
  置信度：<高/中/低>
  分析轨道：[四层下钻 | 三层 | 两层]

### L1 系统层结论
  系统 FD 使用量：<allocated> / <max>（<usage_percent>%）
  内核告警：[有/无] "VFS: file-max limit reached"
  趋势判断：[稳定/上升/耗尽中]

### L2 进程层结论
  FD 数量：<total_fds> / ulimit <soft_limit>（<ratio>%）
  FD 类型分布：
    - IPv4 socket：<N>（<percent>%）
    - regular file：<N>（<percent>%）
    - eventpoll：<N>（<percent>%）
    - inotify：<N>（<percent>%）
    - pipe：<N>（<percent>%）
  泄漏判定：[正常/可疑/泄漏]
  FD 增长率：<N FD/min>

### L3 类型层结论
  主泄漏类型：<泄漏的 FD 类型>
  该类 FD 数量/占比：<N> / <percent>%
  异常指标：<CLOSE_WAIT 数 / epoll 数 / inotify watch 数 / open-close 差>

### L4 根因层结论
  系统调用对比：open <N> / close <M>（差值 <N-M>）
  根因代码路径（如有）：<文件:行号 / 函数名 / 调用链>
  根因假设：<一句话描述>

### 交叉验证结果
  L1↔L2 吻合：□ 是  □ 否（差异说明：<...>）
  L2↔L3 吻合：□ 是  □ 否（差异说明：<...>）
  L3↔L4 吻合：□ 是  □ 否（差异说明：<...>）
  综合判断：<各层结论是否一致>

### 完整因果链
  [根因代码缺陷] → [某类 FD 未关闭] → [进程 FD 持续增长]
  → [系统 FD 水位上升] → [触发 FD 耗尽/错误]

### 排除的替代假设
  - <假设X>：排除原因 <...>

### 修复建议
  立即处置：
    <重启进程 / 增大 ulimit / 清理 CLOSE_WAIT 等>
  根本修复：
    <修改代码在指定路径补上 close() / 修复连接池管理逻辑等>
  验证方法：
    <修复后运行 strace 确认 open=close / 监控 FD 趋势确认不再增长>
```

---

## 第十节：参考文件

- `references/fd_diagnosis_commands.md`：FD 诊断命令速查（lsof/ss/strace/procfs）
- `references/fd_leak_patterns.md`：FD 泄漏模式目录（10 种已知模式）
- `references/kernel_fd_params.md`：内核 FD 相关参数调优参考
