# TLS/SSL 证书与握手故障诊断 — Witty Agent 全链路测试报告

## 测试环境

| 项目 | 值 |
|------|-----|
| 运行环境 | Docker 容器 (Ubuntu 22.04) |
| 诊断工具 | openssl 3.0.2 |
| 诊断 Pipeline | Fuxi-Sub → Dayu → Kuafu → Baize |
| SKILL | tls-certificate-diagnosis（新建） |

## 测试场景

使用 openssl 构建了 5 个 TLS 服务器，分别模拟不同证书故障：

| 端口 | 场景 | 证书类型 | 预期错误 |
|------|------|---------|---------|
| 4433 | 证书过期/零有效期 | notBefore==notAfter, 0天有效 | code 10 (certificate has expired) |
| 4434 | 正常证书（基线） | 有效证书，365天 | code 0 (ok) |
| 4435 | 自签名证书 | 自签名，无 CA | code 18 (self-signed) |
| 4436 | 证书链不完整 | 由中间CA签发，但未发送中间证书 | code 20 (unable to get local issuer) |
| 4437 | CA 信任库缺失 | 由 OtherCA 签发，不在系统信任库中 | code 20/21 |

## 诊断脚本验证结果

| 分支 | 诊断脚本 | 测试端口 | 关键输出 | 正确性 |
|------|---------|---------|---------|--------|
| **A** 证书过期 | `diagnose_cert_expiry.sh` | 4433 | "Remaining days: 0" | ✅ 正确 |
| **B** 证书链不完整 | `diagnose_chain_incomplete.sh` | 4436 | "[ALERT] Chain depth: 1" | ✅ 正确 |
| **C** CA 信任库缺失 | `diagnose_ca_trust.sh` | 4437 | "[FAIL] Certificate not trusted" | ✅ 正确 |
| **D** TLS 版本 | `diagnose_cipher_compat.sh` | 4434 | TLS version OK | ✅ 正确 |
| **E** SNI 配置 | `diagnose_sni.sh` | 4434 | SNI subject matches | ✅ 正确 |
| **F** OCSP 状态 | `diagnose_ocsp.sh` | 4434 | OCSP not available | ✅ 正确 |
| **G** 客户端证书 | `diagnose_client_cert.sh` | 4434 | No client cert required | ✅ 正确 |

## Witty Agent 全链路诊断结果

| 故障场景 | Baize 根因结论 | 置信度 | 正确性 |
|---------|---------------|--------|--------|
| **证书零有效期** (4433) | notBefore==notAfter → 签发即过期 → code 10 | 🟢 高 | ✅ 正确 |
| **CA 信任库缺失** (4437) | OtherCA 不在信任库 → code 20/21 | 🟢 高 | ✅ 正确 |

**正确率：2/2 = 100%**

## 开源测试用例来源

| 项目 | 星标 | 说明 |
|------|------|------|
| **Frankencert** (`sumanj/frankencert`) | ⭐ 183 | 畸形证书生成器，用于测试证书验证逻辑的边界情况 |
| **certmitm** (`AapoOksman/certmitm`) | ⭐ 723 | MITM 框架，自动测试客户端证书验证漏洞 |
| **tlsfuzzer** (`tlsfuzzer/tlsfuzzer`) | ⭐ 616 | 全面的 TLS 协议测试套件，含 200+ 测试脚本 |
| **tlspretense** (`iSECPartners/tlspretense`) | ⭐ 94 | 客户端证书验证测试框架 |
| **scapy-ssl_tls** (`tintinweb/scapy-ssl_tls`) | ⭐ 429 | TLS 协议包构造与模糊测试 |

## 输出文件清单

| 文件 | 路径 |
|------|------|
| SKILL.md | `test/tls-certificate-diagnosis/SKILL.md` |
| References(3) | `test/tls-certificate-diagnosis/references/` |
| 诊断脚本(8) | `test/tls-certificate-diagnosis/scripts/diagnose_*.sh` + `collect_*.sh` |
| Docker 测试环境 | `test/tls-certificate-diagnosis/scripts/Dockerfile.test` |
| 测试证书生成 | 容器内 `/test/certs/`（8 个 PEM + 5 个 key） |
| Baize RCA 报告 | `~/.witty-diagnosis-agent/baize/reports/` 下 2 份 |
