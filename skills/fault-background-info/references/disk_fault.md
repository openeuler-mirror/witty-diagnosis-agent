# 磁盘故障 (Disk Fault) 场景背景参考

## 1. 场景概述
本场景模拟物理机或虚拟机层面的磁盘子系统故障。主要依赖日志分析，无详细指标数据。

## 2. 候选组件 (Candidate Entities)
- **日志源**: `kernel`, `syslog`, `app`
- **磁盘设备**: `sda`, `vda` 等

## 3. 核心指标与数据限制
- **核心指标**: 本场景主要依赖日志分析。
- **数据限制**: 目前仅包含 `app`/`kernel`/`syslog` 日志，**无详细指标数据**。需通过日志模式匹配进行分析。

## 4. 日志策略
**本场景需要下载日志。** 

### 模式说明
本场景支持 **Local (本地)** 和 **Remote (远程)** 两种模式。默认模式由配置文件 `config/rca_config.yaml` 中的 `default_mode` 决定（目前默认为 `local`）。

### 命令示例

**1. 本地模式 (Local Mode)**:
如果不指定 `--mode`，且配置文件中 `default_mode` 为 `local`，则默认使用本地模式。也可以显式指定：
- **默认下载路径**: `datasets/DiskFault/<date>/` (请确保在项目根目录运行脚本)。

```bash
python .claude/skills/fault-background-info/scripts/log_fetcher.py disk_fault \
    --mode local \
    --local-dir /path/to/logs \
    --date <YYYY-MM-DD>
```

**2. 远程模式 (Remote Mode)**:
如果需要从远程环境获取日志，请指定 `--mode remote`。相关连接信息（Host, User, Password）将优先从配置文件读取。
```bash
python .claude/skills/fault-background-info/scripts/log_fetcher.py disk_fault \
    --mode remote \
    --date <YYYY-MM-DD>
```

## 5. 错误日志说明
- **慢盘**：关注 FAILED Result: hostbyte=DID_TIME_OUT 和 Medium access timeout failure. Offlining disk 这两种格式，它们都是出现慢盘的标志。

## 6. 其他提示
- **时区**: **Asia/Shanghai (UTC+8)**。
- **优先级**: 请优先使用日志相关的专家工具。
