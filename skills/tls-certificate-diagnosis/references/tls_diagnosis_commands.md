# TLS 诊断命令与工具参考

## 1. OpenSSL 核心诊断命令

| 命令 | 用途 | 示例 |
|------|------|------|
| `openssl s_client` | 通用 TLS 连接测试 | `openssl s_client -connect example.com:443 -showcerts` |
| `openssl x509` | 证书内容解析 | `openssl x509 -in cert.pem -noout -subject -dates` |
| `openssl verify` | 证书链验证 | `openssl verify -CAfile ca.pem -untrusted intermediate.pem cert.pem` |
| `openssl ciphers` | 列出可用密码套件 | `openssl ciphers -v 'ALL:COMPLEMENTOFALL'` |
| `openssl ocsp` | OCSP 查询 | `openssl ocsp -issuer issuer.pem -cert cert.pem -url http://ocsp.example.com` |
| `openssl s_time` | TLS 连接性能测试 | `openssl s_time -connect example.com:443 -time 10` |
| `openssl speed` | 密码套件性能测试 | `openssl speed aes-256-gcm` |

## 2. s_client 常用参数

| 参数 | 用途 | 示例 |
|------|------|------|
| `-connect host:port` | 指定目标 | `-connect example.com:443` |
| `-showcerts` | 显示完整证书链 | `-showcerts` |
| `-servername name` | 指定 SNI | `-servername www.example.com` |
| `-cert file` | 客户端证书 | `-cert client.pem` |
| `-key file` | 客户端私钥 | `-key client.key` |
| `-CAfile file` | 指定 CA 包 | `-CAfile /etc/ssl/certs/ca-certificates.crt` |
| `-tls1_2` / `-tls1_3` | 指定 TLS 版本 | `-tls1_2` |
| `-cipher cipher` | 指定密码套件 | `-cipher AES256-GCM-SHA384` |
| `-status` | 请求 OCSP stapling | `-status` |
| `-verify_return_error` | 验证失败时终止 | `-verify_return_error` |
| `-timeout sec` | 连接超时 | `-timeout 5` |

## 3. curl TLS 诊断参数

| 参数 | 用途 | 示例 |
|------|------|------|
| `--cacert` | 指定 CA 证书 | `curl --cacert ca.pem https://example.com` |
| `--cert` | 指定客户端证书 | `curl --cert client.pem --key client.key https://example.com` |
| `--tlsv1.2` | 指定 TLS 版本 | `curl --tlsv1.2 https://example.com` |
| `--ciphers` | 指定密码套件 | `curl --ciphers AES256-GCM-SHA384 https://example.com` |
| `--resolve` | 指定 DNS 解析 | `curl --resolve example.com:443:1.2.3.4 https://example.com` |
| `--verbose` | 显示详细握手信息 | `curl --verbose https://example.com` |

## 4. 其他诊断工具

| 工具 | 用途 | 示例 |
|------|------|------|
| `nmap ssl-enum-ciphers` | 枚举服务端密码套件 | `nmap --script ssl-enum-ciphers -p 443 example.com` |
| `nmap ssl-cert` | 获取服务端证书 | `nmap --script ssl-cert -p 443 example.com` |
| `testssl.sh` | 全面的 TLS 安全测试 | `testssl.sh example.com:443` |
| `gnutls-cli` | GnuTLS 客户端测试 | `gnutls-cli -p 443 example.com` |
| `cfssl` | CloudFlare 证书工具 | `cfssl certinfo -cert cert.pem` |

## 5. 客户端信任库位置

| 操作系统 | 信任库路径 |
|---------|-----------|
| Linux (Debian/Ubuntu) | `/etc/ssl/certs/ca-certificates.crt` |
| Linux (RHEL/CentOS) | `/etc/pki/tls/certs/ca-bundle.crt` |
| Alpine Linux | `/etc/ssl/cert.pem` |
| macOS | `/etc/ssl/cert.pem` |
| Windows | `cert:\CurrentUser\Root` |
| Java (JDK) | `$JAVA_HOME/lib/security/cacerts` |
