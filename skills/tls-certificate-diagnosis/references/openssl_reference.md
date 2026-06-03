# OpenSSL 参数与配置参考

## 1. TLS 版本支持

| 版本 | OpenSSL 参数 | 安全性 | 状态 |
|------|-------------|--------|------|
| SSL 3.0 | `-ssl3` | ❌ 不安全 | 已废弃（POODLE 攻击） |
| TLS 1.0 | `-tls1` | ⚠️ 低 | 已弃用（BEAST 攻击） |
| TLS 1.1 | `-tls1_1` | ⚠️ 低 | 已弃用 |
| TLS 1.2 | `-tls1_2` | ✅ 安全 | 当前主流版本 |
| TLS 1.3 | `-tls1_3` | ✅ 最安全 | 现代推荐版本 |

## 2. 常见密码套件分类

| 套件类型 | 示例 | 安全性 | 说明 |
|---------|------|--------|------|
| TLS_AES_256_GCM_SHA384 | `0x13,0x02` | 🟢 安全 | TLS 1.3 默认套件 |
| TLS_AES_128_GCM_SHA256 | `0x13,0x01` | 🟢 安全 | TLS 1.3 推荐 |
| ECDHE-RSA-AES256-GCM-SHA384 | `0xC0,0x30` | 🟢 安全 | 前向安全 |
| ECDHE-RSA-AES128-GCM-SHA256 | `0xC0,0x2F` | 🟢 安全 | 前向安全 |
| ECDHE-RSA-CHACHA20-POLY1305 | `0xCC,0xA8` | 🟢 安全 | 移动端优化 |
| DHE-RSA-AES256-GCM-SHA384 | `0x9F` | 🟡 中等 | 前向安全但性能较低 |
| AES256-GCM-SHA384 | `0x9D` | 🟡 中等 | 无前向安全 |
| ECDHE-RSA-AES128-SHA | `0xC0,0x13` | 🟠 弱 | TLS 1.2 但使用 SHA-1 |
| RC4-SHA | `0x04` | 🔴 不安全 | 已禁用 |
| DES-CBC3-SHA | `0x0A` | 🔴 不安全 | 3DES, 已禁用 |

## 3. 证书链结构

```
叶证书 (End-Entity / Leaf Certificate)
  └─► 由中间 CA 签发
        └─► 由中间 CA2 签发（可选）
              └─► 由根 CA (Root CA) 签发（根 CA 自签名）
```

### 证书链验证必经检查

| 检查项 | 说明 |
|--------|------|
| 有效期 | 每张证书的 notBefore/notAfter 必须包含当前时间 |
| 签名 | 每张证书的签名必须由其签发者的公钥验证 |
| 信任锚 | 根证书必须在客户端信任库中 |
| 名称匹配 | 叶证书的 CN/SAN 必须匹配访问的域名 |
| 密钥用法 | 叶证书必须包含 digitalSignature 或 keyEncipherment |
| 吊销状态 | OCSP/CRL 确认证书未被吊销 |

## 4. 证书扩展关键字段

| 扩展字段 | OID | 用途 |
|---------|-----|------|
| subjectAltName (SAN) | 2.5.29.17 | 证书适用的域名列表 |
| Extended Key Usage | 2.5.29.37 | 证书用途（serverAuth/clientAuth）|
| Basic Constraints | 2.5.29.19 | 标记是否为 CA 证书 |
| Key Usage | 2.5.29.15 | 密钥用途（digitalSignature/keyEncipherment）|
| Authority Key Identifier | 2.5.29.35 | 签发者公钥标识 |
| Subject Key Identifier | 2.5.29.14 | 本证书公钥标识 |
| CRL Distribution Points | 2.5.29.31 | CRL 下载地址 |
| Authority Info Access | 1.3.6.1.5.5.7.1.1 | CA Issuers 和 OCSP Responder URL |

## 5. 常见 OpenSSL 错误码

| 错误码 | 含义 |
|--------|------|
| X509_V_OK | 验证通过 |
| X509_V_ERR_CERT_HAS_EXPIRED | 证书已过期 |
| X509_V_ERR_CERT_NOT_YET_VALID | 证书尚未生效 |
| X509_V_ERR_CERT_REVOKED | 证书已被吊销 |
| X509_V_ERR_UNABLE_TO_GET_ISSUER_CERT | 无法获取签发者证书 |
| X509_V_ERR_UNABLE_TO_DECRYPT_CERT_SIGNATURE | 无法解密证书签名 |
| X509_V_ERR_CERT_SIGNATURE_FAILURE | 证书签名验证失败 |
| X509_V_ERR_DEPTH_ZERO_SELF_SIGNED_CERT | 自签名证书（未添加到信任库）|
| X509_V_ERR_SELF_SIGNED_CERT_IN_CHAIN | 证书链中包含自签名证书 |
| X509_V_ERR_UNABLE_TO_GET_CRL | 无法获取 CRL |
| X509_V_ERR_CERT_UNTRUSTED | 证书不受信任 |

## 6. 密码套件协商优先级顺序

```
客户端 ClientHello (按优先级排列的密码套件列表)
  └─► 服务端 ServerHello (选择列表中最优匹配)
        └─► 协商条件：
              ├─ 双方都支持该套件
              ├─ 服务端偏好该套件（按服务端配置顺序）
              └─ 满足安全策略要求（最小密钥长度等）
```

## 7. OCSP 响应状态码

| 状态码 | 含义 | 说明 |
|--------|------|------|
| 0 (successful) | Good | 证书未被吊销 |
| 1 (malformedRequest) | 请求格式错误 | OCSP 请求结构异常 |
| 2 (internalError) | 内部错误 | OCSP 响应者内部异常 |
| 3 (tryLater) | 稍后再试 | 响应者暂时不可用 |
| 5 (sigRequired) | 需要签名 | 请求需要签名 |
| 6 (unauthorized) | 未授权 | 请求者未被授权查询 |
