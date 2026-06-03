# 🔴 故障诊断报告 — TLS OCSP Stapling 失效

> **报告编号**: RCA-20260602-001
> **故障级别**: P3（功能缺陷，非业务中断，但影响客户端证书信任验证效率）
> **报告时间**: 2026-06-02 02:10:00 UTC
> **当前状态**: 🔴 未恢复（持续性配置缺陷）

---

## 一、故障概览

| 项目 | 内容 |
|------|------|
| 故障标题 | tls-full 容器端口 4443 OCSP Stapling 功能失效，openssl s_client 返回 `OCSP response: no response sent` |
| 影响范围 | 容器 tls-full（端口 4443），客户端使用 `openssl s_client -status` 连接时无法获取服务端推送的证书吊销状态 |
| 故障时段 | 持续性故障 — 自服务部署起截至 2026-06-02 02:10:00 UTC 始终存在 |
| 根本原因 | 双层缺陷叠加：① 服务器证书为 X.509 Version 1，不含 AIA 扩展，无法指定 OCSP Responder URL；② `openssl s_server` 启动命令仅带 `-status_timeout 1` 但未指定 `-status_file`，导致无 OCSP 响应数据可供 stapling |
| 是否恢复 | ❌ 未恢复 |
| 根因置信度 | 🟢 高置信 — 可复现，单一因果链即可解释全部现象 |

### 置信度说明

| 等级 | 标识 | 含义 | 示例场景 |
|------|------|------|--------|
| 高置信 | 🟢 | 根因已明确，可复现，单一原因可解释所有现象 | 本场景：证书无 AIA + 服务端未配置 status_file → OCSP stapling 必然失败 |
| 中置信 | 🟡 | 根因基本确认，但存在 1～2 个无法完全解释的现象 | — |
| 低置信 | 🟠 | 有多个可疑原因，尚未排除竞争，结论为推断 | — |
| 未知 | 🔴 | 现象无法解释，根因未定位，仍在排查中 | — |

---

## 二、根因速览

### 事故时间线 & 故障传导链路

```text
时间                         事件                                                              性质          溯源路径
─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
[服务部署时]                  tls-full 容器启动                                                    🟢 部署       [kuafu_T1_ocsp_stapling_diagnosis_20260602.md:72]
  │                           openssl s_server -key valid.key -cert valid.pem -accept 4443
  │                           -www -status_timeout 1
  │
  ▼
[服务运行期间]                valid.pem 证书为 X.509 Version 1                                      ⛔ 固有限制   [kuafu_T1_ocsp_stapling_diagnosis_20260602.md:39-53]
  │                           无 AIA 扩展，无 OCSP Responder URL 字段
  │                           无法嵌入 OCSP Responder 地址供客户端查询
  │
  ▼
[服务运行期间]                CA 证书 TestRootCA（ca.pem）也                                                          [kuafu_T1_ocsp_stapling_diagnosis_20260602.md:51-53]
  │                           未配置 AIA 扩展
  │                           整个 CA 体系未部署 OCSP Responder 服务实例
  │
  ▼
[服务运行期间]                openssl s_server 启动命令                                                                 [kuafu_T1_ocsp_stapling_diagnosis_20260602.md:77-82]
  │                           仅带 -status_timeout 1（开启 stapling 能力标记）
  │                           缺少 -status_file <ocsp_response.der> 参数
  │                           服务端无预生成 OCSP 响应文件可发送
  │
  ▼
[客户端连接时]                openssl s_client -status -connect localhost:4443                       🔴 故障验证   [kuafu_T1_ocsp_stapling_diagnosis_20260602.md:14-29]
  │                           服务端 TLS 握手时返回 "OCSP response: no response sent"
  │                           证书链验证返回 code 21（unable to verify the first certificate）
  │
  ▼
                              🔴 OCSP Stapling 完全失效 — 客户端无法获取服务端证书吊销状态
```

### 故障因果链

```text
证书为 X.509 Version 1（无 AIA 扩展）
    │
    ├─► 无 Authority Information Access 字段 → 无 OCSP Responder URL
    │
    ├─► CA（TestRootCA）也未配置 AIA → 无 OCSP Responder 服务可用
    │
    └─► 无法生成有效的 OCSP 响应文件供 stapling 使用
            │
            ▼
openssl s_server 缺少 -status_file <ocsp_response.der>
    │
    └─► 虽然 -status_timeout 1 开启 Stapling 能力标记
            │
            └─► 服务端无 OCSP 响应数据可推送
                    │
                    ▼
                    🔴 TLS 握手阶段 "OCSP response: no response sent"
                    │
                    └─► 客户端无法验证证书吊销状态
                            │
                            └─► 回退到 CRL 或完全跳过吊销检查（信任决策降级）
```

---

## 三、排查过程

> 排查逻辑：**提出假设 → 收集证据 → 验证或排除 → 逐步收敛到根因**

### 3.1 初始现象

- **现象 1**：对 tls-full:4443 执行 `openssl s_client -status -connect localhost:4443 -servername localhost`，输出第一行即显示 `OCSP response: no response sent`
- **现象 2**：证书链验证返回代码 `21 (unable to verify the first certificate)`
- **现象 3**：`cert_status: no AIA` 指示客户端无法从证书中找到 OCSP Responder 地址

### 3.2 假设驱动排查

---

#### 假设 F1：OCSP Responder 不可达（OCSP responder unreachable）

> 🧪 假设：OCSP Responder 服务已部署但网络不通，服务端无法获取响应

| 检查项 | 操作（基于真实历史记录） | 结论 |
|--------|------|------|
| 证书 AIA 扩展 | `openssl x509 -in /test/certs/valid.pem -noout -text` | ❌ 证书为 Version 1，**无任何扩展字段**，根本不存在 AIA |
| CA 证书 AIA | `openssl x509 -in /test/certs/ca.pem -noout -text` | ❌ CA 虽为 Version 3，但也**无 AIA 扩展**，未指定 OCSP Responder URL |
| OCSP Responder 服务 | 自签名 CA 环境下推理 | ❌ 无 AIA 意味着客户端和服务端都不知道该去向哪个 URL 查询，OCSP Responder 服务本身也未被部署 |

**❌ 排除**：该假设的前提条件（AIA 扩展存在且指定了 OCSP URL）不成立。场景的根因更上层——证书根本不含 AIA 扩展，"responder 不可达"是次级问题，而非根本问题。

---

#### 假设 F2：OCSP 响应签名无效（OCSP response signature invalid）

> 🧪 假设：OCSP Responder 响应已收到，但其数字签名被验证失败

| 检查项 | 操作（基于真实历史记录） | 结论 |
|--------|------|------|
| OCSP 响应接收 | `openssl s_client -status` 输出 | ❌ 响应根本未被发送（`no response sent`），而非签名无效 |

**❌ 排除**：服务端未发出任何 OCSP 响应，签名验证无从谈起。

---

#### 假设 F3：服务端未启用 OCSP Stapling ✅ 确认根因

> 🧪 假设：服务端 TLS 配置不完整，导致无法发送 OCSP Stapling 响应

**Step 1 — 确认服务端配置**

```bash
# 运行中的进程（ps aux 输出）：
root        51  0.0  0.0   openssl s_server -key /test/certs/valid.key \
                                           -cert /test/certs/valid.pem \
                                           -accept 4443 -www -status_timeout 1
```

分析：
- `-status_timeout 1`：✅ **已开启** OCSP Stapling 能力标记，设置了 1 秒超时
- **未指定 `-status_file`**：❌ `openssl s_server` 必须通过 `-status_file <ocsp_response.der>` 指定预生成的 OCSP 响应文件
- 缺少 `-status_file` 时，`openssl s_server` **没有内置主动查询 OCSP Responder 的能力**，因此永远无法生成或发送 stapling 响应

**Step 2 — 验证证书是否具备 AIA**

```bash
# 服务器证书检查
openssl x509 -in /test/certs/valid.pem -noout -text
# 输出显示: Version: 1 (0x0)  — 无任何扩展字段
# Version 1 证书无法包含 AIA（Authority Information Access）扩展

# CA 证书检查
openssl x509 -in /test/certs/ca.pem -noout -text
# CA 为 Version 3，但也无 AIA 扩展 — 整个 CA 体系未配置 OCSP
```

**✅ 结论（双重根因确认）**：

1. **证书层因**：服务器证书 valid.pem 为 **X.509 Version 1**，不含 AIA 扩展，无法嵌入 OCSP Responder URL。CA 证书也未配置 AIA。
2. **配置层因**：`openssl s_server` 启动时虽然带有 `-status_timeout 1`，但**缺少 `-status_file` 参数**，没有提供预生成的 OCSP 响应 DER 文件，服务端无数据可推送。

两个原因中的任一单独存在即可导致 OCSP Stapling 失效，二者叠加则完全阻塞了该功能。

---

#### 假设 F4：OCSP 响应已过期（OCSP response expired）

> 🧪 假设：服务端曾成功获取 OCSP 响应但已过期

| 检查项 | 操作（基于真实历史记录） | 结论 |
|--------|------|------|
| 响应是否存在 | `openssl s_client -status` | ❌ 服务端从未发送任何 OCSP 响应（`no response sent`） |

**❌ 排除**：服务端从未具备发送 OCSP 响应的能力，"响应过期"的前提不成立。

---

#### 假设 F5：证书已被吊销但未反映（Certificate revoked）

> 🧪 假设：证书已实际吊销，但 OCSP Stapling 未生效导致无法反映吊销状态

| 检查项 | 操作（基于真实历史记录） | 结论 |
|--------|------|------|
| OCSP 吊销状态查询 | 诊断报告第 3 节 | ❌ 无法执行——无 AIA 扩展、无 OCSP Responder URL、自签名 CA 未部署 OCSP Responder |

**❌ 排除**：目前无证据表明证书被吊销，且 OCSP 通道本身未建立，此假设无法验证且非当前故障的直接原因。

---

### 3.3 排查结论与逻辑树

```text
OCSP response: no response sent
│
├─► 假设 F1：OCSP Responder 不可达    → ❌ 排除 — 证书无 AIA，根本未指定 URL
│
├─► 假设 F2：OCSP 响应签名无效         → ❌ 排除 — 无任何响应被发送
│
├─► 假设 F3：服务端 OCSP Stapling 未配置 → ✅ 确认根因
│   │
│   ├─► 证书层：valid.pem 为 X.509 v1，无 AIA 扩展 → 无 OCSP URL
│   │   └─► CA (TestRootCA) 也无 AIA → 整个体系无 OCSP 服务
│   │
│   └─► 配置层：openssl s_server 缺少 -status_file <ocsp_response.der>
│       └─► 服务端无 OCSP 响应数据可推送
│
├─► 假设 F4：OCSP 响应过期             → ❌ 排除 — 从未生成过响应
│
└─► 假设 F5：证书已被吊销              → ❌ 排除 — 无可验证证据，且非本故障直接原因

🎯 根因确认：双层缺陷 — X.509 v1 证书无 AIA + openssl s_server 缺失 -status_file
```

---

## 四、修复方案

### 4.1 应急处置（无 — 非业务中断型故障）

当前故障为功能特性缺失（OCSP Stapling），不影响 TLS 握手与加密通信的核心功能。客户端仍可完成 TLS 连接，但无法在握手阶段获取证书吊销状态。

> **影响分析**：客户端回退到 CRL（证书吊销列表）下载或完全跳过吊销检查。不建议作为 P0/P1 紧急处理，应纳入计划性修复。

### 4.2 永久修复计划

#### 方案一（推荐）：重建为 X.509 v3 证书 + 配置 OCSP Stapling

| 步骤 | 操作 | 说明 |
|------|------|------|
| 1 | 生成新的 X.509 v3 证书，添加 AIA 扩展字段 | 在 `openssl.cnf` 中配置 `authorityInfoAccess = OCSP;URI:http://ocsp.example.com/` |
| 2 | 部署并配置 OCSP Responder 服务 | 在自签名 CA 环境中使用 `openssl ocsp` 命令启动 OCSP Responder：`openssl ocsp -index index.txt -CA ca.pem -rsigner responder.pem -port 8888 -text` |
| 3 | 生成 OCSP 响应文件 | 使用 `openssl ocsp -issuer ca.pem -cert valid.pem -url http://ocsp.example.com/ -respout ocsp_response.der` 生成响应 |
| 4 | 更新 `openssl s_server` 启动命令 | 追加 `-status_file /path/to/ocsp_response.der` 参数 |
| 5 | 设置 OCSP 响应定期更新 | 通过 cron/systemd timer 定期（如每 6 小时）重新生成 OCSP 响应文件并重启服务 |
| 6 | 验证 | `openssl s_client -status -connect localhost:4443` 应显示 `OCSP response: OCSP Response Data` |

#### 方案二（轻量替代）：使用 CRL 替代 OCSP

如果环境复杂度有限，可考虑仅配置 CRL（证书吊销列表）分发而非 OCSP Stapling：

| 步骤 | 操作 |
|------|------|
| 1 | 在 CA 环境中维护 CRL：`openssl ca -gencrl -out ca.crl` |
| 2 | 在客户端配置 CRL 分发点路径 |
| 3 | 客户端 TLS 连接时主动下载 CRL 验证吊销状态 |

| 修复措施 | 负责人 | 完成时间 |
|--------|------|--------|
| 生成 X.509 v3 证书（含 AIA 扩展） | 待定 | 待定 |
| 部署 OCSP Responder 服务 | 待定 | 待定 |
| 配置 openssl s_server 增加 `-status_file` 参数 | 待定 | 待定 |
| 建立 OCSP 响应定时更新机制 | 待定 | 待定 |
| 端到端验证 OCSP Stapling 生效 | 待定 | 待定 |

---

> 📁 **RCA 报告路径**: `C:\Users\86188\.witty-diagnosis-agent\baize\reports\OCSP_Stapling失效诊断_tls-full_20260602_021000_report.md`
