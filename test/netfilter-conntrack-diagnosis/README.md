# Netfilter/conntrack 故障注入测试框架

## 概述

本测试框架为 `netfilter-conntrack-diagnosis` skill 的 8 个故障分支提供容器化故障注入、诊断执行、根因分析和报告生成的全链路测试能力。

### 8 个故障分支

| 分支 | 故障类型 | 注入方式 | 诊断脚本 |
|:----:|----------|----------|----------|
| A | nf_conntrack 表满溢出 | 降低 conntrack_max 并 TCP 连接洪水 | `branch_A_conntrack_full.sh` |
| B | 规则误命中 DROP/REJECT | 双容器 iptables DROP 规则+跨网流量 | `branch_B_rule_mishit.sh` |
| C | NAT/SNAT/DNAT 映射异常 | DNAT 指向 dummy 接口 + SNAT 错误源 IP | `branch_C_nat_mapping.sh` |
| D | conntrack 状态丢包 | SYN 洪水(UNREPLIED)+孤立非SYN包(INVALID) | `branch_D_ct_state_drop.sh` |
| E | TCP window tracking 异常 | 窗口外 seq 数据包 | `branch_E_tcp_window.sh` |
| F | ct timeout 超时 | 极短超时参数(established=10s) | `branch_F_ct_timeout.sh` |
| G | helper/ALG 协议辅助模块故障 | nf_conntrack_helper=0 + 不加载 helper 模块 | `branch_G_helper_alg.sh` |
| H | ipset 匹配失效 | bitmap:port 类型被 src 规则引用(类型不匹配) | `branch_H_ipset.sh` |

## 目录结构

```text
netfilter-conntrack-diagnosis/
├── README.md                          # 本文件
├── tests/                             # 故障注入测试框架
│   ├── Dockerfile                     # 容器镜像构建文件
│   ├── lib/
│   │   └── common.sh                  # 公共函数库（镜像构建/容器管理/故障记录）
│   ├── inject/
│   │   ├── inject_fault_A_conntrack_full.sh  # 分支A~H 故障注入脚本
│   │   └── ...
│   ├── cleanup_all.sh                 # 统一环境清理
│   └── verify_all.sh                  # 统一诊断验证
└── reports/                           # 诊断报告
    ├── kuafu_reports/                 # Kuafu 执行报告
    └── baize_rca_reports/             # Baize RCA 根因分析报告(MD+HTML)
```

> **scripts/** 目录不在此处复制，构建时自动从 skill 目录打包进镜像。

## 使用方式

### 镜像构建

框架在首次注入故障时会自动构建镜像，也可手动构建：

```bash
# 自动构建（通过 common.sh）
source tests/lib/common.sh
build_base_image

# 等价于手动构建
docker build -t netfilter-test:latest \
    -f tests/Dockerfile \
    /home/win11/.config/opencode/skills/netfilter-conntrack-diagnosis
```

构建上下文为 skill 根目录（需包含 `scripts/` 子目录），`COPY scripts/ /scripts/` 将诊断脚本打包进镜像。

### 前置条件

- Docker >= 20.10（需要 `--privileged` 和 `--cap-add=NET_ADMIN` 支持）
- 当前用户有 docker 权限
- 宿主机已加载 `nf_conntrack` 内核模块
- **分支 A 需要宿主机 root 权限**来写入 `nf_conntrack_max`（通过 `-v /proc/sys/net/netfilter/:/host-sys:rw`）

### 单分支测试

```bash
# 注入故障（如分支 B）
bash tests/inject/inject_fault_B_rule_mishit.sh

# 运行诊断
docker exec netfilter-fault-rule_mishit bash /scripts/01_collect_baseline.sh
docker exec netfilter-fault-rule_mishit bash /scripts/branch_B_rule_mishit.sh /tmp/netfilter_diag_*

# 验证
bash tests/verify_all.sh --only B

# 清理
bash tests/cleanup_all.sh
```

### 全链路测试（Fuxi → Dayu → Kuafu → Baize）

参见 Xuanyuan 全链路流程：
1. 调用 `task(subagent_type="fuxi-sub")` 构建诊断计划
2. 调用 `task(subagent_type="dayu")` 编排执行（通过 Kuafu）
3. 调用 `task(subagent_type="baize")` 根因分析 → 生成 RCA 报告
4. 调用 `report_visualization` 将 MD 转换为 HTML

### 批量测试

```bash
# 注入所有故障
for f in tests/inject/inject_fault_*.sh; do bash "$f"; done

# 验证所有分支
bash tests/verify_all.sh

# 清理
bash tests/cleanup_all.sh
```

### 自定义镜像

如需修改基础镜像（如更换内核模块、安装额外工具），编辑 `tests/Dockerfile` 后重新构建：

```bash
docker build -t netfilter-test:latest -f tests/Dockerfile /path/to/scripts/
```

## 已知限制

| 限制 | 涉及分支 | 原因 |
|------|---------|------|
| nf_conntrack_max 写入需 root | A | 非 init netns 中只读，需通过 `/host-sys` 挂载 |
| INVALID 条目非持久化 | D | 内核行为：INVALID 包被丢弃但不创建条目 |
| window violation 容器受限 | E | raw socket 走本地出站路径无法触发 conntrack window 检查 |
