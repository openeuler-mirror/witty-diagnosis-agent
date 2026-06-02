# Crypto/SSL Cost - 加解密与 TLS 握手分析剧本

## 触发条件

用户问题包含以下关键词：
- "TLS 慢"、"HTTPS 慢"、"SSL 握手慢"
- "加密"、"解密"、"加解密"
- "AES"、"RSA"、"ECDHE"
- "证书"、"cert"、"CA"
- "国密"、"SM2"、"SM4"
- "CPU 高" 且涉及 HTTPS / 加密通信

## 场景说明

加解密是另一类"看不见的开销"：
- **对称加密**（AES/ChaCha20）：常用于数据加密传输，CPU 密集
- **非对称加密**（RSA/ECDHE）：常用于 TLS 握手，受密钥长度影响显著
- **哈希**（SHA256/MD5）：签名、消息认证
- **TLS 握手**：HTTPS 请求的隐性延迟来源

典型症状：
- HTTPS 接口 P99 远高于 HTTP
- 火焰图中 `AES_` / `RSA_` / `SSL_*` 出现明显宽度
- 服务端 CPU 在握手时尖刺
- QPS 上不去，但 CPU 利用率看似不高

## 分析流程

### Step 1: 数据准备

1. 转换为折叠栈格式
2. 标记 RPC 入口/出口，便于识别"在做什么时加解密"

### Step 2: 加解密模式检测

```bash
python scripts/analyzers/pattern_match.py --input folded.folded --json
```

重点匹配（来自 `analysis-patterns.md` 第 7 类）：

| 类别 | 特征函数/符号 | 权重 |
|------|-------------|------|
| 对称加密 | `AES_`, `DES_`, `ChaCha20_*`, `Cipher`, `EncryptBlock`, `DecryptBlock` | 0.9 |
| 非对称加密 | `RSA_`, `ECDSA_*`, `ECDH_*`, `DSA_*`, `signer.sign`, `verifier.verify` | 1.0 |
| 哈希 | `SHA1`, `SHA256`, `SHA512`, `MD5`, `HmacSHA*`, `blake2*` | 0.7 |
| SSL/TLS | `SSL_read`, `SSL_write`, `SSL_do_handshake`, `tls.Handshake`, `crypto/tls` | 1.0 |
| 国密 | `SM2_*`, `SM3_*`, `SM4_*`, `gm_*`, `gmssl` | 0.9 |
| HKDF/PRF | `HKDF`, `PRF`, `tls13.derive` | 0.7 |

### Step 3: 加密热点分析

```bash
python scripts/analyzers/hotspot.py --input folded.folded --top 30 --json
```

按"叶帧是加解密函数"聚合：
- 加密类型占比：AES vs RSA vs SHA
- 在哪个业务路径上：`HttpServer` / `MessageDispatcher` / `DataEncryptor`
- 加密粒度：每请求一次 vs 整批一次

### Step 4: TLS 握手分析

针对 HTTPS 服务，重点区分：
- **握手路径**：`SSL_do_handshake` / `tls.Handshake` —— 一次性，但延迟显著
- **数据传输路径**：`SSL_read` / `SSL_write` —— 持续性，CPU 占比可能更高

```bash
# 火焰图中搜 TLS 握手
grep -E "SSL_do_handshake|tls\.Handshake" folded.folded
```

## 输出结构

```
## 加解密分析

### 加解密总占比
- 加解密合计: XX%
- TLS 握手: XX%
- 对称加密: XX%
- 非对称加密: XX%
- 哈希: XX%

### 加密类型分布
| 类别 | 算法 | 占比 | 业务路径 |
|------|------|------|----------|
| 对称 | AES-128-GCM | 15% | HTTPS 数据通道 |
| 非对称 | RSA-2048 | 8% | 数字签名 |
| 哈希 | SHA-256 | 5% | 消息认证 |
| TLS 握手 | TLS 1.2 | 3% | 每次新建连接 |

### 热点栈
| 入口 | 库 | 占比 | 备注 |
|------|----|------|------|
| HttpServer.handle | BoringSSL | 18% | AES-NI 未启用？ |
| DataEncryptor.encrypt | JCE | 5% | 软件实现 |

### TLS 握手分析
- 每次握手耗时（墙钟）: XX ms
- 握手频次: XX/s
- TLS 版本分布: TLS 1.2 XX% / TLS 1.3 XX%
- 密钥交换算法: RSA / ECDHE
```

## 阈值标准

| 指标 | 阈值 | 严重度 |
|------|------|--------|
| 加解密总占比 | > 5% | 中（可优化点） |
| 加解密总占比 | > 15% | 高（首要看点） |
| TLS 握手 P99 | > 100ms | 中（用户体验影响） |
| TLS 握手 P99 | > 500ms | 高（明显瓶颈） |
| 握手频次 / QPS | > 50% | 高（未启用会话复用） |
| 非对称加密占比 | > 5% | 高（应评估是否可批量） |
| 单次 RSA-2048 签名 | > 5ms | 中（CPU 算力不足） |

## 典型场景

### 场景 1: HTTPS 握手频繁，未启用会话复用

**症状**：
- 每次请求都走完整 TLS 握手
- `SSL_do_handshake` 占比 > 5%
- HTTPS 接口 P99 远高于 HTTP

**根因**：
未配置 `SSL_SESSION_CACHE` / `session tickets` / TLS 1.3 0-RTT。

**修复**：
- 启用服务端 session cache：`SSL_CTX_set_session_cache_mode(ctx, SSL_SESS_CACHE_SERVER)`
- 设置合理超时：`SSL_CTX_set_timeout(ctx, timeout)`
- 升级到 TLS 1.3，启用 0-RTT
- 客户端配合：`keep-alive` + `SSL_OP_NO_TICKET` 慎用

### 场景 2: CPU 加密未走硬件加速

**症状**：
- 火焰图中纯软件实现的 AES 占比高
- 加密相关函数调用密集

**根因**：
未启用 AES-NI / ARMv8 Crypto Extensions 硬件加速。

**修复**：
- **OpenSSL/BoringSSL**：确认编译时启用 `-maes -msse4` 等指令
- **Java**：JCE 自动检测 `-XX:+UseAES` / `-XX:+UseAESIntrinsics`
- **Go**：`crypto/aes` 已在 amd64 上自动用 AES-NI
- 检查 `lscpu` 是否有 `aes` 标志

### 场景 3: RSA 签名过于频繁

**症状**：
- 火焰图 `RSA_*` / `signer.sign` 占比 > 3%
- 每个请求/消息都做一次 RSA 签名

**根因**：
- 用 RSA 签名做身份认证（应改用 HMAC 或 ECDSA）
- 每次握手都用 RSA 密钥交换（应改用 ECDHE）

**修复**：
- 用 ECDHE 做密钥交换（比 RSA 快 10x+）
- 签名场景用 ECDSA（比 RSA 快 50x+）
- 预计算能缓存的签名

### 场景 4: 整消息加密粒度过细

**症状**：
- 每个小消息都做 AES 加密
- 加密频率高，加密数据量小

**修复**：
- 合并消息批量加密（AES-NI 吞吐高，小消息浪费）
- 预共享密钥，避免每会话都协商
- 考虑流式加密（只在敏感字段加密）

### 场景 5: 自实现的加密算法

**症状**：
- 火焰图含 `MyCipher.encrypt` / `CustomCrypto.*`
- 占用大量 CPU

**问题**：
- 自实现加密几乎都是错的（侧信道、padding oracle）
- 性能也远不如标准库

**修复**：
- 立即替换为标准库
- 选型：AES-GCM（认证加密）/ ChaCha20-Poly1305（移动端）
- 密钥管理用 KMS / Vault

### 场景 6: 国密算法性能

**症状**：
- 使用 SM2/SM3/SM4 等国密
- CPU 占比高

**特点**：
- 国密软实现性能差于国际算法
- 部分硬件支持 SM 系列指令（如 ARM v9）

**修复**：
- 评估是否必须国密（监管要求）
- 使用国密硬件加速卡
- 启用国密 OpenSSL 优化版本（如 GmSSL）

## 关键识别表

| 算法 | 用途 | 性能特征 | 替代 |
|------|------|---------|------|
| AES-128-GCM | 数据加密 | ⭐⭐⭐⭐⭐（硬件加速） | ChaCha20-Poly1305 |
| AES-256-CBC | 旧系统数据加密 | ⭐⭐⭐⭐ | AES-GCM |
| RSA-2048 | 签名/密钥交换 | ⭐⭐ | ECDSA / ECDHE |
| RSA-4096 | 高安全场景 | ⭐ | 评估是否必须 |
| ECDSA-P256 | 签名 | ⭐⭐⭐⭐ | Ed25519 |
| ECDHE-P256 | 密钥交换 | ⭐⭐⭐⭐ | X25519 |
| SHA-256 | 哈希 | ⭐⭐⭐⭐ | SHA-3 / BLAKE2 |
| MD5 | 旧哈希 | ⭐⭐⭐⭐⭐ | 立刻替换（已不安全） |
| SM2 | 国密签名 | ⭐⭐ | 监管要求时保留 |
| SM3 | 国密哈希 | ⭐⭐⭐ | 监管要求时保留 |
| SM4 | 国密对称 | ⭐⭐⭐ | 监管要求时保留 |

## 与其他剧本的协同

| 关联剧本 | 协同方式 |
|---------|---------|
| [io-wait.md](io-wait.md) | TLS 握手含网络往返，与 TCP 延迟叠加 |
| [why-cpu-high.md](why-cpu-high.md) | 加解密常是 on-CPU 热点来源 |
| [serialization-cost.md](serialization-cost.md) | 加密前的明文数据序列化也是开销 |

## 优化建议

### 1. 启用硬件加速

- AES-NI（Intel/AMD）：`lscpu | grep aes`
- ARMv8 Crypto Extensions（移动/服务器）
- 检测方式：JCE `Cipher.getMaxAllowedKeyLength` / OpenSSL `openssl speed -evp aes-256-gcm`

### 2. 减少握手次数

- 启用 TLS 1.3（0-RTT、1-RTT 握手）
- 启用 session cache / session tickets
- 客户端 keep-alive + 连接复用
- 用连接池（HTTP/2 多路复用天然减少握手）

### 3. 批量加密

- 合并小消息为大批量
- 流式加密只覆盖敏感字段
- 预计算 + 缓存

### 4. 替换慢算法

- RSA-2048 → ECDSA-P256 / Ed25519
- AES-CBC → AES-GCM（认证加密）
- MD5/SHA-1 → SHA-256 / BLAKE2

### 5. 卸载

- **SSL 卸载卡**：硬件加速握手与加密
- **KMS 卸载**：私钥操作卸载到 HSM
- **TLS termination**：用 Nginx/Envoy 反代 TLS

### 6. 协议层

- 升级到 HTTP/2（多路复用减少握手）
- 启用 OCSP Stapling
- 减少证书链长度

## 配套工具命令

```bash
# TLS 握手延迟（用 curl 测）
curl -w "time_appconnect: %{time_appconnect}\n" -o /dev/null -s https://example.com

# OpenSSL 性能测试
openssl speed -evp aes-256-gcm
openssl speed rsa2048
openssl speed ecdsap256

# 火焰图中的加密函数
perf script | grep -E "(AES_|RSA_|SSL_|tls\.Handshake)"

# CPU 硬件加速检测
lscpu | grep -E "(aes|avx|sha)"

# 抓包分析握手
tcpdump -i any -nn -A 'tcp port 443' -w https.pcap
```

## 常见误判

- **"TLS 慢" 不一定是加密慢**：可能是 TCP 三次握手 + TLS 握手的网络往返延迟
- **"RSA 慢" 不一定换算法**：可能密钥长度不匹配，检查实际使用的密钥
- **"握手频次高" 不一定没复用**：HTTP/2 下 1 个连接承载多个请求，少量握手即可
- **"加密占比高" 不一定需要优化**：金融/安全场景必须加密，CPU 开销是合理的
