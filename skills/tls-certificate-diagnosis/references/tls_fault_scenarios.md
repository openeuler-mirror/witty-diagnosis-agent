# TLS/SSL 故障场景分类

## 场景列表

| 场景标签 | 中文描述 | 主要特征与案例 |
|---------|---------|--------------|
| `CERT_EXPIRY` | 证书过期或即将过期 | ① `openssl s_client` 返回 `verify error:num=10:certificate has expired`；② 浏览器显示 NET::ERR_CERT_DATE_INVALID；③ notAfter 日期已过当前时间或将在 30 天内过期 |
| `CHAIN_INCOMPLETE` | 证书链不完整 | ① `openssl s_client -showcerts` 仅返回 1 张证书；② `openssl verify` 报 `unable to get local issuer certificate`；③ 浏览器显示 MOZILLA_PKIX_ERROR_CA_CERT_USED_AS_END_ENTITY |
| `CA_TRUST_MISSING` | CA 信任库缺失或过期 | ① `curl` 报 `SSL certificate problem: unable to get local issuer certificate`；② Java 报 `PKIX path building failed`；③ 本地 `/etc/ssl/certs/` 中缺少签发 CA 的证书 |
| `CIPHER_MISMATCH` | TLS 版本或密码套件不兼容 | ① `openssl s_client` 报 `no protocols available`；② 错误 `no shared cipher`；③ 较旧客户端无法连接到已禁用 TLS 1.0/1.1 的服务端 |
| `SNI_MISCONFIG` | SNI 配置错误 | ① 不带 SNI 连接返回的证书域名与访问域名不匹配；② 浏览器报 SSL_ERROR_BAD_CERT_DOMAIN；③ `openssl s_client -servername` 与不带 SNI 返回不同证书 |
| `OCSP_FAILURE` | OCSP stapling 失败 | ① `openssl s_client -status` 输出 `OCSP Response Status: unknown`；② OCSP responder URL 不可达；③ 浏览器报 `certificate revoked` |
| `CLIENT_CERT_FAIL` | 客户端证书认证失败 | ① 服务端返回 `SSL/TLS alert: certificate required`；② `openssl s_client` 报 `bad certificate`；③ 双向 TLS 握手在 CertificateRequest 后中断 |

## 场景关联性

| 关联模式 | 典型链路 |
|---------|---------|
| 证书过期 → OCSP 吊销状态异常 | 过期证书可能在 OCSP 响应者中标记为未知，两者需同时排查 |
| 证书链不完整 → CA 信任库缺失 | 服务端未发送中间证书时，客户端若信任库无对应 CA，两者效果叠加 |
| SNI 配置错误 → 证书过期误判 | SNI 返回了默认的过期证书，但目标域名的实际证书可能仍在有效期内 |
| TLS 版本不兼容 → 密码套件协商失败 | 版本协商失败后不会继续密码套件协商，先排查版本再排查套件 |
