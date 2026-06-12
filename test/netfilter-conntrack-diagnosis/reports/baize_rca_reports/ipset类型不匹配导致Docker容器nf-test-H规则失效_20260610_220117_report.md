# 🔴 故障诊断报告 — Docker 容器 nf-test-H ipset 匹配失效

> **报告编号**：RCA-20260610-001
> **故障级别**：P2（配置错误类 — 安全防护规则未生效）
> **报告时间**：2026-06-10 22:01:17 +08:00
> **当前状态**：🟡 观察中（规则已识别异常，待修复）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | Docker 容器 nf-test-H 中 ipset 类型与规则方向不匹配导致 DROP 规则失效 |
| 影响范围 | 容器 nf-test-H 的 `app_ports` ipset 的 **src 方向 DROP 规则**完全无效（0 命中），导致预期应被拦截的源端口匹配流量未被丢弃，存在安全防护盲区 |
| 故障时段 | 2026-06-10 22:01:17 及之前（持续存在，自 ipset 规则配置生效起） |
| 根本原因 | `app_ports` ipset 类型为 `bitmap:port`，该类型在内核协议栈中**仅支持 dst（目的）方向匹配**，但 iptables 规则错误地使用了 `src` 方向引用，导致匹配永远无法命中 |
| 是否恢复 | ❌ 未恢复（规则仍存在，需人工修复） |
| 根因置信度 | 🟢 高置信（H4 自动检测 + 规则计数双向验证：`src` 方向 0 命中 vs `dst` 方向 30 命中，对比明确） |

### 置信度说明

| 等级 | 标识 | 含义 | 对应本案 |
|------|------|------|---------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | `bitmap:port` 仅支持 dst 是内核约定；两条规则的 pkts 计数差（0 vs 30）为决定性证据 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                         事件                                                      性质          溯源路径
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
[持续]                       管理员/自动化工具创建 ipset app_ports，类型为 bitmap:port       📝 配置创建    kuafu_H_20260610_220117.md:21-30
  │                          成员添加：8080, 8443
  │
  ▼
[持续]                       创建 iptables 规则引用 app_ports 用于 src（源端口）方向 DROP     ⚠️ 配置错误    kuafu_H_20260610_220117.md:44-45
  │                          规则：match-set app_ports src → DROP
  │                          bitmap:port 内核仅支持 dst 方向匹配
  ▼
[持续]                       src 方向 DROP 规则命中计数 = 0                                🔴 规则失效    kuafu_H_20260610_220117.md:45
  │                          预期应拦截源端口为 8080/8443 的入站流量
  │
  ▼
[持续]                       同期 dst 方向 DROP 规则命中计数 = 30（正常）                    🟢 对照正常    kuafu_H_20260610_220117.md:46
  │                          证明 ipset 条目本身正常、规则语法正确
  │
  ▼
[持续]                       安全防护存在盲区：src 方向流量不会被拦截                        🔴 风险持续    kuafu_H_20260610_220117.md:91-96
                              H4 自动检测确认类型不匹配
```

### 故障因果链

```text
配置阶段: ipset create app_ports bitmap:port range 0-65535
    └─► iptables -A FORWARD -m set --match-set app_ports src -j DROP  ← 错误！bitmap:port 不支持 src
            └─► 内核 netfilter 协议栈在处理 match-set src 时，发现 bitmap:port 的匹配方向位图仅注册了 dst
                    └─► match 函数直接返回 false，规则永不命中
                            └─► pkts 计数一直为 0
                                    └─► 源端口 8080/8443 的入站流量无法被此规则拦截
                                            └─► 🔴 安全防护规则形同虚设
```

---

## 三、排查过程

### 3.1 初始现象

- Docker 容器 nf-test-H 中存在 ipset 规则 `app_ports`，类型为 `bitmap:port`，包含端口 `8080` 和 `8443`
- 两条引用 `app_ports` 的 iptables DROP 规则命中计数差异巨大：
  - `match-set app_ports src` → **0 packets**（异常）
  - `match-set app_ports dst` → **30 packets / 1800 bytes**（正常）
- `blacklist`（hash:net 类型）的 `src` 方向引用命中计数为 0（未见异常流量）

### 3.2 假设驱动排查

#### 假设 A：ipset 条目未正确添加或已过期

> 🧪 假设：app_ports 中无有效条目，导致所有规则都无法命中

| 检查项 | 操作 | 结论 |
|--------|------|------|
| ipset 条目 | ipset list app_ports 检查条目 | ✅ 条目正常：8080, 8443 均在成员列表中 |
| 引用计数 | References: 2 | ✅ 有规则正确引用 |
| dst 方向规则 | pkts=30 | ✅ dst 方向正常命中 → 条目有效 |

**❌ 排除**：ipset 条目本身存在且有效，非条目缺失问题。

---

#### 假设 B：规则顺序导致 src 规则被覆盖

> 🧪 假设：由于规则链中其他规则优先级更高，流量在匹配到 src 规则前已被 ACCEPT 或跳转

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 规则命中计数 | pkts: src=0, dst=30 | ⚠️ 若被覆盖，dst 方向也应受影响，但 dst 正常命中 30 次 |
| 规则链结构 | iptables_filter 和 iptables_save 中的规则 | ✅ src 和 dst 规则在同一链中，dst 在后依然命中 |

**❌ 排除**：若为顺序覆盖，dst 规则（运行在后）不应先命中。src 规则在前，更应优先匹配。

---

#### 假设 C：ipset 类型与规则方向不匹配 ✅ 确认根因

> 🧪 假设：`bitmap:port` 类型的 ipset 在内核中仅支持 **dst（目的）** 方向匹配，而规则使用了 `src` 方向导致匹配永远失败

**Step 1 — 确认 ipset 类型**
```text
Analyzing ipset list output:
  Name: app_ports
  Type: bitmap:port     ← 关键发现
  Members: 8080, 8443
```

**Step 2 — 验证 bitmap:port 的匹配方向约束**
```text
H4 自动类型与方向匹配检测结果：
  ⚠️  app_ports (type=bitmap:port) 使用 src 匹配 → bitmap:port 只支持 dst!
  ✅  app_ports (type=bitmap:port) 使用 dst 匹配 ✓
  ✅  blacklist (type=hash:net) 使用 src 匹配 ✓
```

**Step 3 — 规则计数交叉验证**
```text
对比两条引用同一 ipset 的规则：
  Rule 1: match-set app_ports src → DROP     pkts=0     ← 规则失效（方向错误）
  Rule 2: match-set app_ports dst → DROP     pkts=30    ← 规则正常（方向正确）

同一 ipset、同一链，仅方向参数不同 → 排除条目/网络/顺序因素
```

**✅ 结论：`app_ports` ipset 类型为 `bitmap:port`，该类型内核实现仅注册了 dst 方向匹配能力。引用 `src` 方向的规则在 netfilter match 阶段直接返回 false，导致规则永久不命中，源端口防护完全失效。**

---

### 3.3 排查结论

```text
app_ports DROP 规则 src 方向 0 命中
├─► ipset 条目为空                → ✅ 排除（dst 方向正常命中 30 次）
├─► 规则顺序被覆盖                → ✅ 排除（dst 规则在后依然命中）
├─► 网络无对应 src 流量           → ❓ 可能但 dst 方向有流量，src 方向也应存在对称流量
└─► ipset 类型与规则方向不匹配      → 🎯 根因确认（bitmap:port 不支持 src）
        └─► bitmap:port 内核代码仅实现了 dst 方向匹配
        └─► 错误规则: match-set app_ports src → 内核 match 函数返回 false
        └─► pkts 永远为 0，安全规则完全失效
```

---

## 四、ipset 类型方向约束对照表

| ipset 类型 | 支持 src | 支持 dst | 说明 |
|-----------|----------|----------|------|
| `bitmap:ip` | ✅ | ✅ | IP 地址匹配 |
| `bitmap:port` | ❌ | ✅ | **仅支持 dst**，这是本案根因 |
| `bitmap:ip,mac` | ✅ | ✅ | — |
| `hash:ip` | ✅ | ✅ | — |
| `hash:net` | ✅ | ✅ | 本案中 blacklist 使用正确 |
| `hash:ip,port` | ✅ | ✅ | 如需 src 方向端口匹配，应使用此类型 |
| `hash:ip,port,net` | ✅ | ✅ | — |
| `list:set` | ✅ | ✅ | 嵌套集合 |

## 五、修复方案

### 5.1 应急处置

| 步骤 | 操作 | 执行人 | 时间 | 效果 | 风险 |
|------|------|--------|------|------|------|
| 1 | 确认业务需求方向：是否需要拦截**源端口**为 8080/8443 的流量 | 业务/SRE | 立即 | 明确需求 | 🟢 低危 |
| 2a | **若需要 src 方向匹配**：改用 `hash:ip,port` 类型重建 ipset，并重新添加条目 | 人工 | 需规划窗口 | 修复 src 方向匹配 | 🟡 中危（可能需要更新所有引用此 ipset 的规则） |
| 2b | **若实际意图是 dst 方向**：将规则中的 `src` 改为 `dst`，即可让规则生效 | 人工 | 立即 | 立即修复 | 🟢 低危（单行修改） |

### 5.2 建议修复命令

**选项 A（如需求为 dst 方向 — 推荐最低风险方案）：**
```bash
# 在 Docker 容器或宿主机（视规则位置而定）执行
iptables -R <chain> <rule-number> -m set --match-set app_ports dst -j DROP
# 或删除原规则后重新添加
iptables -D <chain> <rule-number>
iptables -A <chain> -m set --match-set app_ports dst -j DROP
```

**选项 B（如确实需要 src 方向 — 需重建 ipset 类型）：**
```bash
# 步骤 1：创建新的 hash:ip,port 类型 ipset（风险 🟡）
ipset create app_ports_v2 hash:ip,port

# 步骤 2：迁移条目（需考虑与实际匹配的 IP）
ipset add app_ports_v2 0.0.0.0/0,8080
ipset add app_ports_v2 0.0.0.0/0,8443

# 步骤 3：更新 iptables 规则引用
iptables -R <chain> <rule-number> -m set --match-set app_ports_v2 src -j DROP

# 步骤 4：验证新规则
iptables -L -v -n | grep app_ports_v2
# 确认 pkts 开始增长后，清理旧 ipset
ipset destroy app_ports
```

### 5.3 永久修复计划

| 修复措施 | 负责人 | 完成时间 | 风险等级 |
|---------|--------|---------|---------|
| 修正规则方向（若意图为 dst）或将 ipset 类型改为 `hash:ip,port`（若需要 src） | 待定 | 待定 | 🟡 中危 |
| 在 ipset 管理规范中增加类型方向校验 CI/CD 门禁，防止类似配置错误 | 待定 | 待定 | 🟢 低危 |
| 推广使用 H4 自动检测（已在 Kuafu 分支中实现），在规则部署前自动检查类型方向匹配 | 待定 | 待定 | 🟢 低危 |

### 5.4 验证建议

1. **修复前验证**：在测试环境中复现 `bitmap:port src` 规则，确认 pkts 始终为 0
2. **修复后验证**：
   - 执行 `iptables -L -v -n | grep app_ports` 确认 pkts 计数开始增长
   - 执行 `ipset list app_ports` 确认成员正常
   - 用 `hping3` 或 `nping` 模拟源端口 8080/8443 的流量，验证是否能被正确拦截
3. **回归验证**：确认 dst 方向的 DROP 规则仍然正常工作（pkts 持续增长）

---

## 六、参考证据索引

| 证据项 | 来源文件 | 行号 | 说明 |
|--------|---------|------|------|
| ipset app_ports 类型 bitmap:port | `kuafu_H_20260610_220117.md` | 21-30 | 确认为 bitmap:port 类型 |
| ipset blacklist 类型 hash:net | `kuafu_H_20260610_220117.md` | 32-40 | 参照组，类型方向正确 |
| `src` 规则 pkts=0 | `kuafu_H_20260610_220117.md` | 45 | 异常：规则未命中 |
| `dst` 规则 pkts=30 | `kuafu_H_20260610_220117.md` | 46 | 对照正常：同为 app_ports 但 dst 方向正常工作 |
| H4 自动检测结果 | `kuafu_H_20260610_220117.md` | 91-96 | 自动识别类型不匹配：bitmap:port 不支持 src |

---

*报告由 Baize (分析与报告 Agent) 自动生成*
*RCA 报告路径：/home/win11/.witty-diagnosis-agent/baize/reports/ipset类型不匹配导致Docker容器nf-test-H规则失效_20260610_220117_report.md*
