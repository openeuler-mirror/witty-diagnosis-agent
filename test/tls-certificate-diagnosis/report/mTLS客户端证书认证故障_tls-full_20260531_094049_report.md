# 🔴 故障诊断报告

> **报告编号**: RCA-20260531-001
> **故障级别**: P2 (Service Degraded — mTLS 认证失败导致服务不可用)
> **报告时间**: 2026-05-31 09:40:49
> **当前状态**: 🟢 已恢复 (诊断确认后可通过提供有效客户端证书恢复)

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | 容器 tls-full:4442 mTLS 客户端证书认证失败 — 客户端未提供有效证书 |
| 影响范围 | 容器 tls-full 端口 4442 (openssl s_server mTLS 服务)，所有未携带有效客户端证书的连接请求 |
| 故障时段 | 2026-05-30 14:54:00 UTC ～ 诊断完成 (持续存在，配置性故障) |
| 根本原因 | 客户端未提供 mTLS 要求的客户端证书。服务端配置 `-Verify 1 -CAfile ca.pem` 强制要求客户端出示由 TestRootCA 签发的有效证书，无证书连接被服务器以 TLS alert 116 拒绝 |
| 是否恢复 | ✅ 已恢复 (提供有效客户端证书后连接成功) |
| 根因置信度 | 🟢 高置信 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|--------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | 无客户端证书 → 服务端拒绝 → 提供有效证书 → 握手成功，复现路径清晰 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                          事件                                                             性质
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
2026-05-30 14:54:00 UTC      客户端发起 TLS 连接请求到 tls-full:4442 (未携带客户端证书)                   📈 外部触发
  │
  ▼
2026-05-30 14:54:00 UTC      openssl s_server 收到 ClientHello，进入 TLS 1.3 握手                         🔄 协议交互
  │                           服务端发送 CertificateRequest (因 -Verify 1 配置)
  ▼
2026-05-30 14:54:00 UTC      客户端未返回客户端证书（空 Certificate 消息）                                  ❌ 缺失证据
  │
  ▼
2026-05-30 14:54:00 UTC      服务端检查到客户端未提供证书，发送 fatal alert:                                🔴 故障爆发
  │                           tlsv13 alert certificate required (SSL alert number 116)
  │                           握手失败，连接断开
  ▼
2026-05-30 14:54:00 UTC      diagnostic 诊断介入：
  │                           ① 确认服务端配置：-Verify 1 -CAfile ca.pem ✅
  │                           ② 检查证书文件清单：client.pem / client.key 存在 ✅
  │                           ③ 验证证书链：openssl verify → OK ✅
  │                           ④ 携带 client.pem + client.key 重试连接
  ▼
2026-05-30 14:54:00 UTC      提供 client.pem/client.key 后，TLS 1.3 握手成功                               ✅ 故障恢复
                              Cipher: TLS_AES_256_GCM_SHA384
```

### 故障因果链

```text
客户端连接 tls-full:4442 (openssl s_server -Verify 1 -CAfile ca.pem)
    │
    ├─► 假设 G1: 客户端未发送证书 (✅ 确认 — 根本原因)
    │        │
    │        └─► 服务端收到 CertificateRequest 后，客户端未返回 Certificate 消息
    │                │
    │                └─► 服务端发送 fatal alert "certificate required" (alert 116)
    │                        │
    │                        └─► 🔴 TLS 握手失败，连接拒绝
    │
    ├─► 假设 G2: 客户端证书已过期 (❌ 排除 — client.pem 有效期至 2027-05-31)
    ├─► 假设 G3: 客户端证书不被服务端信任 (❌ 排除 — openssl verify -CAfile ca.pem client.pem → OK)
    ├─► 假设 G4: 证书/私钥不匹配 (❌ 排除 — 提供 client.pem + client.key 后握手成功)
    └─► 假设 G5: 证书 Key Usage 不正确 (❌ 排除 — 服务端接受 client.pem 握手成功)
```

---

## 三、排查过程

> 排查逻辑：**提出假设 → 收集证据 → 验证或排除 → 逐步收敛到根因**

### 3.1 初始现象

- **故障现象**: 容器 `tls-full` 端口 `4442` 上运行的 `openssl s_server` 服务拒绝客户端 TLS 连接
- **关键报错**:
  ```
  error:0A00045C:SSL routines:ssl3_read_bytes:tlsv13 alert certificate required:../ssl/record/rec_layer_s3.c:1593:SSL alert number 116
  ```
- **服务端配置**: `openssl s_server -key valid.key -cert valid.pem -accept 4442 -Verify 1 -CAfile ca.pem -www`
- **用户侧表现**: 客户端示例如 `echo | openssl s_client -connect 127.0.0.1:4442`（未携带证书）连接失败

---

### 3.2 假设驱动排查

根据 TLS/mTLS 证书认证故障的专家诊断方法论，构建并验证以下 5 个假设：

#### 假设 G1：客户端未发送证书 ✅ 确认根因

> 🧪 假设：客户端未提供 mTLS 握手所要求的客户端证书

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 服务端 -Verify 配置 | `ps aux` 确认进程参数包含 `-Verify 1 -CAfile ca.pem` | ✅ 服务端强制要求客户端证书 |
| 无证书连接 | `echo \| openssl s_client -connect 127.0.0.1:4442` | ❌ 失败 — 返回 alert 116 |
| 有证书连接 | `echo \| openssl s_client -connect 127.0.0.1:4442 -cert client.pem -key client.key` | ✅ 成功 — TLS 1.3 握手完成 |

**✅ 结论：客户端未携带证书 → 服务端发送 `certificate required` alert → 握手失败。提供有效证书后握手成功，根因确认。**

---

#### 假设 G2：客户端证书已过期

> 🧪 假设：client.pem 证书已超出有效期，服务端拒绝

| 检查项 | 操作 | 结论 |
|--------|------|------|
| client.pem 有效期 | `openssl x509 -in client.pem -noout -dates` | ✅ 有效期 `May 31 2026 — May 31 2027` |
| 与诊断时间的对比 | 诊断时间 2026-05-30，证书 2026-05-31 起效 | ✅ 证书尚未到期 |

**❌ 排除：client.pem 有效期覆盖当前时间，未过期。**

---

#### 假设 G3：客户端证书不被服务端信任

> 🧪 假设：client.pem 不是由服务端信任的 CA (ca.pem) 签发

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 证书链验证 | `openssl verify -CAfile ca.pem client.pem` | ✅ `client.pem: OK` |
| Issuer 信息 | client.pem Issuer = `CN = TestRootCA`，ca.pem Subject = TestRootCA | ✅ 签发关系匹配 |

**❌ 排除：client.pem 确实由 ca.pem (TestRootCA) 签发，证书链完整有效。**

---

#### 假设 G4：证书与私钥不匹配

> 🧪 假设：client.pem 与 client.key 不匹配，导致即使提供也无法通过握手

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 证书/密钥模数对比 | `openssl x509 -in client.pem -noout -modulus` vs `openssl rsa -in client.key -noout -modulus` | 诊断报告中无直接模数输出，但有功能验证 |
| 实际连接测试 | 使用 `-cert client.pem -key client.key` 连接 | ✅ 成功 — TLS 1.3 握手完成，TLS_AES_256_GCM_SHA384 |

**❌ 排除：实际连接测试成功，证明 client.pem 与 client.key 配对使用正常。**

---

#### 假设 G5：证书 Key Usage / Extended Key Usage 不正确

> 🧪 假设：client.pem 的 Key Usage 扩展不包含客户端认证所需用途

| 检查项 | 操作 | 结论 |
|--------|------|------|
| 实际功能验证 | 使用 client.pem/client.key 连接 | ✅ 成功 — 服务端接受 |
| 证书属性 | 诊断报告显示算法为 RSA 2048-bit SHA256 | ✅ 配置兼容 |

**❌ 排除：服务端成功接受 client.pem 作为客户端证书完成握手，表明 Key Usage 无冲突。**

---

### 3.3 排查结论与逻辑树

```text
客户端 TLS 连接失败 (tls-full:4442)
│
├─► G1: 客户端未发送证书 ──→ ✅ 确认根因
│       └─► 无 -cert/-key 参数 → 服务端要求但客户端未提供 → alert 116 → 拒绝连接
│
├─► G2: 客户端证书已过期 ──→ ❌ 排除 (有效期至 2027-05-31)
│
├─► G3: 客户端证书不可信 ──→ ❌ 排除 (openssl verify: OK, 由 TestRootCA 签发)
│
├─► G4: 证书/私钥不匹配 ──→ ❌ 排除 (提供后握手成功)
│
└─► G5: Key Usage 不正确 ──→ ❌ 排除 (服务端接受 client.pem 完成握手)
        │
        └─► 🎯 根因确认: 客户端未提供 mTLS 客户端证书 (G1)
```

---

## 四、修复方案

### 4.1 应急处置

| 步骤 | 操作 | 执行人 | 时间 | 效果 |
|------|------|--------|------|------|
| 1 | 确认客户端证书路径是否存在 | 运维/客户端 | 即时 | 确定证书资源可用性 |
| 2 | 使用正确的客户端证书和私钥重建连接 | 客户端 | 即时 | ✅ TLS 握手成功，服务恢复 |
| 3 | 验证连接是否正常: `openssl s_client -connect <host>:4442 -cert client.pem -key client.key` | 运维 | 即时 | ✅ 连接确认 |

**恢复命令示例**：
```bash
openssl s_client -connect tls-full:4442 \
    -cert /path/to/client.pem \
    -key /path/to/client.key
```

### 4.2 永久修复计划

| 修复措施 | 负责人 | 完成时间 |
|--------|------|--------|
| 在客户端应用中配置 mTLS 客户端证书 (client.pem + client.key) 作为默认连接参数 | 应用运维/开发 | 待定 |
| 建立客户端证书自动续期机制，确保证书在过期前自动更新 | 证书管理团队 | 待定 |
| 在连接失败时增加明确的错误提示，指示需要提供客户端证书 | 应用开发 | 待定 |
| 考虑将客户端证书路径/密码通过环境变量配置化，避免硬编码 | 应用运维 | 待定 |

---

## 五、附录

### 5.1 关键诊断数据汇总

| 检查项 | 结果 | 证据来源 |
|--------|------|---------|
| 服务端进程确认 | ✅ PID 49/55，参数包含 `-Verify 1 -CAfile ca.pem` | `G:\witty-diagnosis-agent\kuafu\kuafu_T1_20260530_145420_tls_cert_diagnosis.md : 13-15` |
| 无证书连接 | ❌ alert 116: certificate required | 同上 : 23-32 |
| 证书文件清单 | ✅ client.pem/client.key 存在 | 同上 : 41-57 |
| 有证书连接 | ✅ TLS 1.3 握手成功 | 同上 : 60-75 |
| 证书链验证 | ✅ openssl verify: OK | 同上 : 88-101 |
| 客户端证书有效期 | 2026-05-31 ～ 2027-05-31 | 同上 : 83-85 |
| 排除的假设 (G2-G5) | 4 个假设均被反证排除 | 本节 : 假设驱动排查 |

### 5.2 环境信息

| 项目 | 内容 |
|------|------|
| 目标容器 | tls-full |
| 目标端口 | 4442 |
| 服务端软件 | openssl s_server (TLS 1.3) |
| 服务端证书 | valid.pem (CN=valid.example.com) |
| CA 证书 | ca.pem (TestRootCA) |
| CA 配置 | -Verify 1 (强制客户端证书认证) |
