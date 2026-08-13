<div align="center">
  <img src="docs/assets/witty-diagnosis-agent_logo.png" alt="Witty Diagnosis Agent Logo" width="600" />
</div>

Witty 智能诊断 Agent 基于「假设-验证」（Hypothetico-Deductive）故障排查范式与 Multi-Agent 协同架构，提供分钟级、代码行级的全自动故障诊断能力。

- **全栈并发诊断**：支持跨系统、内核与硬件的多路径并行排查，彻底打破传统线性排查的效率瓶颈。
- **专家经验封装**：内置多场景诊断技能与丰富故障模式库，固化专家级排查思路，实现根因精准穿透。
- **端到端闭环自愈**：涵盖“现象分析、根因定界、生成报告、执行修复”全链路，提供一站式自动化运维。
- **严格的安全管控**：诊断排查阶段严格只读，仅修复阶段按需赋予操作权限，且变更必经用户审批确认。

<div align="center">
  <img src="docs/assets/sys_crash_diag.gif" alt="系统宕机故障诊断" />
</div>

### 架构与核心能力

Witty 智能诊断 Agent 采用“Agent-Skill-工具-知识”四层解耦架构，兼具高灵活性与可扩展性。

<div align="center">
  <img src="docs/assets/architecture.png" alt="Diagnosis Agent架构图" width="640" />
</div>

#### 1. 多智能体协同 (Agent 层)

采用流水线式机制实现诊断自动化：

- **Xuan Agent(总控)**：调度其它Agent协同完成故障诊断。
- **Shennong Agent(检索)**：检索历史案例,为 Fuxi Agent 制定规划提供参考依据。
- **Fuxi Agent (规划)**：基于现象生成结构化排查计划。
- **Dayu Agent (调度)**：解析计划并并发调度给执行节点。
- **Kuafu Agent (执行)**：加载专属 Skill 深入节点拉取指标与推理。
- **Baize Agent (融合)**：汇总证据链，输出最终根因报告。
- **Nuwa Agent (自愈)**：基于安全规则，自动生成并执行修复。

#### 2. 专家经验沉淀 (Skill & 知识层)

- **Skill 层**：将专家排查流程封装为可复用的诊断技能（如 OOM、死锁排查）。
- **知识底座**：内置 openEuler 专属故障模式与因果规则，持续自我进化。

#### 3. 核心诊断能力

深度结合 openEuler 操作系统特性，目前已支持：

- **用户态诊断**：诊断进程 coredump、文件描述符泄漏、系统调用异常、IPC/资源耗尽、Unix Socket/Pipe、容器（Docker）、时间同步与安全认证等进程/服务层逻辑异常。
- **内核级诊断**：自动解析VMCore，精准回溯内核崩溃（Crash/Panic）调用栈；覆盖 OOM、CPU 调度、文件系统（EXT4/XFS/OverlayFS）、Swap 抖动，以及块设备 IO 与网络协议栈等内核子系统故障。
- **硬件级诊断**：基于 iBMC 带外日志与 OS 信息采集，定位 CPU/内存/磁盘/GPU/NPU/网卡/电源等部件的物理故障（ECC/MCE、坏道、掉卡、链路不稳、供电异常等），并提供磁盘健康预测与 GRUB 启动链故障诊断。

> 💡 诊断能力详情，请参见[功能列表](docs/reference/features.md)。

---

### 快速开始

#### 环境要求

- 依赖框架：已安装[OpenCode](https://opencode.ai/)(运行环境：Node.js >= 20.0.0) 或 [xiaoO](https://gitcode.com/openeuler/xiaoO/)(运行环境：Rust 工具链和 Cargo)
- 依赖工具：已安装 [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/)（`ansible` 命令须在系统 PATH 中可用，可通过 `ansible --version` 提前验证）

> ⚠️ **注意**：执行 `witty-diagnosis-agent install` 前，请确保本地已完成 Ansible 的安装与环境配置，否则安装程序将直接终止。

#### 安装与配置

Witty 智能诊断 Agent 支持**在线安装**、**源码安装**与 **RPM 包安装**，请根据您的网络环境与系统类型选择合适的安装方式。

##### 方式一：在线安装（推荐）

```bash
npm install -g witty-diagnosis-agent@latest
witty-diagnosis-agent install
```

##### 方式二：源码一键安装（适用于源码）

如果您已经克隆了仓库，可以使用一键安装脚本自动完成环境检查、依赖安装、项目构建及插件配置：

```shell
git clone https://atomgit.com/openeuler/witty-diagnosis-agent.git
cd witty-diagnosis-agent
bash install.sh
```

##### 方式三：离线包一键安装（适用于离线情况）

如果您已经下载了源代码安装包，可以使用一键安装脚本自动完成环境检查、依赖安装、项目构建及插件配置，以 witty-diagnosis-agent-v0.6.0-beta.tar.gz 压缩包为例：
```shell
tar -xzvf witty-diagnosis-agent-v0.6.0-beta.tar.gz
cd witty-diagnosis-agent-v0.6.0-beta
bash install.sh
```

##### 方式四：RPM 包安装（适用于 openEuler 等 RPM 系发行版）

适合在多台机器批量部署，或希望由系统包管理器统一管理安装与卸载的场景。安装分两步：**装包**（root，一次）与**注册**（每个使用者各一次）。

```bash
# 第 1 步：装包（root）
sudo dnf install -y witty-diagnosis-agent-0.10.0-1.beta.noarch.rpm

# 第 2 步：注册到个人 OpenCode 配置（普通用户，不要用 sudo）
witty-diagnosis-agent install

# 验证
witty-diagnosis-agent doctor
```

> ⚠️ 第 2 步**不要加 sudo**。该命令写入的是 `~/.config/opencode/`，用 sudo 会写到 root 家目录，导致普通用户实际用不了。

包为 `noarch`，x86_64 与 aarch64 通用；运行依赖已全部内联进产物，目标机器无需安装 npm 依赖。

自行构建 RPM 包（需在 Linux 构建机上执行）：

```bash
bash packaging/build-rpm.sh
```

产物输出到项目下的 `rpm-out/`。完整的打包、离线构建、升级卸载与故障排查说明见 **[packaging/README.md](packaging/README.md)**。

---

### 如何使用

#### 基于opencode框架启动

1. 启动 \*\*OpenCode \*\*。

2. 完成模型相关配置：
   - 第一步：执行 `/model` 命令调出模型配置面板；
   - 第二步：按下快捷键 Ctrl + A 选择模型提供商，粘贴填写模型服务商提供的密钥；
   - 第三步：从列表中选中目标服务商对应的模型。

2. 执行`/agents`命令，选择`Xuanyuan`Agent。
   
   ![选择Xuanyuan Agent](docs/assets/select_xuanyuan.png)

3. 输入故障问题描述，示例：
   
   ```shell
   请诊断2026-03-05 14:31前最近一次硬盘故障，日志路径：/tmp/logs
   ```
   
   <img src="docs/assets/guide_auto_diag_start.png" alt="wittywork命令" width="800" />

4. 系统将自动执行**智能诊断**流程。

5. 诊断完成后，系统将生成[HTML](docs/reference/reports/hard_disk_fault_diagnosis_report.html)和[Markdown](docs/reference/reports/hard_disk_fault_diagnosis_report.md)两种格式的诊断分析报告，同时在界面上展示完整报告内容：
   
   <img src="docs/assets/guide_auto_diag_report.png" alt="诊断报告" width="800" />

如需了解更多操作细节，可查阅[用户手册](docs/guide/MANUAL.md)。

#### 基于xiaoO框架启动

1. 启动 \*\*xiaoO \*\*。

2. 使用`tab`键，切换`Xuanyuan`Agent。
   
   ![选择Xuanyuan Agent](docs/assets/xiaoO_select_xuanyuan.png)

3. 输入故障问题描述，示例：
   
   ```shell
   请诊断2026-03-05 14:31前最近一次硬盘故障，日志路径：/tmp/logs
   ```
   
   <img src="docs/assets/xiaoO_guide_auto_diag_start.png" alt="wittywork命令" width="800" />

4. 系统将自动执行**智能诊断**流程。

5. 诊断完成后，系统将生成[HTML](docs/reference/reports/hard_disk_fault_diagnosis_report.html)和[Markdown](docs/reference/reports/hard_disk_fault_diagnosis_report.md)两种格式的诊断分析报告，同时在界面上展示完整报告内容：
   
   <img src="docs/assets/xiaoO_guide_auto_diag_report.png" alt="诊断报告" width="800" />

---

### 进程 CORE 故障诊断示例

本节以 WSL2 Ubuntu 系统为例，演示如何使用 Witty 智能诊断 Agent 分析进程 Core Dump 文件。本示例仅用于演示和体验智能诊断 Agent 的分析过程和输出报告。由于示例代码非常简单（空指针解引用），直接使用原生 OpenCode 或任何调试工具也能定位出根因。对于更复杂的生产环境故障，智能诊断 Agent 的系统化排查能力将展现更大优势。

#### 1. 修改系统配置以获得进程 Core Dump 文件

默认情况下，Linux 系统可能禁用了进程 core dump 功能。请使用 root 用户执行以下步骤启用：

```bash
# 查看当前 core dump 配置（0 表示禁用）
ulimit -c

# 临时启用 core dump（不限制文件大小）
ulimit -c unlimited

# 永久启用：在 /etc/security/limits.conf 末尾添加
echo "* soft core unlimited" >> /etc/security/limits.conf
echo "* hard core unlimited" >> /etc/security/limits.conf

# 停用 apport（否则会拦截并吃掉 core 文件）
sudo service apport stop
sudo systemctl disable apport

# 设置 core dump 文件存放路径和命名格式（当前目录）
sudo sysctl -w kernel.core_pattern=core.%e.%p

# 验证配置
ulimit -c
cat /proc/sys/kernel/core_pattern
```

> **说明**：`%e` 为进程名，`%p` 为进程 PID。core 文件将保存在当前工作目录。

#### 2. 开发会产生 Core Dump 的示例 C 代码

1）创建 `crash_demo.c` 文件：

```c
#include <stdio.h>
#include <stdlib.h>

void trigger_segfault() {
    int *ptr = NULL;
    *ptr = 42;
}

int main() {
    printf("Starting crash demo...\n");
    trigger_segfault();
    return 0;
}
```

2）安装编译工具和 GDB：

```bash
sudo apt update && sudo apt install -y gcc gdb
```

3）编译（禁用优化，开启调试符号）：

```bash
gcc -g -O0 -o crash_demo crash_demo.c
```

4）运行：

```bash
./crash_demo
```

5）执行后将触发段错误并产生 core dump 文件：

```
Starting crash demo...
Segmentation fault (core dumped)
```

6）查看生成的 core 文件：

```bash
ls -la ./core.*
```

#### 3. 在 WSL 中启动 OpenCode 并使用智能诊断 Agent 分析

1）启动 OpenCode：

```bash
opencode
```

2）加载 Xuanyuan Agent：执行 `/agents` 命令，选择 `Xuanyuan` Agent。

3）输入问题描述：

```
分析/tmp/test目录下的core文件根因。
```

> **提示**：将 `/tmp/test` 替换为示例 C 代码所在的实际目录路径。

4）系统将自动执行智能诊断流程，分析进程崩溃原因并输出诊断报告。
   
   <img src="docs/assets/process_fault_diagnosis_report.png" alt="process_fault_diagnosis_report" width="800" />

---

### 硬盘故障诊断示例

#### 1. 环境准备

1. 下载测试用例日志logs.zip（链接: https://pan.baidu.com/s/1-VlfKy5sx7LR-_tXkJ1G1A?pwd=bykf 提取码: bykf）；
2. 将logs.zip拷贝到/tmp目录下并解压；

#### 2. 使用智能诊断 Agent 分析

1）启动 OpenCode：

```bash
opencode
```

2）加载 Xuanyuan Agent：执行 `/agents` 命令，选择 `Xuanyuan` Agent。

3）输入问题描述：

```
请诊断2026-03-05 14:31前最近一次硬盘故障，日志路径：/tmp/logs
```

4）系统将自动执行智能诊断流程，分析硬盘故障原因并输出诊断报告。

   <img src="docs/assets/hard_disk_fault_diagnosis_report.png" alt="hard_disk_fault_diagnosis_report" width="800" />
---

### 火焰图性能分析示例

本节演示依托 Witty 智能诊断 Agent 排查性能瓶颈，导入 perf script 采样数据后，平台自动生成火焰图并精准定位 CPU 热点函数。

#### 1. 在 OpenCode 中启动分析

1) **启动 OpenCode**：

```bash
opencode
```

2) **加载 Xuanyuan Agent**：执行 `/agents` 命令，选择 `Xuanyuan` Agent。

3) **输入问题描述**：

```
依托/tmp/perf-vertx-stacks-01.txt采样数据，排查性能瓶颈根因。
```

> **提示**：路径按需替换，测试样例预置路径：test/lamegraph-analysis/data/perf-vertx-stacks-01.txt。

#### 2. 系统自动执行分析流程

系统将自动完成以下分析步骤：

1) **数据转换**：将 `perf script` 格式转换为折叠栈格式
2) **热点分析**：识别 CPU 热点函数与调用链
3) **模式匹配**：检测常见性能反模式（如锁竞争、GC overhead、正则回溯等）
4) **归因分析**：关联系统资源与业务逻辑
5) **生成报告**：输出交互式火焰图HTML报告与Markdown报告

#### 3. 分析结果示例

分析完成后，系统将生成交互式 HTML 火焰图，直观展示热点调用栈：

<img src="docs/assets/flamegraph_report.png" alt="火焰图分析结果" width="900" />

图中展示了 Java 应用的关键热点函数，火焰越高表示该函数占用的 CPU 时间越多。通过火焰图可以快速定位到性能瓶颈的根源函数。

**HTML 火焰图报告功能说明**：

- **根因分析**：报告顶部提供核心性能问题的根因总结，帮助用户快速理解性能瓶颈所在
- **关键性能瓶颈项列表**：列出分析到的所有关键性能瓶颈项，每项包含问题描述、帧栈、CPU占用率和样本数
- **交互式钻取**：点击每个关键发现卡片，火焰图将自动定位并高亮显示对应的调用帧栈，方便用户确认和深入分析
- **Markdown 报告**：同时生成 Markdown 格式的分析报告，便于归档和分享

💡 请参见[HTML火焰图报告](test/flamegraph-analysis/reports/Vert.x应用火焰图分析报告.html)。

---

### 如何贡献

#### 社区贡献

我们诚挚欢迎新贡献者加入项目，也会为新加入者提供全面的指导与帮助。请注意：贡献代码前，请先签署 [CLA](https://clasign.osinfra.cn/sign/6983225bdcbb19710248ccf0)，再参考 [代码贡献指引](https://www.openeuler.org/zh/community/contribution/detail#_4-2-代码类贡献) 提交代码。

#### 问题讨论

若您有任何疑问、建议或讨论需求，可通过以下方式联系我们：

- 提交 [issue](https://atomgit.com/openeuler/witty-diagnosis-agent/issues)
- 发送邮件至 <intelligence@openeuler.org>

---

### License

本项目采用 **木兰宽松许可证第2版（Mulan PSL v2）** 开源。详情请参阅项目根目录下的 [LICENSE](./LICENSE) 文件。
