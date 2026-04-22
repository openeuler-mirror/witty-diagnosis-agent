# 硬件故障分析方法论

## MCE（机器检查异常）分析

### MCi_STATUS 寄存器解析

```
MCi_STATUS 位字段：
  [63]    VAL  - 寄存器有效标志
  [62]    OVER - 错误溢出（有更旧的错误被覆盖）
  [61]    UC   - 不可纠正错误 (Uncorrected Error)
  [60]    EN   - 错误报告使能
  [59]    MISCV- MCi_MISC 有效
  [58]    ADDRV- MCi_ADDR 有效
  [57]    PCC  - 处理器上下文损坏
  [56]    S    - 信号类型（1=fatal，0=recoverable）
  [55]    AR   - 需要动作恢复
  [31:16] MCA_ERROR_CODE - 错误代码（见下）
  [15:0]  MODEL_ERROR_CODE - 厂商特定错误代码
```

### MCA 错误类型编码（bits 31:16）

| 错误码（16进制） | 错误类型 | 说明 |
|----------------|---------|------|
| `0000 1xxx xxxx xxxx` | Cache Hierarchy | L1/L2/LLC 缓存错误 |
| `0000 0001 0000 1xxx` | TLB Error | 地址转换错误 |
| `0000 0001 0001 xxxx` | Bus/Interconnect | 总线/互联错误 |
| `0000 0001 0000 0001` | Memory Read Error | 内存读错误（通常是内存控制器报告） |

### MCE Bank 对应关系（Intel）

| Bank | 对应组件 |
|------|---------|
| 0 | 处理器内部（IPB）|
| 1 | ITL（指令 TLB）|
| 2 | DCU（L1 数据缓存） |
| 3 | DTLB（数据 TLB）|
| 4 | MLC（L2 缓存/LLC）|
| 5-8 | 内存控制器 |
| 9+ | 芯片组/QPI/PCIe |

### MCE 分析步骤

```bash
# 从 crash 中提取 MCE 信息
log | grep -A10 "Machine check:"
log | grep -E "mce|MCE|bank" | head -30

# 解析物理地址
# 如有 Physical Address: 0xXXXXXXXXXXXX
# 计算页帧号 PFN = 物理地址 >> 12
# 然后: kmem -p <PFN>
```

---

## EDAC 内存错误分析

### EDAC 错误类型

| 类型 | 含义 | 严重程度 |
|------|------|---------|
| CE (Correctable Error) | 可纠正错误，ECC 已修正 | 低（但需监控趋势）|
| UE (Uncorrectable Error) | 不可纠正错误，超出 ECC 纠错能力 | 严重（导致 panic）|

### EDAC 日志分析

```bash
# 系统运行时查看 EDAC 信息
edac-util -s 4                    # 显示详细错误信息
cat /sys/bus/mc/devices/mc0/ce_count  # 可纠正错误计数
cat /sys/bus/mc/devices/mc0/ue_count  # 不可纠正错误计数

# 从 vmcore 中查看 EDAC 信息
log | grep -i "edac\|dimm\|memory error\|UE\|CE" | head -50
```

### DIMM 物理位置定位

```bash
# EDAC 日志通常包含：
# EDAC MC0: UE row 0, channel 0 (DIMM_A1)
# 格式：mc<控制器编号> row<行> channel<通道> (DIMM_<插槽>)

# 对应物理位置（需查主板手册）：
# MC0/MC1 → CPU0/CPU1 的内存控制器
# channel 0/1/2/3 → DIMM 插槽通道
# DIMM_A1/A2/B1/B2 → 物理插槽标签
```

---

## Bit Flip 识别方法论

### 识别特征

Bit Flip 在 vmcore 中**伪装成软件故障**，识别标志：

1. **随机性**：多次崩溃发生在不同位置，无规律
2. **不可复现**：无法在软件层面稳定复现
3. **证据链断裂**：按软件故障分析，找不到完整的代码路径解释
4. **硬件侧痕迹**：BMC SEL 有 CE/UE 记录，EDAC 纠错计数增长

### 验证流程

```
Step 1: 软件排除
  - 按对应软件故障类型（空指针/UAF等）完整分析
  - 确认找不到完整的软件代码路径解释
  - 确认相同场景无法稳定复现

Step 2: 硬件侧证据收集
  - BMC/IPMI SEL：ipmitool sel list | grep -i "memory\|ECC\|correctable"
  - EDAC 统计：edac-util -s 4
  - 内存巡检日志：vendor-specific 工具（如 HP SmartArray、DELL iDRAC）

Step 3: 物理地址关联
  - 从 vmcore 中的崩溃地址推算物理地址
  - 通过 PFN 定位到 DIMM slot
  - 与 EDAC/BMC 记录的出错 DIMM 比对

Step 4: 趋势分析
  - 查看该 DIMM 的 CE 计数趋势（是否持续增长）
  - 检查是否有温度异常、电压问题
  - 比对同批次 DIMM 的错误率
```

### Bit Flip 与软件故障的区分

| 特征 | 软件故障 | Bit Flip |
|------|---------|---------|
| 复现性 | 可复现（固定场景） | 极难复现 |
| 崩溃位置 | 相对固定 | 随机变化 |
| 软件证据链 | 完整 | 断裂/不合理 |
| KASAN/LOCKDEP | 可能有告警 | 通常无（硬件已破坏数据） |
| BMC/EDAC | 通常无记录 | 有 CE/UE 历史记录 |
| 受影响机器 | 通常单机（代码相关） | 可能多机（同批次 DIMM）|

---

## 硬件故障处置建议

### 内存 UE 处置
1. **立即**：记录出错 DIMM slot，准备更换
2. **短期**：更换问题 DIMM，观察系统稳定性
3. **中期**：全服务器内存压测（memtest86+/HBM test）
4. **长期**：检查同批次 DIMM 的 CE 计数趋势

### MCE 处置
| MCE 类型 | 处置建议 |
|---------|---------|
| 内存控制器 MCE | 检查 DIMM，参考内存 UE 处置 |
| LLC/Cache MCE | 可能是 CPU 问题，考虑更换 CPU 或主板 |
| Bus/PCIe MCE | 检查 PCIe 设备（GPU/NIC/SSD），更换有问题的卡 |
| 频繁出现 MCE | 立即更换硬件，避免数据损坏 |

### Bit Flip 处置
1. 隔离问题 DIMM（通过 BIOS/固件工具）
2. 更换问题 DIMM 模组
3. 更新内存固件（如有可用版本）
4. 考虑启用更强的 ECC 模式（如 Lockstep Mode）
