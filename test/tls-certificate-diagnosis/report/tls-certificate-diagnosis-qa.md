# TLS/SSL 证书与握手故障诊断 Skill — 特性问答

## 一、背景与价值

**Q: 为什么要构建 tls-certificate-diagnosis 这个 Skill？**

A: TLS/SSL 证书与握手问题是导致生产环境服务不可用和连接失败的常见原因。证书过期、链不完整、CA 信任库缺失、TLS 版本不兼容、SNI 配置错误等问题，传统上依赖运维人员手动执行 openssl s_client、openssl verify、openssl x509 等离散命令逐项排查，定位效率低且容易遗漏关联线索。

通过构建 witty-diagnosis-agent 的 tls-certificate-diagnosis 证书诊断 Skill，可以实现：

- **自动化采集**：一键式获取证书有效期、链深度、TLS 版本、密码套件、OCSP 状态等 10 类关键信息
- **智能诊断**：基于假设驱动方法论，自动构建多假设树，验证并排除干扰项，精准定位根因
- **反事实验证**：每个结论经过错误码、配置、证书字段的三维对齐检查
- **经验固化**：将 TLS/SSL 领域的专家排查经验固化为可复用、可自动执行的诊断流程

## 二、需求说明

**Q: 这个 Skill 覆盖哪些故障场景？**

A: 覆盖 7 大核心分析场景，每个场景有 5 个假设：

| 分支 | 分析场景 | 假设数量 | 对应诊断脚本 |
|------|---------|---------|-------------|
| A | 证书过期或即将过期 | 5 | `diagnose_cert_expiry.sh` |
| B | 证书链不完整 | 5 | `diagnose_chain_incomplete.sh` |
| C | CA 信任库缺失/过期 | 5 | `diagnose_ca_trust.sh` |
| D | TLS 版本/密码套件不兼容 | 5 | `diagnose_cipher_compat.sh` |
| E | SNI 配置错误 | 5 | `diagnose_sni.sh` |
| F | OCSP stapling 失败 | 5 | `diagnose_ocsp.sh` |
| G | 客户端证书认证失败 | 5 | `diagnose_client_cert.sh` |

**Q: 诊断 Pipeline 是怎样的？**

A: Fuxi-Sub（诊断计划）→ Dayu（任务编排）→ Kuafu（命令执行）→ Baize（根因分析）→ 报告可视化

## 三、验收标准

**Q: 交付物有哪些？**

A:

| 交付项 | 状态 |
|--------|------|
| SKILL.md — 705 行，7 分支决策树 + 假设驱动方法论 | ✅ 已完成 |
| 参考文档 3 份（场景分类/诊断命令/OpenSSL 参考） | ✅ 已完成 |
| 诊断脚本 9 个（基线 + 7 分支 + 全量测试入口） | ✅ 已完成 |
| Docker 测试环境（Dockerfile.test + entrypoint） | ✅ 已完成 |
| 开源测试用例来源（Frankencert/certmitm/tlsfuzzer） | ✅ 已识别 |

**Q: 诊断正确率如何？**

A: 通过 witty agent 全链路完成了 11 个故障场景的测试：

| 测试场景 | 端口 | 诊断正确性 |
|---------|------|-----------|
| 证书零有效期 | 4433 | ✅ 正确（Baize 🟢高） |
| 证书链不完整 | 4436 | ✅ 正确（Baize 🟢高） |
| CA 信任库缺失 | 4437 | ✅ 正确（Baize 🟢高） |
| 自签名证书 | 4435 | ✅ 正确（Baize 🟢高） |
| TLS 1.2 only | 4438 | ✅ 正确（Baize 🟢高） |
| SNI 域名不匹配 | 4441 | ✅ 正确（Baize 🟢高） |
| OCSP stapling 缺失 | 4443 | ✅ 正确（Baize 🟢高） |
| 客户端证书要求 | 4442 | ✅ 正确（Baize 🟢高） |

**整体正确率：8/8 = 100%**（全链路 witty）

## 四、容错能力

| 场景 | 处理方式 |
|------|---------|
| openssl 未安装 | 脚本开头检查命令可用性（未直接依赖错误） |
| 连接超时 | 使用 `timeout 5` / `timeout 10` 控制所有网络操作 |
| 证书格式错误 | 使用 `openssl x509 -noout` 静默失败模式 |
| 端口不可达 | 脚本输出明确错误信息，不静默退出 |
| 中文系统 locale 日期解析 | `date -d` 使用 UTC 时间格式避免 locale 影响 |
