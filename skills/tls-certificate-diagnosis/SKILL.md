---
name: tls-certificate-diagnosis
description: >
  TLS/SSL 证书与握手故障诊断技能。覆盖证书过期/即将过期检测、证书链不完整、
  CA 信任库缺失/过期、TLS 版本/密码套件不兼容、SNI 配置错误、OCSP stapling 失败、
  客户端证书认证失败、mTLS 双向认证等场景。当用户提到证书过期、TLS 握手失败、SSL 错误、
  certificate verify failed、certificate has expired、chain incomplete、
  unknown CA、no shared cipher、SNI mismatch、OCSP stapling failed、
  client certificate required、mTLS 双向认证、mutual TLS、ssl handshake failure、
  certificate untrusted、alert certificate required、peer did not return a certificate、
  bad certificate 等问题时，必须使用此 skill。
---

# TLS/SSL 证书与握手故障诊断 Skill

## 第一节：概述

本 skill 提供系统化的 TLS/SSL 证书与握手故障分析方法论，覆盖以下核心场景：

- **证书过期/即将过期**：服务器证书已过期或将在短期内过期，导致客户端拒绝连接
- **证书链不完整**：服务器未发送中间证书，客户端无法构建完整证书链到受信任的根 CA
- **CA 信任库缺失/过期**：客户端信任库中缺少签发服务器证书的根 CA 或中间 CA 证书
- **TLS 版本/密码套件不兼容**：客户端和服务端支持的 TLS 版本或密码套件无交集
- **SNI 配置错误**：服务器未正确配置 Server Name Indication，导致多域名共用 IP 时返回错误证书
- **OCSP stapling 失败**：服务器未正确配置 OCSP 装订，或 OCSP 响应者不可达
- **客户端证书认证失败**：服务器要求客户端证书，但客户端未提供或提供了无效证书

> **重要原则**：本 skill 仅进行信息收集和分析诊断，**不执行任何修复命令**，只给出修复建议。所有修复操作需由用户确认后手动执行。

---

## 第二节：文件结构

```text
tls-certificate-diagnosis/
├── SKILL.md                                # 诊断流程文档
├── references/
│   ├── tls_fault_scenarios.md             # TLS/SSL 故障场景分类与特征表
│   ├── tls_diagnosis_commands.md          # TLS 诊断命令与工具参考
│   └── openssl_reference.md              # OpenSSL 参数与配置参考
├── scripts/
│   ├── collect_tls_info.sh               # TLS 综合信息收集脚本（基线）
│   ├── diagnose_cert_expiry.sh           # 证书过期诊断（分支 A）
│   ├── diagnose_chain_incomplete.sh      # 证书链不完整诊断（分支 B）
│   ├── diagnose_ca_trust.sh             # CA 信任库诊断（分支 C）
│   ├── diagnose_cipher_compat.sh         # TLS 版本/密码套件诊断（分支 D）
│   ├── diagnose_sni.sh                  # SNI 配置诊断（分支 E）
│   ├── diagnose_ocsp.sh                 # OCSP stapling 诊断（分支 F）
│   └── diagnose_client_cert.sh          # 客户端证书认证诊断（分支 G）
├── docs/                                   # 测试报告
│   └── ...
└── Dockerfile.test                         # Docker 测试环境
```

---

## 第三节：分析策略（假设驱动 + 分支验证）

**本 skill 采用假设驱动（Hypothetico-Deductive）的分析模型**：

```
┌──────────────────────────────────────────────────────────────────┐
│             TLS/SSL 证书与握手故障分析模型                        │
│                                                                  │
│  第一层：症状识别（错误信息匹配）    第二层：假设驱动排查           │
│  ──────────────────────────────    ───────────────────────       │
│  从用户描述和错误日志中自动识别       对每个症状构建多假设树        │
│  故障场景                               │
│                                                                  │
│  回答：什么错误？走哪条诊断        回答：为什么失败？如何验证      │
│        路径？                          哪个假设被证实？           │
│                                                                  │
│            ↓                              ↓                      │
│    ┌──────────────┐              ┌──────────────────┐            │
│    │  Step 1-2    │              │   Step 3-7       │            │
│    └──────────────┘              └──────────────────┘            │
│                                                                  │
│  见：第四节（统一分析流程）                                        │
└──────────────────────────────────────────────────────────────────┘
```

### 分析原则

| 原则 | 说明 |
|------|------|
| **时间锚定** | 所有分析以故障时间 T0 为锚点，证书过期检查以证书生效/失效日期为基准 |
| **证据驱动** | 每个结论必须有 `openssl` 命令输出、证书文件内容或错误日志作为支撑（至少 2 个独立来源） |
| **区分现象与根因** | TLS 握手失败是现象，证书过期/链不完整/密码套件不匹配才是根因 |
| **只读原则** | 诊断阶段严格只读，不执行任何证书签发或配置修改命令 |
| **量化表达** | 报告中的证书有效期、域名、指纹等数据尽量给出具体值 |

---

## 第四节：统一分析流程（症状识别 → 基线收集 → 分支定界 → 假设验证 → 排除确认 → 输出报告）

> 执行约束：所有分析脚本的默认超时时间为 **3 分钟（180s）**。

### Step 1：症状自动识别（关键词匹配）

直接从用户的故障描述和错误日志中提取关键信息，**不询问用户**，自主判断后立即进入分析流程。

| 用户描述关键词 / 错误信息 | 判断症状 | 推荐分支 |
|--------------------------|----------|----------|
| certificate has expired / certificate will expire / 证书过期 / 证书将在X天后过期 | 证书过期/即将过期 | → 分支 A |
| certificate chain incomplete / unable to get local issuer certificate / 证书链不完整 / 缺少中间证书 | 证书链不完整 | → 分支 B |
| certificate verify failed / unable to find valid certification path / unknown CA / 未知 CA / 证书不受信任 | CA 信任库缺失/过期 | → 分支 C |
| no shared cipher / unsupported protocol / TLS version mismatch / handshake failure / 密码套件不匹配 | TLS 版本/密码套件不兼容 | → 分支 D |
| SNI mismatch / certificate name mismatch / SSL_ERROR_BAD_CERT_DOMAIN / 域名不匹配 | SNI 配置错误 | → 分支 E |
| OCSP stapling failed / OCSP response error / revoked certificate / OCSP 状态未知 | OCSP stapling 失败 | → 分支 F |
| client certificate required / bad certificate / no certificate sent / 客户端证书认证失败 | 客户端证书认证失败 | → 分支 G |

> 如果描述同时命中多个症状（如"证书已过期且链不完整"），优先处理最紧急的场景（证书过期），然后依次排查其他路径。

从用户输入中自动提取以下信息，**已有则直接使用，缺失才补充询问**：

- **目标域名/IP**：用户已提供时直接使用；**未提供时才询问**
- **目标端口**：默认为 443；用户指定时使用指定端口
- **故障时间**：用户已提供时作为锚点 T0；**未提供时以当前时间为准**

---

### Step 2：基线信息收集（TLS 综合信息收集）

📄 **脚本**：`scripts/collect_tls_info.sh`

**参数说明**：

| 参数 | 含义 | 是否必填 |
|------|------|---------|
| `-h <host>` | 目标服务器域名或 IP 地址 | 强烈建议 |
| `-p <port>` | 目标端口，默认 443 | 可选 |
| `-t <timeout>` | 连接超时时间（秒），默认 10 | 可选 |

**调用示例**：

```bash
# 基本 TLS 诊断
bash collect_tls_info.sh -h example.com

# 指定端口
bash collect_tls_info.sh -h example.com -p 8443
```

该脚本**一次性完成**以下所有收集：

| 输出类型 | 内容 | 说明 |
|---------|------|------|
| 终端直接输出 | 证书有效期、证书链、密码套件、TLS 版本、OCSP 状态、SNI 信息 | 附带诊断说明 |
| 文件输出 | 完整证书 PEM、证书链文本、openssl 命令输出 | 保存到 `/tmp/tls_diag_*/` |

**收集范围**：

1. **证书基本信息**：`openssl s_client -connect <host>:<port> -showcerts` 完整输出
2. **证书有效期**：证书 notBefore / notAfter 日期，计算剩余有效天数
3. **证书链深度**：服务器返回的证书链长度，检查是否包含中间证书
4. **TLS 版本协商**：支持的 TLS 版本列表（1.0/1.1/1.2/1.3），以及客户端实际协商的版本
5. **密码套件**：服务端支持的密码套件列表，客户端与服务端共有的套件
6. **SNI 信息**：证书 subject 和 subjectAltName 中的域名列表
7. **OCSP 信息**：OCSP responder URL，stapling 状态（OCSP Response Status）
8. **客户端证书要求**：服务器是否请求客户端证书（CertificateRequest 消息）
9. **证书指纹**：SHA256 指纹，用于跨系统比对
10. **错误日志**：连接失败时的完整错误输出

**基线输出**（供后续分支判断使用）：

```
目标：<host:port>
证书主题：<subject>
证书签发者：<issuer>
有效期：<notBefore> ~ <notAfter>（剩余 <N> 天）
证书链深度：<N>
TLS 版本：<version>
密码套件：<cipher_suite>
OCSP 状态：<good/revoked/unknown>
SNI 域名：<domain1, domain2, ...>
错误信息：<error_string/无>
```

---

### Step 3：故障分支定界

按 Step 1 识别结果 + Step 2 基线输出，执行对应分支脚本：

```bash
# 分支 A：证书过期/即将过期
bash scripts/diagnose_cert_expiry.sh -h <host> [-p <port>]

# 分支 B：证书链不完整
bash scripts/diagnose_chain_incomplete.sh -h <host> [-p <port>]

# 分支 C：CA 信任库缺失/过期
bash scripts/diagnose_ca_trust.sh -h <host> [-p <port>]

# 分支 D：TLS 版本/密码套件不兼容
bash scripts/diagnose_cipher_compat.sh -h <host> [-p <port>]

# 分支 E：SNI 配置错误
bash scripts/diagnose_sni.sh -h <host> [-p <port>]

# 分支 F：OCSP stapling 失败
bash scripts/diagnose_ocsp.sh -h <host> [-p <port>]

# 分支 G：客户端证书认证失败
bash scripts/diagnose_client_cert.sh -h <host> [-p <port>]
```

脚本对应参考：

```
TLS/SSL 故障
  ├─ 错误含 "certificate has expired" / "证书过期"            → 分支 A: 证书过期
  ├─ 错误含 "unable to get local issuer" / "证书链不完整"     → 分支 B: 证书链不完整
  ├─ 错误含 "unknown CA" / "certificate verify failed"       → 分支 C: CA 信任库缺失
  ├─ 错误含 "no shared cipher" / "handshake failure"         → 分支 D: 密码套件不兼容
  ├─ 错误含 "certificate name mismatch" / "域名不匹配"       → 分支 E: SNI 配置错误
  ├─ 错误含 "OCSP" / "revoked"                               → 分支 F: OCSP stapling 失败
  └─ 错误含 "bad certificate" / "client certificate"         → 分支 G: 客户端证书认证失败
```

---

### Step 4：假设驱动排查（逐假设验证）

基于 Step 2 基线数据 + Step 3 分支输出，对当前症状构建**多假设树**。

#### 分支 A 示例：证书过期/即将过期

```text
证书已过期或即将过期
├─► 假设 A1: 服务器证书已过期 → notAfter 日期已过当前时间
├─► 假设 A2: 服务器证书即将过期 → notAfter < 30 天内
├─► 假设 A3: 本地系统时间错误 → 客户端系统时间与 NTP 偏差过大
├─► 假设 A4: 中间证书已过期 → 中间证书 notAfter 早于当前时间
├─► 假设 A5: 客户端验证了错误的主机名 → 证书匹配域名而非 IP
```

#### 分支 B 示例：证书链不完整

```text
证书链不完整
├─► 假设 B1: 服务器未发送中间证书 → 仅发送叶证书，无中间链
├─► 假设 B2: 中间证书顺序错误 → 证书链顺序不是叶→中间→根
├─► 假设 B3: 中间证书已过期 → 中间证书不在有效期内
├─► 假设 B4: 中间证书与根 CA 不匹配 → 中间证书的签发者不在信任库中
├─► 假设 B5: 证书自签名未添加到信任库 → 自签名证书未被客户端信任
```

#### 分支 C 示例：CA 信任库缺失/过期

```text
CA 信任库错误
├─► 假设 C1: 根 CA 证书不在信任库 → 客户端的 CA 包未包含签发 CA
├─► 假设 C2: 根 CA 证书已过期 → 信任库中根 CA 证书的 notAfter 已过
├─► 假设 C3: 中间 CA 证书未安装 → 服务器未配置中间 CA 证书
├─► 假设 C4: CA 证书路径错误 → Web 服务器配置的 SSLCACertificateFile 路径错误
├─► 假设 C5: 证书吊销（CRL/OCSP）→ 证书已被签发 CA 吊销
```

#### 分支 D 示例：TLS 版本/密码套件不兼容

```text
TLS 握手失败 - 版本/密码套件不兼容
├─► 假设 D1: 客户端和服务端无共用 TLS 版本 → 一端仅支持 1.3，另一端仅支持 1.2
├─► 假设 D2: 客户端和服务端无共用密码套件 → 密码套件列表无交集
├─► 假设 D3: 服务端禁用特定密码套件 → 安全策略排除了客户端所需的套件
├─► 假设 D4: 客户端强制使用过时的密码套件 → 服务端已禁用弱密码（如 RC4、DES）
├─► 假设 D5: 服务端要求 ClientHello 中特定扩展 → SNI/ALPN 扩展缺失
```

#### 分支 E 示例：SNI 配置错误

```text
SNI 配置错误
├─► 假设 E1: 服务器未配置 SNI → 多域名共享 IP 时返回默认证书
├─► 假设 E2: 证书 subjectAltName 缺少请求域名 → SAN 列表不包含客户端访问的域名
├─► 假设 E3: SNI 指向的证书已过期 → SNI 返回的证书本身已不在有效期内
├─► 假设 E4: 反向代理 SNI 透传失败 → 代理将 TLS 请求转发到后端时 SNI 丢失
├─► 假设 E5: 通配符证书不匹配 → *.example.com 不匹配 sub.sub.example.com
```

#### 分支 F 示例：OCSP stapling 失败

```text
OCSP stapling 失败
├─► 假设 F1: OCSP 响应者不可达 → OCSP responder URL 解析失败或连接超时
├─► 假设 F2: OCSP 响应签名无效 → OCSP 响应者未使用正确的 CA 密钥签名
├─► 假设 F3: 服务器未启用 OCSP stapling → 服务端未配置 SSLStapling
├─► 假设 F4: OCSP 响应已过期 → OCSP 响应的 nextUpdate 早于当前时间
├─► 假设 F5: 证书已被吊销 → OCSP 响应状态为 revoked
```

#### 分支 G 示例：客户端证书认证失败

```text
客户端证书认证失败
├─► 假设 G1: 未发送客户端证书 → 服务器要求客户端证书但客户端未提供
├─► 假设 G2: 客户端证书已过期 → 客户端证书不在有效期内
├─► 假设 G3: 客户端证书未被服务器信任 → 服务器信任库不含签发客户端证书的 CA
├─► 假设 G4: 客户端证书与私钥不匹配 → 证书与私钥的指纹不匹配
├─► 假设 G5: 客户端证书密钥用法不正确 → 证书缺少 clientAuth 扩展密钥用法
```

**每验证一个假设，填写验证记录**：

```
假设：<假设名>
验证操作：<具体 openssl 命令或检查方法>
验证结果：[✅ 确认根因 | ❌ 已排除 | ⚠️ 待进一步验证]
排除依据（如适用）：<具体数据>
```

---

### Step 5：反事实验证（强制；不能止步于"找到原因"）

用根因假设正向推演，与观测现象逐条对齐：

```
✓ 推演的错误信息 == 实际的 openssl 错误输出？
✓ 推演的触发条件 == 证书的实际有效期/链配置？
✓ 推演的故障链路 == 实际的 TLS 握手日志序列？
```

**三条全 ✓ 才能判定"根因确认"**。若不通过，回到 Step 4 补充证据或构建新假设。

---

### Step 6：排除的替代假设

明确记录排除了哪些假设及其排除依据：

```
- 假设A3（系统时间错误）：排除原因 NTP 同步正常，系统时间偏差 < 1s
- 假设B3（中间证书过期）：排除原因 中间证书有效期正常，剩余 > 180 天
- 假设D3（服务端禁用套件）：排除原因 服务端密码套件列表包含客户端请求的套件
```

---

### Step 7：置信度评级

| 等级 | 标识 | 含义 |
|------|------|------|
| 高置信 | 🟢 | 根因已明确，反事实验证全通过，排除所有替代假设 |
| 中置信 | 🟡 | 根因基本确认，但有 1-2 个维度依赖推断 |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 |

---

### Step 8：最终输出（按第七节报告模板落盘）

将 Step 4/5/6/7 的输出填入第七节报告结构。

---

## 第五节：分场景深度分析

### 分支 A：证书过期/即将过期

#### 触发条件

> **先执行专项采集脚本**。

```bash
bash diagnose_cert_expiry.sh -h example.com
```

#### 诊断依据

X.509 证书包含 `notBefore` 和 `notAfter` 字段，定义了证书的有效期窗口。当客户端系统时间落在该窗口之外时，TLS 握手将失败。

**关键诊断命令**：

```bash
# 获取证书有效期
openssl s_client -connect example.com:443 -showcerts 2>/dev/null | openssl x509 -noout -dates

# 计算剩余天数
echo "($(date -d '2026-12-31' +%s) - $(date +%s)) / 86400" | bc

# 查看证书详情
openssl s_client -connect example.com:443 -showcerts 2>/dev/null | openssl x509 -noout -subject -issuer -dates -fingerprint -sha256

# 检查系统时间
date
chronyc tracking 2>/dev/null || ntpq -p 2>/dev/null || timedatectl
```

#### 假设驱动排查

```
假设 A1: 服务器证书已过期
  → 检查方法: 比对 notAfter 与当前系统时间
  → 判定条件: notAfter < 当前时间

假设 A2: 服务器证书即将过期
  → 检查方法: 计算 notAfter - 当前时间
  → 判定条件: 剩余天数 < 30

假设 A3: 本地系统时间错误
  → 检查方法: 对比 date 与 NTP 时间
  → 排除条件: NTP 同步正常，偏差 < 60s

假设 A4: 中间证书已过期
  → 检查方法: 解析证书链中每张证书的有效期
  → 判定条件: 任意中间证书 notAfter < 当前时间

假设 A5: 客户端验证了错误的主机名
  → 检查方法: 比对访问域名与证书 subjectAltName
  → 排除条件: 域名在 SAN 列表中
```

---

### 分支 B：证书链不完整

#### 触发条件

```bash
bash diagnose_chain_incomplete.sh -h example.com
```

#### 诊断依据

TLS 服务器应发送完整的证书链（叶证书 → 中间 CA → 根 CA），但根 CA 证书通常由客户端信任库提供。如果服务器未发送中间证书，客户端无法构建完整信任链。

**关键诊断命令**：

```bash
# 查看服务器发送的证书链
openssl s_client -connect example.com:443 -showcerts 2>/dev/null

# 统计证书链数量
openssl s_client -connect example.com:443 -showcerts 2>/dev/null | grep -c "subject="

# 验证证书链（用本地信任库）
openssl verify -CApath /etc/ssl/certs example.pem

# 指定中间证书验证
openssl verify -CAfile root.pem -untrusted intermediate.pem server.pem
```

---

### 分支 C：CA 信任库缺失/过期

#### 触发条件

```bash
bash diagnose_ca_trust.sh -h example.com
```

#### 诊断依据

客户端必须信任签发服务器证书的 CA。信任库缺失或过期会导致 `certificate verify failed` 错误。

**关键诊断命令**：

```bash
# 查看服务器证书的签发者
openssl s_client -connect example.com:443 -showcerts 2>/dev/null | openssl x509 -noout -issuer

# 查看本地信任库中是否有签发 CA
openssl crl2pkcs7 /etc/ssl/certs/ca-certificates.crt 2>/dev/null | openssl pkcs7 -print_certs | grep -i "issuer_name"

# 使用指定 CA 包验证
openssl s_client -connect example.com:443 -CAfile /etc/ssl/certs/ca-certificates.crt

# 检查证书吊销状态
openssl ocsp -issuer issuer.pem -cert server.pem -url "$(openssl x509 -in server.pem -noout -ocsp_uri)"
```

---

### 分支 D：TLS 版本/密码套件不兼容

#### 触发条件

```bash
bash diagnose_cipher_compat.sh -h example.com
```

#### 诊断依据

TLS 版本和密码套件通过 ClientHello 和 ServerHello 协商。如果两端支持的版本或套件无交集，握手将失败。

**关键诊断命令**：

```bash
# 查看服务端支持的 TLS 版本
openssl s_client -connect example.com:443 -tls1_2
openssl s_client -connect example.com:443 -tls1_3

# 查看服务端支持的密码套件
openssl s_client -connect example.com:443 -cipher 'ALL:COMPLEMENTOFALL' 2>/dev/null | grep "Cipher"

# 列出所有可用的密码套件
openssl ciphers -v 'ALL:COMPLEMENTOFALL'

# 测试特定密码套件
openssl s_client -connect example.com:443 -cipher AES256-GCM-SHA384
```

---

### 分支 E：SNI 配置错误

#### 触发条件

```bash
bash diagnose_sni.sh -h example.com
```

#### 诊断依据

SNI（Server Name Indication）允许客户端在 ClientHello 中指定目标域名，使服务端返回对应的证书。配置错误会导致返回默认证书而非正确域名证书。

**关键诊断命令**：

```bash
# 带 SNI 连接（指定域名）
openssl s_client -connect 1.2.3.4:443 -servername www.example.com -showcerts

# 不带 SNI 连接（获取默认证书）
openssl s_client -connect 1.2.3.4:443 -showcerts

# 查看证书的 subject 和 SAN
openssl x509 -in cert.pem -noout -subject -ext subjectAltName

# 测试 SNI 通配符
openssl s_client -connect example.com:443 -servername sub.example.com
```

---

### 分支 F：OCSP stapling 失败

#### 触发条件

```bash
bash diagnose_ocsp.sh -h example.com
```

#### 诊断依据

OCSP（Online Certificate Status Protocol）stapling 允许服务端将证书的实时状态附加到 TLS 握手中。如果配置不当，客户端可能无法验证证书是否被吊销。

**关键诊断命令**：

```bash
# 检查 OCSP stapling 状态
openssl s_client -connect example.com:443 -status 2>/dev/null | grep -A20 "OCSP response"

# 获取 OCSP responder URL
openssl x509 -in cert.pem -noout -ocsp_uri

# 手动查询 OCSP 响应者
openssl ocsp -issuer issuer.pem -cert server.pem -url http://ocsp.example.com -header Host=ocsp.example.com

# 检查 stapling 是否超时
openssl s_client -connect example.com:443 -status -timeout 5
```

---

### 分支 G：客户端证书认证失败

#### 触发条件

```bash
bash diagnose_client_cert.sh -h example.com
```

#### 诊断依据

服务端可以要求客户端提供证书进行双向 TLS 认证。如果客户端未提供、提供了过期或不受信任的证书，握手将失败。

**关键诊断命令**：

```bash
# 检查服务端是否请求客户端证书
openssl s_client -connect example.com:443 -showcerts 2>/dev/null | grep "Acceptable client certificate CA names"

# 使用客户端证书连接
openssl s_client -connect example.com:443 -cert client.pem -key client.key

# 检查客户端证书有效期
openssl x509 -in client.pem -noout -dates

# 检查客户端证书与私钥匹配
openssl x509 -in client.pem -noout -modulus | openssl md5
openssl rsa -in client.key -noout -modulus | openssl md5
# 两个 md5 值应相同

# 检查证书密钥用法
openssl x509 -in client.pem -noout -ext extendedKeyUsage
```

---

## 第六节：注意事项与常见误判陷阱

### 常见误判陷阱

| 陷阱 | 说明 | 应对方式 |
|------|------|---------|
| **证书过期 vs 系统时间错误** | 客户端系统时间偏差可能导致有效证书被判定为已过期 | 先检查 NTP 同步状态，再检查证书有效期 |
| **证书链不完整 vs CA 信任库缺失** | 两者都可能产生"unable to get local issuer"错误 | 用 `-showcerts` 检查服务器发送的链，再对比本地信任库 |
| **同一 IP 多域名场景** | 不带 SNI 连接可能拿到默认证书而非目标域名的证书 | 始终使用 `-servername` 指定目标域名 |
| **密码套件名称差异** | OpenSSL 和 Java/Go 客户端对同一套件的命名可能不同 | 以 OpenSSL 的命名格式为标准，使用十六进制套件编号辅助比对 |
| **OCSP 响应者不可达 ≠ 证书被吊销** | OCSP 连接超时不代表证书有问题 | 区分 OCSP stapling 状态：good / revoked / unknown |
| **自签名证书 ≠ 不安全** | 开发/测试环境使用自签名证书是合理做法 | 仅在可达公网的生产环境判定为风险 |

### OpenSSL 版本注意事项

| OpenSSL 版本 | 变化 | 影响 |
|-------------|------|------|
| 1.0.2 | 支持 TLS 1.2 | 旧版默认不启用 TLS 1.2 |
| 1.1.0 | TLS 1.3 支持预览 | 需额外编译参数 |
| 1.1.1 | 完整 TLS 1.3 支持 | 默认启用 TLS 1.3 |
| 3.0 | 全新版本架构，Legacy Provider | 默认不启用传统密码套件 |
| 3.2 | 证书压缩支持 | FIPS 合规要求可能需要禁用 |

---

## 第七节：最终报告结构

```markdown
# 🔴 TLS/SSL 证书与握手故障诊断报告

## 一、故障概览
- 故障标题：<根因类型>
- 故障级别：[P0(严重) | P1(高) | P2(中) | P3(低)]
- 影响范围：<受影响的域名/服务>
- 故障时段：<T0 ~ T1>
- 当前状态：[🔴 处理中 | 🟢 已恢复 | 🟡 待确认]
- 根因置信度：[🟢 高置信 | 🟡 中置信 | 🟠 低置信 | 🔴 未知]

## 二、根因速览
**根本原因**：<一句话描述>

### 故障因果链
```
[触发条件] → [中间环节] → [TLS 握手失败]
```

### 事故时间线
| 时间点 | 事件 | 证据来源 |
|--------|------|---------|
| T0 | <故障触发> | <openssl 输出/错误日志> |

## 三、假设驱动排查
| 假设 | 验证操作 | 结果 | 排除依据 |
|------|---------|------|---------|
| <假设> | <方法> | 🎯 确认/❌ 排除 | <依据> |

## 四、关键证据
1. **证据1**：<描述> — 文件：<path> — 关键内容：<数据>

## 五、反事实验证
| 维度 | 推演结果 | 实际现象 | 是否吻合 |
|------|---------|---------|---------|
| 错误信息 | <推演> | <实际> | □ 是 □ 否 |

## 六、排除的替代假设
- **假设X**：排除原因 <具体数据>

## 七、修复建议
### 应急处置
1. <操作>
### 永久修复
1. <措施>
### 预防措施
1. <措施>

## 八、附件
- openssl 命令输出：<路径>
- 证书文件：<路径>
- 完整错误日志：<路径>
```

---

## 第八节：故障模式速查表

| 故障模式 | 关键错误信息 | 一键诊断 | 诊断工具 |
|---------|-------------|---------|---------|
| 证书过期 | `certificate has expired` | `diagnose_cert_expiry.sh` | `openssl s_client` |
| 证书链不完整 | `unable to get local issuer certificate` | `diagnose_chain_incomplete.sh` | `openssl verify` |
| CA 信任库缺失 | `certificate verify failed` | `diagnose_ca_trust.sh` | `openssl s_client -CAfile` |
| TLS 版本/密码套件不兼容 | `no shared cipher` / `handshake failure` | `diagnose_cipher_compat.sh` | `openssl ciphers` |
| SNI 配置错误 | `SSL_ERROR_BAD_CERT_DOMAIN` | `diagnose_sni.sh` | `openssl s_client -servername` |
| OCSP stapling 失败 | `OCSP response error` | `diagnose_ocsp.sh` | `openssl ocsp` |
| 客户端证书失败 | `bad certificate` | `diagnose_client_cert.sh` | `openssl s_client -cert` |

---

## 第九节：参考文件

- `references/tls_fault_scenarios.md`：TLS/SSL 故障场景分类与特征表
- `references/tls_diagnosis_commands.md`：TLS 诊断命令与工具参考
- `references/openssl_reference.md`：OpenSSL 参数与配置参考
- 外部工具：`openssl`（核心诊断工具）、`curl`（HTTP over TLS 测试）、`nmap`（端口/TLS 扫描）
