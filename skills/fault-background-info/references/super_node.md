# 超节点 (Super Node) 场景背景参考

## 1. 场景概述
超节点场景涉及跨主机内存借入/借出架构。内存借入方统一通过 CPU 访问内存，对 CPU 而言本地内存与借入内存无差别。

**内存访问路径**:
`借入方CPU` → `借入方UB控制器` → `独立UB链路` → `借出方UB控制器` → `借出方内存`

## 2. 关键节点与组件
- **IP 角色**:
  - **内存借出方 (Lender)**: 配置在 `lenders` 列表中。
  - **内存借入方 (Borrower)**: 配置在 `borrowers` 列表中。
  - **UB 链路 (UB Link)**: 对应配置文件中的 `special_ip`。
- **候选组件**:
  - 借入方UB控制器
  - UB链路
  - 借出方UB控制器
  - 借出方内存
- **关键服务**: `order_service` (关注其日志中第一次出现故障的时间)。

## 3. 日志分析指南 (核心)
本场景**仅包含日志数据**，无指标和调用链。

### 3.1 常见日志模式
- **UCE 内存故障**: `Hardware error from APEI Generic Hardware Error...` (section type: `memory error`)
- **Local Ras**: `Hardware error from APEI Generic Hardware Error...` (section type: `unknown`, 常伴随内存地址)
- **错误码格式**: `ub mem error: type=<error_code>`

### 3.2 故障模式匹配 (Fault Patterns)

**重要约束**：最终定位的故障根因**必须且只能**来自下表列出的故障源。严禁编造或推断表外的其他原因。

| 故障源 | 关键特征 (组合) |
| :--- | :--- |
| **借入方UB控制器** | UCE + Local Ras + 错误码 **13** (`MAR_NEAR_AUTH_FAIL_ERR`) |
| **UB链路** | UCE + Local Ras + 错误码 **15** (`MAR_TIMEOUT_ERR`) |
| **借出方UB控制器** | UCE + Local Ras + 错误码 **16** (`MAR_UB_MNG_ERR`) |
| **借出方内存** | UCE + Local Ras + 错误码 **17** (`MAR_DATA_POISON_ERR`) 或 **16** |

**注意**:
- **忽略** `UDEV RAS event injected: type=13 addr=` 和 `GetSupplementalMemory` 类日志。
- `REMOTE_READ_DATA_ERR_OR_WRITE_RESPONSE_ERR` 也是重要错误信号。

## 4. 日志策略
**本场景需要下载日志。** 

### 模式说明
本场景目前仅支持 **Remote (远程)** 下载，因为涉及跨节点的日志聚合。

### 命令示例

**默认模式 (Default)**:
使用配置文件 `config/rca_config.yaml` 中的默认节点列表和凭据。
- **默认节点**: 请参考配置文件
- **默认凭据**: 请参考配置文件 (推荐使用环境变量配置密码)
- **特殊处理**: 脚本会自动识别 `ub_link.log` 并将其归档到虚拟节点（配置于 `special_ip`）下。
- **默认下载路径**: `datasets/SuperNode/<date>/` (请确保在项目根目录运行脚本)。

```bash
python .claude/skills/fault-background-info/scripts/log_fetcher.py super_node --date <YYYY-MM-DD>
```

**指定节点模式 (Custom Servers)**:
如果用户提供了特定的服务器 IP 列表，请使用 `--servers` 参数：
```bash
python .claude/skills/fault-background-info/scripts/log_fetcher.py super_node \
    --date <YYYY-MM-DD> \
    --servers 192.168.1.10 192.168.1.11 \
    --user <USER> \
    --password <PASS>
```

## 5. 其他提示
- **时区**: **UTC+8**。
- **共享根因**: 当 UB 链路或借出方组件故障时，可能导致多个借入方节点同时异常。
